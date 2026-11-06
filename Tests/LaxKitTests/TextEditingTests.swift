import Testing
@testable import LaxKit

@Test func replacingInsertsAtTheCursor() {
    #expect(TextEditing.replacing(3..<3, in: "onetwo", with: "\n") == ("one\ntwo", 4))
    #expect(TextEditing.replacing(0..<3, in: "onetwo", with: "1") == ("1two", 1))
}

@Test func replacingClampsRangesOutsideTheText() {
    #expect(TextEditing.replacing(10..<12, in: "abc", with: "\n") == ("abc\n", 4))
    #expect(TextEditing.replacing(-2..<1, in: "abc", with: "x") == ("xbc", 1))
    #expect(TextEditing.replacing(-5 ..< -2, in: "abc", with: "x") == ("xabc", 1))
}

@Test func replacingCountsCharactersNotBytes() {
    #expect(TextEditing.replacing(2..<2, in: "🎉é", with: "!") == ("🎉é!", 3))
}
