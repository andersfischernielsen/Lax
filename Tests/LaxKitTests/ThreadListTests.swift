import Foundation
import Testing
@testable import LaxKit

private func summary(_ channel: String, _ ts: String, unread: Int = 0) throws -> ThreadSummary {
    let json = #"{"root_msg":{"ts":"\#(ts)","thread_ts":"\#(ts)","text":"root","channel":"\#(channel)"},"unread_replies":\#(Array(repeating: #"{"ts":"0.1","text":"x"}"#, count: unread))}"#
    return try JSONDecoder().decode(ThreadSummary.self, from: Data(json.utf8))
}

private func reply(_ ts: String, to thread: String, by user: String) throws -> SlackMessage {
    try JSONDecoder().decode(SlackMessage.self, from: Data(#"{"ts":"\#(ts)","thread_ts":"\#(thread)","user":"\#(user)","text":"r"}"#.utf8))
}

@Test func replyMovesItsThreadToTheTopAsUnread() throws {
    let threads = [try summary("C1", "1.0"), try summary("C2", "2.0")]
    let updated = threads.receiving(try reply("3.0", to: "2.0", by: "U2"), in: "C2", ownUserID: "U1")
    #expect(updated.map(\.id) == ["C2/2.0", "C1/1.0"])
    #expect(updated[0].unreadReplies == 1)
    #expect(updated[0].latestReplyTS == "3.0")
}

@Test func ownRepliesAndUnknownThreadsLeaveUnreadAlone() throws {
    let threads = [try summary("C1", "1.0")]
    #expect(threads.receiving(try reply("3.0", to: "1.0", by: "U1"), in: "C1", ownUserID: "U1")[0].unreadReplies == 0)
    #expect(threads.receiving(try reply("3.0", to: "9.0", by: "U2"), in: "C1", ownUserID: "U1") == threads)
}

@Test func markingReadClearsOneThread() throws {
    let threads = [try summary("C1", "1.0", unread: 2), try summary("C2", "2.0", unread: 1)]
    let read = threads.markingRead("C1/1.0")
    #expect(read.map(\.unreadReplies) == [0, 1])
}
