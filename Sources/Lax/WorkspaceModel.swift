import AppKit
import LaxKit
import Observation

/// Everything Lax shows for one signed-in workspace, kept current by the real-time connection.
@MainActor @Observable
final class WorkspaceModel: Identifiable {
    let account: SlackAccount
    private(set) var conversations: [SlackConversation] = []
    private(set) var users: [String: SlackUser] = [:]
    private(set) var userGroupHandles: [String: String] = [:]
    private(set) var timelines: [String: Timeline] = [:]
    private(set) var typing = TypingTracker()
    private(set) var unread = UnreadState()
    private(set) var status: RealTimeUpdate.Status = .connecting
    private(set) var loadingHistory: Set<String> = []
    private(set) var selectedConversationID: SlackConversation.ID?
    /// Read position per conversation as it was when opened; the "New" line goes after it.
    private(set) var unreadMarkers: [String: String] = [:]
    var drafts: [String: String] = [:]
    var errorMessage: String?

    @ObservationIgnored private let client: SlackAPIClient
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var requestedUsers: Set<String> = []
    @ObservationIgnored private var readPositionKnown: Set<String> = []
    @ObservationIgnored private var markedReadTS: [String: String] = [:]

    nonisolated var id: SlackAccount.ID { account.id }

    init(account: SlackAccount) {
        self.account = account
        client = SlackAPIClient(credentials: account.credentials)
    }

    private var lastConversationKey: String { "lastConversation.\(account.id)" }

    var selectedConversation: SlackConversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    func start() {
        guard tasks.isEmpty else { return }
        tasks = [
            Task { await loadConversations() },
            Task { await loadUserGroups() },
            Task { await loadUnreadCounts() },
            Task { await listen() },
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    func select(_ conversationID: SlackConversation.ID?) {
        selectedConversationID = conversationID
        UserDefaults.standard.set(conversationID, forKey: lastConversationKey)
        guard let channel = conversationID else { return }
        unread.read(channel)
        if timelines[channel] == nil { loadOlder(in: channel) }

        // Read the old position before marking anything read, or the marker would vanish.
        readPositionKnown.remove(channel)
        unreadMarkers[channel] = nil
        Task {
            unreadMarkers[channel] = try? await client.lastRead(channel: channel)
            readPositionKnown.insert(channel)
            markReadIfVisible(channel)
        }
    }

    /// Marks the open conversation read up to its newest message, while Lax is in front.
    func markReadIfVisible(_ channel: String? = nil) {
        guard let channel = channel ?? selectedConversationID,
              channel == selectedConversationID,
              readPositionKnown.contains(channel),
              NSApplication.shared.isActive,
              let newest = timelines[channel]?.newestTS,
              markedReadTS[channel] != newest else { return }
        markedReadTS[channel] = newest
        Task { try? await client.markRead(channel: channel, ts: newest) }
    }

    // MARK: - Names

    func userName(_ id: String) -> String? {
        users[id]?.preferredName
    }

    func displayName(of conversation: SlackConversation) -> String {
        conversation.displayName(userName: userName)
    }

    func authorName(of message: SlackMessage) -> String {
        message.userID.flatMap(userName) ?? message.username ?? message.userID ?? "Unknown"
    }

    /// A formatter that resolves mentions with the names known right now.
    func textFormatter() -> SlackText {
        let userNames = users.mapValues(\.preferredName)
        let channelNames = Dictionary(conversations.compactMap { c in c.name.map { (c.id, $0) } },
                                      uniquingKeysWith: { first, _ in first })
        let groups = userGroupHandles
        return SlackText(userName: { userNames[$0] }, channelName: { channelNames[$0] },
                         subteamHandle: { groups[$0] })
    }

    // MARK: - Loading

    func loadOlder(in channel: String) {
        guard !loadingHistory.contains(channel) else { return }
        loadingHistory.insert(channel)
        Task {
            defer { loadingHistory.remove(channel) }
            do {
                let page = try await client.history(channel: channel, before: timelines[channel]?.oldestTS)
                timelines[channel, default: Timeline()].addOlder(page)
                requestNames(for: page.messages)
                markReadIfVisible(channel)
            } catch {
                errorMessage = "Couldn't load messages (\(error))."
            }
        }
    }

    private func loadConversations() async {
        do {
            conversations = try await client.conversations()
            if selectedConversationID == nil,
               let last = UserDefaults.standard.string(forKey: lastConversationKey),
               conversations.contains(where: { $0.id == last }) {
                select(last)
            }
            requestUsers(Set(conversations.compactMap(\.userID)))
        } catch {
            errorMessage = "Couldn't load conversations (\(error))."
        }
    }

    private func loadUnreadCounts() async {
        if let counts = try? await client.unreadCounts() { unread = counts }
    }

    private func loadUserGroups() async {
        // Not every workspace allows listing groups; mentions then fall back to "@group".
        userGroupHandles = (try? await client.userGroupHandles()) ?? [:]
    }

    private func requestNames(for messages: [SlackMessage]) {
        var ids = Set(messages.compactMap(\.userID))
        for message in messages { ids.formUnion(SlackText.mentionedUserIDs(in: message.text)) }
        requestUsers(ids)
    }

    private func requestUsers(_ ids: Set<String>) {
        let missing = ids.subtracting(requestedUsers)
        guard !missing.isEmpty else { return }
        requestedUsers.formUnion(missing)
        Task {
            for id in missing.sorted() {
                if let user = try? await client.user(id: id) { users[id] = user }
            }
        }
    }

    // MARK: - Sending

    func send(in channel: String) {
        let text = (drafts[channel] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        drafts[channel] = ""
        Task {
            do {
                let message = try await client.postMessage(channel: channel, text: text)
                timelines[channel]?.upsert(message)
            } catch {
                drafts[channel] = text
                errorMessage = "Couldn't send the message (\(error))."
            }
        }
    }

    /// Adds or removes the user's reaction, showing it at once and undoing it if Slack refuses.
    func toggleReaction(_ name: String, on message: SlackMessage, in channel: String) {
        let me = account.userID
        let adding = !(message.reactions.first { $0.name == name }?.users.contains(me) ?? false)
        timelines[channel]?.react(name, by: me, added: adding, to: message.ts)
        Task {
            do {
                try await client.react(name, to: message.ts, in: channel, added: adding)
            } catch {
                timelines[channel]?.react(name, by: me, added: !adding, to: message.ts)
                errorMessage = "Couldn't update the reaction (\(error))."
            }
        }
    }

    // MARK: - Real time

    private func listen() async {
        for await update in RealTimeConnection(client: client).updates() {
            switch update {
            case .status(let newStatus): status = newStatus
            case .event(let event): apply(event)
            }
        }
    }

    private func apply(_ event: RealTimeEvent) {
        switch event {
        case .message(let channel, let message):
            // Unloaded conversations fetch fresh history when opened.
            timelines[channel]?.upsert(message)
            if let user = message.userID { typing.clear(userID: user, in: channel) }
            if let conversation = conversations.first(where: { $0.id == channel }) {
                let isOpen = channel == selectedConversationID && NSApplication.shared.isActive
                unread.received(message, in: conversation, ownUserID: account.userID, isOpen: isOpen)
            }
            requestNames(for: [message])
            markReadIfVisible(channel)
        case .reaction(let channel, let ts, let name, let user, let added):
            timelines[channel]?.react(name, by: user, added: added, to: ts)
        case .marked(let channel, let unreadCount, let mentionCount):
            unread.marked(channel, unreadCount: unreadCount, mentionCount: mentionCount)
        case .messageChanged(let channel, let message):
            timelines[channel]?.replace(message)
            requestNames(for: [message])
        case .messageDeleted(let channel, let ts):
            timelines[channel]?.remove(ts: ts)
        case .userTyping(let channel, let user):
            typing.record(userID: user, in: channel)
            requestUsers([user])
        case .hello, .goodbye, .other:
            break
        }
    }
}
