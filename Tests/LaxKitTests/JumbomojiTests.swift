import Testing
@testable import LaxKit

@Test func emojiOnlyMessagesAreJumbomoji() {
    #expect(Jumbomoji.items(in: ":partyparrot:") == [.shortcode("partyparrot")])
    #expect(Jumbomoji.items(in: ":wave::skin-tone-3: 🎉") == [.shortcode("wave"), .character("🎉")])
    #expect(Jumbomoji.items(in: "👍🏽👨‍👩‍👧") == [.character("👍🏽"), .character("👨‍👩‍👧")])
}

@Test func anythingElseIsNot() {
    #expect(Jumbomoji.items(in: "nice :tada:") == nil)
    #expect(Jumbomoji.items(in: "123") == nil, "digits are emoji by Unicode, not by look")
    #expect(Jumbomoji.items(in: "#1") == nil)
    #expect(Jumbomoji.items(in: "") == nil)
    #expect(Jumbomoji.items(in: "   ") == nil)
    #expect(Jumbomoji.items(in: String(repeating: ":a:", count: 24)) == nil, "more than Slack shows large")
}
