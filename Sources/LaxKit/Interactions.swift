import Foundation

/// A slash command typed in the composer: `/remind me to stretch in 1 hour`.
public struct SlashCommand: Equatable, Sendable {
    /// With its slash: `/remind`.
    public let command: String
    public let text: String

    /// The command at the start of `draft`, if it is one. `//` and a lone `/` aren't.
    public init?(_ draft: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: /(\/[a-zA-Z0-9_\-.]+)(?:\s+(.*))?/.dotMatchesNewlines()) else {
            return nil
        }
        command = String(match.1)
        text = match.2.map(String.init) ?? ""
    }
}

extension SlackAPIClient {
    /// Runs a slash command in a conversation, as Slack's own clients do; any reply
    /// arrives as a message, often one only the user sees.
    public func run(_ command: SlashCommand, in channel: String) async throws {
        let _: Empty = try await call(
            "chat.command",
            [
                "channel": channel, "command": command.command, "text": command.text,
                "disp": command.command, "client_token": Self.clientToken(),
            ])
    }

    /// Presses a bot's button on a message, which tells the bot's app.
    public func press(_ button: BlockButton, on message: SlackMessage, in channel: String) async throws {
        let action = ButtonAction(
            actionID: button.actionID, blockID: button.blockID,
            text: .init(text: button.text), value: button.value)
        let container = MessageContainer(messageTS: message.ts, channelID: channel)
        var params = [
            "actions": try Self.json([action]), "container": try Self.json(container),
            "client_token": Self.clientToken(),
        ]
        params["service_id"] = message.botID
        params["bot_user_id"] = message.userID
        let _: Empty = try await call("blocks.actions", params)
    }

    /// Identifies one request, so Slack can drop a duplicate.
    static func clientToken(now: Date = .now) -> String {
        "web-\(Int(now.timeIntervalSince1970 * 1000))"
    }

    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

/// The shapes Slack's clients send to `blocks.actions`.
private struct ButtonAction: Encodable {
    struct Text: Encodable {
        var type = "plain_text"
        let text: String
    }

    let actionID: String
    let blockID: String
    var type = "button"
    let text: Text
    let value: String?

    enum CodingKeys: String, CodingKey {
        case type, text, value
        case actionID = "action_id"
        case blockID = "block_id"
    }
}

private struct MessageContainer: Encodable {
    var type = "message"
    let messageTS: String
    let channelID: String
    var isEphemeral = false

    enum CodingKeys: String, CodingKey {
        case type
        case messageTS = "message_ts"
        case channelID = "channel_id"
        case isEphemeral = "is_ephemeral"
    }
}
