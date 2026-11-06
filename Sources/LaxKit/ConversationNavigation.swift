/// Moving between conversations from the keyboard, in sidebar order.
public enum ConversationNavigation {
    /// The conversation `offset` places from `current`, stopping at the ends. With no
    /// current conversation, moving down starts at the top and moving up at the bottom.
    public static func step(from current: String?, in order: [String], by offset: Int) -> String? {
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else {
            return offset >= 0 ? order.first : order.last
        }
        return order[min(max(index + offset, 0), order.count - 1)]
    }

    /// The nearest unread conversation in `direction` (+1 down, -1 up), wrapping around and
    /// skipping `current`; nil when nothing else is unread.
    public static func nextUnread(from current: String?, in order: [String], direction: Int,
                                  isUnread: (String) -> Bool) -> String? {
        guard !order.isEmpty else { return nil }
        let start = current.flatMap { order.firstIndex(of: $0) } ?? (direction >= 0 ? order.count - 1 : 0)
        let step = direction >= 0 ? 1 : -1
        for distance in 1...order.count {
            let candidate = order[((start + step * distance) % order.count + order.count) % order.count]
            if candidate != current, isUnread(candidate) { return candidate }
        }
        return nil
    }
}
