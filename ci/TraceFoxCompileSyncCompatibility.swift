// Compile-test compatibility for missing declarations in the pinned upstream.
// Not a TraceFox sync implementation. No server or credential is configured.
import Foundation

public extension SGSimpleSettings {
    var darkgramSyncEnabled: Bool { false }
    var darkgramSyncServerURL: String { "" }
    var darkgramSyncServerToken: String { "" }
    var darkgramSyncUseSecureConnection: Bool { true }

    var darkgramSyncDeviceIdentifier: String {
        get { UserDefaults.standard.string(forKey: "tracefox.buildtest.sync.device") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "tracefox.buildtest.sync.device") }
    }
    var darkgramSyncConnectionState: String {
        get { UserDefaults.standard.string(forKey: "tracefox.buildtest.sync.state") ?? "disabled" }
        set { UserDefaults.standard.set(newValue, forKey: "tracefox.buildtest.sync.state") }
    }
    var darkgramSyncRegisterStatusCode: Int32 {
        get { (UserDefaults.standard.object(forKey: "tracefox.buildtest.sync.status") as? NSNumber)?.int32Value ?? 0 }
        set { UserDefaults.standard.set(NSNumber(value: newValue), forKey: "tracefox.buildtest.sync.status") }
    }
    var darkgramSyncLastSentAt: Int64 {
        get { (UserDefaults.standard.object(forKey: "tracefox.buildtest.sync.sent") as? NSNumber)?.int64Value ?? 0 }
        set { UserDefaults.standard.set(NSNumber(value: newValue), forKey: "tracefox.buildtest.sync.sent") }
    }
    var darkgramSyncLastReceivedAt: Int64 {
        get { (UserDefaults.standard.object(forKey: "tracefox.buildtest.sync.received") as? NSNumber)?.int64Value ?? 0 }
        set { UserDefaults.standard.set(NSNumber(value: newValue), forKey: "tracefox.buildtest.sync.received") }
    }
}
