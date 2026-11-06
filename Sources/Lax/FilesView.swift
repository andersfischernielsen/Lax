import AppKit
import LaxKit
import SwiftUI

/// Images inline, other files as chips. Clicking either opens the file in Slack.
struct FilesView: View {
    let files: [SlackFile]
    let loadImage: (URL) async -> NSImage?
    /// Opens an image or video in Lax; false for other files, which open in Slack.
    let open: (SlackFile) -> Bool
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(files) { file in
                Group {
                    if let video = file.video {
                        VideoView(video: video, loadImage: loadImage)
                    } else if let preview = file.preview {
                        PreviewImage(preview: preview, loadImage: loadImage)
                    } else {
                        FileChip(file: file)
                    }
                }
                .onTapGesture { show(file) }
                .help(file.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(file.preview == nil ? file.name : "Image, \(file.name)")
                .accessibilityAddTraits(.isLink)
                .accessibilityAction { show(file) }
            }
        }
        .padding(.top, 4)
    }

    private func show(_ file: SlackFile) {
        if !open(file), let permalink = file.permalink { openURL(permalink) }
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
                if preview.isAnimated {
                    AnimatedImage(image: image)
                } else {
                    Image(nsImage: image).resizable().scaledToFit()
                }
            }
        }
        // Up to its fitted size, smaller in a narrow column, always in proportion.
        .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
        .frame(maxWidth: size.width, maxHeight: size.height)
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

/// A video's poster with a play symbol; clicking opens it in its own tab.
private struct VideoView: View {
    let video: SlackFile.Video
    let loadImage: (URL) async -> NSImage?

    var body: some View {
        // The poster's shape; 16:9 without one.
        let size = video.poster?.fitted(maxWidth: 360, maxHeight: 300) ?? (width: 360, height: 202)
        ZStack {
            if let poster = video.poster {
                PreviewImage(preview: poster, loadImage: loadImage)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white, .black.opacity(0.4))
        }
        .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
        .frame(maxWidth: size.width, maxHeight: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
