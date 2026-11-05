import Foundation

enum SendDecision: Equatable { case retryWithBackoff, retryAfter(TimeInterval), pauseAllWrites(TimeInterval), stopAll, couldNotSend }

func sendDecision(for failure: APIFailure) -> SendDecision {
    switch failure {
    case .transport: return .retryWithBackoff
    case .missingKey: return .stopAll
    case let .http(status, _, retryAfter):
        switch status {
        case 401: return .stopAll
        case 409: return .retryAfter(retryAfter ?? 5)
        case 429: return .pauseAllWrites(retryAfter ?? 60)
        case 500...: return .retryWithBackoff
        default: return .couldNotSend
        }
    }
}
