import LaxKit
import SwiftUI

/// A thread's parent and replies, with a composer for replying.
struct ThreadView: View {
    let workspace: WorkspaceModel
    let thread: ThreadRef

    var body: some View {
        let formatter = workspace.textFormatter()
        let messages = workspace.threads[thread]?.messages ?? []

        VStack(spacing: 0) {
            HStack {
                Text("Thread").font(.headline)
                Spacer()
                Button("Close Thread", systemImage: "xmark") { workspace.closeThread() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()

            if messages.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            MessageItem(workspace: workspace, channel: thread.channel, message: message,
                                        formatter: formatter,
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
    }

    private var draft: Binding<String> {
        Binding(get: { workspace.drafts[thread.draftKey] ?? "" },
                set: { workspace.drafts[thread.draftKey] = $0 })
    }
}
