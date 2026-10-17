import Foundation
import CryptoKit

public enum TraceFoxBotLinkClientError: Error {
    case transport, invalidResponse, httpStatus(Int)
}

public struct TraceFoxBotDeviceStatus: Decodable {
    public let connected: Bool
    public let owner_id: Int64
    public let archive_available: Bool
    public let expires_at: Int64
}

public protocol TraceFoxBotClaimTask { func cancel() }
extension URLSessionDataTask: TraceFoxBotClaimTask {}

public protocol TraceFoxBotClaiming: AnyObject {
    func claim(_ attempt: TraceFoxBotPairingAttempt,
               completion: @escaping (Result<TraceFoxBotLinkCredentials?, Error>) -> Void) throws -> TraceFoxBotClaimTask
}

public protocol TraceFoxCloudSubmitting: AnyObject {
    func submit(_ payload: TraceFoxCloudArchivePayload, credentials: TraceFoxBotLinkCredentials,
                completion: @escaping (Result<Int64, Error>) -> Void) throws -> TraceFoxBotClaimTask
}

private final class BotLinkRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // A pairing nonce must never follow a redirect.
    }
}

public final class TraceFoxBotLinkClient: TraceFoxBotClaiming, TraceFoxCloudSubmitting {
    private struct ArchiveReply: Decodable { let ok: Bool; let archive_id: Int64 }
    private let endpoint: URL
    private let statusEndpoint: URL
    private let session: URLSession
    private let uploadSession: URLSession

    public init(origin: URL, configuration: URLSessionConfiguration = .ephemeral) throws {
        endpoint = try TraceFoxBotLinkProtocol.claimURL(origin: origin)
        statusEndpoint = endpoint.deletingLastPathComponent().appendingPathComponent("status")
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config, delegate: BotLinkRedirectPolicy(), delegateQueue: nil)
        let mediaConfig = config.copy() as! URLSessionConfiguration
        mediaConfig.timeoutIntervalForRequest = 30
        mediaConfig.timeoutIntervalForResource = 180
        uploadSession = URLSession(configuration: mediaConfig, delegate: BotLinkRedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel(); uploadSession.invalidateAndCancel() }

    @discardableResult
    public func submit(_ payload: TraceFoxCloudArchivePayload, credentials: TraceFoxBotLinkCredentials,
                       completion: @escaping (Result<Int64, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        return try submit(.cloud(payload), credentials: credentials, completion: completion)
    }
    @discardableResult
    public func upload(file: URL, payload: TraceFoxCloudArchivePayload, credentials: TraceFoxBotLinkCredentials,
                       completion: @escaping (Result<Int64, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        return try upload(file: file, payload: .cloud(payload), credentials: credentials, completion: completion)
    }

    private func backupEndpoint(secret: Bool, resource: String) -> URL {
        if secret {
            return endpoint.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("client/secret").appendingPathComponent(resource)
        }
        return endpoint.deletingLastPathComponent().appendingPathComponent(resource)
    }

    // Explicit single event submission. No automatic queue or retry is started.
    @discardableResult
    public func submit(_ payload: TraceFoxBackupPayload, credentials: TraceFoxBotLinkCredentials,
                       completion: @escaping (Result<Int64, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        try payload.validate()
        guard credentials.ownerId > 0, credentials.token.utf8.count == 43,
              credentials.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw TraceFoxBotLinkError.invalidResponse
        }
        var request = URLRequest(url: backupEndpoint(secret: payload.secret, resource: "messages"))
        request.httpMethod = "POST"
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try payload.encoded()
        let task = session.dataTask(with: request) { data, response, error in
            if error != nil { completion(.failure(TraceFoxBotLinkClientError.transport)); return }
            guard let response = response as? HTTPURLResponse else { completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return }
            guard response.statusCode == 200 else { completion(.failure(TraceFoxBotLinkClientError.httpStatus(response.statusCode))); return }
            guard let data = data, data.count <= 4096,
                  let reply = try? JSONDecoder().decode(ArchiveReply.self, from: data), reply.ok, reply.archive_id > 0 else {
                completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return
            }
            completion(.success(reply.archive_id))
        }
        task.resume()
        return task
    }

    // Upload a completed retained file without loading it fully into memory.
    @discardableResult
    public func upload(file: URL, payload: TraceFoxBackupPayload, credentials: TraceFoxBotLinkCredentials,
                       completion: @escaping (Result<Int64, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        try payload.validate()
        guard credentials.ownerId > 0, credentials.token.utf8.count == 43,
              credentials.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              file.isFileURL else { throw TraceFoxBotLinkError.invalidResponse }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0, size <= 64 * 1024 * 1024 else {
            throw TraceFoxBotLinkError.invalidResponse
        }
        var request = URLRequest(url: backupEndpoint(secret: payload.secret, resource: "media"))
        request.httpMethod = "PUT"
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        let mime = ["jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "mp4": "video/mp4", "ogg": "audio/ogg", "mp3": "audio/mpeg", "pdf": "application/pdf"][file.pathExtension.lowercased()] ?? "application/octet-stream"
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        for (name, value) in payload.identityHeaders { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue(file.lastPathComponent, forHTTPHeaderField: "X-Filename")
        request.setValue("telegram_client", forHTTPHeaderField: "X-Source")
        request.setValue(payload.temporary ? "true" : "false", forHTTPHeaderField: "X-Temporary")
        request.setValue(payload.ttl_seconds == Int32.max ? "true" : "false", forHTTPHeaderField: "X-View-Once")
        let task = uploadSession.uploadTask(with: request, fromFile: file) { data, response, error in
            if error != nil { completion(.failure(TraceFoxBotLinkClientError.transport)); return }
            guard let response = response as? HTTPURLResponse else { completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return }
            guard response.statusCode == 200 else { completion(.failure(TraceFoxBotLinkClientError.httpStatus(response.statusCode))); return }
            guard let data = data, data.count <= 4096,
                  let reply = try? JSONDecoder().decode(ArchiveReply.self, from: data), reply.ok, reply.archive_id > 0 else {
                completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return
            }
            completion(.success(reply.archive_id))
        }
        task.resume(); return task
    }

    @discardableResult
    public func verify(file: URL, archiveId: Int64, payload: TraceFoxBackupPayload,
                       credentials: TraceFoxBotLinkCredentials,
                       completion: @escaping (Result<Void, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        guard archiveId > 0, archiveId < Int64.max else { throw TraceFoxBotLinkClientError.invalidResponse }
        try payload.validate()
        let handle = try FileHandle(forReadingFrom: file)
        defer { handle.closeFile() }
        var digest = SHA256()
        var total = 0
        while true {
            let bytes = handle.readData(ofLength: 256 * 1024)
            if bytes.isEmpty { break }
            total += bytes.count
            guard total <= 64 * 1024 * 1024 else { throw TraceFoxBotLinkClientError.invalidResponse }
            digest.update(data: bytes)
        }
        guard total > 0 else { throw TraceFoxBotLinkClientError.invalidResponse }
        let checksum = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let chat: Int64
        let message: Int64?
        switch payload {
        case let .cloud(value): chat = value.chat_id; message = Int64(value.message_id)
        case let .secretChat(value): chat = -(2_000_000_000_000 + value.secret_chat_id); message = nil
        }
        var components = URLComponents(url: backupEndpoint(secret: false, resource: "archive"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "chat_id", value: String(chat)),
                                URLQueryItem(name: "before", value: String(archiveId + 1)), URLQueryItem(name: "limit", value: "1")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: request) { data, response, error in
            if error != nil { completion(.failure(TraceFoxBotLinkClientError.transport)); return }
            guard let response = response as? HTTPURLResponse else { completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return }
            guard response.statusCode == 200 else { completion(.failure(TraceFoxBotLinkClientError.httpStatus(response.statusCode))); return }
            guard let data = data, data.count <= 1024 * 1024,
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let items = object["items"] as? [[String: Any]], items.count == 1,
                  let row = items.first,
                  (row["id"] as? NSNumber)?.int64Value == archiveId,
                  (row["chat_id"] as? NSNumber)?.int64Value == chat,
                  message == nil || (row["message_id"] as? NSNumber)?.int64Value == message,
                  row["media_available"] as? Bool == true,
                  row["sha256"] as? String == checksum else {
                completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return
            }
            completion(.success(()))
        }
        task.resume(); return task
    }

    @discardableResult
    public func status(credentials: TraceFoxBotLinkCredentials,
                       completion: @escaping (Result<TraceFoxBotDeviceStatus, Error>) -> Void) throws -> TraceFoxBotClaimTask {
        guard credentials.ownerId > 0, credentials.token.utf8.count == 43,
              credentials.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw TraceFoxBotLinkError.invalidResponse
        }
        var request = URLRequest(url: statusEndpoint)
        request.setValue("Bearer " + credentials.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request) { data, response, error in
            if error != nil { completion(.failure(TraceFoxBotLinkClientError.transport)); return }
            guard let response = response as? HTTPURLResponse else { completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return }
            guard response.statusCode == 200 else { completion(.failure(TraceFoxBotLinkClientError.httpStatus(response.statusCode))); return }
            guard let data = data, data.count <= 4096,
                  let value = try? JSONDecoder().decode(TraceFoxBotDeviceStatus.self, from: data),
                  value.connected, value.owner_id == credentials.ownerId,
                  value.expires_at > Int64(Date().timeIntervalSince1970) else {
                completion(.failure(TraceFoxBotLinkClientError.invalidResponse)); return
            }
            completion(.success(value))
        }
        task.resume()
        return task
    }

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
