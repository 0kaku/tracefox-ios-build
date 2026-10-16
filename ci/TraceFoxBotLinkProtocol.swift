import Foundation

public enum TraceFoxBotLinkError: Error {
    case invalidOrigin, invalidNonce, invalidResponse, ownerMismatch
}

public struct TraceFoxBotLinkCredentials {
    public let ownerId: Int64
    public let token: String
    public let archiveAvailable: Bool
}

// Pure request/response validation only. Does not send bot commands, issue HTTP
// requests or store tokens. The caller must use the current account's user ID.
public enum TraceFoxBotLinkProtocol {
    private struct Reply: Decodable {
        let ready: Bool
        let owner_id: Int64?
        let token: String?
        let archive_available: Bool?
    }

    public static func claimURL(origin: URL) throws -> URL {
        guard let parts = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.query == nil, parts.fragment == nil else { throw TraceFoxBotLinkError.invalidOrigin }
        return origin.appendingPathComponent("api/android/link")
    }

    public static func claimBody(nonce: String) throws -> Data {
        guard nonce.utf8.count == 64, nonce.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw TraceFoxBotLinkError.invalidNonce
        }
        return try JSONSerialization.data(withJSONObject: ["nonce": nonce])
    }

    public static func credentials(from data: Data, expectedOwnerId: Int64) throws -> TraceFoxBotLinkCredentials? {
        guard data.count <= 4096, expectedOwnerId > 0,
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
            throw TraceFoxBotLinkError.invalidResponse
        }
        guard reply.ready else { return nil }
        guard let owner = reply.owner_id, owner == expectedOwnerId else { throw TraceFoxBotLinkError.ownerMismatch }
        guard let token = reply.token, token.utf8.count == 43, token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              let access = reply.archive_available else { throw TraceFoxBotLinkError.invalidResponse }
        return TraceFoxBotLinkCredentials(ownerId: owner, token: token, archiveAvailable: access)
    }
}
