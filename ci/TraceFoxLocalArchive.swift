import Foundation
import Postbox

public enum TraceFoxLocalArchive {
    private static let lock = NSLock()
    private static var stores: [String: TraceFoxArchiveStore] = [:]

    public static func store(mediaBox: MediaBox) throws -> TraceFoxArchiveStore {
        let root = URL(fileURLWithPath: mediaBox.basePath).deletingLastPathComponent().appendingPathComponent("tracefox-archive")
        lock.lock(); defer { lock.unlock() }
        if let existing = stores[root.path] { return existing }
        let result = try TraceFoxArchiveStore(root: root)
        stores[root.path] = result
        return result
    }

    // Invoked before Telegram removes message rows or unlinks secret media.
    // Only completed local resources are retained; no network downloads or
    // session/secret-chat keys are serialized into this archive.
    static func captureDeleted(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
        guard let archive = try? store(mediaBox: mediaBox) else { return }
        for id in ids {
            if (try? archive.record(peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id)) != nil { continue }
            guard let message = transaction.getMessage(id) else { continue }
            var resources: [(MediaResource, String)] = []
            for media in message.media {
                if let image = media as? TelegramMediaImage {
                    if let largest = image.representations.max(by: {
                        Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height)
                    }) { resources.append((largest.resource, "jpg")) }
                } else if let file = media as? TelegramMediaFile {
                    let filenameExtension = ((file.fileName ?? "") as NSString).pathExtension
                    let fallback = ["video/mp4": "mp4", "image/jpeg": "jpg", "image/png": "png",
                        "audio/ogg": "ogg", "audio/mpeg": "mp3", "application/pdf": "pdf"][file.mimeType] ?? "bin"
                    resources.append((file.resource, filenameExtension.isEmpty ? fallback : filenameExtension))
                }
            }
            var names: [String] = []
            for (resource, ext) in resources {
                if let path = mediaBox.completedResourcePath(resource),
                   let name = try? archive.retain(source: URL(fileURLWithPath: path),
                        peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id, fileExtension: ext) {
                    names.append(name)
                }
            }
            try? archive.save(TraceFoxArchiveRecord(peer: id.peerId.toInt64(), namespace: id.namespace,
                message: id.id, timestamp: message.timestamp, text: message.text, deleted: true, files: names))
        }
    }
}
