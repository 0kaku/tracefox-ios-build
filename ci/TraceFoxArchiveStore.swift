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
    public let ttlSeconds: Int32?
    public let previousTexts: [String]?

    public init(peer: Int64, namespace: Int32, message: Int32, timestamp: Int32,
                text: String, deleted: Bool, files: [String], ttlSeconds: Int32? = nil, previousTexts: [String]? = nil) {
        self.peer = peer; self.namespace = namespace; self.message = message
        self.timestamp = timestamp; self.text = text; self.deleted = deleted; self.files = files
        self.ttlSeconds = ttlSeconds
        self.previousTexts = previousTexts
    }
    fileprivate var key: String { return "\(peer)_\(namespace)_\(message)" }
}

public final class TraceFoxArchiveStore {
    private let root: URL
    private let manager = FileManager.default
    private let lock = NSRecursiveLock()
    private let maxFile: Int64 = 64 * 1024 * 1024
    private let maxTotal: Int64

    public init(root: URL, maxTotalBytes: Int64 = 1024 * 1024 * 1024) throws {
        guard maxTotalBytes > 0 else { throw CocoaError(.fileWriteOutOfSpace) }
        self.maxTotal = maxTotalBytes
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try manager.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: nil)
        var protectedRoot = self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(values)
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: self.root.path)
        #endif
    }

    private func usedBytes(excluding name: String? = nil) throws -> Int64 {
        var used: Int64 = 0
        for item in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where item.lastPathComponent != name {
            used += ((try manager.attributesOfItem(atPath: item.path))[.size] as? NSNumber)?.int64Value ?? 0
        }
        return used
    }

    private func file(_ name: String) throws -> URL {
        guard !name.isEmpty, name == (name as NSString).lastPathComponent,
              name != ".", name != ".." else { throw CocoaError(.fileReadInvalidFileName) }
        let value = root.appendingPathComponent(name).resolvingSymlinksInPath()
        // Directory URLs may differ only in their trailing-slash representation.
        // Compare canonical filesystem paths, while still rejecting symlink escapes.
        guard value.deletingLastPathComponent().path == root.path else { throw CocoaError(.fileReadNoPermission) }
        return value
    }

    // Hard-link before cleanup: unlinking Telegram's cache cannot remove our
    // independent name. copyItem handles a source on a different volume.
    public func retain(source: URL, peer: Int64, namespace: Int32, message: Int32, fileExtension: String = "bin") throws -> String {
        lock.lock(); defer { lock.unlock() }
        let resolved = source.resolvingSymlinksInPath()
        let attributes = try manager.attributesOfItem(atPath: resolved.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              size > 0, size <= maxFile else { throw CocoaError(.fileReadTooLarge) }
        let used = try usedBytes()
        guard used + size <= maxTotal else { throw CocoaError(.fileWriteOutOfSpace) }
        let proposed = fileExtension.lowercased()
        let ext = proposed.range(of: "^[a-z0-9]{1,8}$", options: .regularExpression) != nil ? proposed : "bin"
        let name = "\(peer)_\(namespace)_\(message)_\(UUID().uuidString).media.\(ext)"
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
        let name = record.key + ".json"
        guard try usedBytes(excluding: name) + Int64(data.count) <= maxTotal else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: file(name), options: .atomic)
    }

    // Only newly retained names from a failed capture belong here. They have
    // never been committed to a record; existing archive files are not passed.
    func discardUncommitted(_ names: [String]) {
        lock.lock(); defer { lock.unlock() }
        for name in names {
            guard let value = try? mediaURL(name: name) else { continue }
            try? manager.removeItem(at: value)
        }
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

    public func record(peer: Int64, namespace: Int32, message: Int32) throws -> TraceFoxArchiveRecord? {
        lock.lock(); defer { lock.unlock() }
        let path = try file("\(peer)_\(namespace)_\(message).json")
        guard manager.fileExists(atPath: path.path) else { return nil }
        return try JSONDecoder().decode(TraceFoxArchiveRecord.self, from: Data(contentsOf: path))
    }

    public func saveTextEdit(peer: Int64, namespace: Int32, message: Int32, timestamp: Int32,
                             previousText: String, updatedText: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard previousText != updatedText else { return }
        let existing = try record(peer: peer, namespace: namespace, message: message)
        var history = existing?.previousTexts ?? []
        if history.last != previousText { history.append(previousText) }
        var bytes = history.reduce(0) { $0 + $1.utf8.count }
        while history.count > 100 || bytes > 512 * 1024 {
            bytes -= history.removeFirst().utf8.count
        }
        try save(TraceFoxArchiveRecord(peer: peer, namespace: namespace, message: message,
            timestamp: timestamp, text: updatedText, deleted: existing?.deleted ?? false,
            files: [], ttlSeconds: existing?.ttlSeconds, previousTexts: history))
    }

    public func mediaURL(name: String) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        let value = try file(name)
        let isMedia = value.pathExtension == "media" || name.range(of: "\\.media\\.[a-z0-9]{1,8}$", options: .regularExpression) != nil
        guard manager.fileExists(atPath: value.path), isMedia else {
            throw CocoaError(.fileNoSuchFile)
        }
        return value
    }
}
