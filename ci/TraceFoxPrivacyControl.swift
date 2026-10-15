import Foundation
import SwiftSignalKit
import TelegramApi

public enum TraceFoxPrivacyControlError: Error {
    case settingsWriteFailed
    case offlineUpdateFailed
}

public enum TraceFoxPrivacyControl {
    // Subscribe and retain the returned disposable until completion. A failed
    // offline update leaves the persisted privacy protection enabled.
    public static func setEnabled(_ enabled: Bool, network: Network) -> Signal<Never, TraceFoxPrivacyControlError> {
        return Signal { subscriber in
            do {
                try TraceFoxPrivacyRuntime.preferences(network: network).setEnabled(enabled)
            } catch {
                subscriber.putError(.settingsWriteFailed)
                return EmptyDisposable
            }
            guard enabled else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            return network.request(Api.functions.account.updateStatus(offline: .boolTrue), automaticFloodWait: false).start(next: { _ in
            }, error: { _ in
                subscriber.putError(.offlineUpdateFailed)
            }, completed: {
                subscriber.putCompletion()
            })
        }
    }
}
