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
        let name = try first.retain(source: source, peer: -42, namespace: 0, message: -7, fileExtension: "JPG")
        precondition(name.hasSuffix(".media.jpg"))
        try first.save(TraceFoxArchiveRecord(peer: -42, namespace: 0, message: -7,
            timestamp: 100, text: "Тест", deleted: true, files: [name]))
        try manager.removeItem(at: source)
        let retained = try Data(contentsOf: folder.appendingPathComponent("owner-a").appendingPathComponent(name))
        precondition(retained == original)
        let exported = try first.mediaURL(name: name)
        precondition(tryData(exported) == original)
        let reopened = try TraceFoxArchiveStore(root: folder.appendingPathComponent("owner-a"))
        let records = try reopened.records()
        precondition(records.count == 1 && records[0].message == -7 && records[0].text == "Тест")
        let foreign = try second.records()
        precondition(foreign.isEmpty)
        let exact = try first.record(peer: -42, namespace: 0, message: -7)
        precondition(exact?.files == [name])
        let other = try second.record(peer: -42, namespace: 0, message: -7)
        precondition(other == nil)
        do {
            try first.save(TraceFoxArchiveRecord(peer: 1, namespace: 0, message: 1,
                timestamp: 100, text: "", deleted: true, files: ["../owner-b/private"]))
            fatalError("Traversal accepted")
        } catch {}
        let outside = folder.appendingPathComponent("private.media")
        try original.write(to: outside)
        let symlink = folder.appendingPathComponent("owner-a/escape.media")
        try manager.createSymbolicLink(at: symlink, withDestinationURL: outside)
        do {
            _ = try first.mediaURL(name: "escape.media")
            fatalError("Symlink escape accepted")
        } catch {}
        print("PASS: independent media after cache deletion, persistence, signed IDs, owner isolation and traversal rejection")
    }

    static func tryData(_ url: URL) -> Data { return (try? Data(contentsOf: url)) ?? Data() }
}
