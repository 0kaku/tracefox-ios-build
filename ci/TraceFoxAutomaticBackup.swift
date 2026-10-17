import Foundation
import Postbox
import SwiftSignalKit

// Owned by the authorized account context. iOS may suspend this foreground worker;
// local records and the acknowledgement ledger make the next launch resumable.
public final class TraceFoxAutomaticBackup {
    private let account: Account
    private let client: TraceFoxBotLinkClient
    private let credentials: TraceFoxBotCredentialStore
    private let coordinator: TraceFoxBotPairingCoordinator
    private let archive: TraceFoxArchiveStore
    private let ledger: TraceFoxBackupLedger
    private let queue = DispatchQueue(label: "tracefox.automatic.backup")
    private let nativeTask = MetaDisposable()
    private var task: TraceFoxBotClaimTask?
    private final class WeakWorker { weak var value: TraceFoxAutomaticBackup?; init(_ value: TraceFoxAutomaticBackup) { self.value = value } }
    private static let registryLock = NSLock()
    private static var workers: [Int64: WeakWorker] = [:]
    private let stateLock = NSLock()
    private var stoppedValue = false
    private var stopped: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return stoppedValue }
        set { stateLock.lock(); stoppedValue = newValue; stateLock.unlock() }
    }
    public static func stopAccount(_ id: Int64) {
        registryLock.lock(); let worker = workers.removeValue(forKey: id)?.value; registryLock.unlock()
        worker?.stop()
    }
    private var timer: DispatchWorkItem?
    private var attemptStarted: Date?
    private var commandSent = false
    private var command: String?
    private var cursor: TraceFoxArchiveCursor?
    private var batch: [TraceFoxArchiveRecord] = []
    private let botName: String

    public convenience init(account: Account) throws {
        try self.init(account: account, server: TraceFoxAutomaticBackupConfiguration.server, botName: TraceFoxAutomaticBackupConfiguration.bot)
    }
    public init(account: Account, server: String, botName: String) throws {
        self.account = account; self.botName = botName
        client = try TraceFoxBotLinkClient(origin: URL(string: server)!)
        credentials = TraceFoxBotCredentialStore(accountRecordId: account.id.int64)
        coordinator = TraceFoxBotPairingCoordinator(client: client, store: credentials)
        archive = try TraceFoxLocalArchive.store(mediaBox: account.postbox.mediaBox)
        let root = URL(fileURLWithPath: account.postbox.mediaBox.basePath).deletingLastPathComponent().appendingPathComponent("tracefox-auto-backup")
        ledger = try TraceFoxBackupLedger(root: root)
        Self.registryLock.lock()
        let previous = Self.workers[account.id.int64]?.value
        Self.workers[account.id.int64] = WeakWorker(self)
        Self.registryLock.unlock(); previous?.stop()
        queue.async { [weak self] in self?.tick() }
    }
    deinit { timer?.cancel(); task?.cancel(); nativeTask.dispose(); coordinator.cancel() }
    public func stop() {
        stopped = true; coordinator.cancel(); nativeTask.dispose()
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopped = true; self.timer?.cancel(); self.task?.cancel()
            self.nativeTask.dispose(); self.coordinator.cancel()
        }
    }
    private var owner: Int64 { account.peerId.id._internalGetInt64Value() }
    private func schedule(_ seconds: Double) {
        guard !stopped else { return }
        timer?.cancel()
        let next = DispatchWorkItem { [weak self] in self?.tick() }
        timer = next; queue.asyncAfter(deadline: .now() + seconds, execute: next)
    }
    private func tick() {
        guard !stopped else { return }
        do {
            if let stored = try credentials.read(ownerId: owner) {
                task = try client.status(credentials: stored) { [weak self] result in
                    self?.queue.async { [weak self] in
                        guard let self = self, !self.stopped else { return }
                        self.task = nil
                        switch result {
                        case let .success(status):
                            if status.archive_available { self.nextRecord(stored) } else { self.schedule(60) }
                        case let .failure(error): self.recordFailed(record, error)
                        }
                    }
                }
            } else { pair() }
        } catch { schedule(60) }
    }
    private func failed(_ error: Error) {
        if case .httpStatus(401)? = error as? TraceFoxBotLinkClientError {
            // Compare/clear only this account's credentials; session work is serialized.
            try? credentials.remove(ownerId: owner)
            coordinator.cancel(); attemptStarted = nil; commandSent = false; command = nil
        }
        schedule(60)
    }
    private func pair() {
        guard !stopped else { return }
        do {
            if attemptStarted == nil || Date().timeIntervalSince(attemptStarted!) > 540 {
                command = try coordinator.begin(ownerId: owner)
                attemptStarted = Date(); commandSent = false
            }
            if !commandSent {
                let text = command!
                let engine = TelegramEngine(account: account)
                nativeTask.set((engine.peers.resolvePeerByName(name: botName, referrer: nil)
                |> mapToSignal { [account] value -> Signal<[MessageId?], NoError> in
                    guard case let .result(peer) = value else { return .complete() }
                    guard let peer = peer, peer.id.namespace == Namespaces.Peer.CloudUser else { return .single([]) }
                    return enqueueMessages(account: account, peerId: peer.id, messages: [
                        .message(text: text, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil,
                                 replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                    ])
                }).start(next: { [weak self] ids in
                    self?.queue.async { [weak self] in
                        guard let self = self, !self.stopped else { return }
                        self.commandSent = ids.contains(where: { $0 != nil })
                        self.schedule(self.commandSent ? 2 : 60)
                    }
                }))
                schedule(60)
                return
            }
            try coordinator.poll { [weak self] result in
                self?.queue.async { [weak self] in
                    guard let self = self, !self.stopped else { return }
                    switch result {
                    case .success(_?): self.attemptStarted = nil; self.command = nil; self.schedule(1)
                    case .success(nil): self.schedule(5)
                    case .failure: self.schedule(60)
                    }
                }
            }
        } catch { schedule(60) }
    }
    private func nextRecord(_ stored: TraceFoxBotLinkCredentials) {
        guard !stopped else { return }
        do {
            while true {
                let urgent = try archive.records(limit: 1, matching: { record in
                    (record.ttlSeconds ?? 0) > 0 && ((try? self.ledger.eligible(record)) ?? false)
                }).first
                if urgent == nil && batch.isEmpty {
                    batch = try archive.records(before: cursor)
                    guard let last = batch.last else { cursor = nil; schedule(30); return }
                    cursor = TraceFoxArchiveCursor(record: last)
                }
                let record = urgent ?? batch.removeFirst()
                if !(try ledger.eligible(record)) { continue }
                guard let payload = try? TraceFoxCloudArchiveBridge.backupPayload(record: record) else {
                    try ledger.deferRecord(record); continue
                }
                do {
                task = try client.submit(payload, credentials: stored) { [weak self] result in
                    self?.queue.async { [weak self] in
                        guard let self = self, !self.stopped else { return }
                        self.task = nil
                        switch result {
                        case .success: self.upload(record, payload, stored)
                        case let .failure(error): self.recordFailed(record, error)
                        }
                    }
                }
                } catch { recordFailed(record, error) }
                return
            }
        } catch { schedule(60) }
    }
    private func upload(_ record: TraceFoxArchiveRecord, _ payload: TraceFoxBackupPayload, _ stored: TraceFoxBotLinkCredentials) {
        do {
            if let name = record.files.first {
                let file = try archive.mediaURL(name: name)
                task = try client.upload(file: file, payload: payload, credentials: stored) { [weak self] result in
                    self?.queue.async { [weak self] in
                        guard let self = self, !self.stopped else { return }
                        self.task = nil
                        switch result {
                        case let .success(archiveId): self.verify(record, payload, stored, file, archiveId)
                        case let .failure(error): self.recordFailed(record, error)
                        }
                    }
                }
            } else { acknowledge(record) }
        } catch { recordFailed(record, error) }
    }
    private func verify(_ record: TraceFoxArchiveRecord, _ payload: TraceFoxBackupPayload,
                        _ stored: TraceFoxBotLinkCredentials, _ file: URL, _ archiveId: Int64) {
        do {
            task = try client.verify(file: file, archiveId: archiveId, payload: payload, credentials: stored) { [weak self] result in
                self?.queue.async { [weak self] in
                    guard let self = self, !self.stopped else { return }
                    self.task = nil
                    switch result {
                    case .success: self.acknowledge(record)
                    case let .failure(error): self.recordFailed(record, error)
                    }
                }
            }
        } catch { recordFailed(record, error) }
    }
    private func recordFailed(_ record: TraceFoxArchiveRecord, _ error: Error) {
        do { try ledger.deferRecord(record) } catch { schedule(60); return }
        if case .httpStatus(401)? = error as? TraceFoxBotLinkClientError { failed(error); return }
        schedule(0.2)
    }
    private func acknowledge(_ record: TraceFoxArchiveRecord) {
        do { try ledger.acknowledge(record) } catch { schedule(60); return }
        schedule(0.2)
    }
}
