import LaxKit
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedAccountID) {
                Section("Workspaces") {
                    ForEach(model.accounts) { account in
                        Label(account.teamName, systemImage: "building.2")
                            .contextMenu {
                                Button("Sign Out", role: .destructive) { model.remove(account) }
                            }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                Button("Add Workspace", systemImage: "plus") { model.beginSignIn() }
            }
        } detail: {
            if let account = model.selectedAccount {
                ContentUnavailableView(account.teamName, systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Signed in as \(account.userName)."))
            } else {
                ContentUnavailableView {
                    Label("No Slack Workspace", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Sign in with your usual Slack login, SSO included.")
                } actions: {
                    Button("Add Workspace…") { model.beginSignIn() }
                }
            }
        }
        .sheet(item: $model.signIn) { controller in
            SignInView(controller: controller, cancel: model.cancelSignIn)
        }
        .alert("Something went wrong", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
