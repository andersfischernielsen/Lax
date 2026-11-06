import Foundation

/// Attributes `SlackText` adds beyond Foundation's, for the app to style.
public enum SlackAttributes {
    /// Text on a `>` quote line.
    public enum Quote: AttributedStringKey {
        public typealias Value = Bool
        public static let name = "lax.quote"
    }

    /// A workspace's custom emoji image, written as `:name:`; the value is the name.
    public enum CustomEmoji: AttributedStringKey {
        public typealias Value = String
        public static let name = "lax.customEmoji"
    }
}

/// Turns Slack message markup ("mrkdwn") into displayable text.
///
/// Handles `<@U1>`, `<#C1|name>`, `<!here>`, `<!subteam^S1>`, `<url|label>`, the
/// `&amp;`/`&lt;`/`&gt;` escapes, `> quotes`, `:emoji:`, and `*bold*`, `_italic_`,
/// `~strike~`, `` `code` `` and ```` ```blocks``` ````.
public struct SlackText: Sendable {
    public var userName: @Sendable (String) -> String?
    public var channelName: @Sendable (String) -> String?
    /// User group handle, without the @.
    public var subteamHandle: @Sendable (String) -> String?
    /// A workspace's custom emoji by name.
    public var customEmoji: @Sendable (String) -> SlackEmoji?

    public init(
        userName: @escaping @Sendable (String) -> String? = { _ in nil },
        channelName: @escaping @Sendable (String) -> String? = { _ in nil },
        subteamHandle: @escaping @Sendable (String) -> String? = { _ in nil },
        customEmoji: @escaping @Sendable (String) -> SlackEmoji? = { _ in nil }
    ) {
        self.userName = userName
        self.channelName = channelName
        self.subteamHandle = subteamHandle
        self.customEmoji = customEmoji
    }

    public func attributed(_ markup: String) -> AttributedString {
        // Tokens become placeholders first so emphasis can span them: `*hi <@U1>*`.
        let (template, tokens) = extractTokens(markup)
        var result = emphasised(Self.markingQuotes(Self.unescape(template[...])))
        Self.substitute(tokens, in: &result)
        Self.applyQuotes(in: &result)
        return result
    }

    public func plain(_ markup: String) -> String {
        String(attributed(markup).characters)
    }

    /// A message's markup as text to edit: escapes undone, mentions and links kept as tokens.
    public static func editable(_ markup: String) -> String {
        unescape(markup[...])
    }

    /// Text typed by the user, made safe to send: `&`, `<` and `>` escaped, except in
    /// mention and link tokens like `<@U1>`, `<#C1>`, `<!here>` and `<https://…>`.
    public static func encodedForSending(_ text: String) -> String {
        var result = ""
        var rest = text[...]
        while let token = rest.firstMatch(of: /<(?:[@#!][^<>\s]+|(?:https?|mailto):[^<>\s]+)(?:\|[^<>]*)?>/) {
            result += escape(rest[..<token.range.lowerBound]) + token.output
            rest = rest[token.range.upperBound...]
        }
        return result + escape(rest)
    }

    private static func escape(_ text: Substring) -> String {
        String(text).replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
    }

    /// User IDs mentioned with `<@U…>`, so their names can be fetched.
    public static func mentionedUserIDs(in markup: String) -> Set<String> {
        Set(markup.matches(of: /<@([A-Z0-9]+)(?:\|[^>]*)?>/).map { String($0.1) })
    }

    // MARK: - Tokens

    /// Private-use characters standing in for tokens, and one marking quote lines.
    private static func placeholder(_ index: Int) -> Character {
        Character(Unicode.Scalar(0xE000 + min(index, 0x17FF))!)
    }
    private static let quoteMarker: Character = "\u{F8FF}"

    private func extractTokens(_ markup: String) -> (String, [AttributedString]) {
        var template = ""
        var tokens: [AttributedString] = []
        var rest = markup[...]
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            template += rest[..<open]
            template.append(Self.placeholder(tokens.count))
            tokens.append(token(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return (template + rest, tokens)
    }

    private func token(_ body: Substring) -> AttributedString {
        let parts = body.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let target = String(parts[0])
        let label = parts.count > 1 ? Self.unescape(parts[1]) : nil

        switch target.first {
        case "@":
            let id = String(target.dropFirst())
            return Self.mention("@" + (userName(id) ?? label ?? id))
        case "#":
            let id = String(target.dropFirst())
            return Self.mention("#" + (channelName(id) ?? label ?? id))
        case "!":
            return Self.mention(special(target.dropFirst(), label: label))
        default:
            let url = Self.unescape(target[...])
            var link = AttributedString(label ?? url.replacing(/^mailto:/, with: ""))
            link.link = URL(string: url)
            return link
        }
    }

    /// `<!here>`, `<!channel>`, `<!everyone>`, `<!subteam^S1>`, `<!date^…|fallback>`.
    private func special(_ command: Substring, label: String?) -> String {
        let parts = command.split(separator: "^").map(String.init)
        switch parts.first ?? "" {
        case "here", "channel", "everyone":
            return "@" + parts[0]
        case "subteam":
            let handle = parts.count > 1 ? subteamHandle(parts[1]) : nil
            return handle.map { "@" + $0 } ?? label ?? "@group"
        case let name:
            return label ?? "@" + name
        }
    }

    private static func mention(_ text: String) -> AttributedString {
        var mention = AttributedString(text)
        mention.inlinePresentationIntent = .stronglyEmphasized
        return mention
    }

    /// Puts rendered tokens in place of their placeholders, keeping surrounding emphasis.
    private static func substitute(_ tokens: [AttributedString], in result: inout AttributedString) {
        for (index, token) in tokens.enumerated() {
            guard let at = result.characters.firstIndex(of: placeholder(index)) else { continue }
            let range = at..<result.characters.index(after: at)
            var replacement = token
            if let outer = result[range].inlinePresentationIntent {
                for run in replacement.runs {
                    replacement[run.range].inlinePresentationIntent = outer.union(run.inlinePresentationIntent ?? [])
                }
            }
            result.replaceSubrange(range, with: replacement)
        }
    }

    // MARK: - Quotes

    /// Swaps a leading `>` (and one space) for a marker that survives emphasis parsing.
    private static func markingQuotes(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                guard line.hasPrefix(">") else { return String(line) }
                let body = line.dropFirst()
                return String(quoteMarker) + (body.hasPrefix(" ") ? body.dropFirst() : body)
            }
            .joined(separator: "\n")
    }

    private static func applyQuotes(in result: inout AttributedString) {
        while let marker = result.characters.firstIndex(of: quoteMarker) {
            let start = result.characters.index(after: marker)
            let end = result.characters[start...].firstIndex(of: "\n") ?? result.endIndex
            result[start..<end][SlackAttributes.Quote.self] = true
            result.removeSubrange(marker..<start)
        }
    }

    // MARK: - Plain text

    private static func unescape(_ text: Substring) -> String {
        String(text).replacing("&lt;", with: "<").replacing("&gt;", with: ">").replacing("&amp;", with: "&")
    }

    private static let emphasis = try! NSRegularExpression(
        pattern: [
            #"```\n?([\s\S]+?)\n?```"#,
            #"`([^`\n]+)`"#,
            #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#,
            #"(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#,
            #"(?<![\w~])~(?=\S)([^~\n]+?)(?<=\S)~(?![\w~])"#,
        ].joined(separator: "|"))

    private static let intents: [InlinePresentationIntent] = [
        .code, .code, .stronglyEmphasized, .emphasized, .strikethrough,
    ]

    private func emphasised(_ text: String) -> AttributedString {
        let nsText = text as NSString
        var result = AttributedString()
        var location = 0
        for match in Self.emphasis.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let group = (1...Self.intents.count).first(where: { match.range(at: $0).location != NSNotFound })
            else { continue }
            let before = nsText.substring(with: NSRange(location: location, length: match.range.location - location))
            result += withEmoji(before, intent: nil)
            let inner = nsText.substring(with: match.range(at: group))
            let intent = Self.intents[group - 1]
            if intent == .code {
                var code = AttributedString(inner)
                code.inlinePresentationIntent = .code
                result += code
            } else {
                result += withEmoji(inner, intent: intent)
            }
            location = match.range.location + match.range.length
        }
        return result + withEmoji(nsText.substring(from: location), intent: nil)
    }

    /// Replaces `:shortcode:`s with emoji; custom images stay as text, tagged for the app.
    private func withEmoji(_ text: String, intent: InlinePresentationIntent?) -> AttributedString {
        var result = AttributedString()
        var rest = text[...]
        for match in text.matches(of: /:([a-z0-9_+'\-]+(?:::skin-tone-[2-6])?):/) {
            let name = String(match.1)
            result += AttributedString(rest[..<match.range.lowerBound])
            switch Emoji.character(for: name).map(SlackEmoji.character) ?? customEmoji(name) {
            case .character(let character):
                result += AttributedString(character)
            case .image:
                var custom = AttributedString(":\(name):")
                custom[SlackAttributes.CustomEmoji.self] = name
                result += custom
            case nil:
                result += AttributedString(text[match.range])
            }
            rest = text[match.range.upperBound...]
        }
        result += AttributedString(rest)
        if let intent { result.inlinePresentationIntent = intent }
        return result
    }
}
