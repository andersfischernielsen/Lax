import Testing

@testable import LaxKit

private let channel = SlackConversation(id: "C1", name: "general", kind: .channel)
private let dm = SlackConversation(id: "D1", name: nil, kind: .directMessage, userID: "U2")

private func message(_ text: String, from user: String = "U2", thread: String? = nil) -> SlackMessage {
    SlackMessage(ts: "2.0", userID: user, text: text, threadTS: thread)
}

@Test func channelMessagesMarkUnreadAndCountMentions() {
    var state = UnreadState()
    state.received(message("hello"), in: channel, ownUserID: "U1", isOpen: false)
    #expect(state["C1"] == .init(hasUnreads: true, mentions: 0))
    state.received(message("hey <@U1>"), in: channel, ownUserID: "U1", isOpen: false)
    state.received(message("<!here> lunch"), in: channel, ownUserID: "U1", isOpen: false)
    #expect(state["C1"].mentions == 2)
}

@Test func everyDirectMessageCounts() {
    var state = UnreadState()
    state.received(message("hi"), in: dm, ownUserID: "U1", isOpen: false)
    #expect(state["D1"] == .init(hasUnreads: true, mentions: 1))
}

@Test func ignoresOwnOpenAndThreadMessages() {
    var state = UnreadState()
    state.received(message("mine", from: "U1"), in: channel, ownUserID: "U1", isOpen: false)
    state.received(message("seen"), in: channel, ownUserID: "U1", isOpen: true)
    state.received(message("reply", thread: "1.0"), in: channel, ownUserID: "U1", isOpen: false)
    #expect(state["C1"] == .init())
}

@Test func markingAndReadingReset() {
    var state = UnreadState(["C1": .init(hasUnreads: true, mentions: 3)])
    state.marked("C1", unreadCount: 1, mentionCount: 0)
    #expect(state["C1"] == .init(hasUnreads: true, mentions: 0))
    state.read("C1")
    #expect(state["C1"] == .init())
}

@Test func attentionIgnoresMutedUnreadsButNotMentions() {
    let quiet = UnreadState(["C1": .init(hasUnreads: true, mentions: 0)])
    #expect(quiet.needsAttention(muted: []))
    #expect(!quiet.needsAttention(muted: ["C1"]))
    let mentioned = UnreadState(["C1": .init(hasUnreads: true, mentions: 1)])
    #expect(mentioned.needsAttention(muted: ["C1"]))
    #expect(!UnreadState().needsAttention(muted: []))
}

@Test func mentionsOnlyAttentionIgnoresPlainUnreads() {
    let quiet = UnreadState(["C1": .init(hasUnreads: true, mentions: 0)])
    #expect(!quiet.needsAttention(muted: [], mentionsOnly: true))
    let mentioned = UnreadState(["C1": .init(hasUnreads: true, mentions: 2)])
    #expect(mentioned.needsAttention(muted: [], mentionsOnly: true))
}
