import LaxKit
import Observation

/// What one window or tab shows. Each has its own, so tabs can show different conversations.
@MainActor @Observable
final class WindowModel {
    /// What the sidebar lists: one of Slack's main views.
    enum Area: String, CaseIterable, Identifiable {
        case channels
        case directMessages
        case threads

        var id: Self { self }

        var title: String {
            switch self {
            case .channels: "Channels"
            case .directMessages: "Direct Messages"
            case .threads: "Threads"
            }
        }

        var systemImage: String {
            switch self {
            case .channels: "number"
            case .directMessages: "bubble.left.and.bubble.right"
            case .threads: "text.bubble"
            }
        }
    }

    var area = Area.channels
    var accountID: SlackAccount.ID?
    var conversationID: SlackConversation.ID?
    /// The thread open in the Threads view.
    var followedThread: ThreadRef?
    /// The thread in the inspector, which is always shown beside conversations.
    var thread: ThreadRef?
    var showsQuickSwitcher = false
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

    /// Where the window is: what back and forward move between.
    struct Place: Equatable, Sendable {
        let area: Area
        let conversationID: SlackConversation.ID?
        let followedThread: ThreadRef?
    }

    private(set) var history = NavigationHistory<Place>()

    var place: Place {
        Place(area: area, conversationID: conversationID, followedThread: followedThread)
    }

    /// Notes a place the window went to; going back or forward doesn't add one.
    func record(_ place: Place) {
        history.visit(place)
    }

    func goBack() {
        if let place = history.goBack() { go(to: place) }
    }

    func goForward() {
        if let place = history.goForward() { go(to: place) }
    }

    private func go(to place: Place) {
        area = place.area
        select(place.conversationID)
        followedThread = place.followedThread
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
    }

    func clearSearch() {
        searchResults = nil
    }

    /// Shows a conversation, switching to the area that lists it.
    func show(_ conversation: SlackConversation) {
        area = conversation.isDirect ? .directMessages : .channels
        select(conversation.id)
    }

    /// Opens the result's conversation, and its thread if it's a reply.
    func open(_ result: SearchResult, conversation: SlackConversation?) {
        searchResults = nil
        searchQuery = ""
        if let conversation { show(conversation) } else { select(result.channelID) }
        if let thread = result.message.threadTS, thread != result.message.ts {
            openThread(thread, in: result.channelID)
        }
    }
}
