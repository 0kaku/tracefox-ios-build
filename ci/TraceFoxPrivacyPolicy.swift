import Foundation

// Pure policy only. This file does not by itself intercept Telegram traffic.
public enum TraceFoxPrivacyDecision: Equatable { case forward, forceOffline, suppress }

public enum TraceFoxPrivacyPolicy {
    private static let silentMethods: Set<String> = [
        "messages.setTyping", "messages.setEncryptedTyping",
        "messages.readHistory", "channels.readHistory", "messages.readEncryptedHistory",
        "messages.readMessageContents", "channels.readMessageContents",
        "messages.readMentions", "channels.readMentions", "messages.readReactions",
        "messages.readDiscussion", "stories.readStories", "stories.incrementStoryViews"
    ]

    public static func decision(enabled: Bool, function: String,
                                isSecretReadService: Bool = false) -> TraceFoxPrivacyDecision {
        guard enabled else { return .forward }
        if isSecretReadService { return .suppress }
        if function == "account.updateStatus" { return .forceOffline }
        return silentMethods.contains(function) ? .suppress : .forward
    }
}

public final class TraceFoxPrivacyPreferences {
    private struct Settings: Codable { let version: Int; let enabled: Bool }
    private let path: URL
    private let lock = NSLock()

    public init(accountRoot: URL) {
        path = accountRoot.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent("tracefox-privacy.json")
    }

    public func readEnabled() throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: path.path) else { return false }
        let value = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: path))
        guard value.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return value.enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        let data = try JSONEncoder().encode(Settings(version: 1, enabled: enabled))
        #if os(iOS)
        try data.write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: path, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        var privatePath = path
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try privatePath.setResourceValues(values)
    }
}
