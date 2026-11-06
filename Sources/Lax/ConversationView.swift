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
    /// Messages at least half on screen right now. A plain box, not observed: rows come and go
    /// many times a second while scrolling, and that mustn't redraw the conversation.
    @State private var visibleRows = VisibleRows()
    @Environment(WindowModel.self) private var window

    var body: some View {
        @Bindable var window = window
        let timeline = workspace.timelines[conversation.id]
        let messages = timeline?.messages ?? []
        let lastRead = workspace.unreadMarkers[conversation.id]
        let firstUnread = lastRead.flatMap {
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
                    let isNewDay = DayLabel.startsNewDay(message.date, after: index > 0 ? messages[index - 1].date : nil)
                    let isUnread = lastRead.map { SlackTimestamp.isBefore($0, message.ts) } ?? false
                        && message.userID != workspace.account.userID
                    if isNewDay { DayDivider(date: message.date).messageListRow(selectable: false) }
                    MessageItem(workspace: workspace, channel: conversation.id, message: message,
                                showsHeader: isNewDay || MessageItem.showsHeader(messages, at: index))
                        // Unread: a red bar down the left edge, gone once it's been read.
                        .overlay(alignment: .leading) {
                            if isUnread { Rectangle().fill(.red).frame(width: 3).accessibilityHidden(true) }
                        }
                        .accessibilityValue(isUnread ? "Unread" : "")
                        .messageListRow(selectable: true)
                        .tag(message.ts)
                        .id(message.ts)
                        // Read once its bottom edge has been on screen, i.e. it's been read to the
                        // end; and only after the list has settled where it opens, so rows passed
                        // on the way there don't count.
                        // Compared on screen against the list's own frame: visibility callbacks
                        // judge the whole row, not where its bottom edge is.
                        .onGeometryChange(for: Bool.self) { [rows = visibleRows] proxy in
                            let bottom = proxy.frame(in: .global).maxY
                            return bottom > rows.listFrame.minY && bottom <= rows.listFrame.maxY
                        } action: { visible in
                            if visible { visibleRows.ids.insert(message.ts) } else { visibleRows.ids.remove(message.ts) }
                            if visible, isPositioned { workspace.saw(message.ts, in: conversation.id) }
                        }
                }
            }
            .listStyle(.plain)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { visibleRows.listFrame = $0 }
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
                // A search result being revealed positions the list itself.
                guard ready, !isPositioned, window.reveal?.channel != conversation.id else { return }
                // The last message already read at the top, so the "New" line and the first
                // unread message follow right below it.
                let target = firstUnread.map { ts -> (String, UnitPoint) in
                    let index = messages.firstIndex { $0.ts == ts } ?? 0
                    return (messages[max(index - 1, 0)].ts, .top)
                } ?? messages.last.map { ($0.ts, UnitPoint.bottom) }
                Task {
                    // Rows for a page that just arrived exist only after the next layout pass,
                    // and their heights settle as names and pictures load; scroll again as they
                    // do, so the list lands on the target rather than near it.
                    for delay in [0, 50, 150, 300] {
                        try? await Task.sleep(for: .milliseconds(delay))
                        if let (id, anchor) = target { proxy.scrollTo(id, anchor: anchor) }
                    }
                    // Let the scroll land before counting what's on screen.
                    try? await Task.sleep(for: .milliseconds(100))
                    isPositioned = true
                    if let newest = visibleRows.ids.max(by: SlackTimestamp.isBefore) {
                        workspace.saw(newest, in: conversation.id)
                    }
                }
            }
            // A search result: load back to it, then scroll to it and select it.
            .task(id: window.reveal) {
                guard let reveal = window.reveal, reveal.channel == conversation.id else { return }
                await workspace.loadThrough(reveal.ts, in: conversation.id)
                for delay in [0, 50, 150, 300] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    proxy.scrollTo(reveal.ts, anchor: .center)
                }
                // As if clicked: selected, with its thread in the inspector.
                window.openThread(reveal.ts, in: conversation.id)
                window.reveal = nil
                isPositioned = true
            }
            // Follow new messages while at the bottom, as chat apps do.
            .onChange(of: messages.last?.ts) { _, newest in
                guard let newest, isPositioned, isAtBottom else { return }
                proxy.scrollTo(newest, anchor: .bottom)
            }
            }

            ComposerView(placeholder: "Message \(workspace.displayName(of: conversation))", draft: draft,
                         suggest: { workspace.suggestions(for: $0) },
                         accept: { workspace.remember($0, inDraft: conversation.id) }) {
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

    private var draft: Binding<AttributedString> {
        Binding(get: { workspace.drafts[conversation.id] ?? AttributedString() },
                set: { text in
                    if !text.characters.isEmpty, text != workspace.drafts[conversation.id] {
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

extension View {
    /// A message list row: edge to edge, without separators; rows pad themselves.
    func messageListRow(selectable: Bool) -> some View {
        listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowSeparator(.hidden)
            .selectionDisabled(!selectable)
    }
}

/// Reference storage a view can change without redrawing. Written on the main actor only;
/// geometry callbacks, which SwiftUI also runs there, read it.
final class VisibleRows: @unchecked Sendable {
    var ids: Set<String> = []
    /// The message list's frame on screen, to tell which bottom edges are inside it.
    var listFrame = CGRect.zero
}
