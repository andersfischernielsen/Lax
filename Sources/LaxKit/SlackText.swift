import Foundation

/// Turns Slack message markup ("mrkdwn") into displayable text.
///
/// Handles `<@U1>`, `<#C1|name>`, `<!here>`, `<!subteam^S1|@team>`, `<url|label>`,
/// the `&amp;`/`&lt;`/`&gt;` escapes, and `*bold*`, `_italic_`, `~strike~`,
/// `` `code` `` and ```` ```blocks``` ````.
public struct SlackText: Sendable {
    public var userName: @Sendable (String) -> String?
    public var channelName: @Sendable (String) -> String?

    public init(userName: @escaping @Sendable (String) -> String? = { _ in nil },
                channelName: @escaping @Sendable (String) -> String? = { _ in nil }) {
        self.userName = userName
        self.channelName = channelName
    }

    public func attributed(_ markup: String) -> AttributedString {
        var result = AttributedString()
        var rest = markup[...]
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            result += Self.emphasised(Self.unescape(rest[..<open]))
            result += token(rest[rest.index(after: open)..<close])
            rest = rest[rest.index(after: close)...]
        }
        result += Self.emphasised(Self.unescape(rest))
        return result
    }

    public func plain(_ markup: String) -> String {
        String(attributed(markup).characters)
    }

    /// User IDs mentioned with `<@U…>`, so their names can be fetched.
    public static func mentionedUserIDs(in markup: String) -> Set<String> {
        Set(markup.matches(of: /<@([A-Z0-9]+)(?:\|[^>]*)?>/).map { String($0.1) })
    }

    // MARK: - Tokens

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
            return Self.mention(Self.special(target.dropFirst(), label: label))
        default:
            let url = Self.unescape(target[...])
            var link = AttributedString(label ?? url.replacing(/^mailto:/, with: ""))
            link.link = URL(string: url)
            return link
        }
    }

    /// `<!here>`, `<!channel>`, `<!everyone>`, `<!subteam^S1|@team>`, `<!date^…|fallback>`.
    private static func special(_ command: Substring, label: String?) -> String {
        let name = command.split(separator: "^").first.map(String.init) ?? ""
        switch name {
        case "here", "channel", "everyone": return "@" + name
        default: return label ?? "@" + name
        }
    }

    private static func mention(_ text: String) -> AttributedString {
        var mention = AttributedString(text)
        mention.inlinePresentationIntent = .stronglyEmphasized
        return mention
    }

    // MARK: - Plain text

    private static func unescape(_ text: Substring) -> String {
        String(text).replacing("&lt;", with: "<").replacing("&gt;", with: ">").replacing("&amp;", with: "&")
    }

    private static let emphasis = try! NSRegularExpression(pattern: [
        #"```\n?([\s\S]+?)\n?```"#,
        #"`([^`\n]+)`"#,
        #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#,
        #"(?<![\w_])_(?=\S)([^_\n]+?)(?<=\S)_(?![\w_])"#,
        #"(?<![\w~])~(?=\S)([^~\n]+?)(?<=\S)~(?![\w~])"#,
    ].joined(separator: "|"))

    private static let intents: [InlinePresentationIntent] = [
        .code, .code, .stronglyEmphasized, .emphasized, .strikethrough,
    ]

    private static func emphasised(_ text: String) -> AttributedString {
        let nsText = text as NSString
        var result = AttributedString()
        var location = 0
        for match in emphasis.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard let group = (1...intents.count).first(where: { match.range(at: $0).location != NSNotFound })
            else { continue }
            result += AttributedString(nsText.substring(with: NSRange(location: location,
                                                                      length: match.range.location - location)))
            var span = AttributedString(nsText.substring(with: match.range(at: group)))
            span.inlinePresentationIntent = intents[group - 1]
            result += span
            location = match.range.location + match.range.length
        }
        result += AttributedString(nsText.substring(from: location))
        return result
    }
}
