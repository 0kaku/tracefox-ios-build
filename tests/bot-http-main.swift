import Foundation
import CryptoKit

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = Data("{\"ready\":false}".utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/api/android/status" {
            precondition(request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        } else if request.url?.path == "/api/android/archive" {
            precondition(request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            precondition(query.contains(URLQueryItem(name: "before", value: "100")))
        } else if request.url?.path == "/api/android/messages" {
            precondition(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        } else if request.url?.path == "/api/client/secret/messages" || request.url?.path == "/api/client/secret/media" {
            precondition(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            if request.httpMethod == "PUT" {
                precondition(request.value(forHTTPHeaderField: "X-Secret-Chat-Id") == "42")
                precondition(request.value(forHTTPHeaderField: "X-Secret-Random-Id") == "-9223372036854775808")
                precondition(request.value(forHTTPHeaderField: "X-Message-Id") == nil)
            } else { precondition(request.httpMethod == "POST") }
        } else if request.url?.path == "/api/android/media" {
            precondition(request.httpMethod == "PUT" && request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
            precondition(request.value(forHTTPHeaderField: "X-Chat-Id") == "42" && request.value(forHTTPHeaderField: "X-Message-Id") == "7")
            precondition(request.value(forHTTPHeaderField: "X-View-Once") == "true" && request.value(forHTTPHeaderField: "X-Source") == "telegram_client")
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        } else {
            precondition(request.url?.path == "/api/android/link" && request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class ControlledTask: TraceFoxBotClaimTask {
    var cancelled = false
    func cancel() { cancelled = true }
}

private final class ControlledClient: TraceFoxBotClaiming {
    var callbacks: [(Result<TraceFoxBotLinkCredentials?, Error>) -> Void] = []
    var tasks: [ControlledTask] = []
    func claim(_ attempt: TraceFoxBotPairingAttempt, completion: @escaping (Result<TraceFoxBotLinkCredentials?, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        let task = ControlledTask()
        callbacks.append(completion); tasks.append(task)
        return task
    }
}

private final class ImmediateClient: TraceFoxBotClaiming {
    var fail = false
    func claim(_ attempt: TraceFoxBotPairingAttempt, completion: @escaping (Result<TraceFoxBotLinkCredentials?, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        if fail { throw TraceFoxBotLinkClientError.transport }
        completion(.success(nil))
        return ControlledTask()
    }
}

@main struct BotHTTPTest {
    static func main() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let client = try TraceFoxBotLinkClient(origin: URL(string: "https://example.test")!, configuration: config)
        let attempt = try TraceFoxBotPairingAttempt(ownerId: 42)
        func poll() throws -> Result<TraceFoxBotLinkCredentials?, Error> {
            let done = DispatchSemaphore(value: 0)
            var result: Result<TraceFoxBotLinkCredentials?, Error>?
            try client.claim(attempt) { result = $0; done.signal() }
            precondition(done.wait(timeout: .now() + 5) == .success)
            return result!
        }
        if case .success(nil) = try poll() {} else { fatalError("Pending response failed") }
        StubProtocol.body = try JSONSerialization.data(withJSONObject: ["ready": true, "owner_id": 42, "token": String(repeating: "a", count: 43), "archive_available": true])
        if case let .success(value?) = try poll() { precondition(value.ownerId == 42) } else { fatalError("Valid claim rejected") }
        StubProtocol.body = try JSONSerialization.data(withJSONObject: ["ready": true, "owner_id": 43, "token": String(repeating: "a", count: 43), "archive_available": true])
        if case .failure = try poll() {} else { fatalError("Foreign owner accepted") }
        StubProtocol.status = 403
        if case .failure = try poll() {} else { fatalError("HTTP error accepted") }
        StubProtocol.status = 200
        StubProtocol.body = Data(repeating: 32, count: 4097)
        if case .failure = try poll() {} else { fatalError("Oversized response accepted") }
        let store = TraceFoxBotCredentialStore(service: "one.tracefox.ci.coordinator." + UUID().uuidString)
        defer { try? store.remove(ownerId: 42) }
        let coordinator = TraceFoxBotPairingCoordinator(client: client, store: store)
        _ = try coordinator.begin(ownerId: 42)
        coordinator.cancel()
        do { try coordinator.poll { _ in fatalError("Cancelled attempt completed") }; fatalError("Cancelled poll accepted") } catch {}
        _ = try coordinator.begin(ownerId: 42)
        StubProtocol.body = try JSONSerialization.data(withJSONObject: ["ready": true, "owner_id": 42, "token": String(repeating: "b", count: 43), "archive_available": true])
        let saved = DispatchSemaphore(value: 0)
        try coordinator.poll { result in
            if case let .success(value?) = result { precondition(value.ownerId == 42) } else { fatalError("Coordinator failed") }
            saved.signal()
        }
        precondition(saved.wait(timeout: .now() + 5) == .success)
        let stored = try store.read(ownerId: 42)
        precondition(stored?.token == String(repeating: "b", count: 43))
        let raceStore = TraceFoxBotCredentialStore(service: "one.tracefox.ci.race." + UUID().uuidString)
        defer { try? raceStore.remove(ownerId: 42); try? raceStore.remove(ownerId: 43) }
        let controlled = ControlledClient()
        let racing = TraceFoxBotPairingCoordinator(client: controlled, store: raceStore)
        _ = try racing.begin(ownerId: 42)
        var staleDelivered = false
        try racing.poll { _ in staleDelivered = true }
        do { try racing.poll { _ in fatalError("Duplicate poll completed") }; fatalError("Duplicate poll accepted") } catch {}
        _ = try racing.begin(ownerId: 43)
        precondition(controlled.tasks[0].cancelled)
        controlled.callbacks[0](.success(TraceFoxBotLinkCredentials(ownerId: 42, token: String(repeating: "a", count: 43), archiveAvailable: true)))
        let stale = try raceStore.read(ownerId: 42)
        precondition(stale == nil && !staleDelivered)
        var currentDelivered = false
        try racing.poll { _ in currentDelivered = true }
        controlled.callbacks[1](.success(TraceFoxBotLinkCredentials(ownerId: 43, token: String(repeating: "c", count: 43), archiveAvailable: false)))
        let current = try raceStore.read(ownerId: 43)
        precondition(current?.ownerId == 43 && currentDelivered)
        let immediate = ImmediateClient()
        let inline = TraceFoxBotPairingCoordinator(client: immediate, store: raceStore)
        _ = try inline.begin(ownerId: 42)
        var inlineCount = 0
        try inline.poll { _ in inlineCount += 1 }
        try inline.poll { _ in inlineCount += 1 }
        precondition(inlineCount == 2)
        immediate.fail = true
        do { try inline.poll { _ in fatalError("Throwing transport completed") }; fatalError("Transport error lost") } catch {}
        immediate.fail = false
        try inline.poll { _ in inlineCount += 1 }
        precondition(inlineCount == 3)
        controlled.callbacks[1](.success(TraceFoxBotLinkCredentials(ownerId: 43, token: String(repeating: "d", count: 43), archiveAvailable: true)))
        let unchanged = try raceStore.read(ownerId: 43)
        precondition(unchanged?.token == String(repeating: "c", count: 43))
        let credential = TraceFoxBotLinkCredentials(ownerId: 42, token: String(repeating: "a", count: 43), archiveAvailable: false)
        func checkStatus() throws -> Result<TraceFoxBotDeviceStatus, Error> {
            let done = DispatchSemaphore(value: 0)
            var result: Result<TraceFoxBotDeviceStatus, Error>?
            try client.status(credentials: credential) { result = $0; done.signal() }
            precondition(done.wait(timeout: .now() + 5) == .success)
            return result!
        }
        for (owner, expiry, accepted) in [(Int64(42), Int64(Date().timeIntervalSince1970) + 600, true), (43, Int64(Date().timeIntervalSince1970) + 600, false), (42, 1, false)] {
            StubProtocol.body = try JSONSerialization.data(withJSONObject: ["connected": true, "owner_id": owner, "archive_available": false, "expires_at": expiry])
            switch try checkStatus() {
            case .success: precondition(accepted)
            case .failure: precondition(!accepted)
            }
        }
        let identity = TraceFoxCloudArchiveIdentity(peerNamespace: 0, peerId: 42, messageNamespace: 0, messageId: 7)!
        let payload = try TraceFoxCloudArchivePayload(identity: identity, text: "synthetic", date: 100, event: .deleted)
        func submit() throws -> Result<Int64, Error> {
            let done = DispatchSemaphore(value: 0)
            var result: Result<Int64, Error>?
            try client.submit(payload, credentials: credential) { result = $0; done.signal() }
            precondition(done.wait(timeout: .now() + 5) == .success)
            return result!
        }
        StubProtocol.body = Data("{\"ok\":true,\"archive_id\":99}".utf8)
        if case .success(99) = try submit() {} else { fatalError("Valid acknowledgement rejected") }
        for invalid in ["{}", "{\"ok\":false,\"archive_id\":99}", "{\"ok\":true,\"archive_id\":0}"] {
            StubProtocol.body = Data(invalid.utf8)
            if case .failure = try submit() {} else { fatalError("Invalid acknowledgement accepted") }
        }
        StubProtocol.status = 403
        if case .failure = try submit() {} else { fatalError("Access failure acknowledged") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at:file) }
        try Data("synthetic-file".utf8).write(to:file)
        let temporary = try TraceFoxCloudArchivePayload(identity:identity,text:"fixture",date:100,ttlSeconds:Int32.max,event:.deleted)
        func upload() throws -> Result<Int64, Error> {
            let done = DispatchSemaphore(value:0);var outcome: Result<Int64, Error>?
            try client.upload(file:file,payload:temporary,credentials:credential) { outcome=$0;done.signal() }
            precondition(done.wait(timeout:.now()+5) == .success);return outcome!
        }
        StubProtocol.status=200;StubProtocol.body=Data("{\"ok\":true,\"archive_id\":99}".utf8)
        if case .success(99) = try upload() {} else { fatalError("Valid file acknowledgement rejected") }
        let secret = TraceFoxBackupPayload.secretChat(try TraceFoxSecretArchivePayload(chatId: 42, randomId: Int64.min, text: "secret", date: 100, ttlSeconds: Int32.max, event: .deleted))
        for media in [false, true] {
            let done = DispatchSemaphore(value: 0); var outcome: Result<Int64, Error>?
            if media { try client.upload(file: file, payload: secret, credentials: credential) { outcome = $0; done.signal() } }
            else { try client.submit(secret, credentials: credential) { outcome = $0; done.signal() } }
            precondition(done.wait(timeout: .now() + 5) == .success)
            if case .success(99)? = outcome {} else { fatalError("Secret archive request failed") }
        }
        func verify() throws -> Result<Void, Error> {
            let done = DispatchSemaphore(value: 0); var outcome: Result<Void, Error>?
            try client.verify(file: file, archiveId: 99, payload: .cloud(temporary), credentials: credential) { outcome = $0; done.signal() }
            precondition(done.wait(timeout: .now() + 5) == .success); return outcome!
        }
        let checksum = SHA256.hash(data: Data("synthetic-file".utf8)).map { String(format: "%02x", $0) }.joined()
        let remote: [String: Any] = ["id": 99, "chat_id": 42, "message_id": 7, "media_available": true, "sha256": checksum]
        StubProtocol.body = try JSONSerialization.data(withJSONObject: ["items": [remote]])
        if case .success = try verify() {} else { fatalError("Matching server checksum rejected") }
        for field in ["id", "chat_id", "message_id", "media_available", "sha256"] {
            var invalid = remote
            invalid[field] = field == "sha256" ? String(repeating: "0", count: 64) : field == "media_available" ? false : 1
            StubProtocol.body = try JSONSerialization.data(withJSONObject: ["items": [invalid]])
            if case .failure = try verify() {} else { fatalError("Mismatched server proof accepted") }
        }
        StubProtocol.status=401
        if case .failure = try upload() {} else { fatalError("Upload authorization failure accepted") }
        try Data().write(to:file)
        do { _ = try upload();fatalError("Empty retained file accepted") } catch {}
        print("PASS: actual URLSession claim client with URLProtocol fixtures; pending/success/foreign owner/HTTP error/size limits; no live network")
        print("PASS: coordinator explicit begin/cancel, validated claim-to-Keychain flow; synthetic account only")
        print("PASS: deterministic late-response/account-switch race and duplicate poll rejection")
        print("PASS: inline transport completions, thrown request recovery and duplicate callback rejection")
        print("PASS: authenticated device status, owner equality and expiration checks; URLProtocol fixtures only")
        print("PASS: explicit cloud submit requires a positive server acknowledgement; no real uploads")
    }
}
