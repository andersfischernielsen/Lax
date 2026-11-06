import Foundation
import Testing
@testable import LaxKit

private func styled(_ text: String, _ intent: InlinePresentationIntent) -> AttributedString {
    var string = AttributedString(text)
    string.inlinePresentationIntent = intent
    return string
}

@Test func plainTextStaysAsTyped() {
    #expect(SlackMarkdown.mrkdwn(from: AttributedString("hello *there*")) == "hello *there*")
}

@Test func stylesBecomeSlackMarkers() {
    let text = AttributedString("say ") + styled("hi", .stronglyEmphasized) + AttributedString(", ")
        + styled("soft", .emphasized) + AttributedString(" and ") + styled("gone", .strikethrough)
        + AttributedString(" in ") + styled("code", .code)
    #expect(SlackMarkdown.mrkdwn(from: text) == "say *hi*, _soft_ and ~gone~ in `code`")
}

@Test func combinedStylesNest() {
    #expect(SlackMarkdown.mrkdwn(from: styled("both", [.stronglyEmphasized, .emphasized])) == "*_both_*")
}

@Test func markersHugTheTextAndEachLine() {
    #expect(SlackMarkdown.mrkdwn(from: AttributedString("a") + styled(" bold ", .stronglyEmphasized) + AttributedString("b"))
        == "a *bold* b")
    #expect(SlackMarkdown.mrkdwn(from: styled("one\ntwo", .stronglyEmphasized)) == "*one*\n*two*")
    #expect(SlackMarkdown.mrkdwn(from: styled("   ", .stronglyEmphasized)) == "   ")
}

@Test func multiLineCodeBecomesABlock() {
    #expect(SlackMarkdown.mrkdwn(from: styled("let a = 1\nlet b = 2", .code)) == "```let a = 1\nlet b = 2```")
}

@Test func linksKeepTheirLabel() {
    var link = AttributedString("the docs")
    link.link = URL(string: "https://example.com")
    #expect(SlackMarkdown.mrkdwn(from: AttributedString("see ") + link) == "see <https://example.com|the docs>")
}

@Test func runsSplitOnlyByStyleNotByOtherAttributes() {
    var text = styled("bo", .stronglyEmphasized) + styled("ld", .stronglyEmphasized)
    text[text.index(text.startIndex, offsetByCharacters: 2)...].languageIdentifier = "da"
    #expect(SlackMarkdown.mrkdwn(from: text) == "*bold*")
}
