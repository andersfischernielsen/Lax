import Foundation
import Testing
@testable import LaxKit

private func message(_ ts: String, _ text: String = "", thread: String? = nil, subtype: String? = nil) -> SlackMessage {
    SlackMessage(ts: ts, userID: "U1", text: text, subtype: subtype, threadTS: thread)
}

@Test func historyPagesEndUpOldestFirst() {
    var timeline = Timeline()
    timeline.addOlder(HistoryPage(messages: [message("3.0"), message("2.0")], hasMore: true))
    timeline.addOlder(HistoryPage(messages: [message("1.0")], hasMore: false))
    #expect(timeline.messages.map(\.ts) == ["1.0", "2.0", "3.0"])
    #expect(!timeline.hasOlder)
    #expect(timeline.oldestTS == "1.0")
}

@Test func upsertKeepsNumericOrderAndReplacesDuplicates() {
    var timeline = Timeline()
    timeline.upsert(message("10.0"))
    timeline.upsert(message("9.5"))
    timeline.upsert(message("10.0", "edited"))
    #expect(timeline.messages.map(\.ts) == ["9.5", "10.0"])
    #expect(timeline.messages.last?.text == "edited")
}

@Test func threadRepliesStayOutUnlessBroadcast() {
    var timeline = Timeline()
    let root = timeline.upsert(message("1.0", thread: "1.0"))
    let reply = timeline.upsert(message("2.0", thread: "1.0"))
    let broadcast = timeline.upsert(message("3.0", thread: "1.0", subtype: "thread_broadcast"))
    #expect(root && !reply && broadcast)
    #expect(timeline.messages.map(\.ts) == ["1.0", "3.0"])
}

@Test func replaceIgnoresUnloadedMessages() {
    var timeline = Timeline()
    timeline.upsert(message("1.0", "a"))
    timeline.replace(message("1.0", "b"))
    timeline.replace(message("2.0", "c"))
    #expect(timeline.messages.map(\.text) == ["b"])
}

@Test func removeDropsMessage() {
    var timeline = Timeline()
    timeline.upsert(message("1.0"))
    timeline.remove(ts: "1.0")
    #expect(timeline.messages.isEmpty)
}

@Test func firstUnreadSkipsOwnMessages() {
    var timeline = Timeline()
    for (ts, user) in [("1.0", "U2"), ("2.0", "U1"), ("3.0", "U2"), ("4.0", "U2")] {
        timeline.upsert(SlackMessage(ts: ts, userID: user, text: ""))
    }
    #expect(timeline.firstUnreadTS(lastRead: "1.0", ownUserID: "U1") == "3.0")
    #expect(timeline.firstUnreadTS(lastRead: "4.0", ownUserID: "U1") == nil)
    #expect(timeline.newestTS == "4.0")
}

@Test func typingEntriesExpire() {
    var tracker = TypingTracker()
    let start = Date(timeIntervalSince1970: 0)
    tracker.record(userID: "U1", in: "C1", at: start)
    tracker.record(userID: "U2", in: "C1", at: start.addingTimeInterval(2))
    #expect(tracker.typingUserIDs(in: "C1", at: start.addingTimeInterval(3)) == ["U1", "U2"])
    #expect(tracker.typingUserIDs(in: "C1", at: start.addingTimeInterval(7)) == ["U2"])
    tracker.clear(userID: "U2", in: "C1")
    #expect(tracker.typingUserIDs(in: "C1", at: start.addingTimeInterval(3)) == ["U1"])
}

@Test func typingExpiryDatesFollowLastSeen() {
    var tracker = TypingTracker()
    let start = Date(timeIntervalSince1970: 1000)
    tracker.record(userID: "U2", in: "C1", at: start.addingTimeInterval(2))
    tracker.record(userID: "U1", in: "C1", at: start)
    tracker.record(userID: "U3", in: "C2", at: start)
    #expect(tracker.expiryDates(in: "C1") == [start.addingTimeInterval(6), start.addingTimeInterval(8)])
    #expect(tracker.expiryDates(in: "C9").isEmpty)
}

@Test func typingSummaries() {
    #expect(TypingTracker.summary([]) == nil)
    #expect(TypingTracker.summary(["Jane"]) == "Jane is typing…")
    #expect(TypingTracker.summary(["Jane", "Bob"]) == "Jane and Bob are typing…")
    #expect(TypingTracker.summary(["A", "B", "C", "D"]) == "Several people are typing…")
}

@Test func threadTimelinesHoldParentAndReplies() {
    let thread = Timeline(thread: "1.0", messages: [
        message("1.0", thread: "1.0"), message("2.0", thread: "1.0"), message("3.0", thread: "9.0"), message("4.0"),
    ])
    #expect(thread.messages.map(\.ts) == ["1.0", "2.0"])
    #expect(!thread.hasOlder)
    var live = thread
    let accepted = live.upsert(message("5.0", thread: "1.0"))
    #expect(accepted)
    #expect(live.messages.map(\.ts) == ["1.0", "2.0", "5.0"])
}
