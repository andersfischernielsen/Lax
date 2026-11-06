import Foundation

/// A thread the user follows, as Slack's Threads view lists it.
public struct ThreadSummary: Decodable, Equatable, Identifiable, Sendable {
    public let channelID: String
    public let root: SlackMessage
    /// The newest replies, oldest first; Slack sends a few.
    public internal(set) var latestReplies: [SlackMessage]
    public internal(set) var unreadReplies: Int
    public internal(set) var latestReplyTS: String?

    public var id: String { "\(channelID)/\(root.ts)" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        root = try c.decode(SlackMessage.self, forKey: .rootMessage)
        let rootInfo = try c.decode(RootInfo.self, forKey: .rootMessage)
        channelID = rootInfo.channel
        latestReplyTS = rootInfo.latestReply
        latestReplies = (try c.decodeIfPresent([Failable<SlackMessage>].self, forKey: .latestReplies) ?? [])
            .compactMap(\.value).sorted { $0.ts.localizedStandardCompare($1.ts) == .orderedAscending }
        unreadReplies = (try c.decodeIfPresent([Failable<SlackMessage>].self, forKey: .unreadReplies))?.count ?? 0
    }

    private enum Keys: String, CodingKey {
        case rootMessage = "root_msg"
        case latestReplies = "latest_replies"
        case unreadReplies = "unread_replies"
    }

    private struct RootInfo: Decodable {
        let channel: String
        let latestReply: String?

        enum CodingKeys: String, CodingKey {
            case channel
            case latestReply = "latest_reply"
        }
    }
}

extension [ThreadSummary] {
    /// The list after a reply arrived: its thread moves to the top with the reply, unread
    /// unless the user wrote it. Replies to threads not in the list change nothing.
    public func receiving(_ reply: SlackMessage, in channel: String, ownUserID: String) -> [ThreadSummary] {
        guard let threadTS = reply.threadTS, threadTS != reply.ts,
              let index = firstIndex(where: { $0.channelID == channel && $0.root.ts == threadTS }) else { return self }
        var thread = self[index]
        guard !thread.latestReplies.contains(where: { $0.ts == reply.ts }) else { return self }
        thread.latestReplies.append(reply)
        thread.latestReplyTS = reply.ts
        if reply.userID != ownUserID { thread.unreadReplies += 1 }
        var result = self
        result.remove(at: index)
        return [thread] + result
    }

    /// The list with a thread read.
    public func markingRead(_ id: ThreadSummary.ID) -> [ThreadSummary] {
        map { thread in
            var thread = thread
            if thread.id == id { thread.unreadReplies = 0 }
            return thread
        }
    }
}

public struct ThreadsPage: Sendable {
    /// Most recently active first.
    public let threads: [ThreadSummary]
    public let hasMore: Bool
}

extension SlackAPIClient {
    /// Followed threads, most recently active first, older than `before` (a reply `ts`) if given.
    public func followedThreads(before: String? = nil, limit: Int = 20, now: Date = .now) async throws -> ThreadsPage {
        let response: ThreadsResponse = try await call("subscriptions.thread.getView", [
            "current_ts": before ?? String(format: "%.6f", now.timeIntervalSince1970),
            "limit": String(limit),
        ])
        return ThreadsPage(threads: response.threads.compactMap(\.value), hasMore: response.hasMore ?? false)
    }

    /// Marks a thread read up to `ts`, its newest reply.
    public func markThreadRead(channel: String, threadTS: String, ts: String) async throws {
        let _: ThreadMarkResponse = try await call("subscriptions.thread.mark", [
            "channel": channel, "thread_ts": threadTS, "ts": ts, "read": "1",
        ])
    }
}

private struct ThreadsResponse: Decodable {
    let threads: [Failable<ThreadSummary>]
    let hasMore: Bool?

    enum CodingKeys: String, CodingKey {
        case threads
        case hasMore = "has_more"
    }
}

private struct ThreadMarkResponse: Decodable {}
