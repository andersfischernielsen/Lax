import AppKit
import LaxKit
import SwiftUI

/// Images inline, other files as chips. Clicking either opens the file in Slack.
struct FilesView: View {
    let files: [SlackFile]
    let loadImage: (URL) async -> NSImage?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(files) { file in
                Group {
                    if let preview = file.preview {
                        PreviewImage(preview: preview, loadImage: loadImage)
                    } else {
                        FileChip(file: file)
                    }
                }
                .onTapGesture { if let permalink = file.permalink { openURL(permalink) } }
                .help(file.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(file.preview == nil ? file.name : "Image, \(file.name)")
                .accessibilityAddTraits(.isLink)
                .accessibilityAction { if let permalink = file.permalink { openURL(permalink) } }
            }
        }
        .padding(.top, 4)
    }
}

private struct PreviewImage: View {
    let preview: SlackFile.Preview
    let loadImage: (URL) async -> NSImage?
    @State private var image: NSImage?

    var body: some View {
        let size = preview.fitted(maxWidth: 360, maxHeight: 300)
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: preview.url) { image = await loadImage(preview.url) }
    }
}

private struct FileChip: View {
    let file: SlackFile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1)
                if let type = file.prettyType {
                    Text(type).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 360, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .contentShape(Rectangle())
    }
}
