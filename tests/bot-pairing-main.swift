import Foundation

@main struct BotPairingTest {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let first = try TraceFoxBotPairingAttempt(ownerId: 42, now: now)
        let second = try TraceFoxBotPairingAttempt(ownerId: 42, now: now)
        let body = try JSONSerialization.jsonObject(with: first.claimBody(now: now)) as! [String: String]
        let other = try JSONSerialization.jsonObject(with: second.claimBody(now: now)) as! [String: String]
        precondition(body["nonce"]!.count == 64 && body["nonce"] != other["nonce"])
        let command = try first.approvalCommand(now: now)
        precondition(command == "/android_link " + body["nonce"]!)
        do { _ = try TraceFoxBotPairingAttempt(ownerId: 0); fatalError("Invalid owner accepted") } catch {}
        do { _ = try first.claimBody(now: first.expiresAt); fatalError("Expired claim accepted") } catch {}
        do { _ = try first.approvalCommand(now: first.expiresAt); fatalError("Expired command accepted") } catch {}
        let response = try JSONSerialization.data(withJSONObject: ["ready": true, "owner_id": 43, "token": String(repeating: "a", count: 43), "archive_available": true])
        do { _ = try first.credentials(from: response, now: now); fatalError("Foreign owner accepted") } catch {}
        let pending = try first.credentials(from: Data("{\"ready\":false}".utf8), now: now)
        precondition(pending == nil)
        print("PASS: Security random nonce, attempt isolation, account binding and expiry; no bot message or HTTP request sent")
    }
}
