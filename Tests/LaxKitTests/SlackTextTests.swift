import Foundation
import Testing
@testable import LaxKit

private let text = SlackText(
    userName: { ["U1": "jane"][$0] },
    channelName: { ["C1": "general"][$0] },
    subteamHandle: { ["S1": "platform"][$0] },
    customEmoji: { ["hi-wave": .image(URL(string: "https://emoji.slack-edge.com/T1/hi-wave/1.gif")!),
                    "yes": .character("👍")][$0] }
)

private func runs(_ attributed: AttributedString) -> [(String, InlinePresentationIntent?)] {
    attributed.runs.map { (String(attributed[$0.range].characters), $0.inlinePresentationIntent) }
}

@Test func resolvesMentions() {
    #expect(text.plain("hi <@U1>, see <#C1> and <#C9|random>") == "hi @jane, see #general and #random")
    #expect(text.plain("<@U9>") == "@U9")
    #expect(text.plain("<!here> <!channel> <!subteam^S2|@design>") == "@here @channel @design")
    #expect(text.plain("<!subteam^S1> <!subteam^S9>") == "@platform @group")
}

@Test func emphasisSpansMentions() {
    let result = runs(text.attributed("*IMPORTANT <!here>* now"))
    #expect(result.map(\.0) == ["IMPORTANT @here", " now"])
    #expect(result.map(\.1) == [.stronglyEmphasized, nil])
}

@Test func linkInsideEmphasisKeepsBoth() {
    let attributed = text.attributed("_see <https://x.io|docs>_")
    let link = attributed.runs.first { $0.link != nil }
    #expect(link?.inlinePresentationIntent == .emphasized)
}

@Test func replacesEmojiShortcodes() {
    #expect(text.plain("ship it :tada: :+1::skin-tone-2: :red_circle::") == "ship it 🎉 👍🏻 🔴:")
    #expect(text.plain("at 10:30:45") == "at 10:30:45")
}

@Test func tagsCustomEmojiAndLeavesUnknownNames() {
    let attributed = text.attributed(":hi-wave: :not-an-emoji: :yes:")
    #expect(String(attributed.characters) == ":hi-wave: :not-an-emoji: 👍")
    #expect(attributed.runs.compactMap { $0[SlackAttributes.CustomEmoji.self] } == ["hi-wave"])
}

@Test func codeKeepsShortcodes() {
    #expect(text.plain("`:tada:`") == ":tada:")
}

@Test func marksQuoteLines() {
    let attributed = text.attributed("intro\n&gt; quoted *bold*\nafter")
    #expect(String(attributed.characters) == "intro\nquoted bold\nafter")
    let quoted = attributed.runs.filter { $0[SlackAttributes.Quote.self] == true }
        .map { String(attributed[$0.range].characters) }.joined()
    #expect(quoted == "quoted bold")
}

@Test func mentionsAreBold() {
    #expect(runs(text.attributed("hi <@U1>")).last?.1 == .stronglyEmphasized)
}

@Test func turnsLinksIntoLinkRuns() {
    let attributed = text.attributed("go <https://example.com/a?b=1&amp;c=2|here> or <mailto:a@b.c|a@b.c> or <https://x.io>")
    #expect(String(attributed.characters) == "go here or a@b.c or https://x.io")
    let links = attributed.runs.compactMap(\.link).map(\.absoluteString)
    #expect(links == ["https://example.com/a?b=1&c=2", "mailto:a@b.c", "https://x.io"])
}

@Test func unescapesEntities() {
    #expect(text.plain("a &lt;b&gt; &amp;&amp; c") == "a <b> && c")
}

@Test func appliesEmphasis() {
    let result = runs(text.attributed("*bold* _it_ ~gone~ `x = 1`"))
    #expect(result.map(\.0) == ["bold", " ", "it", " ", "gone", " ", "x = 1"])
    #expect(result.map(\.1) == [.stronglyEmphasized, nil, .emphasized, nil, .strikethrough, nil, .code])
}

@Test func leavesInWordMarkersAlone() {
    #expect(text.plain("snake_case_name and 2*3*4") == "snake_case_name and 2*3*4")
}

@Test func codeBlocksDropFences() {
    #expect(text.plain("```\nlet x = *1*\n```") == "let x = *1*")
}

@Test func findsMentionedUsers() {
    #expect(SlackText.mentionedUserIDs(in: "<@U1> <@U2|bob> <#C1>") == ["U1", "U2"])
}

@Test func customEmojiAliasesResolve() {
    let resolved = Emoji.resolveCustom([
        "hi-wave": "https://emoji.slack-edge.com/T1/hi-wave/1.gif",
        "wave2": "alias:hi-wave",
        "yes": "alias:+1",
        "loop-a": "alias:loop-b", "loop-b": "alias:loop-a",
        "broken": "alias:does-not-exist",
    ])
    #expect(resolved["wave2"] == .image(URL(string: "https://emoji.slack-edge.com/T1/hi-wave/1.gif")!))
    #expect(resolved["yes"] == .character("👍"))
    #expect(resolved["loop-a"] == nil)
    #expect(resolved["broken"] == nil)
}

@Test func sendingEscapesTextButKeepsTokens() {
    #expect(SlackText.encodedForSending("a < b && c > d") == "a &lt; b &amp;&amp; c &gt; d")
    #expect(SlackText.encodedForSending("hi <@U1> see <https://x.io?a=1&b=2|docs> <!here> <not a token>")
            == "hi <@U1> see <https://x.io?a=1&b=2|docs> <!here> &lt;not a token&gt;")
}

@Test func editingRoundTrips() {
    let markup = "a &lt; b &amp; <@U1> <https://x.io|docs>"
    let editable = SlackText.editable(markup)
    #expect(editable == "a < b & <@U1> <https://x.io|docs>")
    #expect(SlackText.encodedForSending(editable) == markup)
}
