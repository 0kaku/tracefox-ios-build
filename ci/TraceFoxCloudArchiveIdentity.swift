import Foundation

public struct TraceFoxCloudArchiveIdentity: Equatable {
    public let chatId: Int64
    public let messageId: Int32

    // Inputs are unpacked native peer/message components, never packed PeerId.toInt64().
    // Namespace values are pinned in SyncCore_Namespaces.swift at the source commit.
    // Secret/local/scheduled IDs deliberately have no mapping in this cloud-only adapter.
    public init?(peerNamespace: Int32, peerId: Int64, messageNamespace: Int32, messageId: Int32) {
        let backendLimit: Int64 = 1 << 52
        guard peerId > 0, peerId <= backendLimit, messageNamespace == 0, messageId > 0 else { return nil }
        switch peerNamespace {
        case 0: chatId = peerId
        case 1: chatId = -peerId
        case 2:
            guard peerId <= backendLimit - 1_000_000_000_000 else { return nil }
            chatId = -1_000_000_000_000 - peerId
        default: return nil
        }
        self.messageId = messageId
    }
}
