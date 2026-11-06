import Foundation

/// Pulls credentials out of a Slack web client session (an embedded web view the
/// user signed in with). Slack's web client keeps one entry per workspace in
/// `localStorage.localConfig_v2`, and the session itself in the `d` cookie.
public enum SlackWebSession {
    /// JavaScript to evaluate in the signed-in page. Returns a JSON string or null.
    public static let localConfigScript = "localStorage.getItem('localConfig_v2')"

    /// The page the web client lands on once signed in: `https://app.slack.com/client/…`.
    public static func isSignedInClientURL(_ url: URL?) -> Bool {
        url?.host == "app.slack.com" && url?.path.hasPrefix("/client") == true
    }

    /// After sign-in Slack shows "Launching <workspace>" at `<team>.slack.com/ssb/redirect`
    /// and tries to hand the session to its desktop app. The web client works with the
    /// same session, so this is where to go instead; nil for any other page.
    public static func webClientURL(insteadOf url: URL?) -> URL? {
        guard let url, url.host?.hasSuffix(".slack.com") == true, url.path == "/ssb/redirect" else { return nil }
        return URL(string: "https://app.slack.com/client")
    }

    /// One `SlackCredentials` per workspace in the config that has a web token.
    public static func credentials(localConfig: String, cookies: [HTTPCookie]) -> [SlackCredentials] {
        guard let data = localConfig.data(using: .utf8),
              let config = try? JSONDecoder().decode(LocalConfig.self, from: data) else { return [] }
        let sessionCookies = cookies
            .filter { $0.domain == ".slack.com" || $0.domain == "slack.com" }
            .map { SlackCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path) }
            .sorted { $0.name < $1.name }
        return config.teams.values
            .compactMap { team -> SlackCredentials? in
                guard let token = team.token, token.hasPrefix("xoxc-"),
                      let host = team.url.flatMap(URL.init(string:))?.host,
                      SlackCredentials.isValidWorkspaceDomain(host) else { return nil }
                return SlackCredentials(workspaceDomain: host, token: token, cookies: sessionCookies)
            }
            .sorted { $0.workspaceDomain < $1.workspaceDomain }
    }

    private struct LocalConfig: Decodable {
        let teams: [String: Team]
    }

    private struct Team: Decodable {
        let token: String?
        let url: String?
    }
}
