import LaxKit
import SwiftUI

/// Lax ▸ Settings… (⌘,).
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(model: model)
            }
            Tab("Workspaces", systemImage: "building.2") {
                WorkspaceSettings(model: model)
            }
        }
        .scenePadding()
        .frame(width: 460)
    }
}

private struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Picker("Dock icon badge:", selection: $model.dockDot) {
                Text("Unread messages").tag(AppModel.DockDot.unread)
                Text("Mentions and direct messages").tag(AppModel.DockDot.mentions)
            }
            .pickerStyle(.radioGroup)
            Text("Mentions and direct messages show a count; other unread messages a dot. Muted conversations count only when someone mentions you.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkspaceSettings: View {
    let model: AppModel
    @State private var selection: SlackAccount.ID?
    @State private var signingOut: SlackAccount?
    @State private var signIn: SignInController?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(model.accounts, selection: $selection) { account in
                VStack(alignment: .leading) {
                    Text(account.teamName)
                    Text(account.credentials.workspaceDomain).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(height: 180)
            .overlay {
                if model.accounts.isEmpty {
                    ContentUnavailableView("No Workspaces", systemImage: "building.2")
                }
            }
            HStack {
                Button("Add Workspace…") { signIn = model.signIn { _ in signIn = nil } }
                Button("Sign Out…") { signingOut = model.accounts.first { $0.id == selection } }
                    .disabled(selection == nil)
            }
        }
        .confirmationDialog(signOutTitle, isPresented: isSigningOut, presenting: signingOut) { account in
            Button("Sign Out", role: .destructive) { model.signOut(of: account) }
        } message: { _ in
            Text("Lax forgets this workspace's session. You can sign in again at any time.")
        }
        .sheet(item: $signIn) { controller in
            SignInView(controller: controller, cancel: { signIn = nil })
        }
    }

    private var signOutTitle: String {
        "Sign out of \(signingOut?.teamName ?? "the workspace")?"
    }

    private var isSigningOut: Binding<Bool> {
        Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } })
    }
}
