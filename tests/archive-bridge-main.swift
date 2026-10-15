import Foundation
import Postbox

@main struct ArchiveBridgeTest {
    static func main() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: folder) }
        let box = MediaBox(basePath: folder.appendingPathComponent("owner-a/media").path)
        let foreign = MediaBox(basePath: folder.appendingPathComponent("owner-b/media").path)
        let tx = Transaction()
        let id = MessageId(peerId: PeerId(1 << 62), namespace: 0, id: -19)
        let image = TelegramMediaImage([
            FixtureImageRepresentation(dimensions: FixtureDimensions(width: 120, height: 120), resource: FixtureResource(fixtureKey: "small")),
            FixtureImageRepresentation(dimensions: FixtureDimensions(width: 1200, height: 1200), resource: FixtureResource(fixtureKey: "large-missing"))
        ])
        tx.messages[id] = Message(timestamp: 10, text: "secret photo", media: [image],
            attributes: [AutoclearTimeoutMessageAttribute(30), AutoremoveTimeoutMessageAttribute(Int32.max)])
        TraceFoxLocalArchive.captureAvailable(transaction: tx, mediaBox: box, ids: [id])
        let store = try TraceFoxLocalArchive.store(mediaBox: box)
        let metadata = try store.record(peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id)
        precondition(metadata != nil && metadata!.files.isEmpty && !metadata!.deleted)

        let cache = folder.appendingPathComponent("cache.jpg")
        let bytes = Data((0..<70003).map { UInt8($0 % 241) })
        try bytes.write(to: cache)
        box.completed["small"] = cache.path
        TraceFoxLocalArchive.captureAvailable(transaction: tx, mediaBox: box, ids: [id])
        let saved = try store.record(peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id)!
        precondition(saved.files.count == 1 && saved.ttlSeconds == Int32.max && !saved.deleted)
        let url = try store.mediaURL(name: saved.files[0])
        let copied = try Data(contentsOf: url)
        precondition(copied == bytes && url.pathExtension == "jpg")

        // If the retained file disappeared but the source is still available,
        // retry capture instead of treating the old JSON pointer as a saved file.
        try fm.removeItem(at: url)
        TraceFoxLocalArchive.captureAvailable(transaction: tx, mediaBox: box, ids: [id])
        let recovered = try store.record(peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id)!
        precondition(recovered.files.count == 1 && recovered.files != saved.files)
        try fm.removeItem(at: cache)
        box.completed.removeAll()
        tx.messages.removeAll()
        TraceFoxLocalArchive.captureDeleted(transaction: tx, mediaBox: box, ids: [id])
        TraceFoxLocalArchive.captureDeleted(transaction: tx, mediaBox: box, ids: [id])
        let deleted = try store.record(peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id)!
        precondition(deleted.deleted && deleted.files == recovered.files && deleted.text == "secret photo")
        let retained = try Data(contentsOf: store.mediaURL(name: deleted.files[0]))
        precondition(retained == bytes)
        let other = try TraceFoxLocalArchive.store(mediaBox: foreign).records()
        precondition(other.isEmpty)
        print("PASS: actual Swift capture bridge: incomplete retry, available photo size, one-view precedence, missing-file recovery, read-to-delete transition, duplicate events and account isolation")
    }
}
