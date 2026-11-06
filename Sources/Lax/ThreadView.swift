import AppKit
import LaxKit
import SwiftUI

/// A thread's parent and replies, with a composer for replying. Shown in the inspector.
struct ThreadView: View {
    let workspace: WorkspaceModel
    let thread: ThreadRef
    @State private var selectedMessage: String?

    var body: some View {
        let messages = workspace.threads[thread]?.messages ?? []

        VStack(spacing: 0) {
            if messages.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // A native list like the conversation's: arrows move through the replies,
                // ⌘C copies the selected one.
                ScrollViewReader { proxy in
                    List(selection: $selectedMessage) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            MessageItem(
                                workspace: workspace, channel: thread.channel, message: message,
                                showsHeader: index <= 1 || MessageItem.showsHeader(messages, at: index),
                                showsThreadLink: false
                            )
                            .messageListRow(selectable: true)
                            .tag(message.ts)
                            .id(message.ts)
                            if index == 0, messages.count > 1 {
                                Text(messages.count == 2 ? "1 reply" : "\(messages.count - 1) replies")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                    .messageListRow(selectable: false)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onCopyCommand {
                        guard let message = messages.first(where: { $0.ts == selectedMessage }) else { return [] }
                        return [NSItemProvider(object: workspace.plainText(of: message) as NSString)]
                    }
                    // Open at the newest reply, and follow new ones.
                    .onChange(of: messages.last?.ts, initial: true) { _, newest in
                        if let newest { proxy.scrollTo(newest, anchor: .bottom) }
                    }
                }
            }

            ComposerView(
                placeholder: "Reply…", identifier: "thread-composer", draft: draft,
                suggest: { workspace.suggestions(for: $0) },
                accept: { workspace.remember($0, inDraft: thread.draftKey) },
                uploads: uploads,
                isUploading: workspace.uploading[thread.draftKey] ?? false,
                status: { EmptyView() }
            ) {
                workspace.send(in: thread.channel, thread: thread.ts)
            }
        }
        .attachingDroppedFiles { workspace.attach($0, to: thread.draftKey) }
        .accessibilityIdentifier("thread-view")
        .task { await workspace.loadThread(thread) }
    }

    private var uploads: Binding<[Upload]> {
        Binding(get: { workspace.uploads[thread.draftKey] ?? [] }, set: { workspace.uploads[thread.draftKey] = $0 })
    }

    private var draft: Binding<AttributedString> {
        Binding(
            get: { workspace.drafts[thread.draftKey] ?? AttributedString() },
            set: { text in
                if !text.characters.isEmpty, text != workspace.drafts[thread.draftKey] {
                    workspace.userTyped(in: thread.channel)
                }
                workspace.drafts[thread.draftKey] = text
            })
    }
}
