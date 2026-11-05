import CryptoKit
import Foundation
import Testing
@testable import Data

// Fork PRs get an empty secret, so empty counts as unset.
private let key = ProcessInfo.processInfo.environment["SHOWCASE_DEV_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }

@Suite(.enabled(if: key != nil)) struct DevAPITests {
    func client() -> APIClient {
        APIClient(config: APIConfig(host: "dev.api.showcase.bonsung.me", apiKey: key ?? "", installID: UUID()),
                  session: URLSession(configuration: .ephemeral))
    }

    @Test func sameKeyTwiceIsRecordedOnce() async throws {
        let c = client()
        let body = CompletionBody.encode(completedAt: Date(), note: "integration")
        let idem = UUID().uuidString
        let first = try await c.complete(jobID: "job-1", idempotencyKey: idem, body: body)
        let second = try await c.complete(jobID: "job-1", idempotencyKey: idem, body: body)
        #expect(!first.replayed)
        #expect(second.replayed)
        #expect(second.job.status == "completed")
    }

    @Test func uploadedPhotoComesBackWhole() async throws {
        let jpeg = Data((0..<1_024).map { UInt8($0 % 256) })
        let photo = try await client().uploadPhoto(jobID: "job-1", jpeg: jpeg)
        #expect(photo.bytes == 1_024)
        #expect(photo.sha256 == SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined())
    }
}
