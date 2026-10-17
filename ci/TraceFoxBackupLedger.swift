import Foundation
import CryptoKit

// Account-local durable acknowledgements. Local archive records remain the outbox
// until both message metadata and the retained file are acknowledged by the server.
public final class TraceFoxBackupLedger {
    private let path: URL
    private var sent: [String: String]
    private struct Retry: Codable { let digest: String; let after: TimeInterval }
    private let retryPath: URL
    private var retries: [String: Retry] = [:]
    public init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        path = root.appendingPathComponent("sent.json")
        retryPath = root.appendingPathComponent("retry.json")
        if FileManager.default.fileExists(atPath: retryPath.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: retryPath.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            retries = try JSONDecoder().decode([String: Retry].self, from: Data(contentsOf: retryPath))
        }
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
    public func eligible(_ record: TraceFoxArchiveRecord, now: Date = Date()) throws -> Bool {
        if try contains(record) { return false }
        guard let retry = retries[key(record)], retry.digest == (try digest(record)) else { return true }
        return retry.after <= now.timeIntervalSince1970
    }
    public func deferRecord(_ record: TraceFoxArchiveRecord, now: Date = Date()) throws {
        var next = retries.filter { $0.value.after > now.timeIntervalSince1970 }
        next[key(record)] = Retry(digest: try digest(record), after: now.timeIntervalSince1970 + 120)
        let data = try JSONEncoder().encode(next)
        guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        #if os(iOS)
        try data.write(to: retryPath, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: retryPath, options: .atomic)
        #endif
        retries = next
    }
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
