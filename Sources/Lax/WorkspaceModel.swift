import AppKit
import LaxKit
import Observation

/// Everything Lax shows for one signed-in workspace, kept current by the real-time connection.
@MainActor @Observable
final class WorkspaceModel: Identifiable {
    let account: SlackAccount
    private(set) var conversations: [SlackConversation] = []
    // Per-key stores: a view redraws only for the entries it reads.
    let users = KeyedStore<String, SlackUser>()
    private(set) var userGroupHandles: [String: String] = [:]
    /// Members of group DMs, for naming them.
    private(set) var groupMembers: [String: [String]] = [:]
    private(set) var customEmoji: [String: SlackEmoji] = [:]
    /// Custom emoji images by name, sized for inline text.
    let emojiImages = KeyedStore<String, NSImage>()
    let timelines = KeyedStore<String, Timeline>()
    /// Who is typing, per conversation.
    let typing = KeyedStore<String, TypingTracker>()
    private(set) var unread = UnreadState()
    /// `ts` of each conversation's newest message, for ordering DMs by activity.
    private(set) var latestActivity: [String: String] = [:]
    /// Followed threads taken together, for the Threads entry in the sidebar.
    private(set) var threadsUnread = UnreadState.Counts()
    /// Threads the user follows, most recently active first; nil until first loaded.
    private(set) var followedThreads: [ThreadSummary]?
    private(set) var hasMoreFollowedThreads = false
    @ObservationIgnored private var loadingFollowedThreads = false
    /// Muted conversations, derived from `mutePrefs`.
    private(set) var muted: Set<String> = []
    private(set) var status: RealTimeUpdate.Status = .connecting
    private(set) var loadingHistory: Set<String> = []
    /// Read position per conversation as it was when opened; the "New" line goes after it.
    let unreadMarkers = KeyedStore<String, String>()
    let threads = KeyedStore<ThreadRef, Timeline>()
    let drafts = KeyedStore<String, String>()
    /// Channel names by ID, for mentions.
    private(set) var channelNames: [String: String] = [:]
    /// The last thing that went wrong, shown as an alert.
    var problem: Problem?

    @ObservationIgnored private let client: SlackAPIClient
    @ObservationIgnored private let connection: RealTimeConnection
    @ObservationIgnored private var typingThrottle = TypingThrottle()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var requestedUsers: Set<String> = []
    /// Conversations whose read position has been fetched since they were opened.
    private(set) var readPositionKnown: Set<String> = []
    @ObservationIgnored private var markedReadTS: [String: String] = [:]
    /// The newest message that has been on screen, per conversation.
    @ObservationIgnored private var seenTS: [String: String] = [:]
    @ObservationIgnored private var markReadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let images = NSCache<NSURL, NSImage>()
    @ObservationIgnored private var mutePrefs = MutePrefs()
    @ObservationIgnored private var requestedEmoji: Set<String> = []
    @ObservationIgnored private lazy var formattedTexts = FormattedTextCache { [unowned self] lookup in
        switch lookup {
        case .user(let id): .name(userName(id))
        case .channel(let id): .name(channelNames[id])
        case .group(let id): .name(userGroupHandles[id])
        case .emoji(let name): .emoji(customEmoji[name])
        }
    }
    /// How many windows show each conversation; those are kept read.
    @ObservationIgnored private var visible: [String: Int] = [:]

    nonisolated var id: SlackAccount.ID { account.id }

    init(account: SlackAccount) {
        self.account = account
        client = SlackAPIClient(credentials: account.credentials)
        connection = RealTimeConnection(client: client)
    }

    private var lastConversationKey: String { "lastConversation.\(account.id)" }

    func conversation(_ id: SlackConversation.ID?) -> SlackConversation? {
        conversations.first { $0.id == id }
    }

    /// The conversation last opened in any window, for new windows to start with.
    var lastConversationID: SlackConversation.ID? {
        UserDefaults.standard.string(forKey: lastConversationKey)
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
            Task { requestUsers([account.userID]) },
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    /// A window started showing the conversation: load it. Messages are marked read as
    /// they scroll into view (`saw`).
    func show(_ channel: String) {
        visible[channel, default: 0] += 1
        UserDefaults.standard.set(channel, forKey: lastConversationKey)
        // Already on screen elsewhere: keep that window's "New" line.
        guard visible[channel] == 1 else { return }
        if timelines[channel] == nil { loadOlder(in: channel) }

        // Read the old position before marking anything read, or the marker would vanish.
        readPositionKnown.remove(channel)
        unreadMarkers[channel] = nil
        Task {
            let lastRead = try? await client.lastRead(channel: channel)
            unreadMarkers[channel] = lastRead
            // Never move the read position back by seeing older messages.
            if let lastRead { markedReadTS[channel] = SlackTimestamp.later(markedReadTS[channel], lastRead) }
            readPositionKnown.insert(channel)
            markReadIfVisible(channel)
        }
    }

    /// A message scrolled into view.
    func saw(_ ts: String, in channel: String) {
        seenTS[channel] = SlackTimestamp.later(seenTS[channel], ts)
        // Caught up: clear the badge at once; Slack hears about it after a pause.
        if seenTS[channel] == timelines[channel]?.newestTS, NSApplication.shared.isActive { unread.read(channel) }
        markReadIfVisible(channel)
    }

    func hide(_ channel: String) {
        visible[channel, default: 1] -= 1
        guard visible[channel] == 0 else { return }
        visible[channel] = nil
        // Fetched afresh next time, so it opens at the then-current "New" line.
        readPositionKnown.remove(channel)
        // Off screen, keep one page: showing it again then lays out 50 rows, not every
        // message ever scrolled back to.
        timelines.update(channel) { $0 = $0.keepingNewest(50) }
    }

    /// Marks conversations on screen read up to the newest message seen, while Lax is in front.
    func markReadIfVisible(_ channel: String? = nil) {
        for channel in channel.map({ [$0] }) ?? Array(visible.keys) { markRead(channel) }
    }

    /// Waits briefly for scrolling to settle, so passing many messages sends one update.
    private func markRead(_ channel: String) {
        guard visible[channel] != nil,
              readPositionKnown.contains(channel),
              NSApplication.shared.isActive,
              let seen = seenTS[channel],
              SlackTimestamp.isBefore(markedReadTS[channel] ?? "0", seen) else { return }
        markReadTasks[channel]?.cancel()
        markReadTasks[channel] = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let position = seenTS[channel],
                  SlackTimestamp.isBefore(markedReadTS[channel] ?? "0", position) else { return }
            markedReadTS[channel] = position
            // The "New" line follows the read position: it moves down to the first unread
            // message, and goes once everything has been read.
            unreadMarkers[channel] = position
            try? await client.markRead(channel: channel, ts: position)
        }
    }

    // MARK: - Sidebar

    /// Channels by name: the Channels sidebar and its keyboard order.
    var channelsByName: [(conversation: SlackConversation, name: String)] {
        conversations.filter { !$0.isDirect }
            .map { (conversation: $0, name: displayName(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Direct messages, most recently active first.
    var directMessagesByActivity: [(conversation: SlackConversation, name: String)] {
        conversations.filter(\.isDirect)
            .map { (conversation: $0, name: displayName(of: $0)) }
            .sorted { (latestActivity[$0.conversation.id] ?? "0").localizedStandardCompare(latestActivity[$1.conversation.id] ?? "0") == .orderedDescending }
    }

    /// Conversation order for keyboard navigation in an area.
    func navigationOrder(in area: WindowModel.Area) -> [String] {
        switch area {
        case .channels: channelsByName.map(\.conversation.id)
        case .directMessages: directMessagesByActivity.map(\.conversation.id)
        case .threads: []
        }
    }

    /// Worth opening: unread outside muted conversations, or a mention anywhere.
    func isUnread(_ id: String) -> Bool {
        let counts = unread[id]
        return counts.mentions > 0 || (counts.hasUnreads && !muted.contains(id))
    }

    /// Moves the read position to just before `ts`, so it and everything after it are unread.
    func markUnread(from ts: String, in channel: String) {
        guard let position = SlackTimestamp.justBefore(ts) else { return }
        // Read and seen both go back to just before it. It stays unread while on screen,
        // since only rows coming into view count; scrolled away and back, it's read again.
        markReadTasks[channel]?.cancel()
        markedReadTS[channel] = position
        seenTS[channel] = position
        unreadMarkers[channel] = position
        unread.marked(channel, unreadCount: 1, mentionCount: unread[channel].mentions)
        Task {
            do {
                try await client.markRead(channel: channel, ts: position)
            } catch {
                problem = Problem("Couldn't Mark as Unread", error)
            }
        }
    }

    /// Marks everything in a conversation read, from the sidebar.
    func markAllRead(in channel: String) {
        guard let newest = timelines[channel]?.newestTS ?? latestActivity[channel] else { return }
        markedReadTS[channel] = newest
        unreadMarkers[channel] = newest
        unread.read(channel)
        Task {
            do {
                try await client.markRead(channel: channel, ts: newest)
            } catch {
                problem = Problem("Couldn't Mark as Read", error)
            }
        }
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

    /// A formatter that looks names up as it goes, so a view using it depends only on
    /// the names its text mentions. For use on the main actor, in views.
    func textFormatter() -> SlackText {
        SlackText(userName: { id in MainActor.assumeIsolated { self.userName(id) } },
                  channelName: { id in MainActor.assumeIsolated { self.channelNames[id] } },
                  subteamHandle: { id in MainActor.assumeIsolated { self.userGroupHandles[id] } },
                  customEmoji: { name in MainActor.assumeIsolated { self.customEmoji[name] } })
    }

    /// A message's text, formatted and styled, from the cache when nothing it shows changed.
    func formattedText(_ markup: String) -> AttributedString {
        formattedTexts.text(for: markup) { MessageStyle.styled($0.attributed(markup)) }
    }

    // MARK: - Loading

    func loadOlder(in channel: String) {
        Task { await fetchOlder(in: channel) }
    }

    private func fetchOlder(in channel: String) async {
        guard !loadingHistory.contains(channel) else { return }
        loadingHistory.insert(channel)
        defer { loadingHistory.remove(channel) }
        do {
            let page = try await client.history(channel: channel, before: timelines[channel]?.oldestTS)
            var timeline = timelines[channel] ?? Timeline()
            timeline.addOlder(page)
            timelines[channel] = timeline
            requestNames(for: page.messages)
            markReadIfVisible(channel)
        } catch is CancellationError {
        } catch {
            problem = Problem("Couldn't Load Messages", error)
        }
    }

    /// Loads older pages until the conversation reaches back to `ts`, for jumping to a
    /// message; stops after `maxPages` so a very old message can't load the whole history.
    func loadThrough(_ ts: String, in channel: String, maxPages: Int = 20) async {
        for _ in 0..<maxPages {
            // A page already on its way (the first, as the conversation opens) comes first.
            while loadingHistory.contains(channel) { try? await Task.sleep(for: .milliseconds(50)) }
            if let timeline = timelines[channel],
               !timeline.hasOlder || timeline.oldestTS.map({ !SlackTimestamp.isBefore(ts, $0) }) ?? false {
                return
            }
            await fetchOlder(in: channel)
        }
    }

    private func loadConversations() async {
        do {
            conversations = try await client.conversations()
            channelNames = Dictionary(conversations.compactMap { c in c.name.map { (c.id, $0) } },
                                      uniquingKeysWith: { first, _ in first })
            requestUsers(Set(conversations.compactMap(\.userID)))
            await loadGroupMembers()
        } catch {
            problem = Problem("Couldn't Load Conversations", error)
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
            Task { emojiImages[name] = await image(at: url).map { RichText.inline($0) } }
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
                problem = Problem("Couldn't Change Notifications", error)
            }
        }
    }

    private func loadUnreadCounts() async {
        guard let counts = try? await client.clientCounts() else { return }
        unread = counts.unread
        latestActivity = counts.latest
        threadsUnread = counts.threads
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
                problem = Problem("Couldn't Send the Message", error)
            }
        }
    }

    /// Lets the conversation see the user typing, a few seconds at a time.
    func userTyped(in channel: String) {
        guard typingThrottle.shouldSend(in: channel) else { return }
        let connection = connection
        Task { await connection.sendTyping(in: channel) }
    }

    var ownDisplayName: String {
        users[account.userID]?.displayName ?? ""
    }

    /// Saves the display name; the profile change arrives as a `user_change` event too.
    func saveDisplayName(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                try await client.setDisplayName(name)
                if let user = try? await client.user(id: account.userID) { users[user.id] = user }
            } catch {
                problem = Problem("Couldn't Change Your Display Name", error)
            }
        }
    }

    // MARK: - Search

    /// Messages matching `query`, newest first; nil if the search failed.
    func search(_ query: String) async -> [SearchResult]? {
        do {
            let results = try await client.searchMessages(query)
            requestNames(for: results.map(\.message))
            return results
        } catch {
            problem = Problem("Couldn't Search", error)
            return nil
        }
    }

    // MARK: - Message actions

    func saveEdit(_ edit: MessageEdit) {
        let text = edit.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            do {
                // The real-time connection delivers the updated message.
                try await client.editMessage(edit.ts, in: edit.channel, text: SlackText.encodedForSending(text))
            } catch {
                problem = Problem("Couldn't Edit the Message", error)
            }
        }
    }

    func delete(_ message: SlackMessage, in channel: String) {
        Task {
            do {
                try await client.deleteMessage(message.ts, in: channel)
                update(channel) { $0.remove(ts: message.ts) }
            } catch {
                problem = Problem("Couldn't Delete the Message", error)
            }
        }
    }

    /// The message as plain text, mentions and emoji resolved, for copying.
    func plainText(of message: SlackMessage) -> String {
        textFormatter().plain(message.markup)
    }

    func copyText(of message: SlackMessage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText(of: message), forType: .string)
    }

    func copyLink(to message: SlackMessage, in channel: String) {
        Task {
            do {
                let link = try await client.permalink(to: message.ts, in: channel)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.absoluteString, forType: .string)
            } catch {
                problem = Problem("Couldn't Copy the Link", error)
            }
        }
    }

    // MARK: - Threads

    /// Loads the first page of followed threads, replacing what was there.
    func loadFollowedThreads() async {
        guard !loadingFollowedThreads else { return }
        loadingFollowedThreads = true
        defer { loadingFollowedThreads = false }
        do {
            let page = try await client.followedThreads()
            followedThreads = page.threads
            hasMoreFollowedThreads = page.hasMore
            requestNames(for: page.threads.flatMap { [$0.root] + $0.latestReplies })
        } catch is CancellationError {
        } catch {
            problem = Problem("Couldn't Load Threads", error)
        }
    }

    func loadMoreFollowedThreads() {
        guard hasMoreFollowedThreads, !loadingFollowedThreads,
              let oldest = followedThreads?.last?.latestReplyTS ?? followedThreads?.last?.root.ts else { return }
        loadingFollowedThreads = true
        Task {
            defer { loadingFollowedThreads = false }
            guard let page = try? await client.followedThreads(before: oldest) else { return }
            let known = Set(followedThreads?.map(\.id) ?? [])
            followedThreads = (followedThreads ?? []) + page.threads.filter { !known.contains($0.id) }
            hasMoreFollowedThreads = page.hasMore
            requestNames(for: page.threads.flatMap { [$0.root] + $0.latestReplies })
        }
    }

    /// Marks a followed thread read up to its newest reply, here and in every Slack client.
    func markRead(_ thread: ThreadSummary) {
        followedThreads = followedThreads?.markingRead(thread.id)
        threadsUnread.hasUnreads = followedThreads?.contains { $0.unreadReplies > 0 } ?? false
        Task {
            try? await client.markThreadRead(channel: thread.channelID, threadTS: thread.root.ts,
                                             ts: thread.latestReplyTS ?? thread.root.ts)
        }
    }

    /// Fetches the whole thread; it's kept current from then on.
    func loadThread(_ ref: ThreadRef) async {
        do {
            let messages = try await client.replies(channel: ref.channel, threadTS: ref.ts)
            threads[ref] = Timeline(thread: ref.ts, messages: messages)
            requestNames(for: messages)
        } catch is CancellationError {
        } catch {
            problem = Problem("Couldn't Load the Thread", error)
        }
    }

    /// Applies a change to a conversation and to any of its threads that are loaded.
    private func update(_ channel: String, _ change: (inout Timeline) -> Void) {
        timelines.update(channel, change)
        for ref in threads.keys where ref.channel == channel {
            threads.update(ref, change)
        }
    }

    /// An image already downloaded, without waiting.
    func cachedImage(at url: URL) -> NSImage? {
        images.object(forKey: url as NSURL)
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
                problem = Problem("Couldn't Update the Reaction", error)
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
            if message.isChannelLevel { latestActivity[channel] = message.ts }
            if let threads = followedThreads {
                followedThreads = threads.receiving(message, in: channel, ownUserID: account.userID)
                if followedThreads?.first?.unreadReplies ?? 0 > 0, followedThreads != threads {
                    threadsUnread.hasUnreads = true
                }
            }
            if let user = message.userID { typing.update(channel) { $0.clear(userID: user, in: channel) } }
            if let conversation = conversations.first(where: { $0.id == channel }) {
                // Unread until it scrolls into view, even in an open conversation.
                unread.received(message, in: conversation, ownUserID: account.userID, isOpen: false)
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
            var tracker = typing[channel] ?? TypingTracker()
            tracker.record(userID: user, in: channel)
            typing[channel] = tracker
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
struct ThreadRef: Hashable, Sendable {
    let channel: String
    let ts: String

    /// Where the thread's unsent reply lives in `drafts`.
    var draftKey: String { "\(channel)/\(ts)" }
}

struct MessageEdit: Identifiable {
    let channel: String
    let ts: String
    var text: String

    init(_ message: SlackMessage, in channel: String) {
        self.channel = channel
        ts = message.ts
        text = SlackText.editable(message.text)
    }

    var id: String { "\(channel)/\(ts)" }
}

struct ReactionTarget: Identifiable {
    let channel: String
    let message: SlackMessage

    var id: String { "\(channel)/\(message.ts)" }
}
