import Domain
import Foundation

struct APIConfig: Sendable { let host: String; let apiKey: String; let installID: UUID }

struct PhotoDTO: Decodable, Equatable, Sendable { let bytes: Int; let sha256: String }

struct JobDTO: Decodable, Equatable, Sendable {
    let id, address, task, date, windowStart, windowEnd, status: String
    let completedAt: String?
    let note: String?
    let photo: PhotoDTO?
}

enum APIFailure: Error, Equatable {
    case missingKey, transport
    case http(status: Int, code: String?, retryAfter: TimeInterval?)
}

protocol APIClienting: Sendable {
    func listJobs() async throws -> [JobDTO]
    func complete(jobID: String, idempotencyKey: String, body: Data) async throws -> (job: JobDTO, replayed: Bool)
    func uploadPhoto(jobID: String, jpeg: Data) async throws -> PhotoDTO
}

extension JobDTO {
    func toDomain() -> Job {
        let done = status == "completed"
        return Job(
            id: id, address: address, task: task, windowStart: windowStart, windowEnd: windowEnd,
            photo: photo.map { PhotoInfo(bytes: $0.bytes, sha256: $0.sha256) }, note: note,
            completedAt: done ? completedAt.flatMap { CompletionBody.formatter().date(from: $0) } : nil,
            sync: done ? .sent : .notCompleted)
    }
}

struct APIClient: APIClienting {
    let config: APIConfig
    let session: URLSession

    init(config: APIConfig, session: URLSession) {
        self.config = config
        self.session = session
    }

    func listJobs() async throws -> [JobDTO] {
        let (data, _) = try await send(path: "/v1/jobs", method: "GET", timeout: 30)
        return try decode(data)
    }

    func complete(jobID: String, idempotencyKey: String, body: Data) async throws -> (job: JobDTO, replayed: Bool) {
        let (data, response) = try await send(
            path: "/v1/jobs/\(jobID)/complete", method: "POST", timeout: 30, body: body,
            headers: ["Content-Type": "application/json", "Idempotency-Key": idempotencyKey])
        return (try decode(data), response.value(forHTTPHeaderField: "Idempotent-Replayed") == "true")
    }

    func uploadPhoto(jobID: String, jpeg: Data) async throws -> PhotoDTO {
        let (data, _) = try await send(
            path: "/v1/jobs/\(jobID)/photo", method: "PUT", timeout: 60, body: jpeg,
            headers: ["Content-Type": "image/jpeg"])
        return try decode(data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            throw APIFailure.transport // e.g. captive-portal HTML: retry, the idempotency key makes it safe
        }
    }

    private func send(path: String, method: String, timeout: TimeInterval, body: Data? = nil,
                      headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        guard !config.apiKey.isEmpty else { throw APIFailure.missingKey }
        guard let url = URL(string: "https://\(config.host)\(path)") else { throw APIFailure.transport }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.installID.uuidString, forHTTPHeaderField: "X-Install-Id")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) } catch { throw APIFailure.transport }
        guard let http = response as? HTTPURLResponse else { throw APIFailure.transport }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }.map(TimeInterval.init)
            throw APIFailure.http(status: http.statusCode, code: code, retryAfter: retry)
        }
        return (data, http)
    }
}
