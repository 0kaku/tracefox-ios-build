import Foundation

// Foundation-only storage. Callers supply an account-specific root and freeze
// available media before Telegram schedules deletion. No transport keys or
// Telegram session data belong in these records.
public struct TraceFoxArchiveRecord: Codable {
    public let peer: Int64
    public let namespace: Int32
    public let message: Int32
    public let timestamp: Int32
    public let text: String
    public let deleted: Bool
    public let files: [String]

    public init(peer: Int64, namespace: Int32, message: Int32, timestamp: Int32,
                text: String, deleted: Bool, files: [String]) {
        self.peer = peer; self.namespace = namespace; self.message = message
        self.timestamp = timestamp; self.text = text; self.deleted = deleted; self.files = files
    }
    fileprivate var key: String { return "\(peer)_\(namespace)_\(message)" }
}

public final class TraceFoxArchiveStore {
    private let root: URL
    private let manager = FileManager.default
    private let lock = NSRecursiveLock()
    private let maxFile: Int64 = 64 * 1024 * 1024
    private let maxTotal: Int64 = 1024 * 1024 * 1024

    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try manager.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: nil)
    }

    private func file(_ name: String) throws -> URL {
        guard !name.isEmpty, name == (name as NSString).lastPathComponent,
              name != ".", name != ".." else { throw CocoaError(.fileReadInvalidFileName) }
        let value = root.appendingPathComponent(name).resolvingSymlinksInPath()
        guard value.deletingLastPathComponent() == root else { throw CocoaError(.fileReadNoPermission) }
        return value
    }

    // Hard-link before cleanup: unlinking Telegram's cache cannot remove our
    // independent name. copyItem handles a source on a different volume.
    public func retain(source: URL, peer: Int64, namespace: Int32, message: Int32) throws -> String {
        lock.lock(); defer { lock.unlock() }
        let resolved = source.resolvingSymlinksInPath()
        let attributes = try manager.attributesOfItem(atPath: resolved.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              size > 0, size <= maxFile else { throw CocoaError(.fileReadTooLarge) }
        var used: Int64 = 0
        for item in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            if item.pathExtension == "media" {
                used += ((try manager.attributesOfItem(atPath: item.path))[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        guard used + size <= maxTotal else { throw CocoaError(.fileWriteOutOfSpace) }
        let name = "\(peer)_\(namespace)_\(message)_\(UUID().uuidString).media"
        let target = try file(name)
        do { try manager.linkItem(at: resolved, to: target) }
        catch { try manager.copyItem(at: resolved, to: target) }
        return name
    }

    public func save(_ record: TraceFoxArchiveRecord) throws {
        lock.lock(); defer { lock.unlock() }
        for name in record.files {
            let value = try file(name)
            guard manager.fileExists(atPath: value.path) else { throw CocoaError(.fileNoSuchFile) }
        }
        let data = try JSONEncoder().encode(record)
        guard data.count <= 1024 * 1024 else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        try data.write(to: file(record.key + ".json"), options: .atomic)
    }

    public func records(limit: Int = 100) throws -> [TraceFoxArchiveRecord] {
        lock.lock(); defer { lock.unlock() }
        var records: [TraceFoxArchiveRecord] = []
        for item in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where item.pathExtension == "json" {
            let path = try file(item.lastPathComponent)
            let data = try Data(contentsOf: path)
            guard data.count <= 1024 * 1024 else { continue }
            if let value = try? JSONDecoder().decode(TraceFoxArchiveRecord.self, from: data) { records.append(value) }
        }
        return Array(records.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp > $1.timestamp }
            return $0.key > $1.key
        }.prefix(max(0, min(limit, 100))))
    }
}
