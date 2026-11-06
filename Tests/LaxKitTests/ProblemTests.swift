import Foundation
import Testing
@testable import LaxKit

@Test func explainsSlackErrorCodes() {
    #expect(Problem.reason(for: SlackAPIError.slack("not_in_channel")) == "You're not a member of this conversation.")
    #expect(Problem.reason(for: SlackAPIError.slack("invalid_auth")).hasPrefix("Slack ended this session"))
    #expect(Problem.reason(for: SlackAPIError.slack("something_new")) == "Slack refused the request (something_new).")
}

@Test func explainsHTTPAndNetworkErrors() {
    #expect(Problem.reason(for: SlackAPIError.http(status: 429)).hasPrefix("Slack is limiting"))
    #expect(Problem.reason(for: SlackAPIError.http(status: 503)).contains("error 503"))
    #expect(Problem.reason(for: URLError(.notConnectedToInternet)).hasPrefix("You're offline"))
    #expect(Problem.reason(for: URLError(.timedOut)).hasPrefix("Slack didn't answer"))
}

@Test func problemKeepsItsTitle() {
    let problem = Problem("Couldn't Send the Message", SlackAPIError.slack("msg_too_long"))
    #expect(problem.title == "Couldn't Send the Message")
    #expect(problem.reason == "The message is too long.")
}
