import Foundation

public enum TraceFoxCloudQueueError: Error { case invalidState, full, wrongHead }
public struct TraceFoxCloudQueueEntry: Codable {
    public let id: UUID
    public let payload: TraceFoxCloudArchivePayload
}

// Account-specific durable FIFO. Nothing is sent automatically. A caller may
// acknowledge only the current head after a positive server acknowledgement.
public final class TraceFoxCloudArchiveQueue {
    private struct State: Codable { var version = 1; var entries: [TraceFoxCloudQueueEntry] = [] }
    private let root: URL
    private let maxEntries: Int
    private let maxBytes: Int
    private let lock = NSLock()

    public init(root: URL, maxEntries: Int = 1000, maxBytes: Int = 32 * 1024 * 1024) throws {
        guard maxEntries > 0, maxBytes > 0 else { throw TraceFoxCloudQueueError.full }
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.maxEntries = maxEntries; self.maxBytes = maxBytes
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var url = self.root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func path() throws -> URL {
        let path = root.appendingPathComponent("pending.json").resolvingSymlinksInPath()
        guard path.deletingLastPathComponent().path == root.path else { throw TraceFoxCloudQueueError.invalidState }
        return path
    }

    private func read() throws -> State {
        let file = try path()
        guard FileManager.default.fileExists(atPath: file.path) else { return State() }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = (attributes[.size] as? NSNumber)?.intValue, size <= maxBytes else { throw TraceFoxCloudQueueError.invalidState }
        let data = try Data(contentsOf: file)
        guard data.count <= maxBytes, let state = try? JSONDecoder().decode(State.self, from: data),
              state.version == 1, state.entries.count <= maxEntries else { throw TraceFoxCloudQueueError.invalidState }
        return state
    }

    private func write(_ state: State) throws {
        let data = try JSONEncoder().encode(state)
        guard state.entries.count <= maxEntries, data.count <= maxBytes else { throw TraceFoxCloudQueueError.full }
        #if os(iOS)
        try data.write(to: path(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: path(), options: .atomic)
        #endif
    }

    public func first() throws -> TraceFoxCloudQueueEntry? {
        lock.lock(); defer { lock.unlock() }
        return try read().entries.first
    }

    @discardableResult public func enqueue(_ payload: TraceFoxCloudArchivePayload) throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        var state = try read()
        if let last = state.entries.last, last.payload == payload { return last.id }
        let entry = TraceFoxCloudQueueEntry(id: UUID(), payload: payload)
        state.entries.append(entry)
        try write(state)
        return entry.id
    }

    public func acknowledge(_ id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        var state = try read()
        guard state.entries.first?.id == id else { throw TraceFoxCloudQueueError.wrongHead }
        state.entries.removeFirst()
        try write(state)
    }
}
