import AppKit
import LaxKit
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var accounts: [SlackAccount] = []
    private(set) var workspaces: [SlackAccount.ID: WorkspaceModel] = [:]
    /// The last thing that went wrong, shown as an alert.
    var problem: Problem?

    @ObservationIgnored private let store = CredentialStore()

    /// What the dot on the Dock icon stands for.
    enum DockDot: String, CaseIterable {
        case unread
        case mentions
    }

    var dockDot = DockDot(rawValue: UserDefaults.standard.string(forKey: "dockDot") ?? "") ?? .unread {
        didSet { UserDefaults.standard.set(dockDot.rawValue, forKey: "dockDot") }
    }

    /// The Dock badge across all workspaces: the mention count, or a dot for other unreads.
    var dockBadge: String? {
        let all = workspaces.values
        return DockBadge.label(
            mentions: all.reduce(0) { $0 + $1.unread.totalMentions + $1.threadsUnread.mentions },
            hasOtherUnreads: all.contains { $0.unread.needsAttention(muted: $0.muted) || $0.threadsUnread.hasUnreads },
            mentionsOnly: dockDot == .mentions)
    }

    @ObservationIgnored private var showsAttentionInDock = false

    /// Keeps the Dock badge current from now on, with or without windows open.
    func startShowingAttentionInDock() {
        guard !showsAttentionInDock else { return }
        showsAttentionInDock = true
        showAttentionInDock()
    }

    private func showAttentionInDock() {
        NSApplication.shared.dockTile.badgeLabel = withObservationTracking {
            dockBadge
        } onChange: { [weak self] in
            Task { @MainActor in self?.showAttentionInDock() }
        }
    }

    /// The workspace for `id`, or the first one when `id` is unknown.
    func workspace(_ id: SlackAccount.ID?) -> WorkspaceModel? {
        id.flatMap { workspaces[$0] } ?? accounts.first.flatMap { workspaces[$0.id] }
    }

    /// Saved workspaces have been read (or there was nothing to read).
    private(set) var hasLoaded = false
    @ObservationIgnored private var started = false

    /// Reads saved workspaces and keeps the Dock badge current; once, when the first window shows.
    func start() async {
        guard !started else { return }
        started = true
        await load()
        startShowingAttentionInDock()
    }

    /// Reads saved workspaces off the main thread: the Keychain may ask the user for
    /// permission first, and the app must stay responsive meanwhile.
    func load() async {
        defer { hasLoaded = true }
        guard !DemoSlack.isEnabled else {
            accounts = [DemoSlack.account]
            return syncWorkspaces()
        }
        let store = store
        do {
            accounts = try await Task.detached { try store.loadAll() }.value
            Log.workspace.info("loaded \(self.accounts.count) account(s) from the Keychain")
        } catch {
            Log.workspace.error("Keychain read failed: \(Log.describe(error), privacy: .public)")
            problem = Problem("Couldn't Read Saved Workspaces", error)
        }
        syncWorkspaces()
    }

    /// A sign-in that saves the accounts it finds, then calls `finished` with them.
    func signIn(finished: @escaping ([SlackAccount]) -> Void) -> SignInController {
        SignInController { [weak self] accounts in
            self?.save(accounts)
            finished(accounts)
        }
    }

    func signOut(of account: SlackAccount) {
        do {
            try store.delete(id: account.id)
        } catch {
            problem = Problem("Couldn't Remove \(account.teamName)", error)
        }
        Task { await load() }
    }

    private func save(_ newAccounts: [SlackAccount]) {
        do {
            for account in newAccounts {
                try store.save(account)
                // Fresh credentials: drop any workspace still using the old ones.
                workspaces.removeValue(forKey: account.id)?.stop()
            }
        } catch {
            Log.workspace.error("Keychain save failed: \(Log.describe(error), privacy: .public)")
            problem = Problem("Couldn't Save the Workspace", error)
        }
        Task { await load() }
    }

    /// One running workspace per saved account.
    private func syncWorkspaces() {
        let ids = Set(accounts.map(\.id))
        for (id, workspace) in workspaces where !ids.contains(id) {
            workspace.stop()
            workspaces[id] = nil
        }
        for account in accounts where workspaces[account.id] == nil {
            let workspace = DemoSlack.isEnabled
                ? WorkspaceModel(account: account, session: DemoSlack.session, isLive: false)
                : WorkspaceModel(account: account)
            workspaces[account.id] = workspace
            workspace.start()
        }
    }
}
