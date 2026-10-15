import Foundation

public enum TraceFoxPrivacyRuntime {
    public static func preferences(network: Network) -> TraceFoxPrivacyPreferences {
        return TraceFoxPrivacyPreferences(accountRoot: URL(fileURLWithPath: network.basePath))
    }

    static func decision(network: Network, function: String,
                         isSecretReadService: Bool = false) -> TraceFoxPrivacyDecision {
        return decision(accountRoot: URL(fileURLWithPath: network.basePath), function: function,
            isSecretReadService: isSecretReadService)
    }

    static func decision(mediaBoxPath: String, function: String) -> TraceFoxPrivacyDecision {
        // Pinned Postbox uses <account>/postbox/media; Network uses <account>.
        let root = URL(fileURLWithPath: mediaBoxPath).deletingLastPathComponent().deletingLastPathComponent()
        return decision(accountRoot: root, function: function)
    }

    private static func decision(accountRoot: URL, function: String,
                                  isSecretReadService: Bool = false) -> TraceFoxPrivacyDecision {
        let enabled: Bool
        do { enabled = try TraceFoxPrivacyPreferences(accountRoot: accountRoot).readEnabled() }
        catch { enabled = true } // A corrupt saved setting must not silently reveal presence.
        return TraceFoxPrivacyPolicy.decision(enabled: enabled, function: function,
            isSecretReadService: isSecretReadService)
    }
}
