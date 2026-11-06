import AppKit
import LaxKit
import SwiftUI

/// A legacy attachment: pretext, then a box with a coloured bar holding the rest.
struct AttachmentView: View {
    let attachment: SlackAttachment
    let formatter: SlackText
    let emojiImage: (String) -> NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let pretext = attachment.pretext {
                rich(pretext).textSelection(.enabled)
            }
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    if let author = attachment.authorName {
                        Text(author).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if let title = attachment.title {
                        titleView(title).fontWeight(.semibold)
                    }
                    if let body = attachment.body {
                        rich(body).textSelection(.enabled)
                    }
                    if !attachment.fields.isEmpty { fields }
                    if let footer = attachment.footer {
                        Text(formatter.attributed(footer)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func rich(_ markup: String) -> Text {
        RichText.text(MessageStyle.styled(formatter.attributed(markup)), emojiImage: emojiImage)
    }

    private var barColor: Color {
        attachment.color.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color(nsColor: .tertiaryLabelColor)
    }

    @ViewBuilder private func titleView(_ title: String) -> some View {
        if let link = attachment.titleLink {
            // Links center wrapped titles by default.
            Link(title, destination: link).multilineTextAlignment(.leading)
        } else {
            Text(title)
        }
    }

    /// Short fields two to a row, long ones on their own.
    private var fields: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, field in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(field.title).font(.caption.weight(.semibold))
                            rich(field.value).textSelection(.enabled)
                        }
                        .gridCellColumns(field.isShort ? 1 : 2)
                    }
                }
            }
        }
    }

    private var rows: [[SlackAttachment.Field]] {
        var rows: [[SlackAttachment.Field]] = []
        for field in attachment.fields {
            if field.isShort, let last = rows.last, last.count == 1, last[0].isShort {
                rows[rows.count - 1].append(field)
            } else {
                rows.append([field])
            }
        }
        return rows
    }
}
