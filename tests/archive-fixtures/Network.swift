// Native Network.basePath is account-scoped and module-internal in TelegramCore.
public final class Network {
    let basePath: String
    public init(basePath: String) { self.basePath = basePath }
}
