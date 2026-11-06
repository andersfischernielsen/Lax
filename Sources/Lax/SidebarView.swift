import LaxKit
import SwiftUI

struct SidebarView: View {
    let model: AppModel
    let workspace: WorkspaceModel?
    @Environment(WindowModel.self) private var window
    @State private var signingOut: SlackAccount?

    var body: some View {
        Group {
            if let workspace {
                ConversationList(workspace: workspace)
            } else {
                List {}
            }
        }
        .toolbar {
            ToolbarItem { workspaceMenu }
        }
        .safeAreaInset(edge: .bottom) {
            if let workspace { ConnectionStatusView(status: workspace.status) }
        }
        .confirmationDialog("Sign out of \(signingOut?.teamName ?? "the workspace")?",
                            isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
                            presenting: signingOut) { account in
            Button("Sign Out", role: .destructive) { model.signOut(of: account) }
        } message: { _ in
            Text("Lax forgets this workspace's session. You can sign in again at any time.")
        }
    }

    private var workspaceMenu: some View {
        Menu {
            ForEach(model.accounts) { account in
                Toggle(account.teamName, isOn: Binding(
                    get: { workspace?.account.id == account.id },
                    set: { if $0 { window.accountID = account.id } }
                ))
            }
            Divider()
            Button("Add Workspace…") { window.beginSignIn(with: model) }
            if let workspace {
                Button("Set Display Name…") { window.editingDisplayName = workspace.ownDisplayName }
            }
            if let account = workspace?.account {
                Button("Sign Out of \(account.teamName)…", role: .destructive) { signingOut = account }
            }
        } label: {
            Label(workspace?.account.teamName ?? "Workspaces", systemImage: "building.2")
                .labelStyle(.titleAndIcon)
        }
    }
}

private struct ConversationList: View {
    let workspace: WorkspaceModel
    @Environment(WindowModel.self) private var window

    var body: some View {
        List(selection: Binding(get: { window.conversationID }, set: { window.select($0) })) {
            ForEach(workspace.sidebarSections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.items, id: \.conversation.id) { item in
                        ConversationRow(workspace: workspace, conversation: item.conversation, name: item.name)
                    }
                }
            }
        }
        .overlay {
            if workspace.conversations.isEmpty { ProgressView() }
        }
    }
}

/// One sidebar entry; reads its own unread and mute state, so a badge change redraws just it.
private struct ConversationRow: View {
    let workspace: WorkspaceModel
    let conversation: SlackConversation
    let name: String

    var body: some View {
        let id = conversation.id
        let counts = workspace.unread[id]
        let isMuted = workspace.muted.contains(id)
        // Muted conversations only stand out when someone mentions the user.
        let isHighlighted = counts.hasUnreads && !isMuted
        Label {
            HStack(spacing: 4) {
                Text(name.trimmingPrefix("#")).lineLimit(1)
                if isMuted { Image(systemName: "bell.slash").font(.caption2) }
            }
        } icon: {
            Image(systemName: icon(for: conversation.kind))
        }
        .fontWeight(isHighlighted ? .semibold : .regular)
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.primary)
                         : isMuted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
        .badge(counts.mentions)
        .contextMenu {
            Button(isMuted ? "Unmute" : "Mute") { workspace.setMuted(!isMuted, id) }
        }
    }

    private func icon(for kind: SlackConversation.Kind) -> String {
        switch kind {
        case .channel: "number"
        case .privateChannel: "lock"
        case .directMessage: "person"
        case .groupDirectMessage: "person.2"
        }
    }
}

private struct ConnectionStatusView: View {
    let status: RealTimeUpdate.Status

    var body: some View {
        if let text {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
    }

    private var text: String? {
        switch status {
        case .connected: nil
        case .connecting: "Connecting…"
        case .waiting(let delay): "Offline. Retrying in \(delay.components.seconds) s…"
        case .signedOut: "Slack ended this session. Sign in again from the workspace menu."
        }
    }
}
