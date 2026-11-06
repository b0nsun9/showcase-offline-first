import Foundation
import Testing
@testable import Data

struct CompletionBodyTests {
    let date = Date(timeIntervalSince1970: 1_793_954_520)

    @Test func encodesExactJSON() {
        let data = CompletionBody.encode(completedAt: date, note: "Left at the side door")
        #expect(String(decoding: data, as: UTF8.self) == #"{"completedAt":"2026-11-06T08:42:00.000Z","note":"Left at the side door"}"#)
    }

    @Test func encodesNilNoteAsNull() {
        let data = CompletionBody.encode(completedAt: date, note: nil)
        #expect(String(decoding: data, as: UTF8.self) == #"{"completedAt":"2026-11-06T08:42:00.000Z","note":null}"#)
    }

    @Test func awkwardNoteRoundTripsWithStableBytes() throws {
        struct Sent: Decodable { let completedAt: String; let note: String? }
        let note = "Said \"ring twice\"\nGate 1/2 👍"
        let data = CompletionBody.encode(completedAt: date, note: note)
        let sent = try JSONDecoder().decode(Sent.self, from: data)
        #expect(sent.note == note)
        #expect(sent.completedAt == "2026-11-06T08:42:00.000Z")
        #expect(CompletionBody.encode(completedAt: date, note: note) == data)
    }
}
