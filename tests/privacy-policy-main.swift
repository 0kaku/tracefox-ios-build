import Foundation

@main struct PrivacyPolicyTest {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = TraceFoxPrivacyPreferences(accountRoot: folder.appendingPathComponent("account-a"))
        let second = TraceFoxPrivacyPreferences(accountRoot: folder.appendingPathComponent("account-b"))
        let initial = try first.readEnabled(); precondition(!initial)
        try first.setEnabled(true)
        let enabled = try TraceFoxPrivacyPreferences(accountRoot: folder.appendingPathComponent("account-a")).readEnabled()
        let foreign = try second.readEnabled(); precondition(enabled && !foreign)
        for method in ["messages.readHistory", "channels.readHistory", "messages.readEncryptedHistory",
                       "messages.readMessageContents", "channels.readMessageContents", "messages.readMentions",
                       "messages.readReactions", "messages.readDiscussion", "messages.setTyping",
                       "messages.setEncryptedTyping", "stories.readStories"] {
            precondition(TraceFoxPrivacyPolicy.decision(enabled: true, function: method) == .suppress)
            precondition(TraceFoxPrivacyPolicy.decision(enabled: false, function: method) == .forward)
        }
        precondition(TraceFoxPrivacyPolicy.decision(enabled: true, function: "account.updateStatus") == .forceOffline)
        precondition(TraceFoxPrivacyPolicy.decision(enabled: true, function: "messages.sendEncryptedService", isSecretReadService: true) == .suppress)
        for method in ["messages.sendMessage", "messages.sendEncrypted", "messages.sendEncryptedService",
                       "upload.getFile", "auth.sendCode", "auth.signIn", "phone.requestCall", "messages.getHistory"] {
            precondition(TraceFoxPrivacyPolicy.decision(enabled: true, function: method) == .forward)
        }
        try first.setEnabled(false)
        let disabled = try first.readEnabled(); precondition(!disabled)
        let file = folder.appendingPathComponent("account-a/tracefox-privacy.json")
        try Data("invalid".utf8).write(to: file)
        do { _ = try first.readEnabled(); fatalError("Corrupt setting silently accepted") } catch {}
        print("PASS: pure ghost policy, disabled defaults, persistent per-account settings, read/typing/offline decisions, normal messaging/download/auth/calls unchanged; no transport integration claimed")
    }
}
