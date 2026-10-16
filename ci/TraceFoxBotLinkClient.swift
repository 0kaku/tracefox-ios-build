import Foundation

public enum TraceFoxBotLinkClientError: Error {
    case transport, invalidResponse, httpStatus(Int)
}

public protocol TraceFoxBotClaimTask { func cancel() }
extension URLSessionDataTask: TraceFoxBotClaimTask {}

public protocol TraceFoxBotClaiming: AnyObject {
    func claim(_ attempt: TraceFoxBotPairingAttempt,
               completion: @escaping (Result<TraceFoxBotLinkCredentials?, Error>) -> Void) throws -> TraceFoxBotClaimTask
}

private final class BotLinkRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // A pairing nonce must never follow a redirect.
    }
}

public final class TraceFoxBotLinkClient: TraceFoxBotClaiming {
    private let endpoint: URL
    private let session: URLSession

    public init(origin: URL, configuration: URLSessionConfiguration = .ephemeral) throws {
        endpoint = try TraceFoxBotLinkProtocol.claimURL(origin: origin)
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: BotLinkRedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    // Explicit single poll only; callers own polling, cancellation and current-account lifecycle.
    @discardableResult
    public func claim(_ attempt: TraceFoxBotPairingAttempt,
                      completion: @escaping (Result<TraceFoxBotLinkCredentials?, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try attempt.claimBody()
        let task = session.dataTask(with: request) { data, response, error in
            if error != nil { completion(.failure(TraceFoxBotLinkClientError.transport)); return }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return
            }
            guard response.statusCode == 200 else {
                completion(.failure(TraceFoxBotLinkClientError.httpStatus(response.statusCode))); return
            }
            guard let data = data, data.count <= 4096 else {
                completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return
            }
            do { completion(.success(try attempt.credentials(from: data))) }
            catch { completion(.failure(error)) }
        }
        task.resume()
        return task
    }
}
