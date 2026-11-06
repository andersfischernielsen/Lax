import AppKit
import LaxKit
import SwiftUI

@main
struct LaxApp: App {
    @State private var model: AppModel

    init() {
        // Unbundled (`swift run`), macOS treats the process as a background tool:
        // no Dock icon, no menu bar, windows open behind other apps.
        if Bundle.main.bundleIdentifier == nil {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate()
        }
        let model = AppModel()
        model.load()
        model.showAttentionInDock()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .commands {
            WorkspaceCommands(model: model)
            GoCommands(model: model)
            InspectorCommands()
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
