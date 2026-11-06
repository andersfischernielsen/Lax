import AppKit
import LaxKit
import SwiftUI

/// Reaction chips under a message. Clicking one toggles the user's own reaction.
struct ReactionsView: View {
    let reactions: [SlackReaction]
    let ownUserID: String
    let userName: (String) -> String?
    let emojiImage: (String) -> NSImage?
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(reactions, id: \.name) { reaction in
                let isMine = reaction.users.contains(ownUserID)
                Button { toggle(reaction.name) } label: {
                    HStack(spacing: 4) {
                        emoji(reaction.name)
                        Text("\(reaction.count)").font(.caption.monospacedDigit())
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(isMine ? AnyShapeStyle(.tint.quaternary) : AnyShapeStyle(.quaternary)))
                    .overlay(Capsule().strokeBorder(isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
                }
                .buttonStyle(.plain)
                .help(tooltip(for: reaction))
                .accessibilityLabel(accessibilityLabel(for: reaction, isMine: isMine))
                .accessibilityHint(isMine ? "Removes your reaction" : "Adds your reaction")
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func emoji(_ name: String) -> some View {
        if let character = Emoji.character(for: name) {
            Text(character)
        } else if let image = emojiImage(name) {
            EmojiImage(image: image, height: 16)
        } else {
            Text(":\(name):").foregroundStyle(.secondary)
        }
    }

    private func accessibilityLabel(for reaction: SlackReaction, isMine: Bool) -> String {
        let name = reaction.name.replacing("_", with: " ")
        let count = reaction.count == 1 ? "1 reaction" : "\(reaction.count) reactions"
        return "\(name), \(count)" + (isMine ? ", including yours" : "")
    }

    private func tooltip(for reaction: SlackReaction) -> String {
        let names = reaction.users.map { userName($0) ?? $0 }
        let others = reaction.count - names.count
        let people = names.joined(separator: ", ") + (others > 0 ? " and \(others) more" : "")
        return "\(people) reacted with :\(reaction.name):"
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
