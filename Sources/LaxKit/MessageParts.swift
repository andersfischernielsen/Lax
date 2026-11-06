import Foundation

public struct SlackReaction: Decodable, Hashable, Sendable {
    /// Emoji shortcode name, e.g. `tada` or `+1::skin-tone-2`.
    public let name: String
    /// Who reacted; Slack may send fewer IDs than `count` on popular reactions.
    public let users: [String]
    public let count: Int

    public init(name: String, users: [String], count: Int) {
        self.name = name
        self.users = users
        self.count = count
    }

    /// `reactions` after `user` adds or removes `name`. Repeats change nothing, so the
    /// server echoing our own reaction back is harmless.
    public static func applying(_ name: String, by user: String, added: Bool,
                                to reactions: [SlackReaction]) -> [SlackReaction] {
        guard let index = reactions.firstIndex(where: { $0.name == name }) else {
            return added ? reactions + [SlackReaction(name: name, users: [user], count: 1)] : reactions
        }
        let reaction = reactions[index]
        guard added != reaction.users.contains(user) else { return reactions }
        var result = reactions
        if added {
            result[index] = SlackReaction(name: name, users: reaction.users + [user], count: reaction.count + 1)
        } else if reaction.count > 1 {
            result[index] = SlackReaction(name: name, users: reaction.users.filter { $0 != user },
                                          count: reaction.count - 1)
        } else {
            result.remove(at: index)
        }
        return result
    }
}

extension SlackMessage {
    public func reacting(_ name: String, by user: String, added: Bool) -> SlackMessage {
        var copy = self
        copy.reactions = SlackReaction.applying(name, by: user, added: added, to: reactions)
        return copy
    }
}

public struct SlackFile: Decodable, Hashable, Identifiable, Sendable {
    /// A thumbnail to show inline.
    public struct Preview: Hashable, Sendable {
        public let url: URL
        public let width: Int
        public let height: Int
        /// A GIF that should play, not a still thumbnail.
        public var isAnimated = false

        /// Display size within a box, keeping the aspect ratio and never enlarging.
        public func fitted(maxWidth: Double, maxHeight: Double) -> (width: Double, height: Double) {
            guard width > 0, height > 0 else { return (0, 0) }
            let scale = min(1, maxWidth / Double(width), maxHeight / Double(height))
            return ((Double(width) * scale).rounded(), (Double(height) * scale).rounded())
        }
    }

    public let id: String
    public let name: String
    public let prettyType: String?
    /// Needs the session cookie to download.
    public let url: URL?
    /// Opens the file in Slack.
    public let permalink: URL?
    /// Present for images that have a usable thumbnail.
    public let preview: Preview?
    /// Present for videos: what to play, and a still to show until it does.
    public let video: Video?

    public struct Video: Hashable, Sendable {
        /// Needs the session cookie, like any Slack-hosted file.
        public let url: URL
        public let poster: Preview?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        // Hidden or deleted files have no name; treat them as undecodable.
        let title = try c.decodeIfPresent(String.self, forKey: .title)
        name = try title ?? c.decode(String.self, forKey: .name)
        prettyType = try c.decodeIfPresent(String.self, forKey: .prettyType)
        url = try c.decodeIfPresent(String.self, forKey: .urlPrivate).flatMap(URL.init(string:))
        permalink = try c.decodeIfPresent(String.self, forKey: .permalink).flatMap(URL.init(string:))
        let mimetype = try c.decodeIfPresent(String.self, forKey: .mimetype) ?? ""
        preview = mimetype == "image/gif" ? try Self.animatedPreview(in: c) ?? Self.preview(in: c)
            : mimetype.hasPrefix("image/") ? try Self.preview(in: c) : nil
        video = mimetype.hasPrefix("video/") ? try Self.video(in: c) : nil
    }

    /// The animated thumbnail, else the GIF itself, at its original size.
    private static func animatedPreview(in c: KeyedDecodingContainer<Keys>) throws -> Preview? {
        let urls = try [Keys.thumb480Gif, .thumb360Gif, .urlPrivate].lazy
            .compactMap { try c.decodeIfPresent(String.self, forKey: $0).flatMap(URL.init(string:)) }
        guard let url = urls.first,
              let width = try c.decodeIfPresent(Int.self, forKey: .originalW),
              let height = try c.decodeIfPresent(Int.self, forKey: .originalH) else { return nil }
        return Preview(url: url, width: width, height: height, isAnimated: true)
    }

    private static func video(in c: KeyedDecodingContainer<Keys>) throws -> Video? {
        guard let url = try (c.decodeIfPresent(String.self, forKey: .mp4) ?? c.decodeIfPresent(String.self, forKey: .urlPrivate))
            .flatMap(URL.init(string:)) else { return nil }
        let poster: Preview? = if let thumb = try c.decodeIfPresent(String.self, forKey: .thumbVideo).flatMap(URL.init(string:)),
                                  let width = try c.decodeIfPresent(Int.self, forKey: .thumbVideoW),
                                  let height = try c.decodeIfPresent(Int.self, forKey: .thumbVideoH) {
            Preview(url: thumb, width: width, height: height)
        } else { nil }
        return Video(url: url, poster: poster)
    }

    /// The 720px thumbnail, else the 360px one.
    private static func preview(in c: KeyedDecodingContainer<Keys>) throws -> Preview? {
        for (urlKey, widthKey, heightKey) in [(Keys.thumb720, Keys.thumb720W, Keys.thumb720H),
                                              (.thumb360, .thumb360W, .thumb360H)] {
            if let url = try c.decodeIfPresent(String.self, forKey: urlKey).flatMap(URL.init(string:)),
               let width = try c.decodeIfPresent(Int.self, forKey: widthKey),
               let height = try c.decodeIfPresent(Int.self, forKey: heightKey) {
                return Preview(url: url, width: width, height: height)
            }
        }
        return nil
    }

    private enum Keys: String, CodingKey {
        case id, name, title, mimetype, permalink
        case prettyType = "pretty_type"
        case urlPrivate = "url_private"
        case thumb720 = "thumb_720", thumb720W = "thumb_720_w", thumb720H = "thumb_720_h"
        case thumb360 = "thumb_360", thumb360W = "thumb_360_w", thumb360H = "thumb_360_h"
        case thumb480Gif = "thumb_480_gif", thumb360Gif = "thumb_360_gif"
        case originalW = "original_w", originalH = "original_h"
        case mp4
        case thumbVideo = "thumb_video", thumbVideoW = "thumb_video_w", thumbVideoH = "thumb_video_h"
    }
}

/// Decodes to nil instead of failing the surrounding array.
struct Failable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// A legacy message attachment: the boxes with a coloured bar that bots and link previews use.
public struct SlackAttachment: Decodable, Hashable, Sendable {
    public struct Field: Decodable, Hashable, Sendable {
        public let title: String
        public let value: String
        /// Fits beside another short field.
        public let isShort: Bool

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
            isShort = try c.decodeIfPresent(Bool.self, forKey: .short) ?? false
        }

        private enum Keys: String, CodingKey { case title, value, short }
    }

    /// Colour components in 0…1.
    public struct Color: Hashable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        /// `#RRGGBB`, `RRGGBB`, or Slack's names `good`, `warning`, `danger`.
        init?(_ value: String) {
            let named = ["good": "2EB67D", "warning": "ECB22E", "danger": "E01E5A"]
            let hex = named[value] ?? String(value.trimmingPrefix("#"))
            guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
            red = Double(rgb >> 16 & 0xFF) / 255
            green = Double(rgb >> 8 & 0xFF) / 255
            blue = Double(rgb & 0xFF) / 255
        }
    }

    public let color: Color?
    public let pretext: String?
    public let authorName: String?
    public let title: String?
    public let titleLink: URL?
    /// Body markup: the text, else the attachment's blocks, else its plain fallback.
    public let body: String?
    public let fields: [Field]
    public let footer: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        color = try c.decodeIfPresent(String.self, forKey: .color).flatMap(Color.init)
        pretext = try c.decodeIfPresent(String.self, forKey: .pretext)?.nilIfEmpty
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName)?.nilIfEmpty
        title = try c.decodeIfPresent(String.self, forKey: .title)?.nilIfEmpty
        titleLink = try c.decodeIfPresent(String.self, forKey: .titleLink).flatMap(URL.init(string:))
        fields = try c.decodeIfPresent([Failable<Field>].self, forKey: .fields)?.compactMap(\.value) ?? []
        footer = try c.decodeIfPresent(String.self, forKey: .footer)?.nilIfEmpty
        let text = try c.decodeIfPresent(String.self, forKey: .text)?.nilIfEmpty
        let blocks = try c.decodeIfPresent([JSONValue].self, forKey: .blocks).map(BlockKit.markup)?.nilIfEmpty
        let fallback = try c.decodeIfPresent(String.self, forKey: .fallback)?.nilIfEmpty
        // The fallback repeats the rest in plain text; show it only when there is nothing else.
        let hasOtherContent = pretext != nil || title != nil || !fields.isEmpty
        body = text ?? blocks ?? (hasOtherContent ? nil : fallback)
    }

    private enum Keys: String, CodingKey {
        case color, pretext, title, text, fields, footer, fallback, blocks
        case authorName = "author_name"
        case titleLink = "title_link"
    }
}
