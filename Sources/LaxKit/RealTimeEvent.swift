import Foundation

/// An event from Slack's real-time WebSocket that Lax acts on.
public enum RealTimeEvent: Equatable, Sendable {
    case hello
    case goodbye
    case message(channel: String, SlackMessage)
    case messageChanged(channel: String, SlackMessage)
    case messageDeleted(channel: String, ts: String)
    case userTyping(channel: String, userID: String)
    case reaction(channel: String, ts: String, name: String, userID: String, added: Bool)
    /// A user pref changed. `name` is e.g. `muted_channels` or `all_notifications_prefs`.
    case prefChange(name: String, value: String)
    /// The read position moved, here or in another client.
    case marked(channel: String, unreadCount: Int, mentionCount: Int)
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
        case "pref_change":
            guard let name = envelope.name, let value = envelope.value else { return nil }
            return .prefChange(name: name, value: value.text)
        case "reaction_added", "reaction_removed":
            guard let item = envelope.item, item.type == "message", let user = envelope.user,
                  let name = envelope.reaction else { return nil }
            return .reaction(channel: item.channel, ts: item.ts, name: name, userID: user,
                             added: type == "reaction_added")
        case "channel_marked", "group_marked", "im_marked", "mpim_marked":
            guard let channel = envelope.channel else { return nil }
            return .marked(channel: channel,
                           unreadCount: envelope.unreadCountDisplay ?? envelope.unreadCount ?? 0,
                           mentionCount: envelope.mentionCountDisplay ?? envelope.mentionCount ?? 0)
        default:
            return .other(type: type)
        }
    }

    private static func parseMessage(_ envelope: Envelope, data: Data, decoder: JSONDecoder) -> RealTimeEvent? {
        guard let channel = envelope.channel else { return nil }
        switch envelope.subtype {
        case "message_changed", "message_replied":
            // A reply arrives with its updated parent (reply count, latest reply).
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
        let unreadCount: Int?
        let unreadCountDisplay: Int?
        let mentionCount: Int?
        let mentionCountDisplay: Int?
        let reaction: String?
        let item: Item?
        let name: String?
        let value: PrefValue?

        /// Pref values arrive as strings, numbers or booleans; keep their text.
        struct PrefValue: Decodable {
            let text: String

            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let string = try? c.decode(String.self) { text = string }
                else if let bool = try? c.decode(Bool.self) { text = String(bool) }
                else if let number = try? c.decode(Double.self) { text = String(number) }
                else { text = "" }
            }
        }

        struct Item: Decodable {
            let type: String
            let channel: String
            let ts: String
        }

        enum CodingKeys: String, CodingKey {
            case type, subtype, channel, user, message, reaction, item, name, value
            case deletedTS = "deleted_ts"
            case unreadCount = "unread_count"
            case unreadCountDisplay = "unread_count_display"
            case mentionCount = "mention_count"
            case mentionCountDisplay = "mention_count_display"
        }
    }
}
