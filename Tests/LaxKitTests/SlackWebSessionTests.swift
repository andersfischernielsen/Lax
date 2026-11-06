import Foundation
import Testing
@testable import LaxKit

private func cookie(_ name: String, _ value: String, domain: String = ".slack.com") -> HTTPCookie {
    HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"])!
}

private let config = """
{"teams":{
  "T1":{"id":"T1","name":"Acme","url":"https://acme.slack.com/","token":"xoxc-1","user_id":"U1"},
  "T2":{"id":"T2","name":"Grid","url":"https://acme-grid.enterprise.slack.com/","token":"xoxc-2"},
  "T3":{"id":"T3","name":"No token","url":"https://none.slack.com/"},
  "T4":{"id":"T4","name":"Elsewhere","url":"https://evil.example.com/","token":"xoxc-4"}
},"lastActiveTeamId":"T1"}
"""

@Test func extractsOneCredentialPerWorkspaceWithToken() {
    let found = SlackWebSession.credentials(localConfig: config, cookies: [cookie("d", "xyz")])
    #expect(found.map(\.workspaceDomain) == ["acme-grid.enterprise.slack.com", "acme.slack.com"])
    #expect(found.map(\.token) == ["xoxc-2", "xoxc-1"])
}

@Test func keepsOnlySlackWideCookies() {
    let cookies = [cookie("d", "xyz"), cookie("d-s", "1"), cookie("other", "no", domain: "acme.slack.com"),
                   cookie("tracker", "no", domain: ".example.com")]
    let found = SlackWebSession.credentials(localConfig: config, cookies: cookies)
    #expect(found.first?.cookieHeader == "d=xyz; d-s=1")
}

@Test func toleratesMissingOrBrokenConfig() {
    #expect(SlackWebSession.credentials(localConfig: "null", cookies: []).isEmpty)
    #expect(SlackWebSession.credentials(localConfig: "{", cookies: []).isEmpty)
}

@Test func recognisesSignedInClientURL() {
    #expect(SlackWebSession.isSignedInClientURL(URL(string: "https://app.slack.com/client/T1/C1")))
    #expect(!SlackWebSession.isSignedInClientURL(URL(string: "https://acme.slack.com/signin")))
    #expect(!SlackWebSession.isSignedInClientURL(nil))
}
