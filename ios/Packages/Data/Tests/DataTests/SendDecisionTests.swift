import Testing
@testable import Data

struct SendDecisionTests {
    static let cases: [(APIFailure, SendDecision)] = [
        (.transport, .retryWithBackoff),
        (.http(status: 500, code: nil, retryAfter: nil), .retryWithBackoff),
        (.http(status: 502, code: nil, retryAfter: nil), .retryWithBackoff),
        (.http(status: 409, code: nil, retryAfter: 7), .retryAfter(7)),
        (.http(status: 409, code: nil, retryAfter: nil), .retryAfter(5)),
        (.http(status: 429, code: nil, retryAfter: 120), .pauseAllWrites(120)),
        (.http(status: 429, code: nil, retryAfter: nil), .pauseAllWrites(60)),
        (.http(status: 401, code: nil, retryAfter: nil), .stopAll),
        (.missingKey, .stopAll),
        (.http(status: 400, code: nil, retryAfter: nil), .couldNotSend),
        (.http(status: 404, code: nil, retryAfter: nil), .couldNotSend),
        (.http(status: 413, code: nil, retryAfter: nil), .couldNotSend),
        (.http(status: 415, code: nil, retryAfter: nil), .couldNotSend),
        (.http(status: 422, code: nil, retryAfter: nil), .couldNotSend),
    ]

    @Test(arguments: cases) func decides(failure: APIFailure, expected: SendDecision) {
        #expect(sendDecision(for: failure) == expected)
    }
}
