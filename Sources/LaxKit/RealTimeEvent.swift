import Foundation

/// An event from Slack's real-time WebSocket that Lax acts on.
public enum RealTimeEvent: Equatable, Sendable {
    case hello
    case goodbye
    case message(channel: String, SlackMessage)
    case messageChanged(channel: String, SlackMessage)
    case messageDeleted(channel: String, ts: String)
    case userTyping(channel: String, userID: String)
    case other(type: String)

    /// Subtypes that are ordinary messages to show in the timeline.
    static let displayableSubtypes: Set<String?> = [
        nil, "bot_message", "me_message", "thread_broadcast", "file_share",
        "channel_join", "channel_leave", "channel_topic", "channel_purpose", "channel_name",
    ]

    /// nil for frames that aren't events, e.g. replies to our own pings.
    public static func parse(_ data: Data) -> RealTimeEvent? {
        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(Envelope.self, from: data), let type = envelope.type else {
            return nil
        }
        switch type {
        case "hello":
            return .hello
        case "goodbye":
            return .goodbye
        case "user_typing":
            guard let channel = envelope.channel, let user = envelope.user else { return nil }
            return .userTyping(channel: channel, userID: user)
        case "message":
            return parseMessage(envelope, data: data, decoder: decoder)
        default:
            return .other(type: type)
        }
    }

    private static func parseMessage(_ envelope: Envelope, data: Data, decoder: JSONDecoder) -> RealTimeEvent? {
        guard let channel = envelope.channel else { return nil }
        switch envelope.subtype {
        case "message_changed":
            return envelope.message.map { .messageChanged(channel: channel, $0) }
        case "message_deleted":
            return envelope.deletedTS.map { .messageDeleted(channel: channel, ts: $0) }
        case let subtype where displayableSubtypes.contains(subtype):
            return (try? decoder.decode(SlackMessage.self, from: data)).map { .message(channel: channel, $0) }
        default:
            return .other(type: "message/" + (envelope.subtype ?? ""))
        }
    }

    private struct Envelope: Decodable {
        let type: String?
        let subtype: String?
        let channel: String?
        let user: String?
        let message: SlackMessage?
        let deletedTS: String?

        enum CodingKeys: String, CodingKey {
            case type, subtype, channel, user, message
            case deletedTS = "deleted_ts"
        }
    }
}
