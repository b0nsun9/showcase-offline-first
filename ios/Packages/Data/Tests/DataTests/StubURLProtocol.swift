import Foundation

/// Records requests and returns scripted answers. Tests using it run serially (one suite, shared state).
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Answer {
        case response(status: Int, headers: [String: String], body: Data)
        case failure(URLError.Code)
    }

    nonisolated(unsafe) static var answer: Answer = .response(status: 200, headers: [:], body: Data())
    nonisolated(unsafe) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(_ answer: Answer) {
        lock.lock(); defer { lock.unlock() }
        self.answer = answer
        requests = []
    }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            stream.close()
            recorded.httpBody = data
        }
        Self.lock.lock()
        Self.requests.append(recorded)
        let answer = Self.answer
        Self.lock.unlock()
        switch answer {
        case let .response(status, headers, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}
