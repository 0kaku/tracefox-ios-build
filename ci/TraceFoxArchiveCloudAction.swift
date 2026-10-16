import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import SGConfig

// Explicit text-only export. Retains failed/cancelled events in the account queue.
final class TraceFoxArchiveCloudAction {
    let status = Promise<String>()
    private let context: AccountContext
    private let observation = MetaDisposable()
    private let workQueue = DispatchQueue(label: "tracefox.archive.cloud.action")
    private var sender: TraceFoxCloudArchiveSender?
    private var client: TraceFoxBotLinkClient?
    private var active = false
    private var busy = false
    private var generation: UInt64 = 0

    init(context: AccountContext) {
        self.context = context
        status.set(.single("Хмарне надсилання тут передає лише текст вибраної копії. Файли залишаються локальними."))
        observation.set((context.sharedContext.activeAccountsWithInfo |> deliverOnMainQueue).start(next: { [weak self] view in
            guard let self = self else { return }
            let active = view.primary == context.account.id && view.accounts.contains(where: { $0.account.id == context.account.id })
            self.workQueue.async { [weak self] in
                guard let self = self else { return }
                self.active = active
                if !active { self.cancelOnQueue() }
            }
        }))
    }
    deinit { observation.dispose(); sender?.cancel() }
    func cancel() {
        workQueue.async { [weak self] in self?.cancelOnQueue() }
    }
    private func cancelOnQueue() {
        let wasBusy = busy
        generation &+= 1
        sender?.cancel(); sender = nil; client = nil; busy = false
        if wasBusy { status.set(.single("Надсилання скасовано. Непідтверджені події залишаються в черзі.")) }
    }

    func send(record: TraceFoxArchiveRecord? = nil) {
        workQueue.async { [weak self] in self?.sendOnQueue(record: record) }
    }
    private func sendOnQueue(record: TraceFoxArchiveRecord?) {
        guard active else { status.set(.single("Відкрийте архів з активного акаунта.")); return }
        guard !busy else { return }
        do {
            let owner = context.account.peerId.id._internalGetInt64Value()
            let store = TraceFoxBotCredentialStore(accountRecordId: context.account.id.int64)
            guard let credentials = try store.read(ownerId: owner) else {
                status.set(.single("Спочатку прив’яжіть цей акаунт до бота в налаштуваннях TraceFox.")); return
            }
            let root = URL(fileURLWithPath: context.account.postbox.mediaBox.basePath).deletingLastPathComponent().appendingPathComponent("tracefox-cloud-queue")
            let queue = try TraceFoxCloudArchiveQueue(root: root)
            var selected: UUID?
            if let record = record {
                guard let payload = try TraceFoxCloudArchiveBridge.payload(record: record) else {
                    status.set(.single("Цю копію не можна надіслати цим шляхом. Секретні та локальні повідомлення залишаються на пристрої.")); return
                }
                selected = try queue.enqueue(payload)
            }
            guard let origin = URL(string: SG_CONFIG.apiUrl) else { throw TraceFoxBotLinkError.invalidOrigin }
            let client = try TraceFoxBotLinkClient(origin: origin)
            self.client = client
            let sender = TraceFoxCloudArchiveSender(queue: queue, client: client, ownerId: owner)
            self.sender = sender
            busy = true
            let token = generation
            let selectedId = selected
            status.set(.single("Надсилання наступної текстової події черги…"))
            try sender.sendNext(credentials: credentials) { [weak self] result in
                self?.workQueue.async { [weak self] in
                    guard let self = self, self.generation == token, self.active else { return }
                    self.busy = false; self.sender = nil; self.client = nil
                    let message: String
                    switch result {
                    case .success(nil): message = "Черга текстових подій порожня."
                    case let .success(id?):
                        message = selectedId == nil || selectedId == id ? "Сервер підтвердив збереження текстової події." : "Надіслано попередню подію. Вибрана копія залишається в черзі; надішліть наступну подію."
                    case let .failure(error):
                        if case .httpStatus(403)? = error as? TraceFoxBotLinkClientError {
                            message = "Сервер не надав доступу до архіву. Подія залишається в черзі."
                        } else {
                            message = "Надсилання не підтверджено. Подія залишається в черзі; перевірте мережу та прив’язку."
                        }
                    }
                    self.status.set(.single(message))
                }
            }
        } catch {
            busy = false; sender = nil; client = nil
            status.set(.single("Операцію не завершено. Перевірте прив’язку, сховище та обмеження довжини тексту."))
        }
    }
}
