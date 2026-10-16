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
        print("PASS: real macOS Keychain create/update/read/remove, owner isolation and foreign-owner rejection; synthetic credentials only")
    }
}
