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

    public func react(_ name: String, to ts: String, in channel: String, added: Bool) async throws {
        let _: Empty = try await call(added ? "reactions.add" : "reactions.remove",
                                      ["channel": channel, "timestamp": ts, "name": name])
    }

    /// Unread state for every conversation, as Slack's web client fetches it on start.
    public func unreadCounts() async throws -> UnreadState {
        let response: CountsResponse = try await call("client.counts", ["thread_counts_by_channel": "true"])
        let all = (response.channels ?? []) + (response.mpims ?? []) + (response.ims ?? [])
        return UnreadState(Dictionary(all.map {
            ($0.id, UnreadState.Counts(hasUnreads: $0.hasUnreads ?? false, mentions: $0.mentionCount ?? 0))
        }, uniquingKeysWith: { first, _ in first }))
    }

    /// User group ID → handle (without the @), for `<!subteam^S…>` mentions.
    public func userGroupHandles() async throws -> [String: String] {
        let response: UserGroupsResponse = try await call("usergroups.list", ["include_disabled": "true"])
        return Dictionary(response.usergroups.map { ($0.id, $0.handle) }, uniquingKeysWith: { first, _ in first })
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

private struct ConversationInfoResponse: Decodable {
    struct Channel: Decodable {
        let lastRead: String?

        enum CodingKeys: String, CodingKey {
            case lastRead = "last_read"
        }
    }

    let channel: Channel
}

private struct CountsResponse: Decodable {
    struct Conversation: Decodable {
        let id: String
        let hasUnreads: Bool?
        let mentionCount: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case hasUnreads = "has_unreads"
            case mentionCount = "mention_count"
        }
    }

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
