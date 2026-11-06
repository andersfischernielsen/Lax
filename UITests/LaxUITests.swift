import XCTest

/// Drives Lax against its fixture workspace (`-ui-testing`): channels #general, #random and
/// #design (unread, with a mention), DMs with Jane Doe (newest) and Bob Lee, and a lunch
/// thread in #general with two replies.
@MainActor
final class LaxUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        // A failed expectation ends the test there, so later steps don't act on a wrong state.
        continueAfterFailure = false
        app = XCUIApplication()
        // A clean slate every time: fixture data, and no restored windows or scene state.
        app.launchArguments = ["-ui-testing", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        expect(element("conversation-C1"), "the channel list loads")
    }

    override func tearDown() async throws {
        app.terminate()
    }

    // MARK: - Views

    func testChannelsListsOnlyChannels() {
        expect(element("conversation-C3"), "#design is listed")
        XCTAssertFalse(element("conversation-D1").exists, "DMs belong in their own view")
    }

    func testDirectMessagesListsDMsByActivity() {
        app.typeKey("2", modifierFlags: .command)
        let jane = expect(element("conversation-D1"), "Jane's DM is listed")
        let bob = expect(element("conversation-D2"), "Bob's DM is listed")
        XCTAssertLessThan(jane.frame.minY, bob.frame.minY, "the most recently active DM comes first")
        XCTAssertFalse(element("conversation-C1").exists)
    }

    func testThreadsListsFollowedThreadsAndOpensThem() {
        app.typeKey("3", modifierFlags: .command)
        expect(element("followed-thread-C1/1700000020.000000"), "the lunch thread is listed").click()
        expect(element("message-1700000040.000000"), "its replies show")
        expect(element("thread-composer"), "with a reply field")
    }

    // MARK: - Open Quickly

    func testOpenQuicklyGoesToTheTypedConversation() {
        app.typeKey("k", modifierFlags: .command)
        let field = expect(element("quick-switcher-field"), "the panel opens")
        field.typeText("rand")
        expect(element("quick-switcher-C2"), "#random matches")
        field.typeKey(.return, modifierFlags: [])
        XCTAssertFalse(element("quick-switcher-field").waitForExistence(timeout: 1), "the panel closes")
        expect(app.windows["#random"], "#random opens")
    }

    func testOpenQuicklyArrowsMoveThroughMatches() {
        app.typeKey("k", modifierFlags: .command)
        let field = expect(element("quick-switcher-field"), "the panel opens")
        // "e" matches several channels; ↓ then Return opens the second match.
        field.typeText("e")
        let matches = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'quick-switcher-C'"))
        expect(matches.firstMatch, "matches show")
        let second = matches.element(boundBy: 1).identifier.replacingOccurrences(of: "quick-switcher-", with: "")
        field.typeKey(.downArrow, modifierFlags: [])
        field.typeKey(.return, modifierFlags: [])
        let row = expect(element("conversation-\(second)"), "the second match's conversation is listed")
        XCTAssertTrue(row.isSelected, "and it's the one open")
    }

    // MARK: - Back and forward

    func testBackAndForwardRetraceConversations() {
        element("conversation-C1").click()
        expect(app.windows["#general"], "#general opens")
        element("conversation-C2").click()
        expect(app.windows["#random"], "#random opens")

        app.typeKey("[", modifierFlags: .command)
        expect(app.windows["#general"], "⌘[ goes back to #general")
        app.typeKey("]", modifierFlags: .command)
        expect(app.windows["#random"], "⌘] goes forward to #random")

        element("back").click()
        expect(app.windows["#general"], "the toolbar's back button works too")
    }

    // MARK: - Messages and threads

    func testSelectingAMessageShowsItsThreadInTheInspector() {
        element("conversation-C1").click()
        expect(element("no-thread"), "the inspector starts empty")
        expect(element("message-1700000020.000000"), "the lunch message shows").click()
        expect(element("thread-view"), "its thread opens beside the conversation")
        expect(element("message-1700000030.000000"), "with Bob's reply")
    }

    func testArrowKeysMoveThroughThreadReplies() {
        element("conversation-C1").click()
        expect(element("message-1700000020.000000"), "the lunch message shows").click()
        let firstReply = expect(element("message-1700000030.000000"), "the thread loads")
        firstReply.click()
        XCTAssertTrue(firstReply.isSelected)
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(element("message-1700000040.000000").isSelected, "↓ selects the next reply")
    }

    func testSendingAMessageShowsItInTheConversation() {
        element("conversation-C2").click()
        let composer = expect(element("composer"), "the message field shows")
        composer.click()
        composer.typeText("Hello from the tests\r")
        expect(element("message-1700000900.000000"), "the sent message shows")
    }

    // MARK: - Composer

    func testMentionSuggestionsCompleteWithTab() {
        element("conversation-C2").click()
        let composer = expect(element("composer"), "the message field shows")
        composer.click()
        composer.typeText("Hi @ja")
        expect(element("suggestion-U2"), "Jane is suggested")
        composer.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(composer.value as? String, "Hi @Jane Doe ")
    }

    func testChannelSuggestionsCompleteWithReturn() {
        element("conversation-C2").click()
        let composer = expect(element("composer"), "the message field shows")
        composer.click()
        composer.typeText("See #ran")
        expect(element("suggestion-C2"), "#random is suggested")
        composer.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(composer.value as? String, "See #random ")
        XCTAssertFalse(element("message-1700000900.000000").exists, "Return took the suggestion, not sent")
    }

    func testShiftReturnStartsANewLine() {
        element("conversation-C2").click()
        let composer = expect(element("composer"), "the message field shows")
        composer.click()
        composer.typeText("one")
        composer.typeKey(.return, modifierFlags: .shift)
        composer.typeText("two")
        composer.typeKey(.return, modifierFlags: .option)
        composer.typeText("three")
        XCTAssertEqual(composer.value as? String, "one\ntwo\nthree")
        XCTAssertFalse(element("message-1700000900.000000").exists, "nothing was sent")
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Waits for `element`; if it never appears the test fails, saying what was expected.
    @discardableResult
    private func expect(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 5) -> XCUIElement {
        let appeared = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(appeared, "Expected: \(what)")
        return element
    }
}
