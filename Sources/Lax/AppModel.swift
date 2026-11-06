import LaxKit
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var accounts: [SlackAccount] = []
    private(set) var workspaces: [SlackAccount.ID: WorkspaceModel] = [:]
    /// The last thing that went wrong, shown as an alert.
    var problem: Problem?

    @ObservationIgnored private let store = CredentialStore()

    /// Any workspace has something unread worth a look; drives the Dock icon's dot.
    var needsAttention: Bool {
        workspaces.values.contains { $0.unread.needsAttention(muted: $0.muted) }
    }

    /// The workspace for `id`, or the first one when `id` is unknown.
    func workspace(_ id: SlackAccount.ID?) -> WorkspaceModel? {
        id.flatMap { workspaces[$0] } ?? accounts.first.flatMap { workspaces[$0.id] }
    }

    func load() {
        do {
            accounts = try store.loadAll()
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
        load()
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
        load()
    }

    /// One running workspace per saved account.
    private func syncWorkspaces() {
        let ids = Set(accounts.map(\.id))
        for (id, workspace) in workspaces where !ids.contains(id) {
            workspace.stop()
            workspaces[id] = nil
        }
        for account in accounts where workspaces[account.id] == nil {
            let workspace = WorkspaceModel(account: account)
            workspaces[account.id] = workspace
            workspace.start()
        }
    }
}
