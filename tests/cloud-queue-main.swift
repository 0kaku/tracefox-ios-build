import Foundation

@main struct CloudQueueTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = TraceFoxCloudArchiveIdentity(peerNamespace: 0, peerId: 42, messageNamespace: 0, messageId: 7)!
        let a = try TraceFoxCloudArchivePayload(identity: identity, text: "a", date: 100, event: .message)
        let b = try TraceFoxCloudArchivePayload(identity: identity, text: "b", date: 100, event: .edited)
        let queue = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("a"), maxEntries: 2)
        let emptyCount = try queue.pendingCount()
        precondition(emptyCount == 0)
        let firstId = try queue.enqueue(a)
        let duplicateId = try queue.enqueue(a)
        precondition(firstId == duplicateId)
        let secondId = try queue.enqueue(b)
        let queuedCount = try queue.pendingCount()
        precondition(queuedCount == 2) // adjacent duplicates must not inflate the UI backlog
        do { _ = try queue.enqueue(a); fatalError("Quota bypassed") } catch {}
        do { try queue.acknowledge(secondId); fatalError("Out-of-order acknowledgement accepted") } catch {}
        let reopened = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("a"), maxEntries: 2)
        let first = try reopened.first()
        precondition(first?.id == firstId && first?.payload == a)
        try reopened.acknowledge(firstId)
        let acknowledgedCount = try queue.pendingCount()
        precondition(acknowledgedCount == 1) // another instance must see the persisted acknowledgement
        let next = try reopened.first()
        precondition(next?.id == secondId)
        let thirdId = try reopened.enqueue(a) // a -> b -> a must not lose the last edit.
        precondition(thirdId != firstId)
        let foreign = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("b"))
        let foreignFirst = try foreign.first()
        precondition(foreignFirst == nil)
        try Data("broken".utf8).write(to: root.appendingPathComponent("a/pending.json"))
        do { _ = try reopened.first(); fatalError("Corrupt queue silently reset") } catch {}
        do { _ = try reopened.pendingCount(); fatalError("Corrupt queue displayed as empty") } catch {}
        let writerA = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("concurrent"))
        let writerB = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("concurrent"))
        let errorLock = NSLock()
        var errors = 0
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            do {
                let item = try TraceFoxCloudArchivePayload(identity: identity, text: "item\(index)", date: 100, event: .edited)
                try (index % 2 == 0 ? writerA : writerB).enqueue(item)
            } catch { errorLock.lock(); errors += 1; errorLock.unlock() }
        }
        precondition(errors == 0)
        var texts = Set<String>()
        while let item = try writerA.first() {
            texts.insert(item.payload.text)
            try writerB.acknowledge(item.id)
        }
        precondition(texts.count == 30)
        let validQueue = try TraceFoxCloudArchiveQueue(root: root.appendingPathComponent("invalid-payload"))
        try validQueue.enqueue(a)
        let statePath = root.appendingPathComponent("invalid-payload/pending.json")
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: statePath)) as! [String: Any]
        var entries = state["entries"] as! [[String: Any]]
        var invalid = entries[0]["payload"] as! [String: Any]
        invalid["message_id"] = 0
        entries[0]["payload"] = invalid; state["entries"] = entries
        try JSONSerialization.data(withJSONObject: state).write(to: statePath)
        do { _ = try validQueue.first(); fatalError("Invalid persisted payload accepted") } catch {}
        print("PASS: durable FIFO/reopen, adjacent duplicate coalescing, ordered acknowledgement, quota, account isolation and corruption errors; no network")
        print("PASS: concurrent writers across two queue instances preserve all 30 distinct events")
    }
}
