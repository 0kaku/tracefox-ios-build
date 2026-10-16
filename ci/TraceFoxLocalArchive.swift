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
        capture(transaction: transaction, mediaBox: mediaBox, ids: ids, deleted: true)
    }

    static func captureAvailable(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId]) {
        capture(transaction: transaction, mediaBox: mediaBox, ids: ids, deleted: false)
    }

    private static func lifetime(_ message: Message) -> Int32? {
        var ttl: Int32?
        for attribute in message.attributes {
            let candidate: Int32?
            if let value = attribute as? AutoremoveTimeoutMessageAttribute { candidate = value.timeout }
            else if let value = attribute as? AutoclearTimeoutMessageAttribute { candidate = value.timeout }
            else { candidate = nil }
            if let candidate = candidate, candidate > 0 {
                if candidate == viewOnceTimeout { ttl = candidate; break }
                if ttl == nil { ttl = candidate }
            }
        }
        return ttl
    }

    // Initial edit-history support is deliberately limited to plain text messages.
    // Attachment/caption edits need resource identity and media-revision tracking.
    static func captureTextEdit(transaction: Transaction, mediaBox: MediaBox, id: MessageId,
                                updatedText: String, updatedHasMedia: Bool) {
        guard !updatedHasMedia, let message = transaction.getMessage(id), message.media.isEmpty,
              let archive = try? store(mediaBox: mediaBox) else { return }
        try? archive.saveTextEdit(peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id,
            timestamp: message.timestamp, previousText: message.text, updatedText: updatedText,
            globallyUniqueId: message.globallyUniqueId, ttlSeconds: lifetime(message))
    }

    private static func capture(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], deleted: Bool) {
        guard let archive = try? store(mediaBox: mediaBox) else { return }
        for id in ids {
            let previous = try? archive.record(peer: id.peerId.toInt64(), namespace: id.namespace, message: id.id)
            if let previous = previous, !previous.files.isEmpty,
               previous.files.allSatisfy({ (try? archive.mediaURL(name: $0)) != nil }) {
                if deleted && !previous.deleted {
                    try? archive.save(TraceFoxArchiveRecord(peer: previous.peer, namespace: previous.namespace,
                        message: previous.message, timestamp: previous.timestamp, text: previous.text,
                        deleted: true, files: previous.files, ttlSeconds: previous.ttlSeconds, previousTexts: previous.previousTexts,
                        globallyUniqueId: previous.globallyUniqueId))
                }
                continue
            }
            guard let message = transaction.getMessage(id) else { continue }
            let ttl = lifetime(message)
            var resources: [(MediaResource, String)] = []
            for media in message.media {
                if let image = media as? TelegramMediaImage {
                    if let largest = image.representations.filter({ mediaBox.completedResourcePath($0.resource) != nil }).max(by: {
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
            do {
                try archive.save(TraceFoxArchiveRecord(peer: id.peerId.toInt64(), namespace: id.namespace,
                    message: id.id, timestamp: message.timestamp, text: message.text,
                    deleted: deleted || (previous?.deleted ?? false), files: names,
                    ttlSeconds: ttl ?? previous?.ttlSeconds, previousTexts: previous?.previousTexts,
                    globallyUniqueId: message.globallyUniqueId ?? previous?.globallyUniqueId))
            } catch {
                archive.discardUncommitted(names)
            }
        }
    }
}
