import Testing

@testable import LaxKit

private let order = ["C1", "C2", "C3", "D1"]

@Test func stepsStopAtTheEnds() {
    #expect(ConversationNavigation.step(from: "C2", in: order, by: 1) == "C3")
    #expect(ConversationNavigation.step(from: "C2", in: order, by: -1) == "C1")
    #expect(ConversationNavigation.step(from: "D1", in: order, by: 1) == "D1")
    #expect(ConversationNavigation.step(from: "C1", in: order, by: -1) == "C1")
}

@Test func stepsWithoutCurrentStartAtAnEnd() {
    #expect(ConversationNavigation.step(from: nil, in: order, by: 1) == "C1")
    #expect(ConversationNavigation.step(from: "gone", in: order, by: -1) == "D1")
    #expect(ConversationNavigation.step(from: nil, in: [], by: 1) == nil)
}

@Test func nextUnreadWrapsAndSkipsCurrent() {
    let unread: Set = ["C1", "C3"]
    #expect(ConversationNavigation.nextUnread(from: "C1", in: order, direction: 1, isUnread: unread.contains) == "C3")
    #expect(ConversationNavigation.nextUnread(from: "C3", in: order, direction: 1, isUnread: unread.contains) == "C1")
    #expect(ConversationNavigation.nextUnread(from: "C3", in: order, direction: -1, isUnread: unread.contains) == "C1")
    #expect(ConversationNavigation.nextUnread(from: nil, in: order, direction: 1, isUnread: unread.contains) == "C1")
    #expect(ConversationNavigation.nextUnread(from: "C1", in: order, direction: 1, isUnread: { $0 == "C1" }) == nil)
}
