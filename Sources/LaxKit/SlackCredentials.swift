import Foundation

/// A cookie from a signed-in Slack web session.
public struct SlackCookie: Codable, Hashable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String

    public init(name: String, value: String, domain: String = ".slack.com", path: String = "/") {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
    }
}

/// What it takes to act as one Slack user on one workspace.
public struct SlackCredentials: Codable, Hashable, Sendable {
    /// Full host, e.g. `example.slack.com`.
    public var workspaceDomain: String
    /// `xoxc-…` (web session) or `xoxs-…` (legacy).
    public var token: String
    /// Web session cookies. `xoxc` tokens are rejected without the `d` cookie.
    public var cookies: [SlackCookie]

    public init(workspaceDomain: String, token: String, cookies: [SlackCookie]) {
        self.workspaceDomain = workspaceDomain
        self.token = token
        self.cookies = cookies
    }

    public var requiresCookies: Bool { token.hasPrefix("xoxc-") }

    /// Value for the `Cookie` request header, or nil when there are no cookies.
    public var cookieHeader: String? {
        guard !cookies.isEmpty else { return nil }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// A Slack workspace host, like `acme.slack.com`.
    public static func isValidWorkspaceDomain(_ domain: String) -> Bool {
        domain.wholeMatch(of: /[^\.][a-z0-9\-_\.]*\.slack\.com/) != nil
    }
}
