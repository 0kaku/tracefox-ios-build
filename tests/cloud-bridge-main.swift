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
        let record = TraceFoxArchiveRecord(peer: PeerId(42, namespace: 2).toInt64(), namespace: 0,
            message: 7, timestamp: 100, text: "deleted copy", deleted: true, files: [], ttlSeconds: Int32.max)
        let archived = try TraceFoxCloudArchiveBridge.payload(record: record)!
        precondition(archived.chat_id == -1_000_000_000_042 && archived.event == .deleted && archived.text == "deleted copy")
        let secretRecord = TraceFoxArchiveRecord(peer: PeerId(42, namespace: 3).toInt64(), namespace: 1,
            message: 7, timestamp: 100, text: "local only", deleted: true, files: [])
        let ignored = try TraceFoxCloudArchiveBridge.payload(record: secretRecord)
        precondition(ignored == nil)
        for excluded in [message(namespace: 3), message(messageNamespace: 1), message(mid: -7), message(peer: 777000, namespace: 0), message(text: "/android_link synthetic-code")] {
            let value = try TraceFoxCloudArchiveBridge.payload(message: excluded, event: .message)
            precondition(value == nil)
        }
        print("PASS: actual cloud bridge uses unpacked native IDs, one-view priority and rejects secret/local/auth/pairing content; Postbox API fixtures, no upload")
    }
}
