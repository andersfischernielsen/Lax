import Foundation
import Synchronization

/// Answers requests with canned JSON, keyed by Slack API method, and records them.
/// Shared state: use only from `.serialized` suites.
final class StubURLProtocol: URLProtocol {
    private static let state = Mutex<(responses: [String: [String]], requests: [URLRequest])>(([:], []))

    /// Queue one or more JSON bodies for a method; they're served in order.
    static func reset(_ responses: [String: [String]]) {
        state.withLock { $0 = (responses, []) }
    }

    static var requests: [URLRequest] { state.withLock { $0.requests } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        // URLSession moves the body into a stream; keep it readable for assertions.
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = Data(reading: stream)
        }
        let method = request.url?.lastPathComponent ?? ""
        let body = Self.state.withLock { state -> String in
            state.requests.append(recorded)
            guard var queue = state.responses[method], !queue.isEmpty else {
                return #"{"ok":false,"error":"unstubbed"}"#
            }
            let next = queue.removeFirst()
            state.responses[method] = queue
            return next
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// Decoded form fields of the body.
    var formFields: [String: String] {
        guard let body = httpBody.flatMap({ String(data: $0, encoding: .utf8) }) else { return [:] }
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).removingPercentEncoding ?? String($0)
            }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }
}

extension Data {
    fileprivate init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            append(buffer, count: count)
        }
    }
}
