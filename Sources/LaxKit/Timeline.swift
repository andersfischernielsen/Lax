import Foundation

/// Messages oldest first: a conversation's top-level messages (thread replies stay
/// out unless also sent to the channel), or one thread's parent and replies.
public struct Timeline: Equatable, Sendable {
    /// The thread this timeline holds, or nil for a whole conversation.
    public let threadTS: String?
    public private(set) var messages: [SlackMessage] = []
    /// Slack has older messages than the first one here.
    public private(set) var hasOlder = true

    public init(threadTS: String? = nil) {
        self.threadTS = threadTS
    }

    /// A thread loaded in full from `conversations.replies`.
    public init(thread threadTS: String, messages: [SlackMessage]) {
        self.threadTS = threadTS
        hasOlder = false
        for message in messages { upsert(message) }
    }

    /// Adds a page from `conversations.history` (newest first), older than what's here.
    public mutating func addOlder(_ page: HistoryPage) {
        for message in page.messages { upsert(message) }
        hasOlder = page.hasMore
    }

    /// Adds or replaces a message, keeping order. Returns false if it doesn't belong here.
    @discardableResult
    public mutating func upsert(_ message: SlackMessage) -> Bool {
        guard belongs(message) else { return false }
        if let index = messages.firstIndex(where: { $0.ts == message.ts }) {
            messages[index] = message
        } else {
            let index = messages.firstIndex { Self.isOrdered(message.ts, before: $0.ts) } ?? messages.endIndex
            messages.insert(message, at: index)
        }
        return true
    }

    /// Replaces an edited message; ignored if it isn't loaded.
    public mutating func replace(_ message: SlackMessage) {
        guard let index = messages.firstIndex(where: { $0.ts == message.ts }) else { return }
        messages[index] = message
    }

    /// Applies a reaction change to a loaded message.
    public mutating func react(_ name: String, by user: String, added: Bool, to ts: String) {
        guard let index = messages.firstIndex(where: { $0.ts == ts }) else { return }
        messages[index] = messages[index].reacting(name, by: user, added: added)
    }

    public mutating func remove(ts: String) {
        messages.removeAll { $0.ts == ts }
    }

    /// The `latest` to ask for when loading older messages.
    public var oldestTS: String? { messages.first?.ts }

    public var newestTS: String? { messages.last?.ts }

    /// Where the "New" line goes: the first message after `lastRead` not sent by `ownUserID`.
    public func firstUnreadTS(lastRead: String, ownUserID: String) -> String? {
        messages.first { Self.isOrdered(lastRead, before: $0.ts) && $0.userID != ownUserID }?.ts
    }

    private func belongs(_ message: SlackMessage) -> Bool {
        guard let threadTS else { return message.isChannelLevel }
        return message.ts == threadTS || message.threadTS == threadTS
    }

    /// Timestamps are decimal strings, so compare them as numbers.
    static func isOrdered(_ lhs: String, before rhs: String) -> Bool {
        (Decimal(string: lhs) ?? 0) < (Decimal(string: rhs) ?? 0)
    }
}
