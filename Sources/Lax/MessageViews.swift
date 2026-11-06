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
        let jumbomoji = message.files.isEmpty && message.attachments.isEmpty ? Jumbomoji.items(in: message.markup) : nil
        MessageRow(
            message: message,
            author: workspace.authorName(of: message),
            avatar: message.userID.flatMap { workspace.users[$0] }?.avatarURL
                .map { AvatarView(url: $0, workspace: workspace) },
            // Emoji-only messages show their emoji large instead, as in Slack.
            text: jumbomoji == nil ? RichText.text(text, emojiImage: emojiImage) : nil,
            animation: RichText.customEmojiNames(in: text).contains { workspace.emojiAnimations[$0] != nil }
                ? { workspace.emojiAnimations[$0] } : nil,
            showsHeader: showsHeader,
            isSystem: message.subtype.map(Self.systemSubtypes.contains) ?? false
        ) {
            if let jumbomoji {
                JumbomojiView(items: jumbomoji, emojiImage: emojiImage)
            }
            ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, attachment in
                AttachmentView(attachment: attachment, formatter: formatter, emojiImage: emojiImage)
            }
            if !message.files.isEmpty {
                FilesView(files: message.files, loadImage: workspace.image(at:), playerItem: workspace.playerItem(for:))
            }
            if !message.buttons.isEmpty {
                BotButtons(buttons: message.buttons) { workspace.press($0, on: message, in: channel) }
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
    /// The message body; nil when the footer shows it instead, as for jumbomoji.
    let text: Text?
    /// Frames for the animated emoji in `text`; nil when it has none, so it's drawn once.
    var animation: ((String) -> EmojiAnimation?)? = nil
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
                if let text {
                    if let animation {
                        // Redrawn as frames change; the text is laid out once.
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            text.textRenderer(AnimatedEmojiRenderer(
                                time: context.date.timeIntervalSinceReferenceDate, animation: animation))
                        }
                        .foregroundStyle(isSystem ? .secondary : .primary)
                    } else {
                        text.foregroundStyle(isSystem ? .secondary : .primary)
                    }
                }
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
/// Rich text: ⌘B bold, ⌘I italic, ⇧⌘X strikethrough, ⇧⌘C code, sent as Slack markup. Return
/// sends; Shift- or Option-Return starts a new line. With suggestions showing, ↑/↓ move
/// through them, Return or Tab takes one, and Esc hides them.
struct ComposerView<Status: View>: View {
    let placeholder: String
    var identifier = "composer"
    @Binding var draft: AttributedString
    /// Completions for the word being typed; none unless given.
    var suggest: (Autocomplete.Token) -> [Suggestion] = { _ in [] }
    /// Told about each completion taken, e.g. to send mentions as tokens.
    var accept: (Suggestion) -> Void = { _ in }
    @ViewBuilder var status: Status
    let send: () -> Void
    @State private var selection = AttributedTextSelection()
    @State private var highlighted = 0
    /// The word whose suggestions were dismissed with Esc.
    @State private var dismissed: Autocomplete.Token?

    var body: some View {
        let plain = String(draft.characters)
        // Completes the word at the end of the draft, where typing happens.
        let token = Autocomplete.token(in: plain)
        let suggestions = token.flatMap { $0 == dismissed ? nil : suggest($0) } ?? []
        VStack(alignment: .leading, spacing: 4) {
            status
            if !suggestions.isEmpty, let token {
                SuggestionList(suggestions: suggestions, highlighted: highlighted) { take($0, for: token) }
            }
            // The field is as tall as its text: one line to start, growing to six, then scrolling.
            // The hidden copy sets the height (TextEditor alone fills any space it's offered),
            // wrapping like the editor, which pads its lines by AppKit's standard 5 points.
            Text(plain.isEmpty ? " " : plain + " ")
                .lineLimit(1...6)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .overlay(alignment: .topLeading) {
                    if plain.isEmpty {
                        Text(placeholder).foregroundStyle(.placeholder).padding(.leading, 5).allowsHitTesting(false)
                    }
                }
                .overlay {
                    TextEditor(text: $draft, selection: $selection)
                        .textEditorStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .accessibilityIdentifier(identifier)
                        // Return sends; Shift- and Option-Return fall through to a new line.
                        .onKeyPress(keys: [.return]) { press in
                            guard press.modifiers.isDisjoint(with: [.shift, .option]) else { return .ignored }
                            if let token, suggestions.indices.contains(highlighted) {
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
                        .onKeyPress(keys: ["b", "i", "x", "c"]) { press in
                            guard let style = Self.style(for: press) else { return .ignored }
                            toggle(style)
                            return .handled
                        }
                }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .onChange(of: draft) { highlighted = 0 }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// ⌘B, ⌘I, ⇧⌘X and ⇧⌘C, as in Slack.
    private static func style(for press: KeyPress) -> InlinePresentationIntent? {
        switch (press.characters.lowercased(), press.modifiers) {
        case ("b", .command): .stronglyEmphasized
        case ("i", .command): .emphasized
        case ("x", [.command, .shift]): .strikethrough
        case ("c", [.command, .shift]): .code
        default: nil
        }
    }

    /// Turns a style on or off for the selection, or for what's typed next at the cursor.
    private func toggle(_ style: InlinePresentationIntent) {
        draft.transformAttributes(in: &selection) { attributes in
            var intent = attributes.inlinePresentationIntent ?? []
            if intent.contains(style) { intent.remove(style) } else { intent.insert(style) }
            attributes.inlinePresentationIntent = intent.isEmpty ? nil : intent
            // How it looks follows from what it means.
            attributes.font = Self.font(for: intent)
            attributes.strikethroughStyle = intent.contains(.strikethrough) ? .single : nil
        }
    }

    private static func font(for intent: InlinePresentationIntent) -> Font? {
        guard !intent.isEmpty else { return nil }
        var font = intent.contains(.code) ? Font.body.monospaced() : .body
        if intent.contains(.stronglyEmphasized) { font = font.bold() }
        if intent.contains(.emphasized) { font = font.italic() }
        return font
    }

    /// Replaces the word being typed, at the end of the draft, with the suggestion.
    private func take(_ suggestion: Suggestion, for token: Autocomplete.Token) {
        let start = draft.characters.index(draft.startIndex, offsetBy: min(token.start, draft.characters.count))
        draft.replaceSubrange(start..<draft.endIndex, with: AttributedString(suggestion.insert + " "))
        selection = AttributedTextSelection(insertionPoint: draft.endIndex)
        accept(suggestion)
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
    init(placeholder: String, identifier: String, draft: Binding<AttributedString>, send: @escaping () -> Void) {
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

/// A bot's buttons: standard buttons, prominent or red as the bot styles them.
private struct BotButtons: View {
    let buttons: [BlockButton]
    let press: (BlockButton) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(buttons, id: \.self) { button in
                let action = { if let url = button.url { openURL(url) } else { press(button) } }
                switch button.style {
                case .primary:
                    Button(button.text, action: action).buttonStyle(.borderedProminent)
                case .danger:
                    Button(button.text, role: .destructive, action: action).buttonStyle(.bordered).tint(.red)
                case nil:
                    Button(button.text, action: action).buttonStyle(.bordered)
                }
            }
        }
        .controlSize(.small)
        .padding(.top, 4)
    }
}

/// A message of only emoji, shown large; custom ones play if animated.
private struct JumbomojiView: View {
    static let size: CGFloat = 32
    let items: [Jumbomoji.Item]
    let emojiImage: (String) -> NSImage?

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .character(let character):
                    Text(character).font(.system(size: Self.size))
                case .shortcode(let name):
                    if let character = Emoji.character(for: name) {
                        Text(character).font(.system(size: Self.size))
                    } else if let image = emojiImage(name) {
                        EmojiImage(image: image, height: Self.size)
                    } else {
                        // Its place, until the image loads.
                        Color.clear.frame(width: Self.size, height: Self.size)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map { item -> String in
            switch item {
            case .character(let character): character
            case .shortcode(let name): name.replacing("_", with: " ")
            }
        }.joined(separator: ", "))
    }
}
