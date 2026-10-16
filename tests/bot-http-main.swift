import Foundation

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var body = Data("{\"ready\":false}".utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.url?.path == "/api/android/link" && request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
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
        print("PASS: actual URLSession claim client with URLProtocol fixtures; pending/success/foreign owner/HTTP error/size limits; no live network")
    }
}
