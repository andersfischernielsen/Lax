import LaxKit
import SwiftUI

/// Search results, newest first; clicking one opens its conversation.
struct SearchResultsView: View {
    let workspace: WorkspaceModel
    let results: [SearchResult]

    var body: some View {
        let formatter = workspace.textFormatter()
        if results.isEmpty {
            ContentUnavailableView.search(text: workspace.searchQuery)
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
                            MessageItem(workspace: workspace, channel: result.channelID, message: result.message,
                                        formatter: formatter, showsHeader: true, showsThreadLink: false)
                            Text(result.message.date, format: .dateTime.day().month().year())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 62)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { workspace.open(result) }
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
