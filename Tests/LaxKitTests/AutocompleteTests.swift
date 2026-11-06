import Testing
@testable import LaxKit

@Test func findsTheWordBeingCompleted() {
    #expect(Autocomplete.token(in: "hi @ja") == .init(kind: .mention, query: "ja", start: 3))
    #expect(Autocomplete.token(in: "#gen") == .init(kind: .channel, query: "gen", start: 0))
    #expect(Autocomplete.token(in: "nice :ta") == .init(kind: .emoji, query: "ta", start: 5))
    #expect(Autocomplete.token(in: "@") == .init(kind: .mention, query: "", start: 0))
}

@Test func ignoresWordsThatArentCompletions() {
    #expect(Autocomplete.token(in: "hi there") == nil)
    #expect(Autocomplete.token(in: "hi @jane ") == nil, "a space ends the word")
    #expect(Autocomplete.token(in: "time 10:3") == nil, "not after a digit-less trigger")
    #expect(Autocomplete.token(in: "nice :t") == nil, "emoji need two characters")
    #expect(Autocomplete.token(in: "nice :tada:") == nil, "a finished emoji")
    #expect(Autocomplete.token(in: "") == nil)
}

@Test func completingReplacesTheWord() throws {
    let token = try #require(Autocomplete.token(in: "hi @ja"))
    #expect(Autocomplete.completing("hi @ja", token: token, with: "@Jane Doe") == "hi @Jane Doe ")
}

@Test func mentionsBecomeSlackTokens() {
    let mentions = ["@Jane": "<@U9>", "@Jane Doe": "<@U2>", "#general": "<#C1>"]
    #expect(Autocomplete.encodingMentions(in: "@Jane Doe in #general", mentions) == "<@U2> in <#C1>")
}
