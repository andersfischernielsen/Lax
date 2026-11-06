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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        // Hidden or deleted files have no name; treat them as undecodable.
        let title = try c.decodeIfPresent(String.self, forKey: .title)
        name = try title ?? c.decode(String.self, forKey: .name)
        prettyType = try c.decodeIfPresent(String.self, forKey: .prettyType)
        url = try c.decodeIfPresent(String.self, forKey: .urlPrivate).flatMap(URL.init(string:))
        permalink = try c.decodeIfPresent(String.self, forKey: .permalink).flatMap(URL.init(string:))
        let isImage = try c.decodeIfPresent(String.self, forKey: .mimetype)?.hasPrefix("image/") ?? false
        preview = isImage ? try Self.preview(in: c) : nil
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
    }
}

/// Decodes to nil instead of failing the surrounding array.
struct Failable<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
