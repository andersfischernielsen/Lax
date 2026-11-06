import Testing

@testable import LaxKit

@Test func xoxcTokensRequireCookies() {
    #expect(SlackCredentials(workspaceDomain: "a.slack.com", token: "xoxc-1", cookies: []).requiresCookies)
    #expect(!SlackCredentials(workspaceDomain: "a.slack.com", token: "xoxs-1", cookies: []).requiresCookies)
}

@Test func noCookieHeaderWithoutCookies() {
    #expect(SlackCredentials(workspaceDomain: "a.slack.com", token: "xoxs-1", cookies: []).cookieHeader == nil)
}

@Test(arguments: ["example.slack.com", "my-team.slack.com", "acme.enterprise.slack.com"])
func acceptsWorkspaceDomains(_ domain: String) {
    #expect(SlackCredentials.isValidWorkspaceDomain(domain))
}

@Test(arguments: ["slack.com", ".slack.com", "example.slack.com.evil.io", "exa mple.slack.com", "example.com"])
func rejectsWorkspaceDomains(_ domain: String) {
    #expect(!SlackCredentials.isValidWorkspaceDomain(domain))
}
