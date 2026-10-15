public enum Api {
    public enum Bool: Equatable { case boolTrue, boolFalse }
    public struct OfflineRequest { public let offline: Bool }
    public enum functions {
        public enum account {
            public static func updateStatus(offline: Bool) -> OfflineRequest { return OfflineRequest(offline: offline) }
        }
    }
}
