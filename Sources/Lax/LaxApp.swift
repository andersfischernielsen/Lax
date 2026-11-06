import AppKit
import SwiftUI

@main
struct LaxApp: App {
    @State private var model = AppModel()

    init() {
        // Unbundled (`swift run`), macOS treats the process as a background tool:
        // no Dock icon, no menu bar, windows open behind other apps.
        if Bundle.main.bundleIdentifier == nil {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { model.load() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Workspace…") { model.beginSignIn() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
