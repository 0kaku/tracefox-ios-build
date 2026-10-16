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
            timestamp: 100, text: "Тест", deleted: true, files: [name], ttlSeconds: Int32.max))
        try manager.removeItem(at: source)
        let retained = try Data(contentsOf: folder.appendingPathComponent("owner-a").appendingPathComponent(name))
        precondition(retained == original)
        let exported = try first.mediaURL(name: name)
        precondition(tryData(exported) == original)
        let reopened = try TraceFoxArchiveStore(root: folder.appendingPathComponent("owner-a"))
        let records = try reopened.records()
        precondition(records.count == 1 && records[0].message == -7 && records[0].text == "Тест")
        precondition(records[0].ttlSeconds == Int32.max)
        let legacy = Data("{\"peer\":1,\"namespace\":0,\"message\":1,\"timestamp\":1,\"text\":\"old\",\"deleted\":false,\"files\":[]}".utf8)
        let old = try JSONDecoder().decode(TraceFoxArchiveRecord.self, from: legacy)
        precondition(old.ttlSeconds == nil)
        precondition(old.previousTexts == nil)
        precondition(old.globallyUniqueId == nil)
        for index in 0..<105 {
            try first.saveTextEdit(peer: 42, namespace: 0, message: 55, timestamp: 20,
                previousText: "v\(index)", updatedText: "v\(index + 1)")
        }
        let edited = try first.record(peer: 42, namespace: 0, message: 55)!
        precondition(edited.text == "v105" && edited.previousTexts?.count == 100)
        precondition(edited.previousTexts?.first == "v5" && edited.previousTexts?.last == "v104")
        try first.saveTextEdit(peer: 42, namespace: 0, message: 55, timestamp: 20,
            previousText: "v104", updatedText: "v105")
        let duplicate = try first.record(peer: 42, namespace: 0, message: 55)!
        precondition(duplicate.previousTexts == edited.previousTexts)
        let foreign = try second.records()
        precondition(foreign.isEmpty)
        let exact = try first.record(peer: -42, namespace: 0, message: -7)
        precondition(exact?.files == [name])
        try first.saveTextEdit(peer: -42, namespace: 0, message: -7, timestamp: 100,
            previousText: "����", updatedText: "Updated text")
        let updatedRetained = try first.record(peer: -42, namespace: 0, message: -7)!
        precondition(updatedRetained.files == [name] && updatedRetained.deleted && updatedRetained.ttlSeconds == Int32.max)
        let retainedAfterEdit = try first.mediaURL(name: name)
        precondition(tryData(retainedAfterEdit) == original)
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
        let quota = try TraceFoxArchiveStore(root: folder.appendingPathComponent("quota"), maxTotalBytes: 1200)
        let small = TraceFoxArchiveRecord(peer: 1, namespace: 0, message: 1, timestamp: 1,
            text: String(repeating: "x", count: 600), deleted: false, files: [])
        try quota.save(small)
        try quota.save(small) // Replacing the same record must not count it twice.
        do {
            try quota.save(TraceFoxArchiveRecord(peer: 1, namespace: 0, message: 2, timestamp: 2,
                text: String(repeating: "y", count: 600), deleted: false, files: []))
            fatalError("Text-only records bypassed archive quota")
        } catch {}
        let afterQuota = try quota.records()
        precondition(afterQuota.count == 1 && afterQuota[0].text == small.text)
        let rollbackSource = folder.appendingPathComponent("rollback-source")
        try Data(repeating: 7, count: 100).write(to: rollbackSource)
        let rollbackName = try quota.retain(source: rollbackSource, peer: 2, namespace: 0, message: 3)
        quota.discardUncommitted([rollbackName, "../private.media", "1_0_1.json"])
        do { _ = try quota.mediaURL(name: rollbackName); fatalError("Failed capture file leaked") } catch {}
        precondition(manager.fileExists(atPath: rollbackSource.path))
        let afterRollback = try quota.records()
        precondition(afterRollback.count == 1 && afterRollback[0].text == small.text)
        let quotaRoot = folder.appendingPathComponent("quota")
        try Data("not json".utf8).write(to: quotaRoot.appendingPathComponent("bad.json"))
        try Data(repeating: 32, count: 1024 * 1024 + 1).write(to: quotaRoot.appendingPathComponent("9_0_9.json"))
        try manager.createSymbolicLink(at: quotaRoot.appendingPathComponent("escape.json"), withDestinationURL: outside)
        let resilient = try quota.records()
        precondition(resilient.count == 1 && resilient[0].text == small.text)
        do { _ = try quota.record(peer: 9, namespace: 0, message: 9); fatalError("Oversized record read") } catch {}
        let paged = try TraceFoxArchiveStore(root: folder.appendingPathComponent("paged"))
        for id: Int32 in 1...205 {
            try paged.save(TraceFoxArchiveRecord(peer: 42, namespace: 0, message: id, timestamp: 100, text: "page", deleted: true, files: []))
        }
        let page1 = try paged.records()
        let page2 = try paged.records(before: TraceFoxArchiveCursor(record: page1.last!))
        let page3 = try paged.records(before: TraceFoxArchiveCursor(record: page2.last!))
        precondition(page1.count == 100 && page2.count == 100 && page3.count == 5)
        precondition(Set((page1 + page2 + page3).map { $0.message }).count == 205)
        print("PASS: independent media, persistence, signed IDs, owner isolation, path guards and text-record quota")
    }

    static func tryData(_ url: URL) -> Data { return (try? Data(contentsOf: url)) ?? Data() }
}
