import AppKit
import Foundation
import LaxKit
import SwiftUI

/// A state to open the demo workspace in, for screenshots: `-demo -demo-scene thread`.
enum DemoScene: String, CaseIterable {
    case channel
    case thread
    case directMessages = "direct-messages"
    case threads
    case openQuickly = "open-quickly"
    case composer
    case search
    case bot
    case video
    case emojiPicker = "emoji-picker"
    case media
    case settings

    static var current: DemoScene? {
        guard DemoSlack.isEnabled, let index = CommandLine.arguments.firstIndex(of: "-demo-scene"),
              CommandLine.arguments.indices.contains(index + 1) else { return nil }
        return DemoScene(rawValue: CommandLine.arguments[index + 1])
    }

    /// What the window shows from its first frame.
    @MainActor
    func prepare(_ window: WindowModel) {
        window.area = switch self {
        case .directMessages: .directMessages
        case .threads: .threads
        default: .channels
        }
        window.conversationID = switch self {
        case .directMessages: "D1"
        case .bot: "C5"
        case .video: "C2"
        case .threads: nil
        default: "C1"
        }
        switch self {
        case .thread:
            window.openThread(DemoSlack.allHandsTS, in: "C1")
        case .threads:
            window.followedThread = ThreadRef(channel: "C1", ts: DemoSlack.allHandsTS)
        case .openQuickly:
            window.quickSwitcherQuery = "de"
            window.showsQuickSwitcher = true
        default:
            break
        }
    }

    /// What needs the workspace loaded first: drafts, searches, sheets and other windows.
    @MainActor
    func finish(_ window: WindowModel, workspace: () -> WorkspaceModel?, openWindow: OpenWindowAction,
                openSettings: OpenSettingsAction) async {
        // The workspace appears just after the window, then its conversations and names load.
        var loaded: WorkspaceModel?
        for _ in 0..<80 {
            if let candidate = workspace(), !candidate.conversations.isEmpty, candidate.userName("U2") != nil {
                loaded = candidate
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let workspace = loaded else { return }
        switch self {
        case .composer:
            var draft = AttributedString("Great work on the launch, ")
            var bold = AttributedString("everyone")
            bold.inlinePresentationIntent = .stronglyEmphasized
            bold.font = .body.bold()
            draft += bold + AttributedString("! Thanks especially to @ma")
            workspace.drafts["C1"] = draft
        case .search:
            window.searchQuery = "all-hands"
            window.searchResults = await workspace.search("all-hands")
        case .emojiPicker:
            if let message = workspace.timelines["C1"]?.messages.first(where: { $0.ts == DemoSlack.reviewTS }) {
                window.reactingTo = ReactionTarget(channel: "C1", message: message)
            }
        case .media:
            TabJoiner.opener = NSApp.keyWindow
            openWindow(id: "media", value: MediaItem(
                accountID: workspace.account.id, kind: .image,
                url: URL(string: "https://files.slack.com/demo/office.png")!, name: "office.png",
                permalink: URL(string: "https://acme.slack.com/files/F1")))
        case .settings:
            openSettings()
        default:
            break
        }
    }
}
