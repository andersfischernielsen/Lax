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
        WindowGroup(id: "main") {
            ContentView(model: model)
                // Joins the window in front as a tab when opened with File ▸ New Tab.
                .background(TabJoiner())
                // Only once a window shows: nothing may delay the first window, and setting
                // the Dock badge before it exists stops SwiftUI from opening it.
                .task { await model.start() }
        }
        // A window on every launch, even when the last session ended with none open.
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1280, height: 800)
        .commands {
            // View ▸ Show/Hide Sidebar, ⌃⌘S.
            SidebarCommands()
            WorkspaceCommands(model: model)
            GoCommands(model: model)
            MessageCommands(model: model)
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
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let _ = AppDelegate.openMainWindow = { [openWindow] in openWindow(id: "main") }
        CommandGroup(after: .newItem) {
            // As in Safari and Finder: a new window, as a tab of the one in front.
            Button("New Tab") {
                TabJoiner.opener = NSApp.keyWindow
                openWindow(id: "main")
            }
            .keyboardShortcut("t", modifiers: .command)
        }
        CommandMenu("Workspace") {
            Group {
                let current = model.workspace(window?.accountID)
                // ⌃⌘1–9 switch workspaces; ⌘1–3 already switch views.
                ForEach(Array(model.accounts.prefix(9).enumerated()), id: \.element.id) { index, account in
                    Toggle(account.teamName, isOn: Binding(
                        get: { current?.account.id == account.id },
                        set: { if $0 { window?.accountID = account.id } }
                    ))
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .control])
                }
                Divider()
                Button("Add Workspace…") { window?.beginSignIn(with: model) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Set Display Name…") { window?.editingDisplayName = current?.ownDisplayName }
                    .disabled(current == nil)
                Divider()
                Button("Sign Out of \(current?.account.teamName ?? "Workspace")…") { window?.signingOut = current?.account }
                    .disabled(current == nil)
            }
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
    /// SwiftUI's way to open the main window, handed over by the menu commands, which exist
    /// even when no window does.
    @MainActor static var openMainWindow: (() -> Void)?

    /// Opens a window when Lax launches without one. A session that ended with every window
    /// closed restores as no windows, and that wins over `.defaultLaunchBehavior(.presented)`.
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Screenshots in light mode, whatever the Mac is set to.
        if DemoSlack.isEnabled, CommandLine.arguments.contains("-demo-light") {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        }
        // Once SwiftUI has restored or opened its windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                guard !NSApplication.shared.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
                Self.openMainWindow?()
            }
        }
    }
}

/// The Message and Conversation menus: what the right-click menus offer, for the selected
/// message and the open conversation, so their shortcuts work from the keyboard.
private struct MessageCommands: Commands {
    let model: AppModel
    @FocusedValue(WindowModel.self) private var window

    var body: some Commands {
        CommandMenu("Message") {
            let selected = selection
            let message = selected?.message
            let isOwn = message?.userID != nil && message?.userID == selected?.workspace.account.userID
            Button("Reply in Thread") {
                if let selected, let message { window?.openThread(message.threadTS ?? message.ts, in: selected.channel) }
            }
            .keyboardShortcut(Shortcuts.replyInThread)
            .disabled(message == nil)
            Button("Add Reaction…") {
                if let selected, let message { window?.reactingTo = ReactionTarget(channel: selected.channel, message: message) }
            }
            .keyboardShortcut(Shortcuts.addReaction)
            .disabled(message == nil)
            Button("Mark as Unread") {
                if let selected, let message { selected.workspace.markUnread(from: message.ts, in: selected.channel) }
            }
            .keyboardShortcut(Shortcuts.markUnread)
            .disabled(!(message?.isChannelLevel ?? false))
            Divider()
            Button("Copy Link") {
                if let selected, let message { selected.workspace.copyLink(to: message, in: selected.channel) }
            }
            .keyboardShortcut(Shortcuts.copyLink)
            .disabled(message == nil)
            Divider()
            Button("Edit…") {
                if let selected, let message { window?.editing = MessageEdit(message, in: selected.channel) }
            }
            .keyboardShortcut(Shortcuts.edit)
            .disabled(!isOwn)
            Button("Delete…") {
                if let selected, let message { window?.deleting = ReactionTarget(channel: selected.channel, message: message) }
            }
            .keyboardShortcut(Shortcuts.delete)
            .disabled(!isOwn)
        }
        CommandMenu("Conversation") {
            let workspace = model.workspace(window?.accountID)
            let channel = window?.conversationID
            let isUnread = channel.map { workspace?.isUnread($0) ?? false } ?? false
            let isMuted = channel.map { workspace?.muted.contains($0) ?? false } ?? false
            Button(isUnread ? "Mark as Read" : "Mark as Unread") {
                guard let workspace, let channel else { return }
                if isUnread {
                    workspace.markAllRead(in: channel)
                } else if let newest = workspace.latestActivity[channel] ?? workspace.timelines[channel]?.newestTS {
                    workspace.markUnread(from: newest, in: channel)
                }
            }
            .keyboardShortcut(Shortcuts.markConversationRead)
            .disabled(channel == nil)
            Button(isMuted ? "Unmute" : "Mute") {
                if let workspace, let channel { workspace.setMuted(!isMuted, channel) }
            }
            .keyboardShortcut(Shortcuts.mute)
            .disabled(channel == nil)
        }
    }

    /// The selected message in the open conversation, with where it is.
    private var selection: (workspace: WorkspaceModel, channel: String, message: SlackMessage?)? {
        guard let window, let channel = window.conversationID,
              let workspace = model.workspace(window.accountID) else { return nil }
        let message = window.selectedMessage.flatMap { ts in
            workspace.timelines[channel]?.messages.first { $0.ts == ts }
        }
        return (workspace, channel, message)
    }
}
