import Foundation

enum CompletionBody {
    static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }

    /// Built by hand so the key order and bytes are fixed; the same bytes are resent on every retry.
    static func encode(completedAt: Date, note: String?) -> Data {
        let date = formatter().string(from: completedAt)
        let noteJSON = note.map { jsonString($0) } ?? "null"
        return Data(#"{"completedAt":"\#(date)","note":\#(noteJSON)}"#.utf8)
    }

    private static func jsonString(_ s: String) -> String {
        // Bare-string JSON encoding is not supported before iOS 13.1 fragments; wrap in an array and strip the brackets.
        let data = (try? JSONEncoder().encode([s])) ?? Data("[\"\"]".utf8)
        let text = String(decoding: data, as: UTF8.self)
        return String(text.dropFirst().dropLast())
    }
}
