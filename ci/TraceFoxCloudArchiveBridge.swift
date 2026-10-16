import Foundation
import Postbox

public enum TraceFoxCloudArchiveBridge {
    // Converts native cloud messages only. Does not enqueue or transmit content.
    public static func payload(message: Message, title: String = "Telegram",
                               event: TraceFoxCloudArchiveEvent) throws -> TraceFoxCloudArchivePayload? {
        let peer = message.id.peerId
        let namespace = peer.namespace._internalGetInt32Value()
        let peerId = peer.id._internalGetInt64Value()
        guard let identity = TraceFoxCloudArchiveIdentity(peerNamespace: namespace, peerId: peerId,
            messageNamespace: message.id.namespace, messageId: message.id.id) else { return nil }
        // Authentication notifications and pairing commands never enter cloud events.
        guard !(namespace == 0 && peerId == 777000), !message.text.hasPrefix("/android_link ") else { return nil }
        var ttl: Int32?
        for attribute in message.attributes {
            let candidate: Int32?
            if let value = attribute as? AutoremoveTimeoutMessageAttribute { candidate = value.timeout }
            else if let value = attribute as? AutoclearTimeoutMessageAttribute { candidate = value.timeout }
            else { candidate = nil }
            if let value = candidate, value > 0 {
                if value == Int32.max { ttl = value; break }
                if ttl == nil { ttl = value }
            }
        }
        return try TraceFoxCloudArchivePayload(identity: identity, title: title, text: message.text,
            date: Int64(message.timestamp), ttlSeconds: ttl, event: event)
    }
}
