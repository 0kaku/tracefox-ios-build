import Foundation

public enum TraceFoxPrivacyRuntime {
    public static func preferences(network: Network) -> TraceFoxPrivacyPreferences {
        return TraceFoxPrivacyPreferences(accountRoot: URL(fileURLWithPath: network.basePath))
    }

    static func decision(network: Network, function: String,
                         isSecretReadService: Bool = false) -> TraceFoxPrivacyDecision {
        let enabled: Bool
        do { enabled = try preferences(network: network).readEnabled() }
        catch { enabled = true } // A corrupt saved setting must not silently reveal presence.
        return TraceFoxPrivacyPolicy.decision(enabled: enabled, function: function,
            isSecretReadService: isSecretReadService)
    }
}
