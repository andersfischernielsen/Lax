import AppKit
import LaxKit
import SwiftUI

enum RichText {
    /// An empty square the size of an inline emoji, so text keeps its layout while images load.
    static let placeholder = NSImage(size: NSSize(width: 18, height: 18))

    /// Builds a `Text`, drawing custom emoji inline; `emojiImage` gives images sized by `inline`.
    static func text(_ attributed: AttributedString, emojiImage: (String) -> NSImage?) -> Text {
        attributed.runs.reduce(Text("")) { result, run in
            let piece = attributed[run.range]
            guard let name = run[SlackAttributes.CustomEmoji.self] else {
                return Text("\(result)\(Text(AttributedString(piece)))")
            }
            let image = emojiImage(name) ?? placeholder
            // Identical emoji in a row share one run (":x::x:"); draw one image each.
            let count = max(1, piece.characters.count / (name.count + 2))
            let images = (0..<count).reduce(Text("")) { row, _ in
                Text("\(row)\(Text(Image(nsImage: image)).baselineOffset(-3))")
            }
            return Text("\(result)\(images)")
        }
    }

    /// Names of custom emoji in `attributed`, to fetch their images.
    static func customEmojiNames(in attributed: AttributedString) -> Set<String> {
        Set(attributed.runs.compactMap { $0[SlackAttributes.CustomEmoji.self] })
    }

    /// A copy drawn at text height, keeping its aspect ratio.
    static func inline(_ image: NSImage, height: CGFloat = 18) -> NSImage {
        guard image.size.height > 0, let copy = image.copy() as? NSImage else { return image }
        copy.size = NSSize(width: image.size.width * height / image.size.height, height: height)
        return copy
    }
}
