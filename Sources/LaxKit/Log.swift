import Foundation
import os

/// Unified-log channels. Watch them with:
/// `log stream --level debug --predicate 'subsystem == "app.lax.Lax"'`
///
/// Never log tokens, cookie values, request parameters or message text.
public enum Log {
    public static let subsystem = "app.lax.Lax"

    public static let signIn = Logger(subsystem: subsystem, category: "signin")
    public static let api = Logger(subsystem: subsystem, category: "api")
    public static let realTime = Logger(subsystem: subsystem, category: "realtime")
    public static let workspace = Logger(subsystem: subsystem, category: "workspace")

    /// An error, safe to log publicly: URL errors by code only, since their
    /// descriptions include the URL.
    public static func describe(_ error: Error) -> String {
        switch error {
        case let error as URLError: "URLError(\(error.code.rawValue))"
        case let error as SlackAPIError: "\(error)"
        case let error as DecodingError: "DecodingError(\(Self.describe(decoding: error)))"
        default: "\(type(of: error)): \((error as NSError).domain) \((error as NSError).code)"
        }
    }

    /// Host and path only, since queries can carry tickets or tokens. Path segments
    /// that look like one-time codes (e.g. Slack's `z-app-…` login links) are masked.
    public static func redacted(_ url: URL?) -> String {
        guard let url else { return "nil" }
        let path = url.path.split(separator: "/", omittingEmptySubsequences: false)
            .map { isSecretLike($0) ? "<redacted>" : String($0) }
            .joined(separator: "/")
        return "\(url.scheme ?? "")://\(url.host ?? "")\(path)"
    }

    static func isSecretLike(_ segment: Substring) -> Bool {
        segment.hasPrefix("z-app-") || segment.hasPrefix("xox")
            || (segment.count >= 24 && segment.contains(where: \.isNumber))
    }

    private static func describe(decoding error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context): "missing \(path(context.codingPath + [key]))"
        case .typeMismatch(_, let context): "type mismatch at \(path(context.codingPath))"
        case .valueNotFound(_, let context): "null at \(path(context.codingPath))"
        case .dataCorrupted(let context): "corrupt at \(path(context.codingPath))"
        @unknown default: "unknown"
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}
