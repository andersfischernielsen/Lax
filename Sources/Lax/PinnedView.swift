import LaxKit
import SwiftUI

/// A conversation's pinned messages, for the toolbar popover.
struct PinnedView: View {
    let workspace: WorkspaceModel
    let channel: String

    var body: some View {
        let formatter = workspace.textFormatter()
        Group {
            if let messages = workspace.pinned[channel] {
                if messages.isEmpty {
                    ContentUnavailableView("No Pinned Messages", systemImage: "pin.slash")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(messages) { message in
                                MessageItem(workspace: workspace, channel: channel, message: message,
                                            formatter: formatter, showsHeader: true)
                                Divider().padding(.top, 10)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .frame(width: 440, height: 480)
        .task { workspace.loadPinned(in: channel) }
    }
}
