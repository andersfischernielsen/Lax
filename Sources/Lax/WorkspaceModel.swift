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
    /// Members of group DMs, for naming them.
    private(set) var groupMembers: [String: [String]] = [:]
    private(set) var customEmoji: [String: SlackEmoji] = [:]
    /// Custom emoji images by name, sized for inline text.
    private(set) var emojiImages: [String: NSImage] = [:]
    private(set) var timelines: [String: Timeline] = [:]
    private(set) var typing = TypingTracker()
    private(set) var unread = UnreadState()
    /// Muted conversations, derived from `mutePrefs`.
    private(set) var muted: Set<String> = []
    private(set) var status: RealTimeUpdate.Status = .connecting
    private(set) var loadingHistory: Set<String> = []
    private(set) var selectedConversationID: SlackConversation.ID?
    /// Read position per conversation as it was when opened; the "New" line goes after it.
    private(set) var unreadMarkers: [String: String] = [:]
    /// The thread shown beside the conversation, if any.
    private(set) var openThread: ThreadRef?
    private(set) var threads: [ThreadRef: Timeline] = [:]
    var drafts: [String: String] = [:]
    /// Pinned messages per conversation, loaded when asked for.
    private(set) var pinned: [String: [SlackMessage]] = [:]
    var searchQuery = ""
    /// Results of the last search; nil when not searching.
    private(set) var searchResults: [SearchResult]?
    /// A message being edited, shown in a sheet.
    var editing: MessageEdit?
    var errorMessage: String?

    @ObservationIgnored private let client: SlackAPIClient
    @ObservationIgnored private let connection: RealTimeConnection
    @ObservationIgnored private var typingThrottle = TypingThrottle()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var requestedUsers: Set<String> = []
    @ObservationIgnored private var readPositionKnown: Set<String> = []
    @ObservationIgnored private var markedReadTS: [String: String] = [:]
    @ObservationIgnored private let images = NSCache<NSURL, NSImage>()
    @ObservationIgnored private var mutePrefs = MutePrefs()
    @ObservationIgnored private var requestedEmoji: Set<String> = []

    nonisolated var id: SlackAccount.ID { account.id }

    init(account: SlackAccount) {
        self.account = account
        client = SlackAPIClient(credentials: account.credentials)
        connection = RealTimeConnection(client: client)
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
            Task { await loadMutePrefs() },
            Task { await loadCustomEmoji() },
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
        if openThread?.channel != channel { openThread = nil }
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
        conversation.displayName(userName: userName, members: groupMembers[conversation.id],
                                 ownUserID: account.userID)
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
        let emoji = customEmoji
        return SlackText(userName: { userNames[$0] }, channelName: { channelNames[$0] },
                         subteamHandle: { groups[$0] }, customEmoji: { emoji[$0] })
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
            await loadGroupMembers()
        } catch {
            errorMessage = "Couldn't load conversations (\(error))."
        }
    }

    private func loadGroupMembers() async {
        let groups = conversations.filter { $0.kind == .groupDirectMessage }.map(\.id)
        let client = client
        await withTaskGroup(of: (String, [String])?.self) { group in
            var pending = groups[...]
            for _ in 0..<min(6, pending.count) {
                let id = pending.removeFirst()
                group.addTask { (try? await client.members(of: id)).map { (id, $0) } }
            }
            for await result in group {
                if let (id, members) = result { groupMembers[id] = members }
                if let id = pending.popFirst() {
                    group.addTask { (try? await client.members(of: id)).map { (id, $0) } }
                }
            }
        }
        requestUsers(Set(groupMembers.values.joined()))
    }

    private func loadCustomEmoji() async {
        customEmoji = (try? await client.customEmoji()) ?? customEmoji
    }

    /// Fetches custom emoji images the first time they're shown.
    func requestEmojiImages(_ names: Set<String>) {
        let missing = names.subtracting(requestedEmoji)
        guard !missing.isEmpty else { return }
        requestedEmoji.formUnion(missing)
        for name in missing {
            guard case .image(let url) = customEmoji[name] else { continue }
            Task { emojiImages[name] = await image(at: url) }
        }
    }

    private func loadMutePrefs() async {
        guard let prefs = try? await client.mutePrefs() else { return }
        mutePrefs = prefs
        muted = prefs.muted
    }

    /// Mutes or unmutes at once; Slack echoes the change as a `pref_change`.
    func setMuted(_ isMuted: Bool, _ channel: String) {
        let before = muted
        if isMuted { muted.insert(channel) } else { muted.remove(channel) }
        Task {
            do {
                try await client.setMuted(isMuted, channel: channel)
            } catch {
                muted = before
                errorMessage = "Couldn't change notifications for the channel (\(error))."
            }
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
        for message in messages {
            let texts = [message.markup] + message.attachments.flatMap { [$0.pretext, $0.body].compactMap { $0 } }
            for text in texts { ids.formUnion(SlackText.mentionedUserIDs(in: text)) }
        }
        requestUsers(ids)
    }

    private func requestUsers(_ ids: Set<String>) {
        let missing = ids.subtracting(requestedUsers)
        guard !missing.isEmpty else { return }
        requestedUsers.formUnion(missing)
        // Each batch runs on its own, a few at a time, so the names for the messages
        // on screen don't queue behind a long batch like every DM partner.
        let client = client
        Task {
            await withTaskGroup(of: SlackUser?.self) { group in
                var pending = missing.sorted()[...]
                for _ in 0..<min(6, pending.count) {
                    let id = pending.removeFirst()
                    group.addTask { try? await client.user(id: id) }
                }
                for await user in group {
                    if let user { users[user.id] = user }
                    if let id = pending.popFirst() {
                        group.addTask { try? await client.user(id: id) }
                    }
                }
            }
        }
    }

    // MARK: - Sending

    /// Sends the draft for a conversation, or for a thread in it.
    func send(in channel: String, thread: String? = nil) {
        let key = thread.map { ThreadRef(channel: channel, ts: $0).draftKey } ?? channel
        let text = (drafts[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        drafts[key] = ""
        Task {
            do {
                let message = try await client.postMessage(channel: channel, text: SlackText.encodedForSending(text),
                                                            threadTS: thread)
                update(channel) { _ = $0.upsert(message) }
            } catch {
                drafts[key] = text
                errorMessage = "Couldn't send the message (\(error))."
            }
        }
    }

    /// Lets the conversation see the user typing, a few seconds at a time.
    func userTyped(in channel: String) {
        guard typingThrottle.shouldSend(in: channel) else { return }
        let connection = connection
        Task { await connection.sendTyping(in: channel) }
    }

    func loadPinned(in channel: String) {
        Task {
            do {
                let messages = try await client.pinnedMessages(in: channel)
                pinned[channel] = messages
                requestNames(for: messages)
            } catch {
                errorMessage = "Couldn't load pinned messages (\(error))."
            }
        }
    }

    // MARK: - Search

    func search() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return clearSearch() }
        Task {
            do {
                let results = try await client.searchMessages(query)
                searchResults = results
                requestNames(for: results.map(\.message))
            } catch {
                errorMessage = "Search failed (\(error))."
            }
        }
    }

    func clearSearch() {
        searchResults = nil
    }

    /// Opens the result's conversation, and its thread if it's a reply.
    func open(_ result: SearchResult) {
        clearSearch()
        searchQuery = ""
        select(result.channelID)
        if let thread = result.message.threadTS, thread != result.message.ts {
            openThread(thread, in: result.channelID)
        }
    }

    // MARK: - Message actions

    func beginEdit(_ message: SlackMessage, in channel: String) {
        editing = MessageEdit(channel: channel, ts: message.ts, text: SlackText.editable(message.text))
    }

    func saveEdit() {
        guard let edit = editing else { return }
        editing = nil
        let text = edit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            do {
                // The real-time connection delivers the updated message.
                try await client.editMessage(edit.ts, in: edit.channel, text: SlackText.encodedForSending(text))
            } catch {
                errorMessage = "Couldn't edit the message (\(error))."
            }
        }
    }

    func delete(_ message: SlackMessage, in channel: String) {
        Task {
            do {
                try await client.deleteMessage(message.ts, in: channel)
                update(channel) { $0.remove(ts: message.ts) }
            } catch {
                errorMessage = "Couldn't delete the message (\(error))."
            }
        }
    }

    func copyText(of message: SlackMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textFormatter().plain(message.markup), forType: .string)
    }

    func copyLink(to message: SlackMessage, in channel: String) {
        Task {
            do {
                let link = try await client.permalink(to: message.ts, in: channel)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.absoluteString, forType: .string)
            } catch {
                errorMessage = "Couldn't get a link to the message (\(error))."
            }
        }
    }

    // MARK: - Threads

    func openThread(_ ts: String, in channel: String) {
        let ref = ThreadRef(channel: channel, ts: ts)
        openThread = ref
        Task {
            do {
                let messages = try await client.replies(channel: channel, threadTS: ts)
                threads[ref] = Timeline(thread: ts, messages: messages)
                requestNames(for: messages)
            } catch {
                errorMessage = "Couldn't load the thread (\(error))."
            }
        }
    }

    func closeThread() {
        openThread = nil
    }

    /// Applies a change to a conversation and to any of its threads that are loaded.
    private func update(_ channel: String, _ change: (inout Timeline) -> Void) {
        if var timeline = timelines[channel] {
            change(&timeline)
            timelines[channel] = timeline
        }
        for ref in threads.keys where ref.channel == channel {
            change(&threads[ref]!)
        }
    }

    /// A Slack-hosted image, downloaded with the session cookie and kept in memory.
    func image(at url: URL) async -> NSImage? {
        if let cached = images.object(forKey: url as NSURL) { return cached }
        guard let data = try? await client.download(url), let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Adds or removes the user's reaction, showing it at once and undoing it if Slack refuses.
    func toggleReaction(_ name: String, on message: SlackMessage, in channel: String) {
        let me = account.userID
        let adding = !(message.reactions.first { $0.name == name }?.users.contains(me) ?? false)
        update(channel) { $0.react(name, by: me, added: adding, to: message.ts) }
        Task {
            do {
                try await client.react(name, to: message.ts, in: channel, added: adding)
            } catch {
                update(channel) { $0.react(name, by: me, added: !adding, to: message.ts) }
                errorMessage = "Couldn't update the reaction (\(error))."
            }
        }
    }

    // MARK: - Real time

    private func listen() async {
        for await update in connection.updates() {
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
            update(channel) { _ = $0.upsert(message) }
            if let user = message.userID { typing.clear(userID: user, in: channel) }
            if let conversation = conversations.first(where: { $0.id == channel }) {
                let isOpen = channel == selectedConversationID && NSApplication.shared.isActive
                unread.received(message, in: conversation, ownUserID: account.userID, isOpen: isOpen)
            }
            requestNames(for: [message])
            markReadIfVisible(channel)
        case .reaction(let channel, let ts, let name, let user, let added):
            update(channel) { $0.react(name, by: user, added: added, to: ts) }
        case .prefChange(let name, let value):
            mutePrefs.apply(prefChange: name, value: value)
            muted = mutePrefs.muted
        case .marked(let channel, let unreadCount, let mentionCount):
            unread.marked(channel, unreadCount: unreadCount, mentionCount: mentionCount)
        case .messageChanged(let channel, let message):
            update(channel) { $0.replace(message) }
            requestNames(for: [message])
        case .messageDeleted(let channel, let ts):
            update(channel) { $0.remove(ts: ts) }
        case .userTyping(let channel, let user):
            typing.record(userID: user, in: channel)
            requestUsers([user])
        case .other("emoji_changed"):
            requestedEmoji = []
            Task { await loadCustomEmoji() }
        case .hello, .goodbye, .other:
            break
        }
    }
}

/// A thread: its conversation and the parent message's `ts`.
struct ThreadRef: Hashable {
    let channel: String
    let ts: String

    /// Where the thread's unsent reply lives in `drafts`.
    var draftKey: String { "\(channel)/\(ts)" }
}

struct MessageEdit: Identifiable {
    let channel: String
    let ts: String
    var text: String

    var id: String { "\(channel)/\(ts)" }
}
