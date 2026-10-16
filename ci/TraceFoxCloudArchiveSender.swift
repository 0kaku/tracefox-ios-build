import Foundation

public enum TraceFoxCloudSenderError: Error { case busy, ownerMismatch, invalidAcknowledgement }

// Explicit one-event worker. Cancellation retains pending data. Retries are
// at-least-once: a server commit followed by a lost response can be sent again.
public final class TraceFoxCloudArchiveSender {
    private let queue: TraceFoxCloudArchiveQueue
    private let client: TraceFoxCloudSubmitting
    private let ownerId: Int64
    private let lock = NSLock()
    private var active: UUID?
    private var task: TraceFoxBotClaimTask?

    public init(queue: TraceFoxCloudArchiveQueue, client: TraceFoxCloudSubmitting, ownerId: Int64) {
        self.queue = queue; self.client = client; self.ownerId = ownerId
    }
    deinit { cancel() }

    public func cancel() {
        lock.lock(); active = nil
        let old = task; task = nil
        lock.unlock(); old?.cancel()
    }

    public func sendNext(credentials: TraceFoxBotLinkCredentials,
                         completion: @escaping (Result<UUID?, Error>) -> Void) throws {
        guard ownerId > 0, credentials.ownerId == ownerId else { throw TraceFoxCloudSenderError.ownerMismatch }
        lock.lock()
        guard active == nil else { lock.unlock(); throw TraceFoxCloudSenderError.busy }
        let entry: TraceFoxCloudQueueEntry?
        do { entry = try queue.first() } catch { lock.unlock(); throw error }
        guard let entry = entry else { lock.unlock(); completion(.success(nil)); return }
        let token = UUID(); active = token
        lock.unlock()
        do {
            let next = try client.submit(entry.payload, credentials: credentials) { [weak self] response in
                guard let self = self else { return }
                self.lock.lock()
                guard self.active == token else { self.lock.unlock(); return }
                self.active = nil; self.task = nil
                let outcome: Result<UUID?, Error>
                switch response {
                case let .success(ack):
                    do {
                        guard ack > 0 else { throw TraceFoxCloudSenderError.invalidAcknowledgement }
                        try self.queue.acknowledge(entry.id)
                        outcome = .success(entry.id)
                    } catch { outcome = .failure(error) }
                case let .failure(error): outcome = .failure(error)
                }
                self.lock.unlock()
                completion(outcome)
            }
            lock.lock()
            let keep = active == token
            if keep { task = next }
            lock.unlock()
            if !keep { next.cancel() }
        } catch {
            lock.lock()
            if active == token { active = nil; task = nil }
            lock.unlock()
            throw error
        }
    }
}
