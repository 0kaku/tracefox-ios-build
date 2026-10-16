import Foundation
import Postbox

@main struct CloudBridgeTest {
    static func main() throws {
        func message(peer: Int64 = 42, namespace: Int32 = 2, messageNamespace: Int32 = 0, mid: Int32 = 7, text: String = "synthetic") -> Message {
            return Message(timestamp: 100, text: text, media: [], attributes: [AutoclearTimeoutMessageAttribute(30), AutoremoveTimeoutMessageAttribute(Int32.max)], id: MessageId(peerId: PeerId(peer, namespace: namespace), namespace: messageNamespace, id: mid))
        }
        let payload = try TraceFoxCloudArchiveBridge.payload(message: message(), event: .deleted)!
        precondition(payload.chat_id == -1_000_000_000_042 && payload.message_id == 7 && payload.ttl_seconds == Int32.max)
        precondition(PeerId(42, namespace: 2).toInt64() != 42)
        for excluded in [message(namespace: 3), message(messageNamespace: 1), message(mid: -7), message(peer: 777000, namespace: 0), message(text: "/android_link synthetic-code")] {
            let value = try TraceFoxCloudArchiveBridge.payload(message: excluded, event: .message)
            precondition(value == nil)
        }
        print("PASS: actual cloud bridge uses unpacked native IDs, one-view priority and rejects secret/local/auth/pairing content; Postbox API fixtures, no upload")
    }
}
