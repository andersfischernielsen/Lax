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
            Log.api.debug(
                "\(method, privacy: .public) ok on \(host, privacy: .public) in \(ContinuousClock.now - start, privacy: .public)"
            )
            return decoded
        } catch {
            let error = Self.normalized(error)
            if !(error is CancellationError) {
                Log.api.error(
                    "\(method, privacy: .public) failed on \(host, privacy: .public): \(Log.describe(error), privacy: .public)"
                )
            }
            throw error
        }
    }

    /// URLSession reports a cancelled task as `URLError.cancelled`; callers expect Swift's
    /// `CancellationError`, which they ignore.
    static func normalized(_ error: Error) -> Error {
        (error as? URLError)?.code == .cancelled ? CancellationError() : error
    }

    /// Downloads a file Slack hosts (e.g. `url_private`, thumbnails) with the session cookie.
    /// Refuses other hosts so the cookie never leaves Slack.
    public func download(_ url: URL) async throws -> Data {
        guard Self.isSlackHost(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        if let cookie = credentials.cookieHeader {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.normalized(error)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SlackAPIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    /// Sends a file's bytes to an upload URL Slack handed out. The URL carries its own
    /// authorization, so neither the token nor the cookie goes with it.
    func upload(_ file: URL, to url: URL) async throws {
        guard Self.isSlackHost(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, fromFile: file)
        } catch {
            throw Self.normalized(error)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SlackAPIError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// Headers for loading a Slack-hosted file outside `download`, such as streaming a video:
    /// the session cookie. Nil for any other host, so the cookie never leaves Slack.
    public func fileHeaders(for url: URL) -> [String: String]? {
        guard Self.isSlackHost(url) else { return nil }
        return credentials.cookieHeader.map { ["Cookie": $0] } ?? [:]
    }

    /// HTTPS on `slack.com`, `slack-edge.com` or `slack-files.com`, or a subdomain of them.
    static func isSlackHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return ["slack.com", "slack-edge.com", "slack-files.com"].contains { host == $0 || host.hasSuffix("." + $0) }
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
