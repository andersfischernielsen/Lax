import LaxKit
import Observation

/// What one window or tab shows. Each has its own, so tabs can show different conversations.
@MainActor @Observable
final class WindowModel {
    /// What the sidebar lists: one of Slack's main views.
    enum Area: String, CaseIterable, Identifiable {
        case home
        case directMessages
        case threads

        var id: Self { self }

        var title: String {
            switch self {
            case .home: "Home"
            case .directMessages: "Direct Messages"
            case .threads: "Threads"
            }
        }

        var systemImage: String {
            switch self {
            case .home: "house"
            case .directMessages: "bubble.left.and.bubble.right"
            case .threads: "text.bubble"
            }
        }
    }

    var area = Area.home
    var accountID: SlackAccount.ID?
    var conversationID: SlackConversation.ID?
    /// The thread open in the Threads view.
    var followedThread: ThreadRef?
    /// The thread in the inspector; the inspector can be open without one.
    var thread: ThreadRef?
    var showsQuickSwitcher = false
    var showsInspector = false {
        // The highlight stands for what the inspector shows; hidden, nothing is shown.
        didSet { if !showsInspector { selectedMessage = nil } }
    }
    /// `ts` of the message highlighted in the conversation.
    var selectedMessage: String?
    var searchQuery = ""
    /// Bumped to put the cursor in the search field.
    var searchFocusRequests = 0
    /// Results of the last search; nil when not searching.
    var searchResults: [SearchResult]?
    var signIn: SignInController?
    /// The display name being edited, shown in a sheet.
    var editingDisplayName: String?
    /// A message the reaction picker is open for.
    var reactingTo: ReactionTarget?
    /// A message being edited, shown in a sheet.
    var editing: MessageEdit?

    /// Signs in to another workspace and switches this window to it.
    func beginSignIn(with app: AppModel) {
        signIn = app.signIn { [weak self] accounts in
            self?.signIn = nil
            if let account = accounts.first { self?.accountID = account.id }
        }
    }

    func select(_ conversation: SlackConversation.ID?) {
        guard conversation != conversationID else { return }
        conversationID = conversation
        selectedMessage = nil
        if thread?.channel != conversation { thread = nil }
    }

    func openThread(_ ts: String, in channel: String) {
        thread = ThreadRef(channel: channel, ts: ts)
        selectedMessage = ts
        showsInspector = true
    }

    func clearSearch() {
        searchResults = nil
    }

    /// Opens the result's conversation, and its thread if it's a reply.
    func open(_ result: SearchResult) {
        searchResults = nil
        searchQuery = ""
        select(result.channelID)
        if let thread = result.message.threadTS, thread != result.message.ts {
            openThread(thread, in: result.channelID)
        }
    }
}
