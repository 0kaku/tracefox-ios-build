// Host-only API fixtures. These do not emulate Telegram transport or an iPhone.
import Foundation

public protocol MediaResource { var fixtureKey: String { get } }
public protocol Media {}
public struct PeerId: Hashable {
    public let value: Int64
    public init(_ value: Int64) { self.value = value }
    public func toInt64() -> Int64 { value }
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
    public let timestamp: Int32
    public let text: String
    public let media: [Media]
    public let attributes: [Any]
    public init(timestamp: Int32, text: String, media: [Media], attributes: [Any]) {
        self.timestamp = timestamp; self.text = text; self.media = media; self.attributes = attributes
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
