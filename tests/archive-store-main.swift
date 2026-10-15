import Foundation

@main struct ArchiveStoreTest {
    static func main() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: folder) }
        let first = try TraceFoxArchiveStore(root: folder.appendingPathComponent("owner-a"))
        let second = try TraceFoxArchiveStore(root: folder.appendingPathComponent("owner-b"))
        let source = folder.appendingPathComponent("telegram-cache")
        let original = Data((0..<131103).map { UInt8($0 % 251) })
        try original.write(to: source)
        let name = try first.retain(source: source, peer: -42, namespace: 0, message: -7)
        try first.save(TraceFoxArchiveRecord(peer: -42, namespace: 0, message: -7,
            timestamp: 100, text: "Тест", deleted: true, files: [name]))
        try manager.removeItem(at: source)
        let retained = try Data(contentsOf: folder.appendingPathComponent("owner-a").appendingPathComponent(name))
        precondition(retained == original)
        let reopened = try TraceFoxArchiveStore(root: folder.appendingPathComponent("owner-a"))
        let records = try reopened.records()
        precondition(records.count == 1 && records[0].message == -7 && records[0].text == "Тест")
        let foreign = try second.records()
        precondition(foreign.isEmpty)
        do {
            try first.save(TraceFoxArchiveRecord(peer: 1, namespace: 0, message: 1,
                timestamp: 100, text: "", deleted: true, files: ["../owner-b/private"]))
            fatalError("Traversal accepted")
        } catch {}
        print("PASS: independent media after cache deletion, persistence, signed IDs, owner isolation and traversal rejection")
    }
}
