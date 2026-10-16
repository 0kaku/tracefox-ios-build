import Foundation

private final class TestTask: TraceFoxBotClaimTask {
    var cancelled = false
    func cancel() { cancelled = true }
}
private final class TestSubmitter: TraceFoxCloudSubmitting {
    var replies: [(Result<Int64, Error>) -> Void] = []
    var tasks: [TestTask] = []
    func submit(_ payload: TraceFoxCloudArchivePayload, credentials: TraceFoxBotLinkCredentials, completion: @escaping (Result<Int64, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        let task = TestTask(); tasks.append(task); replies.append(completion); return task
    }
}
@main struct CloudSenderTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let queue = try TraceFoxCloudArchiveQueue(root: root)
        let identity = TraceFoxCloudArchiveIdentity(peerNamespace: 0, peerId: 99, messageNamespace: 0, messageId: 7)!
        let payload = try TraceFoxCloudArchivePayload(identity: identity, text: "synthetic", date: 100, event: .deleted)
        let firstId = try queue.enqueue(payload)
        let client = TestSubmitter()
        let sender = TraceFoxCloudArchiveSender(queue: queue, client: client, ownerId: 42)
        let credential = TraceFoxBotLinkCredentials(ownerId: 42, token: String(repeating: "a", count: 43), archiveAvailable: true)
        try sender.sendNext(credentials: credential) { _ in }
        client.replies[0](.failure(TraceFoxBotLinkClientError.transport))
        let retained = try queue.first(); precondition(retained?.id == firstId)
        try sender.sendNext(credentials: credential) { _ in }
        sender.cancel(); precondition(client.tasks[1].cancelled)
        client.replies[1](.success(99))
        let cancelled = try queue.first(); precondition(cancelled?.id == firstId)
        try sender.sendNext(credentials: credential) { _ in }
        client.replies[2](.success(0))
        let badAck = try queue.first(); precondition(badAck?.id == firstId)
        try sender.sendNext(credentials: credential) { _ in }
        client.replies[3](.success(99))
        let empty = try queue.first(); precondition(empty == nil)
        let second = try queue.enqueue(payload)
        client.replies[3](.success(99))
        let duplicate = try queue.first(); precondition(duplicate?.id == second)
        let foreign = TraceFoxBotLinkCredentials(ownerId: 43, token: credential.token, archiveAvailable: true)
        do { try sender.sendNext(credentials: foreign) { _ in }; fatalError("Foreign owner sent queue") } catch {}
        for status in [401, 403] {
            var receivedStatus: Int?
            try sender.sendNext(credentials: credential) { result in
                if case let .failure(error) = result,
                   case let .httpStatus(code)? = error as? TraceFoxBotLinkClientError { receivedStatus = code }
            }
            client.replies.last?(.failure(TraceFoxBotLinkClientError.httpStatus(status)))
            let pending = try queue.first()
            precondition(receivedStatus == status && pending?.id == second)
        }
        // A renewed credential can retry the same durable event after authorization failure.
        let renewed = TraceFoxBotLinkCredentials(ownerId: 42, token: String(repeating: "b", count: 43), archiveAvailable: true)
        try sender.sendNext(credentials: renewed) { _ in }
        client.replies.last?(.success(100))
        let retried = try queue.first(); precondition(retried == nil)
        print("PASS: queue-to-submit acknowledgement, failure/cancel retention, invalid/duplicate acknowledgement and owner rejection; fake transport only")
    }
}
