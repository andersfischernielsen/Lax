import Testing
@testable import LaxKit

private let names = ["U1": "Jane"]

@Test func channelNamesGetAHash() {
    #expect(SlackConversation(id: "C1", name: "general", kind: .channel).displayName { names[$0] } == "#general")
    #expect(SlackConversation(id: "G1", name: "secret", kind: .privateChannel).displayName { names[$0] } == "#secret")
}

@Test func directMessagesUseThePersonsName() {
    let known = SlackConversation(id: "D1", name: nil, kind: .directMessage, userID: "U1")
    let unknown = SlackConversation(id: "D2", name: nil, kind: .directMessage, userID: "U9")
    #expect(known.displayName { names[$0] } == "Jane")
    #expect(unknown.displayName { names[$0] } == "U9")
}

@Test func groupDirectMessagesListMembers() {
    let group = SlackConversation(id: "G2", name: "mpdm-alice--bob--carol-1", kind: .groupDirectMessage)
    #expect(group.displayName { names[$0] } == "alice, bob, carol")
}

@Test func messageDateComesFromTimestamp() {
    #expect(SlackMessage(ts: "1700000000.500000", userID: nil, text: "").date.timeIntervalSince1970 == 1_700_000_000.5)
}
