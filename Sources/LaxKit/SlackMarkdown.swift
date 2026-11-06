import Foundation

/// Rich text from the composer, written as Slack's markup ("mrkdwn").
///
/// Formatting is read from `inlinePresentationIntent` (bold, italic, strikethrough, code)
/// and `link`. Slack only recognises markers that hug the text on one line, so spaces stay
/// outside them and each line of a multi-line run is wrapped on its own; code spanning
/// lines becomes a ``` block.
public enum SlackMarkdown {
    public static func mrkdwn(from text: AttributedString) -> String {
        // Runs by the attributes that matter, so differently styled fonts don't split a word.
        text.runs[\.inlinePresentationIntent, \.link].map { intent, link, range in
            let piece = String(text[range].characters)
            let intent = intent ?? []
            if let link { return "<\(link.absoluteString)|\(piece)>" }
            if intent.contains(.code), piece.contains("\n") { return "```" + piece + "```" }
            return piece.split(separator: "\n", omittingEmptySubsequences: false)
                .map { wrap(String($0), intent) }
                .joined(separator: "\n")
        }.joined()
    }

    private static func wrap(_ line: String, _ intent: InlinePresentationIntent) -> String {
        let leading = line.prefix { $0.isWhitespace }
        let trailing = line.reversed().prefix { $0.isWhitespace }
        guard leading.count < line.count else { return line }
        var core = String(line.dropFirst(leading.count).dropLast(trailing.count))
        if intent.contains(.code) {
            core = "`\(core)`"
        } else {
            if intent.contains(.strikethrough) { core = "~\(core)~" }
            if intent.contains(.emphasized) { core = "_\(core)_" }
            if intent.contains(.stronglyEmphasized) { core = "*\(core)*" }
        }
        return leading + core + String(trailing.reversed())
    }
}
