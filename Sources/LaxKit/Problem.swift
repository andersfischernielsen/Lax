import Foundation

/// Something that went wrong, said for people: what failed, and why in plain words.
public struct Problem: Equatable, Identifiable, Sendable {
    /// What failed, as an alert title: "Couldn't Send the Message".
    public let title: String
    /// Why, and what to do about it if anything.
    public let reason: String

    public var id: String { title + "\n" + reason }

    public init(_ title: String, reason: String) {
        self.title = title
        self.reason = reason
    }

    public init(_ title: String, _ error: Error) {
        self.init(title, reason: Self.reason(for: error))
    }

    /// A plain explanation of an error from the Slack client, the network or the system.
    public static func reason(for error: Error) -> String {
        switch error {
        case SlackAPIError.slack(let code): reason(forSlackCode: code)
        case SlackAPIError.http(429): rateLimited
        case SlackAPIError.http(let status) where status >= 500:
            "Slack is having problems (error \(status)). Try again in a moment."
        case SlackAPIError.http(let status): "Slack answered with an unexpected status (\(status))."
        case SlackAPIError.invalidResponse: "Slack sent a reply Lax doesn't understand."
        case let error as URLError: reason(for: error)
        default: error.localizedDescription
        }
    }

    private static let rateLimited = "Slack is limiting how fast Lax can make requests. Try again in a minute."

    private static func reason(forSlackCode code: String) -> String {
        switch code {
        case "not_in_channel": "You're not a member of this conversation."
        case "channel_not_found": "This conversation no longer exists, or you no longer have access to it."
        case "is_archived": "This conversation is archived."
        case "msg_too_long": "The message is too long."
        case "message_not_found", "thread_not_found": "The message no longer exists."
        case "cant_update_message", "edit_window_closed": "Slack doesn't allow editing this message anymore."
        case "cant_delete_message": "You can't delete this message."
        case "too_many_reactions": "This message has the most reactions Slack allows."
        case "ratelimited", "rate_limited": rateLimited
        case "not_authed", "invalid_auth", "token_revoked", "account_inactive":
            "Slack ended this session. Sign in again from the workspace menu."
        case "no_permission", "restricted_action", "not_allowed_token_type":
            "Your workspace doesn't allow this."
        default: "Slack refused the request (\(code))."
        }
    }

    private static func reason(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            "You're offline. Check your internet connection."
        case .timedOut: "Slack didn't answer in time. Try again in a moment."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: "Lax couldn't reach Slack."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            "Lax couldn't make a secure connection to Slack."
        default: error.localizedDescription
        }
    }
}
