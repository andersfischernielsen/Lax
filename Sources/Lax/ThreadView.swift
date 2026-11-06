import LaxKit
import SwiftUI

/// A thread's parent and replies, with a composer for replying. Shown in the inspector.
struct ThreadView: View {
    let workspace: WorkspaceModel
    let thread: ThreadRef
    @Environment(WindowModel.self) private var window

    var body: some View {
        let messages = workspace.threads[thread]?.messages ?? []

        VStack(spacing: 0) {
            if messages.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            MessageItem(workspace: workspace, channel: thread.channel, message: message,
                                        showsHeader: index <= 1 || MessageItem.showsHeader(messages, at: index),
                                        showsThreadLink: false)
                            if index == 0, messages.count > 1 {
                                Text(messages.count == 2 ? "1 reply" : "\(messages.count - 1) replies")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 10)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
            }

            ComposerView(placeholder: "Reply…", draft: draft) {
                workspace.send(in: thread.channel, thread: thread.ts)
            }
        }
        .task { await workspace.loadThread(thread) }
        .onExitCommand { window.showsInspector = false }
    }

    private var draft: Binding<String> {
        Binding(get: { workspace.drafts[thread.draftKey] ?? "" },
                set: { text in
                    if !text.isEmpty, text != workspace.drafts[thread.draftKey] {
                        workspace.userTyped(in: thread.channel)
                    }
                    workspace.drafts[thread.draftKey] = text
                })
    }
}
