import Foundation

public enum TraceFoxBotCoordinatorError: Error { case notStarted, busy }

public final class TraceFoxBotPairingCoordinator {
    private let client: TraceFoxBotClaiming
    private let store: TraceFoxBotCredentialStore
    private let lock = NSLock()
    private var attempt: TraceFoxBotPairingAttempt?
    private var task: TraceFoxBotClaimTask?
    private var generation: UInt64 = 0
    private var activePoll: UUID?

    public init(client: TraceFoxBotClaiming, store: TraceFoxBotCredentialStore = TraceFoxBotCredentialStore()) {
        self.client = client; self.store = store
    }

    deinit { cancel() }

    // Callers cancel on account switch/logout. This method returns command text;
    // the authorized automatic service owns sending and polling cadence.
    public func begin(ownerId: Int64) throws -> String {
        let next = try TraceFoxBotPairingAttempt(ownerId: ownerId)
        let command = try next.approvalCommand()
        lock.lock()
        generation &+= 1
        let previous = task
        task = nil; activePoll = nil; attempt = next
        lock.unlock()
        previous?.cancel()
        return command
    }

    public func cancel() {
        lock.lock()
        generation &+= 1
        let previous = task
        task = nil; activePoll = nil; attempt = nil
        lock.unlock()
        previous?.cancel()
    }

    // One poll at a time. Cancelled/superseded completions are ignored and cannot
    // write Keychain. The UI owns polling cadence and cancellation presentation.
    public func poll(completion: @escaping (Result<TraceFoxBotLinkCredentials?, Error>) -> Void) throws {
        lock.lock()
        guard let attempt = attempt else { lock.unlock(); throw TraceFoxBotCoordinatorError.notStarted }
        guard activePoll == nil else { lock.unlock(); throw TraceFoxBotCoordinatorError.busy }
        let current = generation
        let pollId = UUID()
        activePoll = pollId
        lock.unlock()
        do {
            let newTask = try client.claim(attempt) { [weak self] result in
            guard let self = self else { return }
            self.lock.lock()
            guard self.generation == current, self.activePoll == pollId else { self.lock.unlock(); return }
            self.task = nil; self.activePoll = nil
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
            lock.lock()
            let keep = generation == current && activePoll == pollId
            if keep { task = newTask }
            lock.unlock()
            if !keep { newTask.cancel() }
        } catch {
            lock.lock()
            if generation == current && activePoll == pollId { activePoll = nil; task = nil }
            lock.unlock()
            throw error
        }
    }
}
