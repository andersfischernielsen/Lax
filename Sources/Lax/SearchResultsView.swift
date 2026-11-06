import LaxKit
import SwiftUI

/// Search results, newest first; clicking one opens its conversation.
struct SearchResultsView: View {
    let workspace: WorkspaceModel
    let results: [SearchResult]
    @Environment(WindowModel.self) private var window

    var body: some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: window.searchQuery)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(place(of: result))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                            MessageItem(
                                workspace: workspace, channel: result.channelID, message: result.message,
                                showsHeader: true, showsThreadLink: false)
                            Text(result.message.date, format: .dateTime.day().month().year())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 62)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { window.open(result, conversation: workspace.conversation(result.channelID)) }
                        Divider().padding(.top, 8)
                    }
                }
            }
            .navigationTitle("Search")
            .navigationSubtitle("\(results.count) results")
        }
    }

    private func place(of result: SearchResult) -> String {
        if let name = result.channelName { return "#" + name }
        return workspace.conversations.first { $0.id == result.channelID }
            .map(workspace.displayName(of:)) ?? "Direct message"
    }
}
