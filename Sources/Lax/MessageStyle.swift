import LaxKit
import SwiftUI

enum MessageStyle {
    /// Applies Lax's look to formatter output: quote lines get a bar and secondary colour,
    /// custom emoji not yet shown as images are dimmed.
    static func styled(_ text: AttributedString) -> AttributedString {
        var result = text
        for run in result.runs.reversed() {
            if run[SlackAttributes.Quote.self] == true {
                result[run.range].foregroundColor = .secondary
            }
            if run[SlackAttributes.CustomEmoji.self] != nil {
                result[run.range].foregroundColor = .secondary
            }
        }
        for start in quoteLineStarts(in: result).reversed() {
            var bar = AttributedString("▎ ")
            bar.foregroundColor = .secondary.opacity(0.6)
            result.insert(bar, at: start)
        }
        return result
    }

    private static func quoteLineStarts(in text: AttributedString) -> [AttributedString.Index] {
        text.runs.compactMap { run -> AttributedString.Index? in
            guard run[SlackAttributes.Quote.self] == true else { return nil }
            let start = run.range.lowerBound
            let atLineStart = start == text.startIndex || text.characters[text.characters.index(before: start)] == "\n"
            return atLineStart ? start : nil
        }
    }
}
