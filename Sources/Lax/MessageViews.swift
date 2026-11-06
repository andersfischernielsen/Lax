import LaxKit
import SwiftUI

/// A message with everything under it: files, reactions, and the thread link.
struct MessageItem: View {
    let workspace: WorkspaceModel
    let channel: String
    let message: SlackMessage
    let formatter: SlackText
    let showsHeader: Bool
    /// False inside a thread, where the replies are already on screen.
    var showsThreadLink = true

    private static let systemSubtypes: Set<String> = [
        "channel_join", "channel_leave", "channel_topic", "channel_purpose", "channel_name",
    ]

    var body: some View {
        MessageRow(
            message: message,
            author: workspace.authorName(of: message),
            avatarURL: message.userID.flatMap { workspace.users[$0] }?.avatarURL,
            text: MessageStyle.styled(formatter.attributed(message.markup)),
            showsHeader: showsHeader,
            isSystem: message.subtype.map(Self.systemSubtypes.contains) ?? false
        ) {
            ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, attachment in
                AttachmentView(attachment: attachment, formatter: formatter)
            }
            if !message.files.isEmpty {
                FilesView(files: message.files, loadImage: workspace.image(at:))
            }
            if !message.reactions.isEmpty {
                ReactionsView(reactions: message.reactions, ownUserID: workspace.account.userID,
                              userName: workspace.userName) { name in
                    workspace.toggleReaction(name, on: message, in: channel)
                }
            }
            if showsThreadLink, message.replyCount > 0 {
                Button(message.replyCount == 1 ? "1 reply" : "\(message.replyCount) replies") {
                    workspace.openThread(message.ts, in: channel)
                }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
                .padding(.top, 2)
            }
        }
    }

    /// Consecutive messages from one author within five minutes share a header.
    static func showsHeader(_ messages: [SlackMessage], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = messages[index - 1], message = messages[index]
        return previous.userID != message.userID
            || previous.username != message.username
            || message.date.timeIntervalSince(previous.date) > 5 * 60
    }
}

struct MessageRow<Footer: View>: View {
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
                        if message.isEdited { Text("(edited)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Text(text)
                    .foregroundStyle(isSystem ? .secondary : .primary)
                    .textSelection(.enabled)
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, showsHeader ? 10 : 2)
    }
}

struct AvatarView: View {
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

/// The message field, with a line above it for who is typing.
struct ComposerView: View {
    let placeholder: String
    @Binding var draft: String
    /// Typing summary at a moment, e.g. "Jane is typing…".
    var typing: (Date) -> String? = { _ in nil }
    let send: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Re-evaluated every second so typing entries disappear when they expire.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(typing(context.date) ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .onSubmit(send)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}
