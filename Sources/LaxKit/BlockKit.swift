import Foundation

/// Any JSON value, for formats too open-ended to model field by field.
public enum JSONValue: Decodable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { object[key] } else { nil }
    }

    public var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    public var array: [JSONValue] {
        if case .array(let value) = self { value } else { [] }
    }

    public var bool: Bool {
        if case .bool(let value) = self { value } else { false }
    }

    public var number: Double? {
        if case .number(let value) = self { value } else { nil }
    }
}

/// Renders Block Kit blocks as Slack markup, so they format like any message text.
public enum BlockKit {
    public static func markup(_ blocks: [JSONValue]) -> String {
        blocks.compactMap(block).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Blocks beyond rich text: what bots and apps send, which `text` only summarises.
    public static func hasLayoutBlocks(_ blocks: [JSONValue]) -> Bool {
        blocks.contains { $0["type"]?.string != "rich_text" }
    }

    private static func block(_ block: JSONValue) -> String? {
        switch block["type"]?.string {
        case "rich_text":
            return block["elements"]?.array.map(richTextElement).joined(separator: "\n")
        case "section":
            let fields = block["fields"]?.array.compactMap(textObject) ?? []
            return ([block["text"].flatMap(textObject)].compactMap { $0 } + fields).joined(separator: "\n")
        case "header":
            return block["text"].flatMap(textObject).map { "*\($0)*" }
        case "context":
            return block["elements"]?.array.compactMap(textObject).joined(separator: " · ")
        case "divider":
            return "———"
        default:
            return nil
        }
    }

    /// A `{"type": "mrkdwn" | "plain_text", "text": …}` object.
    private static func textObject(_ object: JSONValue) -> String? {
        guard let text = object["text"]?.string else { return nil }
        return object["type"]?.string == "plain_text" ? escape(text) : text
    }

    private static func richTextElement(_ element: JSONValue) -> String {
        let inline = element["elements"]?.array.map(inlineElement).joined() ?? ""
        switch element["type"]?.string {
        case "rich_text_preformatted":
            return "```\(inline)```"
        case "rich_text_quote":
            return inline.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
        case "rich_text_list":
            let ordered = element["style"]?.string == "ordered"
            let depth = Int(element["indent"]?.number ?? 0)
            let indent = String(repeating: "    ", count: max(depth, 0))
            return (element["elements"]?.array ?? []).enumerated().map { index, item in
                let body = item["elements"]?.array.map(inlineElement).joined() ?? ""
                return indent + (ordered ? "\(index + 1). " : "• ") + body
            }.joined(separator: "\n")
        default:
            return inline
        }
    }

    private static func inlineElement(_ element: JSONValue) -> String {
        switch element["type"]?.string {
        case "text":
            return styled(escape(element["text"]?.string ?? ""), element["style"])
        case "link":
            let url = element["url"]?.string ?? ""
            let label = element["text"]?.string.map { "|" + escape($0) } ?? ""
            return styled("<\(url)\(label)>", element["style"])
        case "user":
            return "<@\(element["user_id"]?.string ?? "")>"
        case "channel":
            return "<#\(element["channel_id"]?.string ?? "")>"
        case "usergroup":
            return "<!subteam^\(element["usergroup_id"]?.string ?? "")>"
        case "broadcast":
            return "<!\(element["range"]?.string ?? "here")>"
        case "emoji":
            return element["unicode"]?.string.flatMap(unicodeEmoji) ?? ":\(element["name"]?.string ?? ""):"
        case "date":
            return escape(element["fallback"]?.string ?? "")
        default:
            return escape(element["text"]?.string ?? "")
        }
    }

    /// Wraps text in markers for each style, keeping surrounding spaces outside them
    /// (`*bold *` wouldn't parse as bold).
    private static func styled(_ text: String, _ style: JSONValue?) -> String {
        guard let style, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }
        let leading = text.prefix { $0 == " " }, trailing = String(text.reversed().prefix { $0 == " " })
        var core = text.trimmingCharacters(in: .whitespaces)
        if style["code"]?.bool == true { core = "`\(core)`" }
        if style["bold"]?.bool == true { core = "*\(core)*" }
        if style["italic"]?.bool == true { core = "_\(core)_" }
        if style["strike"]?.bool == true { core = "~\(core)~" }
        return leading + core + trailing
    }

    /// `"1f44d-1f3fb"` → 👍🏻.
    private static func unicodeEmoji(_ codes: String) -> String? {
        let scalars = codes.split(separator: "-").compactMap { UInt32($0, radix: 16).flatMap(Unicode.Scalar.init) }
        return scalars.isEmpty ? nil : String(String.UnicodeScalarView(scalars))
    }

    private static func escape(_ text: String) -> String {
        text.replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
    }
}
