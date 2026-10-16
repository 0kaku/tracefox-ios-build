import Foundation
import CryptoKit

// Account-local durable acknowledgements. Local archive records remain the outbox
// until both message metadata and the retained file are acknowledged by the server.
public final class TraceFoxBackupLedger {
    private let path: URL
    private var sent: [String: String]
    public init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        path = root.appendingPathComponent("sent.json")
        if FileManager.default.fileExists(atPath: path.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            sent = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: path))
        } else { sent = [:] }
    }
    private func key(_ record: TraceFoxArchiveRecord) -> String { "\(record.peer)_\(record.namespace)_\(record.message)" }
    private func digest(_ record: TraceFoxArchiveRecord) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(record)).map { String(format: "%02x", $0) }.joined()
    }
    public func contains(_ record: TraceFoxArchiveRecord) throws -> Bool { sent[key(record)] == (try digest(record)) }
    public func acknowledge(_ record: TraceFoxArchiveRecord) throws {
        var next = sent; next[key(record)] = try digest(record)
        let data = try JSONEncoder().encode(next)
        guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        #if os(iOS)
        try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: path, options: .atomic)
        #endif
        sent = next
    }
}
