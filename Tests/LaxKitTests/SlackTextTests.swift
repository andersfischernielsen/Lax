import Foundation
import Testing
@testable import LaxKit

private let text = SlackText(
    userName: { ["U1": "jane"][$0] },
    channelName: { ["C1": "general"][$0] }
)

private func runs(_ attributed: AttributedString) -> [(String, InlinePresentationIntent?)] {
    attributed.runs.map { (String(attributed[$0.range].characters), $0.inlinePresentationIntent) }
}

@Test func resolvesMentions() {
    #expect(text.plain("hi <@U1>, see <#C1> and <#C9|random>") == "hi @jane, see #general and #random")
    #expect(text.plain("<@U9>") == "@U9")
    #expect(text.plain("<!here> <!channel> <!subteam^S1|@design>") == "@here @channel @design")
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
