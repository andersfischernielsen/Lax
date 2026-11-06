import LaxKit
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var accounts: [SlackAccount] = []
    private(set) var workspaces: [SlackAccount.ID: WorkspaceModel] = [:]
    var selectedAccountID: SlackAccount.ID?
    var signIn: SignInController?
    var errorMessage: String?

    @ObservationIgnored private let store = CredentialStore()

    var currentWorkspace: WorkspaceModel? {
        selectedAccountID.flatMap { workspaces[$0] }
    }

    func load() {
        do {
            accounts = try store.loadAll()
        } catch {
            errorMessage = "Couldn't read saved accounts from the Keychain (\(error))."
        }
        syncWorkspaces()
        if currentWorkspace == nil { selectedAccountID = accounts.first?.id }
    }

    func beginSignIn() {
        signIn = SignInController { [weak self] accounts in self?.finishSignIn(with: accounts) }
    }

    func cancelSignIn() {
        signIn = nil
    }

    func signOut(of account: SlackAccount) {
        do {
            try store.delete(id: account.id)
        } catch {
            errorMessage = "Couldn't remove \(account.teamName) from the Keychain (\(error))."
        }
        if selectedAccountID == account.id { selectedAccountID = nil }
        load()
    }

    private func finishSignIn(with newAccounts: [SlackAccount]) {
        signIn = nil
        do {
            for account in newAccounts {
                try store.save(account)
                // Fresh credentials: drop any workspace still using the old ones.
                workspaces.removeValue(forKey: account.id)?.stop()
            }
        } catch {
            errorMessage = "Couldn't save the account to the Keychain (\(error))."
        }
        load()
        selectedAccountID = newAccounts.first?.id ?? selectedAccountID
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
