import LaxKit
import SwiftUI

/// Go ▸ Open Quickly… (⌘K): type part of a name, then Return. Shaped like Xcode's Open Quickly.
struct QuickSwitcherView: View {
    let workspace: WorkspaceModel
    let open: (SlackConversation.ID) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var highlighted: SlackConversation.ID?

    var body: some View {
        let ids = matches
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                CommandField(placeholder: "Go to a channel or person", text: $query,
                             move: { move($0, in: ids) },
                             submit: { if let id = highlighted ?? ids.first { open(id) } },
                             cancel: close)
            }
            .padding(12)
            // Just the field until something is typed, like Spotlight.
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyView()
            } else if ids.isEmpty {
                Divider()
                Text("No Matches").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(20)
            } else {
                Divider()
                ScrollViewReader { proxy in
                    List(ids, id: \.self, selection: $highlighted) { id in
                        if let conversation = workspace.conversation(id) {
                            row(conversation).id(id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contextMenu(forSelectionType: SlackConversation.ID.self, menu: { _ in }) { selected in
                        if let id = selected.first { open(id) }
                    }
                    .onChange(of: highlighted) { _, id in if let id { proxy.scrollTo(id) } }
                }
                .frame(height: 300)
            }
        }
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(radius: 24, y: 8)
        .onExitCommand(perform: close)
        // The best match is highlighted, so Return opens it.
        .onChange(of: query) { highlighted = matches.first }
    }

    private var matches: [String] {
        query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : QuickSwitcher.rank(candidates, query: query)
    }

    private var candidates: [QuickSwitcher.Candidate] {
        workspace.conversations.map {
            QuickSwitcher.Candidate(id: $0.id, name: workspace.displayName(of: $0), isUnread: workspace.isUnread($0.id))
        }
    }

    private func row(_ conversation: SlackConversation) -> some View {
        let mentions = workspace.unread[conversation.id].mentions
        return Label {
            HStack {
                Text(workspace.displayName(of: conversation).trimmingPrefix("#"))
                    .fontWeight(workspace.isUnread(conversation.id) ? .semibold : .regular)
                Spacer(minLength: 4)
                UnreadBadge(count: mentions)
            }
        } icon: {
            Image(systemName: conversation.kind.systemImage)
        }
        .padding(.vertical, 2)
    }

    private func move(_ offset: Int, in ids: [String]) {
        highlighted = ConversationNavigation.step(from: highlighted, in: ids, by: offset)
    }
}
