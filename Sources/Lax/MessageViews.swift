import AppKit
import LaxKit
import SwiftUI

/// A message with everything under it: files, reactions, and the thread link.
struct MessageItem: View {
    let workspace: WorkspaceModel
    let channel: String
    let message: SlackMessage
    let showsHeader: Bool
    /// False inside a thread, where the replies are already on screen.
    var showsThreadLink = true
    @State private var confirmingDelete = false
    @Environment(WindowModel.self) private var window

    /// Offered under "Add Reaction" in the message menu.
    private static let quickReactions = ["+1", "heart", "joy", "tada", "eyes", "pray", "white_check_mark", "raised_hands"]

    private static let systemSubtypes: Set<String> = [
        "channel_join", "channel_leave", "channel_topic", "channel_purpose", "channel_name",
    ]

    var body: some View {
        // Built here rather than passed in: the row's inputs stay comparable, so SwiftUI
        // skips rows that haven't changed.
        let formatter = workspace.textFormatter()
        let text = workspace.formattedText(message.markup)
        let emojiImage = { (name: String) in workspace.emojiImages[name] }
        MessageRow(
            message: message,
            author: workspace.authorName(of: message),
            avatar: message.userID.flatMap { workspace.users[$0] }?.avatarURL
                .map { AvatarView(url: $0, workspace: workspace) },
            text: RichText.text(text, emojiImage: emojiImage),
            showsHeader: showsHeader,
            isSystem: message.subtype.map(Self.systemSubtypes.contains) ?? false
        ) {
            ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, attachment in
                AttachmentView(attachment: attachment, formatter: formatter, emojiImage: emojiImage)
            }
            if !message.files.isEmpty {
                FilesView(files: message.files, loadImage: workspace.image(at:), playerItem: workspace.playerItem(for:))
            }
            if !message.reactions.isEmpty {
                ReactionsView(reactions: message.reactions, ownUserID: workspace.account.userID,
                              userName: workspace.userName, emojiImage: emojiImage) { name in
                    workspace.toggleReaction(name, on: message, in: channel)
                }
            }
            if showsThreadLink, message.replyCount > 0 {
                Button(message.replyCount == 1 ? "1 reply" : "\(message.replyCount) replies") {
                    window.openThread(message.ts, in: channel)
                }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
                .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("message-\(message.ts)")
        .contextMenu { menu }
        .confirmationDialog("Delete this message?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { workspace.delete(message, in: channel) }
        } message: {
            Text("It's removed for everyone in the conversation.")
        }
        .onAppear { workspace.requestEmojiImages(customEmojiNames(in: text, formatter: formatter)) }
    }

    @ViewBuilder private var menu: some View {
        Button("Reply in Thread") { window.openThread(message.threadTS ?? message.ts, in: channel) }
        Menu("Add Reaction") {
            ForEach(Self.quickReactions, id: \.self) { name in
                let isMine = message.reactions.first { $0.name == name }?.users.contains(workspace.account.userID) ?? false
                Toggle("\(Emoji.character(for: name) ?? "")  :\(name):", isOn: Binding(
                    get: { isMine },
                    set: { _ in workspace.toggleReaction(name, on: message, in: channel) }
                ))
            }
            Divider()
            Button("More…") { window.reactingTo = ReactionTarget(channel: channel, message: message) }
        }
        Divider()
        // In the conversation only: thread replies have their own read state.
        if showsThreadLink, message.isChannelLevel {
            Button("Mark as Unread") { workspace.markUnread(from: message.ts, in: channel) }
            Divider()
        }
        Button("Copy Text") { workspace.copyText(of: message) }
        Button("Copy Link") { workspace.copyLink(to: message, in: channel) }
        if message.userID == workspace.account.userID {
            Divider()
            Button("Edit…") { window.editing = MessageEdit(message, in: channel) }
            Button("Delete…", role: .destructive) { confirmingDelete = true }
        }
    }

    /// Custom emoji in the message, its attachments and its reactions.
    private func customEmojiNames(in text: AttributedString, formatter: SlackText) -> Set<String> {
        let attachmentTexts = message.attachments.flatMap { [$0.pretext, $0.body].compactMap { $0 } }
        return attachmentTexts.reduce(into: RichText.customEmojiNames(in: text)) { names, markup in
            names.formUnion(RichText.customEmojiNames(in: formatter.attributed(markup)))
        }.union(message.reactions.map(\.name).filter { Emoji.character(for: $0) == nil })
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
    let avatar: AvatarView?
    let text: Text
    let showsHeader: Bool
    let isSystem: Bool
    @ViewBuilder let footer: Footer

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if showsHeader {
                    if let avatar { avatar } else { AvatarView.placeholder }
                } else {
                    Color.clear.frame(width: AvatarView.size, height: 1)
                }
            }
            // The name is read out with the message; the picture adds nothing.
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if showsHeader {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(author).fontWeight(.semibold)
                        Text(message.date, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if message.isEdited { Text("(edited)").font(.caption).foregroundStyle(.secondary) }
                    }
                    .accessibilityElement(children: .combine)
                }
                // Not selectable: selectable text brings its own right-click menu, which would
                // hide the message menu. ⌘C copies the selected message instead.
                text
                    .foregroundStyle(isSystem ? .secondary : .primary)
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .padding(.top, showsHeader ? 6 : 0)
    }
}

/// A profile picture, downloaded once per session and kept in memory.
struct AvatarView: View {
    static let size: CGFloat = 36
    static var placeholder: some View {
        RoundedRectangle(cornerRadius: 8).fill(.quaternary).frame(width: size, height: size)
    }

    let url: URL
    let workspace: WorkspaceModel
    @State private var loaded: (url: URL, image: NSImage)?

    var body: some View {
        // From the cache straight away when it's there, so reused rows don't flash.
        if let image = loaded.flatMap({ $0.url == url ? $0.image : nil }) ?? workspace.cachedImage(at: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: Self.size, height: Self.size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Self.placeholder.task(id: url) {
                if let image = await workspace.image(at: url) { loaded = (url, image) }
            }
        }
    }
}

/// The message field, with a status line above it such as who is typing, and suggestions
/// for the `@`, `#` or `:` word being typed.
///
/// Return sends; Shift- or Option-Return starts a new line. With suggestions showing, ↑/↓
/// move through them, Return or Tab takes one, and Esc hides them.
struct ComposerView<Status: View>: View {
    let placeholder: String
    var identifier = "composer"
    @Binding var draft: String
    /// Completions for the word being typed; none unless given.
    var suggest: (Autocomplete.Token) -> [Suggestion] = { _ in [] }
    /// Told about each completion taken, e.g. to send mentions as tokens.
    var accept: (Suggestion) -> Void = { _ in }
    @ViewBuilder var status: Status
    let send: () -> Void
    @State private var selection: TextSelection?
    @State private var highlighted = 0
    /// The word whose suggestions were dismissed with Esc.
    @State private var dismissed: Autocomplete.Token?

    var body: some View {
        let token = Autocomplete.token(in: String(draft[..<cursor]))
        let suggestions = token.flatMap { $0 == dismissed ? nil : suggest($0) } ?? []
        VStack(alignment: .leading, spacing: 4) {
            status
            if !suggestions.isEmpty, let token {
                SuggestionList(suggestions: suggestions, highlighted: highlighted) { take($0, for: token) }
            }
            TextField(placeholder, text: $draft, selection: $selection, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .onKeyPress(keys: [.return]) { press in
                    if !press.modifiers.isDisjoint(with: [.shift, .option]) {
                        insert("\n")
                    } else if let token, suggestions.indices.contains(highlighted) {
                        take(suggestions[highlighted], for: token)
                    } else {
                        send()
                    }
                    return .handled
                }
                .onKeyPress(.tab) {
                    guard let token, suggestions.indices.contains(highlighted) else { return .ignored }
                    take(suggestions[highlighted], for: token)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    highlighted = min(highlighted + 1, suggestions.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    guard !suggestions.isEmpty else { return .ignored }
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onKeyPress(.escape) {
                    guard !suggestions.isEmpty else { return .ignored }
                    dismissed = token
                    return .handled
                }
                .onChange(of: draft) { highlighted = 0 }
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// Where the cursor is; the end of the draft when that's unknown.
    private var cursor: String.Index {
        guard case .selection(let range) = selection?.indices,
              range.upperBound >= draft.startIndex, range.upperBound <= draft.endIndex else { return draft.endIndex }
        return range.upperBound
    }

    private func take(_ suggestion: Suggestion, for token: Autocomplete.Token) {
        let before = Autocomplete.completing(String(draft[..<cursor]), token: token, with: suggestion.insert)
        draft = before + draft[cursor...]
        selection = TextSelection(insertionPoint: draft.index(draft.startIndex, offsetBy: before.count))
        accept(suggestion)
    }

    /// Puts `text` in place of the selection, leaving the cursor after it.
    private func insert(_ text: String) {
        let range: Range<String.Index> = if case .selection(let range) = selection?.indices,
            range.lowerBound >= draft.startIndex, range.upperBound <= draft.endIndex { range } else { draft.endIndex..<draft.endIndex }
        let offset = draft.distance(from: draft.startIndex, to: range.lowerBound) + text.count
        draft.replaceSubrange(range, with: text)
        selection = TextSelection(insertionPoint: draft.index(draft.startIndex, offsetBy: offset))
    }
}

/// Suggestions above the composer; the highlighted one is taken with Return or Tab.
private struct SuggestionList: View {
    let suggestions: [Suggestion]
    let highlighted: Int
    let take: (Suggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button { take(suggestion) } label: {
                    HStack {
                        Text(suggestion.title).fontWeight(.medium)
                        if let detail = suggestion.detail { Text(detail).foregroundStyle(.secondary) }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background(index == highlighted ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("suggestion-\(suggestion.id)")
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

extension ComposerView where Status == EmptyView {
    init(placeholder: String, identifier: String, draft: Binding<String>, send: @escaping () -> Void) {
        self.init(placeholder: placeholder, identifier: identifier, draft: draft, status: { EmptyView() }, send: send)
    }
}

/// "Jane is typing…" under a conversation, redrawn only when someone starts or stops.
struct TypingIndicator: View {
    let workspace: WorkspaceModel
    let channel: String

    var body: some View {
        let tracker = workspace.typing[channel] ?? TypingTracker()
        TimelineView(.explicit(tracker.expiryDates(in: channel))) { context in
            let names = tracker.typingUserIDs(in: channel, at: context.date).map { workspace.userName($0) ?? "Someone" }
            Text(TypingTracker.summary(names) ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
