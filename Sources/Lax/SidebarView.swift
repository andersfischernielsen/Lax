import LaxKit
import SwiftUI

struct SidebarView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let workspace = model.currentWorkspace {
                ConversationList(workspace: workspace)
            } else {
                List {}
            }
        }
        .toolbar {
            ToolbarItem { workspaceMenu }
        }
        .safeAreaInset(edge: .bottom) {
            if let workspace = model.currentWorkspace { ConnectionStatusView(status: workspace.status) }
        }
    }

    private var workspaceMenu: some View {
        Menu {
            ForEach(model.accounts) { account in
                Toggle(account.teamName, isOn: Binding(
                    get: { model.selectedAccountID == account.id },
                    set: { if $0 { model.selectedAccountID = account.id } }
                ))
            }
            Divider()
            Button("Add Workspace…") { model.beginSignIn() }
            if let account = model.currentWorkspace?.account {
                Button("Sign Out of \(account.teamName)", role: .destructive) { model.signOut(of: account) }
            }
        } label: {
            Label(model.currentWorkspace?.account.teamName ?? "Workspaces", systemImage: "building.2")
                .labelStyle(.titleAndIcon)
        }
    }
}

private struct ConversationList: View {
    let workspace: WorkspaceModel

    var body: some View {
        List(selection: Binding(get: { workspace.selectedConversationID }, set: { workspace.select($0) })) {
            section("Channels", kinds: [.channel, .privateChannel])
            section("Direct Messages", kinds: [.directMessage, .groupDirectMessage])
        }
        .overlay {
            if workspace.conversations.isEmpty { ProgressView() }
        }
    }

    private func section(_ title: String, kinds: Set<SlackConversation.Kind>) -> some View {
        let items = workspace.conversations
            .filter { kinds.contains($0.kind) }
            .map { (conversation: $0, name: workspace.displayName(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Section(title) {
            ForEach(items, id: \.conversation.id) { item in
                let id = item.conversation.id
                let counts = workspace.unread[id]
                let isMuted = workspace.muted.contains(id)
                // Muted conversations only stand out when someone mentions the user.
                let isHighlighted = counts.hasUnreads && !isMuted
                Label {
                    HStack(spacing: 4) {
                        Text(item.name.trimmingPrefix("#")).lineLimit(1)
                        if isMuted { Image(systemName: "bell.slash").font(.caption2) }
                    }
                } icon: {
                    Image(systemName: icon(for: item.conversation.kind))
                }
                .fontWeight(isHighlighted ? .semibold : .regular)
                .foregroundStyle(isHighlighted ? AnyShapeStyle(.primary)
                                 : isMuted ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                .badge(counts.mentions)
                .contextMenu {
                    Button(isMuted ? "Unmute" : "Mute") { workspace.setMuted(!isMuted, id) }
                }
            }
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
