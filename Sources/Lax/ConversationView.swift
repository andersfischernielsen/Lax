import AppKit
import LaxKit
import SwiftUI

struct ConversationView: View {
    let workspace: WorkspaceModel
    let conversation: SlackConversation

    /// Consecutive messages from one author within this window share a header.
    private static let groupingWindow: TimeInterval = 5 * 60
    private static let systemSubtypes: Set<String> = [
        "channel_join", "channel_leave", "channel_topic", "channel_purpose", "channel_name",
    ]

    var body: some View {
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
                        let author = message.userID.flatMap { workspace.users[$0] }
                        let isFirstUnread = message.ts == firstUnread
                        let isNewDay = DayLabel.startsNewDay(message.date, after: index > 0 ? messages[index - 1].date : nil)
                        if isNewDay { DayDivider(date: message.date) }
                        if isFirstUnread { NewMessagesDivider() }
                        MessageRow(
                            message: message,
                            author: workspace.authorName(of: message),
                            avatarURL: author?.avatarURL,
                            text: MessageStyle.styled(formatter.attributed(message.text)),
                            showsHeader: isNewDay || isFirstUnread || showsHeader(messages, at: index),
                            isSystem: message.subtype.map(Self.systemSubtypes.contains) ?? false
                        ) {
                            if !message.reactions.isEmpty {
                                ReactionsView(reactions: message.reactions, ownUserID: workspace.account.userID,
                                              userName: workspace.userName) { name in
                                    workspace.toggleReaction(name, on: message, in: conversation.id)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)

            ComposerView(workspace: workspace, conversation: conversation)
        }
        .navigationTitle(workspace.displayName(of: conversation))
        .navigationSubtitle(conversation.topic ?? "")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            workspace.markReadIfVisible()
        }
    }

    private func showsHeader(_ messages: [SlackMessage], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = messages[index - 1], message = messages[index]
        return previous.userID != message.userID
            || previous.username != message.username
            || message.date.timeIntervalSince(previous.date) > Self.groupingWindow
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

private struct MessageRow<Footer: View>: View {
    let message: SlackMessage
    let author: String
    let avatarURL: URL?
    let text: AttributedString
    let showsHeader: Bool
    let isSystem: Bool
    @ViewBuilder let footer: Footer

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsHeader {
                AvatarView(url: avatarURL)
            } else {
                Color.clear.frame(width: AvatarView.size, height: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                if showsHeader {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(author).fontWeight(.semibold)
                        Text(message.date, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(text)
                    .foregroundStyle(isSystem ? .secondary : .primary)
                    .textSelection(.enabled)
                footer
                if message.isEdited || message.replyCount > 0 {
                    HStack(spacing: 8) {
                        if message.replyCount > 0 {
                            Text(message.replyCount == 1 ? "1 reply" : "\(message.replyCount) replies")
                                .foregroundStyle(.tint)
                        }
                        if message.isEdited { Text("(edited)").foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, showsHeader ? 10 : 2)
    }
}

private struct AvatarView: View {
    static let size: CGFloat = 36
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ComposerView: View {
    let workspace: WorkspaceModel
    let conversation: SlackConversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Re-evaluated every second so typing entries disappear when they expire.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let names = workspace.typing.typingUserIDs(in: conversation.id, at: context.date)
                    .map { workspace.userName($0) ?? "Someone" }
                Text(TypingTracker.summary(names) ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Message \(workspace.displayName(of: conversation))", text: draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .onSubmit { workspace.send(in: conversation.id) }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var draft: Binding<String> {
        Binding(get: { workspace.drafts[conversation.id] ?? "" },
                set: { workspace.drafts[conversation.id] = $0 })
    }
}
