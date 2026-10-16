import Foundation

@main struct CloudQueueTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = TraceFoxCloudArchiveIdentity(peerNamespace: 0, peerId: 42, messageNamespace: 0, messageId: 7)!
        let a = try TraceFoxCloudArchivePayload(identity: identity, text: "a", date: 100, event: .message)
        let b = try TraceFoxCloudArchivePayload(identity: identity, text: "b", date: 100, event: .edited)
        let queue = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("a"), maxEntries: 2)
        let firstId = try queue.enqueue(a)
        let duplicateId = try queue.enqueue(a)
        precondition(firstId == duplicateId)
        let secondId = try queue.enqueue(b)
        do { _ = try queue.enqueue(a); fatalError("Quota bypassed") } catch {}
        do { try queue.acknowledge(secondId); fatalError("Out-of-order acknowledgement accepted") } catch {}
        let reopened = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("a"), maxEntries: 2)
        let first = try reopened.first()
        precondition(first?.id == firstId && first?.payload == a)
        try reopened.acknowledge(firstId)
        let next = try reopened.first()
        precondition(next?.id == secondId)
        let thirdId = try reopened.enqueue(a) // a -> b -> a must not lose the last edit.
        precondition(thirdId != firstId)
        let foreign = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("b"))
        let foreignFirst = try foreign.first()
        precondition(foreignFirst == nil)
        try Data("broken".utf8).write(to: root.appendingPathComponent("a/pending.json"))
        do { _ = try reopened.first(); fatalError("Corrupt queue silently reset") } catch {}
        print("PASS: durable FIFO/reopen, adjacent duplicate coalescing, ordered acknowledgement, quota, account isolation and corruption errors; no network")
    }
}
