import Foundation

@main struct BotLinkTest {
    static func main() throws {
        let url = try TraceFoxBotLinkProtocol.claimURL(origin: URL(string: "https://example.test")!)
        precondition(url.absoluteString == "https://example.test/api/android/link")
        for bad in ["http://example.test", "https://user:pass@example.test", "https://example.test/other", "https://example.test?query", "https://example.test#fragment"] {
            do { _ = try TraceFoxBotLinkProtocol.claimURL(origin: URL(string: bad)!); fatalError("Bad origin accepted") } catch {}
        }
        let nonce = String(repeating: "a", count: 64)
        let body = try TraceFoxBotLinkProtocol.claimBody(nonce: nonce)
        let decoded = try JSONSerialization.jsonObject(with: body) as! [String: String]
        precondition(decoded["nonce"] == nonce)
        do { _ = try TraceFoxBotLinkProtocol.claimBody(nonce: "invalid"); fatalError("Bad nonce accepted") } catch {}
        do { _ = try TraceFoxBotLinkProtocol.claimBody(nonce: nonce + "\n"); fatalError("Trailing newline accepted") } catch {}
        let waiting = try TraceFoxBotLinkProtocol.credentials(from: Data("{\"ready\":false}".utf8), expectedOwnerId: 42)
        precondition(waiting == nil)
        let response = Data("{\"ready\":true,\"owner_id\":42,\"token\":\"\(String(repeating: "a", count: 43))\",\"archive_available\":false}".utf8)
        let credential = try TraceFoxBotLinkProtocol.credentials(from: response, expectedOwnerId: 42)!
        precondition(credential.ownerId == 42 && !credential.archiveAvailable)
        do { _ = try TraceFoxBotLinkProtocol.credentials(from: response, expectedOwnerId: 43); fatalError("Foreign account accepted") } catch {}
        for invalid in [Data("{}".utf8), Data("{\"ready\":true,\"owner_id\":42,\"token\":\"short\",\"archive_available\":true}".utf8), Data(repeating: 32, count: 4097)] {
            do { _ = try TraceFoxBotLinkProtocol.credentials(from: invalid, expectedOwnerId: 42); fatalError("Invalid response accepted") } catch {}
        }
        let newlineToken = try JSONSerialization.data(withJSONObject: ["ready": true, "owner_id": 42, "token": String(repeating: "a", count: 43) + "\n", "archive_available": true])
        do { _ = try TraceFoxBotLinkProtocol.credentials(from: newlineToken, expectedOwnerId: 42); fatalError("Token newline accepted") } catch {}
        print("PASS: bot-link protocol validation, origin/nonce boundaries, pending response, owner mismatch and malformed response rejection; no live requests")
    }
}
