/// Completing what's being typed in the composer: `@person`, `#channel` and `:emoji:`.
public enum Autocomplete {
    public enum Kind: Equatable, Sendable {
        case mention
        case channel
        case emoji
    }

    /// The word being typed at the end of the draft, when it starts a completion.
    public struct Token: Equatable, Sendable {
        public let kind: Kind
        /// What follows the `@`, `#` or `:`.
        public let query: String
        /// Where the word starts in the draft, counted in characters.
        public let start: Int
    }

    /// The completion being typed at the end of `text`: a word starting with `@` or `#`, or
    /// with `:` and at least two more characters, as in Slack.
    public static func token(in text: String) -> Token? {
        let word = text.reversed().prefix { !$0.isWhitespace }.reversed()
        guard let trigger = word.first else { return nil }
        let query = String(word.dropFirst())
        let start = text.count - word.count
        switch trigger {
        case "@" where !query.contains("@"): return Token(kind: .mention, query: query, start: start)
        case "#" where !query.contains("#"): return Token(kind: .channel, query: query, start: start)
        case ":" where query.count >= 2 && !query.contains(":"): return Token(kind: .emoji, query: query, start: start)
        default: return nil
        }
    }

    /// `text` with the word `token` stands for replaced by `completion` and a space.
    public static func completing(_ text: String, token: Token, with completion: String) -> String {
        String(text.prefix(token.start)) + completion + " "
    }

    /// Readable mentions typed in the draft, like `@Jane Doe`, turned into the tokens Slack
    /// expects, like `<@U2>`; the longest first, so `@Jane Doe` beats `@Jane`.
    public static func encodingMentions(in text: String, _ mentions: [String: String]) -> String {
        mentions.keys.sorted { $0.count > $1.count }.reduce(text) { text, readable in
            text.replacing(readable, with: mentions[readable]!)
        }
    }
}
