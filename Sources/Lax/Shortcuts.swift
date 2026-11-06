import SwiftUI

/// Keyboard shortcuts shared by the menu bar and the right-click menus that show them.
/// A right-click menu only displays a shortcut; the menu bar item is what answers it.
enum Shortcuts {
    static let replyInThread = KeyboardShortcut("r", modifiers: .command)
    static let addReaction = KeyboardShortcut("\\", modifiers: [.command, .shift])
    static let markUnread = KeyboardShortcut("u", modifiers: [.command, .shift])
    static let copyText = KeyboardShortcut("c", modifiers: .command)
    /// Not ⇧⌘C, which formats code in the composer.
    static let copyLink = KeyboardShortcut("c", modifiers: [.command, .option])
    /// Not ⌘E, the standard Use Selection for Find.
    static let edit = KeyboardShortcut("e", modifiers: [.command, .option])
    static let delete = KeyboardShortcut(.delete, modifiers: .command)

    /// In the composer, as in Slack.
    static let attachFiles = KeyboardShortcut("u", modifiers: .command)

    static let markConversationRead = KeyboardShortcut("r", modifiers: [.command, .shift])
    static let mute = KeyboardShortcut("m", modifiers: [.command, .shift])
}
