import Foundation
import Testing

@testable import LaxKit

@Test func redactionDropsQueriesAndOneTimeCodes() {
    let login = URL(string: "https://app.slack.com/t/acme/login/z-app-2121287163317-1251161398-6b94d0?x=secret")
    #expect(Log.redacted(login) == "https://app.slack.com/t/acme/login/<redacted>")
    #expect(Log.redacted(URL(string: "https://acme.slack.com/ssb/redirect")) == "https://acme.slack.com/ssb/redirect")
    #expect(
        Log.redacted(URL(string: "https://app.slack.com/client/T01ABCDEF/C01ABCDEF"))
            == "https://app.slack.com/client/T01ABCDEF/C01ABCDEF")
    #expect(Log.redacted(nil) == "nil")
}
