import AppKit
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
