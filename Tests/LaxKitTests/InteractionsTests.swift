import Foundation
import Testing

@testable import LaxKit

@Test func slashCommandsSplitIntoCommandAndText() {
    #expect(
        SlashCommand("/remind me to stretch in 1 hour") == SlashCommand.parsed("/remind", "me to stretch in 1 hour"))
    #expect(SlashCommand("/giphy") == SlashCommand.parsed("/giphy", ""))
    #expect(SlashCommand(#"/poll "Lunch?" "Pizza""#)?.text == #""Lunch?" "Pizza""#)
    #expect(SlashCommand("/note first line\nsecond line")?.text == "first line\nsecond line")
}

@Test func onlyACommandAtTheStartCounts() {
    #expect(SlashCommand("see /remind") == nil)
    #expect(SlashCommand("//not a command") == nil)
    #expect(SlashCommand("/") == nil)
    #expect(SlashCommand("hello") == nil)
}

@Test func buttonsComeFromActionsBlocksAndSectionAccessories() throws {
    let blocks = try JSONDecoder().decode(
        [JSONValue].self,
        from: Data(
            #"""
            [{"type":"section","block_id":"b1","text":{"type":"mrkdwn","text":"Deploy?"},
              "accessory":{"type":"button","action_id":"details","text":{"type":"plain_text","text":"Details"},"url":"https://example.com"}},
             {"type":"actions","block_id":"b2","elements":[
               {"type":"button","action_id":"approve","text":{"type":"plain_text","text":"Approve"},"value":"yes","style":"primary"},
               {"type":"static_select","action_id":"pick"},
               {"type":"button","action_id":"deny","text":{"type":"plain_text","text":"Deny"},"style":"danger"}]}]
            """#.utf8))
    let buttons = BlockKit.buttons(in: blocks)
    #expect(buttons.map(\.actionID) == ["details", "approve", "deny"])
    #expect(buttons[0].url?.absoluteString == "https://example.com")
    #expect(buttons[1].blockID == "b2" && buttons[1].value == "yes" && buttons[1].style == .primary)
    #expect(buttons[2].style == .danger)
}

// In EndpointTests: the URL stub is shared, so these must not run alongside its other tests.
extension EndpointTests {
    @Test func commandsGoToChatCommand() async throws {
        StubURLProtocol.reset(["chat.command": [#"{"ok":true}"#]])
        try await client.run(try #require(SlashCommand("/remind me later")), in: "C1")
        let fields = StubURLProtocol.requests[0].formFields
        #expect(fields["channel"] == "C1")
        #expect(fields["command"] == "/remind")
        #expect(fields["text"] == "me later")
        #expect(fields["disp"] == "/remind")
        #expect(fields["client_token"]?.hasPrefix("web-") == true)
    }

    @Test func buttonPressesGoToBlocksActions() async throws {
        StubURLProtocol.reset(["blocks.actions": [#"{"ok":true}"#]])
        let message = SlackMessage(ts: "5.0", userID: "U9", text: "", botID: "B1")
        let button = BlockButton(
            blockID: "b2", actionID: "approve", text: "Approve", value: "yes", url: nil, style: .primary)
        try await client.press(button, on: message, in: "C1")
        let fields = StubURLProtocol.requests[0].formFields
        #expect(
            fields["actions"]
                == #"[{"action_id":"approve","block_id":"b2","text":{"text":"Approve","type":"plain_text"},"type":"button","value":"yes"}]"#
        )
        #expect(fields["container"] == #"{"channel_id":"C1","is_ephemeral":false,"message_ts":"5.0","type":"message"}"#)
        #expect(fields["service_id"] == "B1")
        #expect(fields["bot_user_id"] == "U9")
    }
}

extension SlashCommand {
    static func parsed(_ command: String, _ text: String) -> SlashCommand? {
        SlashCommand(text.isEmpty ? command : command + " " + text)
    }
}
