// Native Network.basePath is account-scoped and module-internal in TelegramCore.
#if CONTROL_TEST
import SwiftSignalKit
import TelegramApi
#endif
public final class Network {
    let basePath: String
    public init(basePath: String) { self.basePath = basePath }
    #if CONTROL_TEST
    var requests = 0
    var failRequest = false
    var wasEnabledBeforeRequest = false
    func request(_ request: Api.OfflineRequest, automaticFloodWait: Bool) -> Signal<Api.Bool, TestNetworkError> {
        requests += 1
        precondition(request.offline == .boolTrue && !automaticFloodWait)
        wasEnabledBeforeRequest = (try? TraceFoxPrivacyRuntime.preferences(network: self).readEnabled()) == true
        return Signal { subscriber in
            if self.failRequest { subscriber.putError(.failed) }
            else { subscriber.putNext(.boolTrue); subscriber.putCompletion() }
            return EmptyDisposable
        }
    }
    #endif
}
#if CONTROL_TEST
enum TestNetworkError { case failed }
#endif
