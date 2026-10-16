import Foundation
import Security

public enum TraceFoxBotPairingError: Error {
    case invalidOwner, expired, randomGenerationFailed(OSStatus)
}

// An explicit, account-bound attempt. Creating it never sends a bot message.
public struct TraceFoxBotPairingAttempt {
    public let ownerId: Int64
    public let expiresAt: Date
    private let nonce: String

    public init(ownerId: Int64, now: Date = Date()) throws {
        guard ownerId > 0 else { throw TraceFoxBotPairingError.invalidOwner }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else { throw TraceFoxBotPairingError.randomGenerationFailed(status) }
        self.ownerId = ownerId
        self.expiresAt = now.addingTimeInterval(600)
        self.nonce = bytes.map { String(format: "%02x", $0) }.joined()
    }

    public func approvalCommand(now: Date = Date()) throws -> String {
        guard now < expiresAt else { throw TraceFoxBotPairingError.expired }
        return "/android_link " + nonce
    }

    public func claimBody(now: Date = Date()) throws -> Data {
        guard now < expiresAt else { throw TraceFoxBotPairingError.expired }
        return try TraceFoxBotLinkProtocol.claimBody(nonce: nonce)
    }

    public func credentials(from data: Data, now: Date = Date()) throws -> TraceFoxBotLinkCredentials? {
        guard now < expiresAt else { throw TraceFoxBotPairingError.expired }
        return try TraceFoxBotLinkProtocol.credentials(from: data, expectedOwnerId: ownerId)
    }
}
