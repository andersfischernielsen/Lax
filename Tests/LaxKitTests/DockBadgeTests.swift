import Testing
@testable import LaxKit

@Test func mentionsShowTheirCount() {
    #expect(DockBadge.label(mentions: 3, hasOtherUnreads: true, mentionsOnly: false) == "3")
    #expect(DockBadge.label(mentions: 1, hasOtherUnreads: false, mentionsOnly: true) == "1")
}

@Test func plainUnreadsShowADotUnlessMentionsOnly() {
    #expect(DockBadge.label(mentions: 0, hasOtherUnreads: true, mentionsOnly: false) == "•")
    #expect(DockBadge.label(mentions: 0, hasOtherUnreads: true, mentionsOnly: true) == nil)
    #expect(DockBadge.label(mentions: 0, hasOtherUnreads: false, mentionsOnly: false) == nil)
}

@Test func totalMentionsAddsUpConversations() {
    let unread = UnreadState(["C1": .init(hasUnreads: true, mentions: 2), "D1": .init(hasUnreads: true, mentions: 3)])
    #expect(unread.totalMentions == 5)
}
