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
}
