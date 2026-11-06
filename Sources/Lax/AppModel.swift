import LaxKit
import Observation

@MainActor @Observable
final class AppModel {
    private(set) var accounts: [SlackAccount] = []
    var selectedAccountID: SlackAccount.ID?
    var signIn: SignInController?
    var errorMessage: String?

    @ObservationIgnored private let store = CredentialStore()

    var selectedAccount: SlackAccount? {
        accounts.first { $0.id == selectedAccountID }
    }

    func load() {
        do {
            accounts = try store.loadAll()
        } catch {
            errorMessage = "Couldn't read saved accounts from the Keychain (\(error))."
        }
        if selectedAccount == nil { selectedAccountID = accounts.first?.id }
    }

    func beginSignIn() {
        signIn = SignInController { [weak self] accounts in self?.finishSignIn(with: accounts) }
    }

    func cancelSignIn() {
        signIn = nil
    }

    func remove(_ account: SlackAccount) {
        do {
            try store.delete(id: account.id)
        } catch {
            errorMessage = "Couldn't remove \(account.teamName) from the Keychain (\(error))."
        }
        load()
    }

    private func finishSignIn(with newAccounts: [SlackAccount]) {
        signIn = nil
        do {
            for account in newAccounts { try store.save(account) }
        } catch {
            errorMessage = "Couldn't save the account to the Keychain (\(error))."
        }
        load()
        selectedAccountID = newAccounts.first?.id ?? selectedAccountID
    }
}
