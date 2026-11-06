import AppKit
import LaxKit
import SwiftUI

@main
struct LaxApp: App {
    @State private var model: AppModel
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        // Unbundled (`swift run`), macOS treats the process as a background tool:
        // no Dock icon, no menu bar, windows open behind other apps.
        if Bundle.main.bundleIdentifier == nil {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate()
        }
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                // Only once a window shows: nothing may delay the first window, and setting
                // the Dock badge before it exists stops SwiftUI from opening it.
                .task { await model.start() }
        }
        // A window on every launch, even when the last session ended with none open.
        .defaultLaunchBehavior(.presented)
        .commands {
            WorkspaceCommands(model: model)
            GoCommands(model: model)
        }

        // Images and videos from messages, each in a tab beside the window it came from.
        WindowGroup("Media", id: "media", for: MediaItem.self) { $item in
            if let item { MediaViewer(model: model, item: item) }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

/// Menu commands that act on the window in front.
private struct WorkspaceCommands: Commands {
    let model: AppModel
    @FocusedValue(WindowModel.self) private var window

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Workspace…") { window?.beginSignIn(with: model) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(window == nil)
        }
    }
}

/// Moving around from the keyboard, in the window in front.
private struct GoCommands: Commands {
    let model: AppModel
    @FocusedValue(WindowModel.self) private var window

    var body: some Commands {
        CommandMenu("Go") {
            Group {
                // Again closes it, as in Slack.
                Button("Open Quickly…") { window?.showsQuickSwitcher.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Divider()
                Button("Back") { window?.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!(window?.history.canGoBack ?? false))
                Button("Forward") { window?.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!(window?.history.canGoForward ?? false))
                Divider()
                Button("Previous Conversation") { step(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Next Conversation") { step(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
                Button("Previous Unread Conversation") { stepToUnread(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option, .shift])
                Button("Next Unread Conversation") { stepToUnread(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option, .shift])
            }
            .disabled(window == nil)
        }
        CommandGroup(before: .sidebar) {
            ForEach(Array(WindowModel.Area.allCases.enumerated()), id: \.element) { index, area in
                Button(area.title) { window?.area = area }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(window == nil)
            }
            Divider()
        }
        CommandGroup(before: .textEditing) {
            Button("Search Messages") { window?.searchFocusRequests += 1 }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(window == nil)
        }
    }

    private var order: [String] {
        guard let window, let workspace = model.workspace(window.accountID) else { return [] }
        return workspace.navigationOrder(in: window.area)
    }

    private func step(by offset: Int) {
        guard let window else { return }
        window.select(ConversationNavigation.step(from: window.conversationID, in: order, by: offset))
    }

    private func stepToUnread(_ direction: Int) {
        guard let window, let workspace = model.workspace(window.accountID),
              let next = ConversationNavigation.nextUnread(from: window.conversationID, in: order,
                                                           direction: direction, isUnread: workspace.isUnread)
        else { return NSSound.beep() }
        window.select(next)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opens a window when Lax launches without one. A session that ended with every window
    /// closed restores as no windows, and that wins over `.defaultLaunchBehavior(.presented)`.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Once SwiftUI has restored or opened its windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                let app = NSApplication.shared
                guard !app.windows.contains(where: { $0.isVisible && $0.canBecomeMain }),
                      let newWindow = app.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
                        .first(where: { $0.keyEquivalent == "n" && $0.keyEquivalentModifierMask == .command }),
                      let action = newWindow.action else { return }
                app.sendAction(action, to: newWindow.target, from: newWindow)
            }
        }
    }
}
