import Foundation

public enum TraceFoxBotCoordinatorError: Error { case notStarted, busy }

public final class TraceFoxBotPairingCoordinator {
    private let client: TraceFoxBotLinkClient
    private let store: TraceFoxBotCredentialStore
    private let lock = NSLock()
    private var attempt: TraceFoxBotPairingAttempt?
    private var task: URLSessionDataTask?
    private var generation: UInt64 = 0

    public init(client: TraceFoxBotLinkClient, store: TraceFoxBotCredentialStore = TraceFoxBotCredentialStore()) {
        self.client = client; self.store = store
    }

    deinit { cancel() }

    // The UI must cancel on account switch/logout and send no approval command
    // without the user's explicit action. This method only returns command text.
    public func begin(ownerId: Int64) throws -> String {
        let next = try TraceFoxBotPairingAttempt(ownerId: ownerId)
        let command = try next.approvalCommand()
        lock.lock()
        generation &+= 1
        let previous = task
        task = nil; attempt = next
        lock.unlock()
        previous?.cancel()
        return command
    }

    public func cancel() {
        lock.lock()
        generation &+= 1
        let previous = task
        task = nil; attempt = nil
        lock.unlock()
        previous?.cancel()
    }

    // One poll at a time. Cancelled/superseded completions are ignored and cannot
    // write Keychain. The UI owns polling cadence and cancellation presentation.
    public func poll(completion: @escaping (Result<TraceFoxBotLinkCredentials?, Error>) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let attempt = attempt else { throw TraceFoxBotCoordinatorError.notStarted }
        guard task == nil else { throw TraceFoxBotCoordinatorError.busy }
        let current = generation
        task = try client.claim(attempt) { [weak self] result in
            guard let self = self else { return }
            self.lock.lock()
            guard self.generation == current else { self.lock.unlock(); return }
            self.task = nil
            var outcome = result
            if case let .success(credentials?) = result {
                do {
                    try self.store.save(credentials, expectedOwnerId: attempt.ownerId)
                    self.attempt = nil
                } catch { outcome = .failure(error) }
            }
            self.lock.unlock()
            completion(outcome)
        }
    }
}
