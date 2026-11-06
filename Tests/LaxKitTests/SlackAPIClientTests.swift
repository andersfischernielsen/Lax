import Foundation
import Testing
@testable import LaxKit

private let credentials = SlackCredentials(
    workspaceDomain: "example.slack.com",
    token: "xoxc-123",
    cookies: [SlackCookie(name: "d", value: "abc%2F"), SlackCookie(name: "d-s", value: "42")]
)

@Test func requestTargetsWorkspaceAPI() {
    let request = SlackAPIClient(credentials: credentials).makeRequest("conversations.history")
    #expect(request.url?.absoluteString == "https://example.slack.com/api/conversations.history")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
}

@Test func requestCarriesTokenAndParamsInBody() throws {
    let request = SlackAPIClient(credentials: credentials)
        .makeRequest("conversations.history", ["channel": "C1", "oldest": "1.5"])
    let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
    #expect(body == "channel=C1&oldest=1.5&token=xoxc-123")
}

@Test func requestSendsStoredCookiesOnly() {
    let request = SlackAPIClient(credentials: credentials).makeRequest("auth.test")
    #expect(request.value(forHTTPHeaderField: "Cookie") == "d=abc%2F; d-s=42")
    #expect(request.httpShouldHandleCookies == false)
}

@Test func formEncodingEscapesReservedCharacters() {
    #expect(SlackAPIClient.formEncode(["text": "a b&c=d/é"]) == "text=a%20b%26c%3Dd%2F%C3%A9")
}

@Test func decodesSuccessfulResponse() throws {
    let json = Data("""
    {"ok":true,"url":"https://example.slack.com/","team":"Example","user":"me","team_id":"T1","user_id":"U1"}
    """.utf8)
    let response = try SlackAPIClient.decode(AuthTestResponse.self, from: json)
    #expect(response.teamID == "T1")
    #expect(response.userID == "U1")
}

@Test func surfacesSlackError() {
    let json = Data(#"{"ok":false,"error":"invalid_auth"}"#.utf8)
    #expect(throws: SlackAPIError.slack("invalid_auth")) {
        try SlackAPIClient.decode(AuthTestResponse.self, from: json)
    }
}

@Test func rejectsNonJSON() {
    #expect(throws: SlackAPIError.invalidResponse) {
        try SlackAPIClient.decode(AuthTestResponse.self, from: Data("<html>".utf8))
    }
}

@Test(arguments: [
    ("https://files.slack.com/files-pri/T1-F1/a.png", true),
    ("https://acme.slack.com/files/U1/F1", true),
    ("https://avatars.slack-edge.com/a.png", true),
    ("http://files.slack.com/a.png", false),
    ("https://files.slack.com.evil.io/a.png", false),
    ("https://notslack.com/a.png", false),
])
func cookiesOnlyGoToSlackHosts(_ url: String, _ allowed: Bool) {
    #expect(SlackAPIClient.isSlackHost(URL(string: url)!) == allowed)
}

@Test func cancelledRequestsThrowCancellationError() {
    #expect(SlackAPIClient.normalized(URLError(.cancelled)) is CancellationError)
    #expect(SlackAPIClient.normalized(URLError(.timedOut)) is URLError)
}
