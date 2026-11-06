import AppKit
import AVKit
import LaxKit
import SwiftUI

/// An image or video opened from a message, shown in its own tab.
struct MediaItem: Codable, Hashable {
    enum Kind: String, Codable {
        case image
        case video
    }

    let accountID: SlackAccount.ID
    let kind: Kind
    /// The full file, not a thumbnail; needs the session cookie.
    let url: URL
    let name: String
    let permalink: URL?
}

extension MediaItem {
    /// For images and videos; other files open in Slack.
    init?(_ file: SlackFile, accountID: SlackAccount.ID) {
        if let video = file.video {
            self.init(accountID: accountID, kind: .video, url: video.url, name: file.name, permalink: file.permalink)
        } else if file.preview != nil, let url = file.url {
            self.init(accountID: accountID, kind: .image, url: url, name: file.name, permalink: file.permalink)
        } else {
            return nil
        }
    }
}

struct MediaViewer: View {
    let model: AppModel
    let item: MediaItem
    @State private var image: NSImage?
    @State private var player: AVPlayer?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                if let image {
                    if image.isAnimated {
                        AnimatedImage(image: image)
                    } else {
                        Image(nsImage: image).resizable().scaledToFit()
                    }
                } else {
                    ProgressView()
                }
            case .video:
                if let player { VideoPlayer(player: player) } else { ProgressView() }
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .navigationTitle(item.name)
        .toolbar {
            if let permalink = item.permalink {
                Button("Open in Slack", systemImage: "arrow.up.forward.app") { openURL(permalink) }
                    .help("Open this file in Slack")
            }
        }
        .task {
            guard let workspace = model.workspace(item.accountID) else { return }
            switch item.kind {
            case .image:
                image = await workspace.image(at: item.url)
            case .video:
                guard let playerItem = workspace.playerItem(for: item.url) else { return }
                let player = AVPlayer(playerItem: playerItem)
                self.player = player
                player.play()
            }
        }
        .onDisappear { player?.pause() }
        .background(TabJoiner())
    }
}

/// Puts the window it's in beside the window it was opened from, as a tab.
struct TabJoiner: NSViewRepresentable {
    /// The window to join, noted just before opening a new one.
    @MainActor static var opener: NSWindow?

    func makeNSView(context: Context) -> JoiningView { JoiningView() }
    func updateNSView(_ view: JoiningView, context: Context) {}

    final class JoiningView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let opener = TabJoiner.opener, opener !== window else { return }
            TabJoiner.opener = nil
            opener.addTabbedWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
