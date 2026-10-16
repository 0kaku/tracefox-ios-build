import Foundation

@main struct BotKeychainTest {
    static func main() throws {
        // Unique service and synthetic owners; never inspect/delete other items.
        let store = TraceFoxBotCredentialStore(service: "one.tracefox.ci." + UUID().uuidString)
        defer { try? store.remove(ownerId: 41); try? store.remove(ownerId: 42) }
        let value = TraceFoxBotLinkCredentials(ownerId: 41, token: String(repeating: "a", count: 43), archiveAvailable: false)
        do { try store.save(value, expectedOwnerId: 42); fatalError("Foreign owner accepted") } catch {}
        try store.save(value, expectedOwnerId: 41)
        let loaded = try store.read(ownerId: 41)
        let foreign = try store.read(ownerId: 42)
        precondition(loaded?.token == value.token && foreign == nil)
        let changed = TraceFoxBotLinkCredentials(ownerId: 41, token: String(repeating: "b", count: 43), archiveAvailable: true)
        try store.save(changed, expectedOwnerId: 41)
        let updated = try store.read(ownerId: 41)
        precondition(updated?.token == changed.token && updated?.archiveAvailable == true)
        try store.remove(ownerId: 41)
        let removed = try store.read(ownerId: 41)
        precondition(removed == nil)
        let service = "one.tracefox.ci.records." + UUID().uuidString
        let recordA = TraceFoxBotCredentialStore(service: service, accountRecordId: -10)
        let recordB = TraceFoxBotCredentialStore(service: service, accountRecordId: 20)
        defer { try? recordA.removeAccountRecord(-10); try? recordB.removeAccountRecord(20) }
        try recordA.save(value, expectedOwnerId: 41)
        try recordB.save(changed, expectedOwnerId: 41)
        try recordA.removeAccountRecord(-10)
        let erased = try recordA.read(ownerId: 41)
        let kept = try recordB.read(ownerId: 41)
        precondition(erased == nil && kept?.token == changed.token)
        print("PASS: real macOS Keychain create/update/read/remove, owner isolation and foreign-owner rejection; synthetic credentials only")
    }
}
