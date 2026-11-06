import Foundation
import Testing
@testable import LaxKit

private func parse(_ json: String) -> RealTimeEvent? {
    RealTimeEvent.parse(Data(json.utf8))
}

@Test func parsesConnectionEvents() {
    #expect(parse(#"{"type":"hello","start":true}"#) == .hello)
    #expect(parse(#"{"type":"goodbye","source":"gateway_server"}"#) == .goodbye)
    #expect(parse(#"{"type":"pong","reply_to":3}"#) == .other(type: "pong"))
    #expect(parse(#"{"ok":true,"reply_to":3,"ts":"1.2"}"#) == nil)
    #expect(parse("not json") == nil)
}

@Test func parsesNewMessage() {
    let event = parse(#"{"type":"message","channel":"C1","user":"U1","text":"hi","ts":"1700000000.000100"}"#)
    #expect(event == .message(channel: "C1", SlackMessage(ts: "1700000000.000100", userID: "U1", text: "hi")))
}

@Test func parsesBotMessage() {
    let event = parse(#"{"type":"message","subtype":"bot_message","channel":"C1","bot_id":"B1","username":"CI","text":"ok","ts":"1.0"}"#)
    guard case .message(_, let message) = event else { Issue.record("not a message"); return }
    #expect(message.username == "CI")
}

@Test func parsesEditAndDelete() {
    let edit = parse(#"""
        {"type":"message","subtype":"message_changed","channel":"C1",
         "message":{"type":"message","user":"U1","text":"fixed","ts":"1.0","edited":{"user":"U1","ts":"2.0"}}}
        """#)
    #expect(edit == .messageChanged(channel: "C1", SlackMessage(ts: "1.0", userID: "U1", text: "fixed", isEdited: true)))
    #expect(parse(#"{"type":"message","subtype":"message_deleted","channel":"C1","deleted_ts":"1.0"}"#)
            == .messageDeleted(channel: "C1", ts: "1.0"))
}

@Test func reportsUnhandledMessageSubtypes() {
    #expect(parse(#"{"type":"message","subtype":"channel_archive","channel":"C1","ts":"1.0"}"#)
            == .other(type: "message/channel_archive"))
}

@Test func threadRepliesUpdateTheParent() {
    let event = parse(#"""
        {"type":"message","subtype":"message_replied","channel":"C1","hidden":true,
         "message":{"type":"message","user":"U1","text":"root","ts":"1.0","thread_ts":"1.0","reply_count":3}}
        """#)
    guard case .messageChanged(_, let parent) = event else { Issue.record("not an update"); return }
    #expect(parent.replyCount == 3)
}

@Test func parsesReadPositionChanges() {
    #expect(parse(#"{"type":"channel_marked","channel":"C1","ts":"1.0","unread_count":4,"unread_count_display":2,"mention_count":1}"#)
            == .marked(channel: "C1", unreadCount: 2, mentionCount: 1))
    #expect(parse(#"{"type":"im_marked","channel":"D1","ts":"1.0"}"#)
            == .marked(channel: "D1", unreadCount: 0, mentionCount: 0))
}

@Test func parsesTyping() {
    #expect(parse(#"{"type":"user_typing","channel":"C1","user":"U1"}"#) == .userTyping(channel: "C1", userID: "U1"))
}

@Test func backoffDoublesUpToAMinute() {
    #expect((0...7).map { RealTimeConnection.backoff(attempt: $0) }
            == [1, 2, 4, 8, 16, 32, 60, 60].map { .seconds($0) })
}
