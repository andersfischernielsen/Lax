import Foundation

public struct HistoryPage: Sendable {
    /// Newest first, as Slack returns them.
    public let messages: [SlackMessage]
    public let hasMore: Bool
}

extension SlackAPIClient {
    /// Every open conversation the user belongs to: channels, private channels, DMs and group DMs.
    public func conversations() async throws -> [SlackConversation] {
        var all: [SlackConversation] = []
        var cursor: String?
        repeat {
            var params = ["types": "public_channel,private_channel,mpim,im", "exclude_archived": "true", "limit": "200"]
            params["cursor"] = cursor
            let page: ConversationsPage = try await call("users.conversations", params)
            all += page.channels
            cursor = page.responseMetadata?.nextCursor?.nilIfEmpty
        } while cursor != nil
        return all
    }

    /// Up to `limit` messages before `latest` (a message `ts`), or the newest ones.
    public func history(channel: String, limit: Int = 50, before latest: String? = nil) async throws -> HistoryPage {
        var params = ["channel": channel, "limit": String(limit)]
        params["latest"] = latest
        let response: HistoryResponse = try await call("conversations.history", params)
        return HistoryPage(messages: response.messages, hasMore: response.hasMore ?? false)
    }

    /// `ts` of the last message the user has read here, if Slack tracks it for this conversation.
    public func lastRead(channel: String) async throws -> String? {
        let response: ConversationInfoResponse = try await call("conversations.info", ["channel": channel])
        return response.channel.lastRead
    }

    /// Moves the read position to `ts`, which every Slack client follows.
    public func markRead(channel: String, ts: String) async throws {
        let _: Empty = try await call("conversations.mark", ["channel": channel, "ts": ts])
    }

    public func editMessage(_ ts: String, in channel: String, text: String) async throws {
        let _: Empty = try await call("chat.update", ["channel": channel, "ts": ts, "text": text])
    }

    public func deleteMessage(_ ts: String, in channel: String) async throws {
        let _: Empty = try await call("chat.delete", ["channel": channel, "ts": ts])
    }

    /// A link to the message that opens it in Slack.
    public func permalink(to ts: String, in channel: String) async throws -> URL {
        let response: PermalinkResponse = try await call("chat.getPermalink", ["channel": channel, "message_ts": ts])
        guard let url = URL(string: response.permalink) else { throw SlackAPIError.invalidResponse }
        return url
    }

    public func react(_ name: String, to ts: String, in channel: String, added: Bool) async throws {
        let _: Empty = try await call(added ? "reactions.add" : "reactions.remove",
                                      ["channel": channel, "timestamp": ts, "name": name])
    }

    /// Unread state and latest activity for every conversation, and for followed threads,
    /// as Slack's web client fetches it on start.
    public func clientCounts() async throws -> ClientCounts {
        let response: CountsResponse = try await call("client.counts", ["thread_counts_by_channel": "true"])
        let all = (response.channels ?? []) + (response.mpims ?? []) + (response.ims ?? [])
        return ClientCounts(
            unread: UnreadState(Dictionary(all.map {
                ($0.id, UnreadState.Counts(hasUnreads: $0.hasUnreads ?? false, mentions: $0.mentionCount ?? 0))
            }, uniquingKeysWith: { first, _ in first })),
            latest: Dictionary(all.compactMap { c in c.latest.map { (c.id, $0) } }, uniquingKeysWith: { first, _ in first }),
            threads: UnreadState.Counts(hasUnreads: response.threads?.hasUnreads ?? false,
                                        mentions: response.threads?.mentionCount ?? 0)
        )
    }

    /// User group ID → handle (without the @), for `<!subteam^S…>` mentions.
    public func userGroupHandles() async throws -> [String: String] {
        let response: UserGroupsResponse = try await call("usergroups.list", ["include_disabled": "true"])
        return Dictionary(response.usergroups.map { ($0.id, $0.handle) }, uniquingKeysWith: { first, _ in first })
    }

    /// Changes the user's display name, the name Slack shows in place of their full name.
    public func setDisplayName(_ name: String) async throws {
        let profile = try JSONEncoder().encode(["display_name": name])
        let _: Empty = try await call("users.profile.set", ["profile": String(decoding: profile, as: UTF8.self)])
    }

    /// Messages matching a search, newest first.
    public func searchMessages(_ query: String, count: Int = 50) async throws -> [SearchResult] {
        let response: SearchResponse = try await call("search.messages", [
            "query": query, "count": String(count), "sort": "timestamp", "sort_dir": "desc",
        ])
        return response.messages.matches.compactMap(\.value)
    }

    /// Pinned messages, most recently pinned first.
    public func pinnedMessages(in channel: String) async throws -> [SlackMessage] {
        let response: PinsResponse = try await call("pins.list", ["channel": channel])
        return response.items.compactMap(\.value?.message)
    }

    /// Member user IDs of a conversation.
    public func members(of channel: String) async throws -> [String] {
        var all: [String] = []
        var cursor: String?
        repeat {
            var params = ["channel": channel, "limit": "200"]
            params["cursor"] = cursor
            let page: MembersResponse = try await call("conversations.members", params)
            all += page.members
            cursor = page.responseMetadata?.nextCursor?.nilIfEmpty
        } while cursor != nil
        return all
    }

    /// A whole thread: the parent first, then every reply.
    public func replies(channel: String, threadTS: String) async throws -> [SlackMessage] {
        var all: [SlackMessage] = []
        var cursor: String?
        repeat {
            var params = ["channel": channel, "ts": threadTS, "limit": "200"]
            params["cursor"] = cursor
            let page: RepliesResponse = try await call("conversations.replies", params)
            all += page.messages
            cursor = page.responseMetadata?.nextCursor?.nilIfEmpty
        } while cursor != nil
        return all
    }

    public func user(id: String) async throws -> SlackUser {
        let response: UserResponse = try await call("users.info", ["user": id])
        return response.user
    }

    @discardableResult
    public func postMessage(channel: String, text: String, threadTS: String? = nil) async throws -> SlackMessage {
        var params = ["channel": channel, "text": text]
        params["thread_ts"] = threadTS
        let response: PostMessageResponse = try await call("chat.postMessage", params)
        return response.message
    }

    /// WebSocket URL for real-time events.
    public func realTimeURL() async throws -> URL {
        let response: RTMConnectResponse = try await call("rtm.connect")
        guard let url = URL(string: response.url) else { throw SlackAPIError.invalidResponse }
        return url
    }
}

private struct ResponseMetadata: Decodable {
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case nextCursor = "next_cursor"
    }
}

private struct ConversationsPage: Decodable {
    let channels: [SlackConversation]
    let responseMetadata: ResponseMetadata?

    enum CodingKeys: String, CodingKey {
        case channels
        case responseMetadata = "response_metadata"
    }
}

private struct HistoryResponse: Decodable {
    let messages: [SlackMessage]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
    }
}

private struct Empty: Decodable {}

private struct SearchResponse: Decodable {
    struct Matches: Decodable {
        let matches: [Failable<SearchResult>]
    }

    let messages: Matches
}

private struct PinsResponse: Decodable {
    /// Pinned files come back without a message; those are skipped.
    struct Item: Decodable {
        let message: SlackMessage?
    }

    let items: [Failable<Item>]
}

private struct MembersResponse: Decodable {
    let members: [String]
    let responseMetadata: ResponseMetadata?

    enum CodingKeys: String, CodingKey {
        case members
        case responseMetadata = "response_metadata"
    }
}

private struct PermalinkResponse: Decodable {
    let permalink: String
}

private struct RepliesResponse: Decodable {
    let messages: [SlackMessage]
    let responseMetadata: ResponseMetadata?

    enum CodingKeys: String, CodingKey {
        case messages
        case responseMetadata = "response_metadata"
    }
}

private struct ConversationInfoResponse: Decodable {
    struct Channel: Decodable {
        let lastRead: String?

        enum CodingKeys: String, CodingKey {
            case lastRead = "last_read"
        }
    }

    let channel: Channel
}

public struct ClientCounts: Sendable {
    public let unread: UnreadState
    /// `ts` of each conversation's newest message, for ordering by activity.
    public let latest: [String: String]
    /// Followed threads, taken together.
    public let threads: UnreadState.Counts
}

private struct CountsResponse: Decodable {
    struct Conversation: Decodable {
        let id: String
        let hasUnreads: Bool?
        let mentionCount: Int?
        let latest: String?

        enum CodingKeys: String, CodingKey {
            case id, latest
            case hasUnreads = "has_unreads"
            case mentionCount = "mention_count"
        }
    }

    struct Threads: Decodable {
        let hasUnreads: Bool?
        let mentionCount: Int?

        enum CodingKeys: String, CodingKey {
            case hasUnreads = "has_unreads"
            case mentionCount = "mention_count"
        }
    }

    let threads: Threads?

    let channels: [Conversation]?
    let mpims: [Conversation]?
    let ims: [Conversation]?
}

private struct UserGroupsResponse: Decodable {
    struct Group: Decodable {
        let id: String
        let handle: String
    }

    let usergroups: [Group]
}

private struct UserResponse: Decodable {
    let user: SlackUser
}

private struct PostMessageResponse: Decodable {
    let message: SlackMessage
}

private struct RTMConnectResponse: Decodable {
    let url: String
}

/// A message found by search, with the conversation it's in.
public struct SearchResult: Decodable, Identifiable, Sendable {
    public let message: SlackMessage
    public let channelID: String
    /// Channel name; nil for DMs.
    public let channelName: String?

    public var id: String { "\(channelID)/\(message.ts)" }

    public init(from decoder: Decoder) throws {
        message = try SlackMessage(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        let channel = try c.decode(Channel.self, forKey: .channel)
        channelID = channel.id
        channelName = channel.isPrivateIM == true ? nil : channel.name
    }

    private enum Keys: String, CodingKey { case channel }

    private struct Channel: Decodable {
        let id: String
        let name: String?
        let isPrivateIM: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name
            case isPrivateIM = "is_im"
        }
    }
}
