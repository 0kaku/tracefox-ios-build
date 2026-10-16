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

// Secret random IDs are strings to preserve all signed Int64 bits through JSON.
public struct TraceFoxSecretArchivePayload: Codable {
    public let secret_chat_id: Int64
    public let random_id: String
    public let title: String
    public let text: String
    public let date: Int64
    public let temporary: Bool
    public let ttl_seconds: Int32?
    public let event: TraceFoxCloudArchiveEvent
    public init(chatId: Int64, randomId: Int64, title: String = "Secret chat", text: String,
                date: Int64, ttlSeconds: Int32?, event: TraceFoxCloudArchiveEvent) throws {
        secret_chat_id = chatId; random_id = String(randomId); self.title = title
        self.text = text; self.date = date; ttl_seconds = ttlSeconds
        temporary = (ttlSeconds ?? 0) > 0; self.event = event
        try validate()
    }
    public func validate() throws {
        guard secret_chat_id > 0, secret_chat_id <= Int64(Int32.max),
              let random = Int64(random_id), random != 0, String(random) == random_id,
              text.unicodeScalars.count <= 16000, title.unicodeScalars.count <= 255,
              date >= 1, date <= 4_102_444_800, (ttl_seconds ?? 0) >= 0,
              temporary == ((ttl_seconds ?? 0) > 0) else { throw TraceFoxCloudArchivePayloadError.invalidIdentity }
    }
}

public enum TraceFoxBackupPayload {
    case cloud(TraceFoxCloudArchivePayload)
    case secretChat(TraceFoxSecretArchivePayload)
    public func validate() throws {
        switch self { case let .cloud(p): try p.validate(); case let .secretChat(p): try p.validate() }
    }
    public func encoded() throws -> Data {
        switch self { case let .cloud(p): return try JSONEncoder().encode(p)
        case let .secretChat(p): return try JSONEncoder().encode(p) }
    }
    public var temporary: Bool {
        switch self { case let .cloud(p): return p.temporary; case let .secretChat(p): return p.temporary }
    }
    public var ttl_seconds: Int32? {
        switch self { case let .cloud(p): return p.ttl_seconds; case let .secretChat(p): return p.ttl_seconds }
    }
    public var secret: Bool { if case .secretChat = self { return true }; return false }
    public var identityHeaders: [String: String] {
        switch self {
        case let .cloud(p): return ["X-Chat-Id": String(p.chat_id), "X-Message-Id": String(p.message_id)]
        case let .secretChat(p): return ["X-Secret-Chat-Id": String(p.secret_chat_id), "X-Secret-Random-Id": p.random_id]
        }
    }
}
