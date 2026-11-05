import Foundation
import Testing
@testable import Data

@Suite(.serialized) struct APIClientTests {
    let install = UUID()
    func client(key: String = "k") -> APIClient {
        APIClient(config: APIConfig(host: "dev.api.showcase.bonsung.me", apiKey: key, installID: install),
                  session: StubURLProtocol.session)
    }
    static let jobJSON = #"{"id":"job-1","address":"1 Main St","task":"Fix","date":"2026-11-06","windowStart":"09:00","windowEnd":"11:00","status":"completed","completedAt":"2026-11-06T08:42:00.000Z","note":null,"photo":null}"#

    @Test func listJobsSendsKeyAndInstallID() async throws {
        StubURLProtocol.reset(.response(status: 200, headers: [:], body: Data("[\(Self.jobJSON)]".utf8)))
        let jobs = try await client().listJobs()
        #expect(jobs.count == 1)
        let r = try #require(StubURLProtocol.requests.first)
        #expect(r.httpMethod == "GET")
        #expect(r.url?.absoluteString == "https://dev.api.showcase.bonsung.me/v1/jobs")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(r.value(forHTTPHeaderField: "X-Install-Id") == install.uuidString)
        #expect(r.timeoutInterval == 30)
    }

    @Test func completeSendsKeyAndExactBody() async throws {
        StubURLProtocol.reset(.response(status: 200, headers: [:], body: Data(Self.jobJSON.utf8)))
        let body = Data(#"{"completedAt":"x","note":null}"#.utf8)
        _ = try await client().complete(jobID: "job-1", idempotencyKey: "key-1", body: body)
        let r = try #require(StubURLProtocol.requests.first)
        #expect(r.httpMethod == "POST")
        #expect(r.url?.absoluteString == "https://dev.api.showcase.bonsung.me/v1/jobs/job-1/complete")
        #expect(r.value(forHTTPHeaderField: "Idempotency-Key") == "key-1")
        #expect(r.httpBody == body)
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(r.value(forHTTPHeaderField: "X-Install-Id") == install.uuidString)
    }

    @Test func completeReportsReplayed() async throws {
        StubURLProtocol.reset(.response(status: 200, headers: ["Idempotent-Replayed": "true"], body: Data(Self.jobJSON.utf8)))
        let replayed = try await client().complete(jobID: "job-1", idempotencyKey: "k", body: Data())
        #expect(replayed.replayed)
        StubURLProtocol.reset(.response(status: 200, headers: [:], body: Data(Self.jobJSON.utf8)))
        let fresh = try await client().complete(jobID: "job-1", idempotencyKey: "k", body: Data())
        #expect(!fresh.replayed)
    }

    @Test func uploadPhotoSendsJPEG() async throws {
        StubURLProtocol.reset(.response(status: 200, headers: [:], body: Data(#"{"bytes":3,"sha256":"abc"}"#.utf8)))
        let jpeg = Data([1, 2, 3])
        let photo = try await client().uploadPhoto(jobID: "job-1", jpeg: jpeg)
        #expect(photo == PhotoDTO(bytes: 3, sha256: "abc"))
        let r = try #require(StubURLProtocol.requests.first)
        #expect(r.httpMethod == "PUT")
        #expect(r.url?.absoluteString == "https://dev.api.showcase.bonsung.me/v1/jobs/job-1/photo")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(r.timeoutInterval == 60)
        #expect(r.httpBody == jpeg)
    }

    @Test func httpErrorCarriesCodeAndRetryAfter() async {
        StubURLProtocol.reset(.response(status: 429, headers: ["Retry-After": "120"], body: Data(#"{"error":"write_limit_reached"}"#.utf8)))
        await #expect(throws: APIFailure.http(status: 429, code: "write_limit_reached", retryAfter: 120)) {
            _ = try await client().listJobs()
        }
    }

    @Test func droppedConnectionIsTransport() async {
        StubURLProtocol.reset(.failure(.networkConnectionLost))
        await #expect(throws: APIFailure.transport) { _ = try await client().listJobs() }
    }

    @Test func emptyKeyFailsWithoutRequest() async {
        StubURLProtocol.reset(.response(status: 200, headers: [:], body: Data("[]".utf8)))
        await #expect(throws: APIFailure.missingKey) { _ = try await client(key: "").listJobs() }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test func undecodableSuccessBodyIsTransport() async {
        StubURLProtocol.reset(.response(status: 200, headers: [:], body: Data("<html>Sign in to Wi-Fi</html>".utf8)))
        await #expect(throws: APIFailure.transport) { _ = try await client().listJobs() }
    }
}
