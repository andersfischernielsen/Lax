import AppKit
import LaxKit
import SwiftUI

struct ConversationView: View {
    let workspace: WorkspaceModel
    let conversation: SlackConversation
    @State private var showsPinned = false
    @Environment(WindowModel.self) private var window

    var body: some View {
        @Bindable var window = window
        let formatter = workspace.textFormatter()
        let timeline = workspace.timelines[conversation.id]
        let messages = timeline?.messages ?? []
        let firstUnread = workspace.unreadMarkers[conversation.id].flatMap {
            timeline?.firstUnreadTS(lastRead: $0, ownUserID: workspace.account.userID)
        }

        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if timeline?.hasOlder ?? true {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                            // Visible at the top: load the next page, and again each time one lands.
                            .task(id: timeline?.oldestTS) { workspace.loadOlder(in: conversation.id) }
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let isFirstUnread = message.ts == firstUnread
                        let isNewDay = DayLabel.startsNewDay(message.date, after: index > 0 ? messages[index - 1].date : nil)
                        if isNewDay { DayDivider(date: message.date) }
                        if isFirstUnread { NewMessagesDivider() }
                        MessageItem(workspace: workspace, channel: conversation.id, message: message,
                                    formatter: formatter,
                                    showsHeader: isNewDay || isFirstUnread || MessageItem.showsHeader(messages, at: index))
                    }
                }
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)

            ComposerView(placeholder: "Message \(workspace.displayName(of: conversation))", draft: draft,
                         typing: typingSummary) {
                workspace.send(in: conversation.id)
            }
        }
        .navigationTitle(workspace.displayName(of: conversation))
        .navigationSubtitle(conversation.topic ?? "")
        .toolbar {
            Button("Pinned Messages", systemImage: "pin") { showsPinned.toggle() }
                .help("Show pinned messages")
                .popover(isPresented: $showsPinned) {
                    PinnedView(workspace: workspace, channel: conversation.id)
                }
        }
        .sheet(item: $window.reactingTo) { target in
            EmojiPickerView(customEmoji: workspace.customEmoji, emojiImages: workspace.emojiImages,
                            requestImages: workspace.requestEmojiImages) { name in
                window.reactingTo = nil
                let alreadyMine = target.message.reactions.first { $0.name == name }?
                    .users.contains(workspace.account.userID) ?? false
                if !alreadyMine { workspace.toggleReaction(name, on: target.message, in: target.channel) }
            } cancel: {
                window.reactingTo = nil
            }
        }
        .sheet(item: $window.editing) { _ in
            EditMessageView(text: editText, save: {
                if let edit = window.editing { workspace.saveEdit(edit) }
                window.editing = nil
            }, cancel: { window.editing = nil })
        }
        .onAppear { workspace.show(conversation.id) }
        .onDisappear { workspace.hide(conversation.id) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            workspace.markReadIfVisible()
        }
    }

    private var draft: Binding<String> {
        Binding(get: { workspace.drafts[conversation.id] ?? "" },
                set: { text in
                    if !text.isEmpty, text != workspace.drafts[conversation.id] {
                        workspace.userTyped(in: conversation.id)
                    }
                    workspace.drafts[conversation.id] = text
                })
    }

    private var editText: Binding<String> {
        Binding(get: { window.editing?.text ?? "" }, set: { window.editing?.text = $0 })
    }

    private func typingSummary(at date: Date) -> String? {
        let names = workspace.typing.typingUserIDs(in: conversation.id, at: date)
            .map { workspace.userName($0) ?? "Someone" }
        return TypingTracker.summary(names)
    }
}

private struct DayDivider: View {
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.separator).frame(height: 1)
            Text(DayLabel.text(for: date)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Rectangle().fill(.separator).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
}

private struct NewMessagesDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.red).frame(height: 1)
            Text("New").font(.caption.weight(.semibold)).foregroundStyle(.red)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

