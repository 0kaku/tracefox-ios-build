// Host-only API fixtures. These do not emulate Telegram transport or an iPhone.
import Foundation

public protocol MediaResource { var fixtureKey: String { get } }
public protocol Media {}
public struct PeerId: Hashable {
    public struct Namespace: Hashable {
        let value: Int32
        public func _internalGetInt32Value() -> Int32 { value }
    }
    public struct Id: Hashable {
        let value: Int64
        public func _internalGetInt64Value() -> Int64 { value }
    }
    public let value: Int64
    public let namespace: Namespace
    public var id: Id { Id(value: value) }
    public init(_ value: Int64) {
        // Synthetic packing for host adapter tests, not Telegram's bit layout.
        let encoded = Int32(truncatingIfNeeded: value >> 56)
        if (1...3).contains(encoded) {
            self.value = value ^ (Int64(encoded) << 56); self.namespace = Namespace(value: encoded)
        } else { self.value = value; self.namespace = Namespace(value: 0) }
    }
    public init(_ value: Int64, namespace: Int32) { self.value = value; self.namespace = Namespace(value: namespace) }
    public func toInt64() -> Int64 { value ^ (Int64(namespace.value) << 56) }
}
public struct MessageId: Hashable {
    public let peerId: PeerId
    public let namespace: Int32
    public let id: Int32
    public init(peerId: PeerId, namespace: Int32, id: Int32) {
        self.peerId = peerId; self.namespace = namespace; self.id = id
    }
}
public struct Message {
    public let id: MessageId
    public let timestamp: Int32
    public let text: String
    public let media: [Media]
    public let attributes: [Any]
    public let globallyUniqueId: Int64?
    public init(timestamp: Int32, text: String, media: [Media], attributes: [Any], globallyUniqueId: Int64? = nil, id: MessageId? = nil) {
        self.id = id ?? MessageId(peerId: PeerId(0), namespace: 0, id: 0)
        self.timestamp = timestamp; self.text = text; self.media = media; self.attributes = attributes
        self.globallyUniqueId = globallyUniqueId
    }
}
public final class Transaction {
    public var messages: [MessageId: Message] = [:]
    public init() {}
    public func getMessage(_ id: MessageId) -> Message? { messages[id] }
}
public final class MediaBox {
    public let basePath: String
    public var completed: [String: String] = [:]
    public init(basePath: String) { self.basePath = basePath }
    public func completedResourcePath(_ resource: MediaResource) -> String? { completed[resource.fixtureKey] }
}
