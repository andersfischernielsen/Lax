import Foundation

/// Unread state per conversation, for sidebar badges.
public struct UnreadState: Equatable, Sendable {
    public struct Counts: Equatable, Sendable {
        public var hasUnreads: Bool
        /// Mentions of the user; every new message counts in a DM.
        public var mentions: Int

        public init(hasUnreads: Bool = false, mentions: Int = 0) {
            self.hasUnreads = hasUnreads
            self.mentions = mentions
        }
    }

    public private(set) var byConversation: [String: Counts] = [:]

    public init(_ counts: [String: Counts] = [:]) {
        byConversation = counts
    }

    public subscript(conversation: String) -> Counts {
        byConversation[conversation] ?? Counts()
    }

    /// A new message arrived over the real-time connection.
    public mutating func received(_ message: SlackMessage, in conversation: SlackConversation,
                                  ownUserID: String, isOpen: Bool) {
        guard !isOpen, message.userID != ownUserID, message.isChannelLevel else { return }
        var counts = self[conversation.id]
        counts.hasUnreads = true
        if conversation.isDirect || message.mentions(userID: ownUserID) { counts.mentions += 1 }
        byConversation[conversation.id] = counts
    }

    /// Slack reported the read position moved (here or in another client).
    public mutating func marked(_ conversation: String, unreadCount: Int, mentionCount: Int) {
        byConversation[conversation] = Counts(hasUnreads: unreadCount > 0, mentions: mentionCount)
    }

    /// The user opened the conversation.
    public mutating func read(_ conversation: String) {
        byConversation[conversation] = Counts()
    }
}

extension SlackConversation {
    public var isDirect: Bool { kind == .directMessage || kind == .groupDirectMessage }
}

extension SlackMessage {
    /// Shown in the channel itself: not a thread reply, unless also sent to the channel.
    public var isChannelLevel: Bool {
        guard let threadTS, threadTS != ts else { return true }
        return subtype == "thread_broadcast"
    }

    /// Mentions the user directly, or via @here, @channel or @everyone.
    public func mentions(userID: String) -> Bool {
        text.contains("<@\(userID)>") || text.contains("<@\(userID)|")
            || text.contains("<!here") || text.contains("<!channel") || text.contains("<!everyone")
    }
}
