/// Messages that are only emoji, which Slack shows large ("jumbomoji").
public enum Jumbomoji {
    public enum Item: Equatable, Sendable {
        /// `:name:`, a standard or custom emoji; skin tones (`::skin-tone-3:`) are dropped.
        case shortcode(String)
        /// An emoji typed as itself.
        case character(String)
    }

    /// Slack shows up to this many large.
    public static let limit = 23

    /// The emoji `markup` consists of, when it's nothing else; nil otherwise.
    public static func items(in markup: String) -> [Item]? {
        var items: [Item] = []
        var rest = markup[...]
        while let first = rest.first {
            if first.isWhitespace {
                rest = rest.dropFirst()
            } else if let match = rest.prefixMatch(of: /:([a-z0-9_+'\-]+):(?::skin-tone-[2-6]:)?/) {
                items.append(.shortcode(String(match.1)))
                rest = rest[match.range.upperBound...]
            } else if first.isEmoji {
                items.append(.character(String(first)))
                rest = rest.dropFirst()
            } else {
                return nil
            }
        }
        return (1...limit).contains(items.count) ? items : nil
    }
}

extension Character {
    /// Shown as an emoji: digits and `#`, emoji by Unicode but text by default, don't count.
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first, scalar.properties.isEmoji else { return false }
        return scalar.properties.isEmojiPresentation || unicodeScalars.count > 1
    }
}
