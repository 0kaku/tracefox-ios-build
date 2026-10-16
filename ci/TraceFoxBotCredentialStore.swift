import Foundation
import Security

public enum TraceFoxBotCredentialError: Error {
    case invalidCredentials
    case keychain(OSStatus)
}

// The service has no access-group override: credentials stay in this app's
// Keychain scope. Native UI uses stable local account-record IDs, with Telegram
// owner validation on read/write. Owner-only scope remains available to host tests.
public final class TraceFoxBotCredentialStore {
    private let service: String
    private let accountRecordId: Int64?
    public init(service: String = "one.tracefox.telegram.bot", accountRecordId: Int64? = nil) {
        self.service = service; self.accountRecordId = accountRecordId
    }

    private func baseQuery(accountKey: String) -> [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: accountKey,
                kSecAttrSynchronizable as String: false]
    }

    private func query(ownerId: Int64) throws -> [String: Any] {
        guard ownerId > 0 else { throw TraceFoxBotCredentialError.invalidCredentials }
        return baseQuery(accountKey: accountRecordId.map { "record:\($0)" } ?? "owner:\(ownerId)")
    }

    private func validate(_ value: TraceFoxBotLinkCredentials, ownerId: Int64) throws {
        guard value.ownerId == ownerId, value.token.utf8.count == 43,
              value.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw TraceFoxBotCredentialError.invalidCredentials
        }
    }

    public func save(_ value: TraceFoxBotLinkCredentials, expectedOwnerId: Int64) throws {
        try validate(value, ownerId: expectedOwnerId)
        let match = try query(ownerId: expectedOwnerId)
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(value),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            let item = match.merging(attributes) { _, new in new }
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw TraceFoxBotCredentialError.keychain(result) }
        } else if update != errSecSuccess {
            throw TraceFoxBotCredentialError.keychain(update)
        }
    }

    public func read(ownerId: Int64) throws -> TraceFoxBotLinkCredentials? {
        var match = try query(ownerId: ownerId)
        match[kSecReturnData as String] = true
        match[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(match as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TraceFoxBotCredentialError.keychain(status) }
        guard let data = result as? Data, data.count <= 4096,
              let value = try? JSONDecoder().decode(TraceFoxBotLinkCredentials.self, from: data) else {
            throw TraceFoxBotCredentialError.invalidCredentials
        }
        try validate(value, ownerId: ownerId)
        return value
    }

    public func remove(ownerId: Int64) throws {
        let status = SecItemDelete(try query(ownerId: ownerId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TraceFoxBotCredentialError.keychain(status)
        }
    }

    // Logout has a local record ID even after Telegram authorization is lost.
    public func removeAccountRecord(_ recordId: Int64) throws {
        let status = SecItemDelete(baseQuery(accountKey: "record:\(recordId)") as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TraceFoxBotCredentialError.keychain(status)
        }
    }
}
