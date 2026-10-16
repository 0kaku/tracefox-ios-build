import Foundation

public enum TraceFoxCloudArchiveEvent: String, Codable { case message, edited, deleted }
public enum TraceFoxCloudArchivePayloadError: Error { case invalidText, invalidTitle, invalidDate, invalidTTL, invalidIdentity }

// Mirrors the existing AndroidMessage backend schema. Encoding does not enqueue
// or transmit an event. Native callers must first derive a supported cloud identity.
public struct TraceFoxCloudArchivePayload: Codable, Equatable {
    public let chat_id: Int64
    public let message_id: Int32
    public let chat_type: String
    public let title: String
    public let text: String
    public let date: Int64
    public let temporary: Bool
    public let ttl_seconds: Int32?
    public let event: TraceFoxCloudArchiveEvent

    public init(identity: TraceFoxCloudArchiveIdentity, title: String = "Telegram", text: String,
                date: Int64, ttlSeconds: Int32? = nil, event: TraceFoxCloudArchiveEvent) throws {
        // Python/Pydantic string length counts Unicode scalar values, not Swift graphemes.
        guard text.unicodeScalars.count <= 16000 else { throw TraceFoxCloudArchivePayloadError.invalidText }
        guard title.unicodeScalars.count <= 255 else { throw TraceFoxCloudArchivePayloadError.invalidTitle }
        guard date >= 1, date <= 4_102_444_800 else { throw TraceFoxCloudArchivePayloadError.invalidDate }
        if let ttl = ttlSeconds, ttl < 0 { throw TraceFoxCloudArchivePayloadError.invalidTTL }
        chat_id = identity.chatId; message_id = identity.messageId; chat_type = identity.chatType
        self.title = title; self.text = text; self.date = date
        ttl_seconds = ttlSeconds; temporary = (ttlSeconds ?? 0) > 0; self.event = event
    }

    // Codable decoding can bypass the public validating initializer. Revalidate
    // persisted payloads before returning them from the queue or sending HTTP.
    public func validate() throws {
        guard chat_id >= -(1 << 52), chat_id <= (1 << 52) else { throw TraceFoxCloudArchivePayloadError.invalidIdentity }
        let namespace: Int32
        let peer: Int64
        switch chat_type {
        case "private": namespace = 0; peer = chat_id
        case "group": namespace = 1; peer = -chat_id
        case "channel": namespace = 2; peer = -chat_id - 1_000_000_000_000
        default: throw TraceFoxCloudArchivePayloadError.invalidIdentity
        }
        guard let identity = TraceFoxCloudArchiveIdentity(peerNamespace: namespace, peerId: peer, messageNamespace: 0, messageId: message_id) else {
            throw TraceFoxCloudArchivePayloadError.invalidIdentity
        }
        let checked = try TraceFoxCloudArchivePayload(identity: identity, title: title, text: text, date: date, ttlSeconds: ttl_seconds, event: event)
        guard checked == self else { throw TraceFoxCloudArchivePayloadError.invalidIdentity }
    }
}
