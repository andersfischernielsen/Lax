import Foundation

public enum SlackAPIError: Error, Equatable {
    /// Non-2xx HTTP status.
    case http(status: Int)
    /// Slack answered `"ok": false`; the associated value is its `error` field.
    case slack(String)
    case invalidResponse
}

/// Calls `https://<workspace>/api/<method>` the way Slack's web client does:
/// form-encoded POST, token in the body, session cookies in the header.
public struct SlackAPIClient: Sendable {
    public let credentials: SlackCredentials
    private let session: URLSession

    public init(credentials: SlackCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    public func call<Response: Decodable>(
        _ method: String,
        _ params: [String: String] = [:],
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let start = ContinuousClock.now
        let host = credentials.workspaceDomain
        do {
            let (data, response) = try await session.data(for: makeRequest(method, params))
            guard let http = response as? HTTPURLResponse else { throw SlackAPIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw SlackAPIError.http(status: http.statusCode)
            }
            let decoded = try Self.decode(Response.self, from: data)
            Log.api.debug("\(method, privacy: .public) ok on \(host, privacy: .public) in \(ContinuousClock.now - start, privacy: .public)")
            return decoded
        } catch {
            Log.api.error("\(method, privacy: .public) failed on \(host, privacy: .public): \(Log.describe(error), privacy: .public)")
            throw error
        }
    }

    public func makeRequest(_ method: String, _ params: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(credentials.workspaceDomain)/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Cookies come from the stored credentials, not from a shared cookie jar.
        request.httpShouldHandleCookies = false
        if let cookie = credentials.cookieHeader {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        var fields = params
        fields["token"] = credentials.token
        request.httpBody = Data(Self.formEncode(fields).utf8)
        return request
    }

    /// Checks Slack's `ok`/`error` envelope, then decodes the full body.
    static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        let decoder = JSONDecoder()
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw SlackAPIError.invalidResponse
        }
        guard envelope.ok else { throw SlackAPIError.slack(envelope.error ?? "unknown_error") }
        return try decoder.decode(Response.self, from: data)
    }

    /// Sorted so requests are deterministic.
    static func formEncode(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    private static let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    private static func escape(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }

    private struct Envelope: Decodable {
        let ok: Bool
        let error: String?
    }
}
