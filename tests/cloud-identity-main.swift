import Foundation

@main struct CloudIdentityTest {
    static func main() throws {
        let user = TraceFoxCloudArchiveIdentity(peerNamespace: 0, peerId: 42, messageNamespace: 0, messageId: 7)!
        let group = TraceFoxCloudArchiveIdentity(peerNamespace: 1, peerId: 42, messageNamespace: 0, messageId: 7)!
        let channel = TraceFoxCloudArchiveIdentity(peerNamespace: 2, peerId: 42, messageNamespace: 0, messageId: 7)!
        precondition(user.chatId == 42 && group.chatId == -42 && channel.chatId == -1_000_000_000_042)
        precondition(channel.messageId == 7)
        for peerNamespace: Int32 in [3, 4, -1] {
            precondition(TraceFoxCloudArchiveIdentity(peerNamespace: peerNamespace, peerId: 42, messageNamespace: 0, messageId: 7) == nil)
        }
        for namespace: Int32 in [1, 2, 3, 5] {
            precondition(TraceFoxCloudArchiveIdentity(peerNamespace: 0, peerId: 42, messageNamespace: namespace, messageId: 7) == nil)
        }
        for id: Int32 in [0, -1, Int32.min] {
            precondition(TraceFoxCloudArchiveIdentity(peerNamespace: 0, peerId: 42, messageNamespace: 0, messageId: id) == nil)
        }
        precondition(TraceFoxCloudArchiveIdentity(peerNamespace: 0, peerId: Int64.max, messageNamespace: 0, messageId: 7) == nil)
        precondition(TraceFoxCloudArchiveIdentity(peerNamespace: 2, peerId: 1 << 52, messageNamespace: 0, messageId: 7) == nil)
        let payload = try TraceFoxCloudArchivePayload(identity: channel, text: "test", date: 100, ttlSeconds: Int32.max, event: .deleted)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [String: Any]
        precondition(json["chat_id"] as? Int64 == -1_000_000_000_042 && json["chat_type"] as? String == "channel")
        precondition(json["event"] as? String == "deleted" && json["temporary"] as? Bool == true)
        for invalid in [String(repeating: "x", count: 16001), String(repeating: "e\u{301}", count: 8001)] {
            do { _ = try TraceFoxCloudArchivePayload(identity: user, text: invalid, date: 100, event: .message); fatalError("Oversized Unicode text accepted") } catch {}
        }
        do { _ = try TraceFoxCloudArchivePayload(identity: user, text: "", date: 0, event: .message); fatalError("Invalid date accepted") } catch {}
        do { _ = try TraceFoxCloudArchivePayload(identity: user, text: "", date: 100, ttlSeconds: -1, event: .message); fatalError("Invalid TTL accepted") } catch {}
        for random in [Int64.min, Int64.max, -1, 1] {
            let secret = try TraceFoxSecretArchivePayload(chatId: 42, randomId: random, text: "secret", date: 100, ttlSeconds: 30, event: .deleted)
            let data = try JSONEncoder().encode(secret)
            let decoded = try JSONDecoder().decode(TraceFoxSecretArchivePayload.self, from: data)
            try decoded.validate(); precondition(decoded.random_id == String(random))
        }
        do { _ = try TraceFoxSecretArchivePayload(chatId: 42, randomId: 0, text: "", date: 100, ttlSeconds: nil, event: .message); fatalError("Zero secret ID accepted") } catch {}
        if let path = ProcessInfo.processInfo.environment["TRACEFOX_PAYLOAD_FIXTURE"] {
            let plain = try TraceFoxCloudArchivePayload(identity: user, text: "plain", date: 100, event: .message)
            let combining = try TraceFoxCloudArchivePayload(identity: group, text: String(repeating: "e\u{301}", count: 8000), date: 100, ttlSeconds: 0, event: .edited)
            try JSONEncoder().encode([payload, plain, combining]).write(to: URL(fileURLWithPath: path))
        }
        print("PASS: Android-compatible cloud user/group/channel IDs; secret/local/scheduled/overflow rejection; no upload")
    }
}
