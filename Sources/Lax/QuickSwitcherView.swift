import LaxKit
import SwiftUI

/// Go ▸ Open Quickly… (⌘K): type part of a name, then Return. Shaped like Xcode's Open Quickly.
struct QuickSwitcherView: View {
    let workspace: WorkspaceModel
    let open: (SlackConversation.ID) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var highlighted: SlackConversation.ID?
    @FocusState private var isFocused: Bool

    var body: some View {
        let ids = matches
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Go to a channel or person", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    // The cursor stays in the field; arrows move the highlight in the list.
                    .onKeyPress(.downArrow) { move(1, in: ids); return .handled }
                    .onKeyPress(.upArrow) { move(-1, in: ids); return .handled }
                    .onSubmit { if let id = highlighted ?? ids.first { open(id) } }
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
        .onAppear { isFocused = true }
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
            Text(workspace.displayName(of: conversation).trimmingPrefix("#"))
                .fontWeight(workspace.isUnread(conversation.id) ? .semibold : .regular)
        } icon: {
            Image(systemName: conversation.kind.systemImage)
        }
        .badge(mentions)
        .padding(.vertical, 2)
    }

    private func move(_ offset: Int, in ids: [String]) {
        highlighted = ConversationNavigation.step(from: highlighted, in: ids, by: offset)
    }
}
