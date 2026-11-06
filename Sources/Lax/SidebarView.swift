import LaxKit
import SwiftUI

struct SidebarView: View {
    let model: AppModel
    let workspace: WorkspaceModel?
    @Environment(WindowModel.self) private var window
    @State private var signingOut: SlackAccount?

    var body: some View {
        @Bindable var window = window
        Group {
            if let workspace {
                switch window.area {
                case .home: ConversationList(workspace: workspace)
                case .directMessages: DirectMessageList(workspace: workspace)
                case .threads: FollowedThreadList(workspace: workspace)
                }
            } else {
                List {}
            }
        }
        // Switches what the sidebar lists, like Xcode's navigator bar.
        .safeAreaInset(edge: .top) {
            Picker("View", selection: $window.area) {
                ForEach(WindowModel.Area.allCases) { area in
                    Label(area.title, systemImage: area.systemImage).tag(area)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
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

/// Direct messages only, most recently active first.
private struct DirectMessageList: View {
    let workspace: WorkspaceModel
    @Environment(WindowModel.self) private var window

    var body: some View {
        List(selection: Binding(get: { window.conversationID }, set: { window.select($0) })) {
            ForEach(workspace.directMessagesByActivity, id: \.conversation.id) { item in
                ConversationRow(workspace: workspace, conversation: item.conversation, name: item.name)
            }
        }
        .overlay {
            if workspace.conversations.isEmpty { ProgressView() }
        }
    }
}

/// Threads the user follows, most recently active first; unread ones in bold.
private struct FollowedThreadList: View {
    let workspace: WorkspaceModel
    @Environment(WindowModel.self) private var window

    var body: some View {
        let threads = workspace.followedThreads ?? []
        List(selection: selection(threads)) {
            ForEach(threads) { thread in
                FollowedThreadRow(workspace: workspace, thread: thread)
                    .tag(ThreadRef(channel: thread.channelID, ts: thread.root.ts))
                    .onAppear { if thread.id == threads.last?.id { workspace.loadMoreFollowedThreads() } }
            }
        }
        .overlay {
            if workspace.followedThreads == nil {
                ProgressView()
            } else if threads.isEmpty {
                ContentUnavailableView("No Threads", systemImage: "text.bubble",
                                       description: Text("Threads you reply to or follow show up here."))
            }
        }
        .task { await workspace.loadFollowedThreads() }
    }

    /// Opening a thread marks it read.
    private func selection(_ threads: [ThreadSummary]) -> Binding<ThreadRef?> {
        Binding(get: { window.followedThread },
                set: { ref in
                    window.followedThread = ref
                    if let thread = threads.first(where: { $0.channelID == ref?.channel && $0.root.ts == ref?.ts }),
                       thread.unreadReplies > 0 {
                        workspace.markRead(thread)
                    }
                })
    }
}

private struct FollowedThreadRow: View {
    let workspace: WorkspaceModel
    let thread: ThreadSummary

    var body: some View {
        let isUnread = thread.unreadReplies > 0
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(workspace.conversation(thread.channelID).map(workspace.displayName(of:)) ?? "Conversation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let ts = thread.latestReplyTS, let seconds = Double(ts) {
                    Text(Date(timeIntervalSince1970: seconds), format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(workspace.authorName(of: thread.root)).fontWeight(isUnread ? .semibold : .regular)
            // One flowing preview: line breaks would leave blank lines in two lines of space.
            Text(workspace.plainText(of: thread.root).split(whereSeparator: \.isNewline).joined(separator: " "))
                .lineLimit(2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .badge(thread.unreadReplies)
        .accessibilityElement(children: .combine)
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
                if isMuted { Image(systemName: "bell.slash").font(.caption2).accessibilityLabel("Muted") }
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
