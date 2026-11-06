/// What the Dock icon's badge says, as in Slack: how many mentions (every direct message
/// counts as one), or just a dot when only other conversations or threads are unread.
public enum DockBadge {
    /// The badge text, or nil for no badge. With `mentionsOnly`, plain unreads show nothing.
    public static func label(mentions: Int, hasOtherUnreads: Bool, mentionsOnly: Bool) -> String? {
        if mentions > 0 { return String(mentions) }
        return hasOtherUnreads && !mentionsOnly ? "•" : nil
    }
}

extension UnreadState {
    /// Mentions across all conversations; in direct messages every message counts.
    public var totalMentions: Int {
        byConversation.values.reduce(0) { $0 + $1.mentions }
    }
}
