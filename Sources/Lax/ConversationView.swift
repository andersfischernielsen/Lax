import AppKit
import LaxKit
import SwiftUI

struct ConversationView: View {
    let workspace: WorkspaceModel
    let conversation: SlackConversation
    /// Scrolled to the newest message once; older pages load only after that.
    @State private var isPositioned = false
    @State private var isAtBottom = true
    /// The top message when older ones were asked for; kept in place when they arrive.
    @State private var pageAnchor: String?
    /// Messages at least half on screen right now.
    @State private var visibleRows: Set<String> = []
    @Environment(WindowModel.self) private var window

    var body: some View {
        @Bindable var window = window
        let timeline = workspace.timelines[conversation.id]
        let messages = timeline?.messages ?? []
        let firstUnread = workspace.unreadMarkers[conversation.id].flatMap {
            timeline?.firstUnreadTS(lastRead: $0, ownUserID: workspace.account.userID)
        }

        VStack(spacing: 0) {
            // A native list, like Mail's: the selected message's thread shows in the inspector.
            ScrollViewReader { proxy in
            List(selection: selectedMessage(messages)) {
                if isPositioned, timeline?.hasOlder ?? true {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                        // Scrolled into view: load the page before the first message.
                        .onAppear {
                            pageAnchor = timeline?.oldestTS
                            workspace.loadOlder(in: conversation.id)
                        }
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                }
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    let isFirstUnread = message.ts == firstUnread
                    let isNewDay = DayLabel.startsNewDay(message.date, after: index > 0 ? messages[index - 1].date : nil)
                    if isNewDay { DayDivider(date: message.date).messageListRow(selectable: false) }
                    if isFirstUnread { NewMessagesDivider().messageListRow(selectable: false).id(Self.newLineID) }
                    MessageItem(workspace: workspace, channel: conversation.id, message: message,
                                showsHeader: isNewDay || isFirstUnread || MessageItem.showsHeader(messages, at: index))
                        .messageListRow(selectable: true)
                        .tag(message.ts)
                        .id(message.ts)
                        // Read once at least half of it has been on screen, after the list has
                        // settled where it opens; rows passed on the way there don't count.
                        .onScrollVisibilityChange(threshold: 0.5) { visible in
                            if visible { visibleRows.insert(message.ts) } else { visibleRows.remove(message.ts) }
                            if visible, isPositioned { workspace.saw(message.ts, in: conversation.id) }
                        }
                }
            }
            .listStyle(.plain)
            // Edit ▸ Copy copies the selected message, as in Mail and Messages.
            .onCopyCommand {
                guard let message = messages.first(where: { $0.ts == window.selectedMessage }) else { return [] }
                return [NSItemProvider(object: workspace.plainText(of: message) as NSString)]
            }
            .overlay { if timeline == nil { ProgressView() } }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 60
            } action: { _, atBottom in
                isAtBottom = atBottom
            }
            // Older messages arrived above: keep the message that was on top where it was, so
            // the reading position holds and the spinner is out of view until scrolled to again.
            .onChange(of: timeline?.oldestTS) { _, oldest in
                guard let anchor = pageAnchor, oldest != anchor else { return }
                pageAnchor = nil
                proxy.scrollTo(anchor, anchor: .top)
            }
            // Open at the "New" line when there is one, as Slack does, else at the newest message.
            .onChange(of: timeline != nil && workspace.readPositionKnown.contains(conversation.id), initial: true) { _, ready in
                guard ready, !isPositioned else { return }
                if firstUnread != nil {
                    proxy.scrollTo(Self.newLineID, anchor: .top)
                } else if let newest = messages.last?.ts {
                    proxy.scrollTo(newest, anchor: .bottom)
                }
                Task {
                    // Let the scroll land before counting what's on screen.
                    try? await Task.sleep(for: .milliseconds(300))
                    isPositioned = true
                    if let newest = visibleRows.max(by: SlackTimestamp.isBefore) {
                        workspace.saw(newest, in: conversation.id)
                    }
                }
            }
            // Follow new messages while at the bottom, as chat apps do.
            .onChange(of: messages.last?.ts) { _, newest in
                guard let newest, isPositioned, isAtBottom else { return }
                proxy.scrollTo(newest, anchor: .bottom)
            }
            }

            ComposerView(placeholder: "Message \(workspace.displayName(of: conversation))", draft: draft) {
                TypingIndicator(workspace: workspace, channel: conversation.id)
            } send: {
                workspace.send(in: conversation.id)
            }
        }
        .navigationTitle(workspace.displayName(of: conversation))
        .navigationSubtitle(conversation.topic ?? "")
        .sheet(item: $window.reactingTo) { target in
            EmojiPickerView(customEmoji: workspace.customEmoji, emojiImage: { workspace.emojiImages[$0] },
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

    /// The message whose thread is in the inspector; one without replies shows there alone,
    /// ready for the first reply.
    private func selectedMessage(_ messages: [SlackMessage]) -> Binding<String?> {
        Binding(get: { window.selectedMessage },
                set: { ts in
                    window.selectedMessage = ts
                    guard let message = messages.first(where: { $0.ts == ts }) else { return }
                    window.openThread(message.threadTS ?? message.ts, in: conversation.id)
                })
    }

    private static let newLineID = "new-messages-line"

    private var editText: Binding<String> {
        Binding(get: { window.editing?.text ?? "" }, set: { window.editing?.text = $0 })
    }
}

private struct DayDivider: View {
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            VStack { Divider() }
            Text(DayLabel.text(for: date)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            VStack { Divider() }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("New messages")
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

extension View {
    /// A message list row: edge to edge, without separators; rows pad themselves.
    func messageListRow(selectable: Bool) -> some View {
        listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowSeparator(.hidden)
            .selectionDisabled(!selectable)
    }
}
