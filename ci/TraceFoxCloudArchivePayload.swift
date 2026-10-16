import Foundation

public enum TraceFoxCloudArchiveEvent: String, Codable { case message, edited, deleted }
public enum TraceFoxCloudArchivePayloadError: Error { case invalidText, invalidTitle, invalidDate, invalidTTL }

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
}
