import Foundation

public struct SlackConversation: Decodable, Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        case channel
        case privateChannel
        case directMessage
        case groupDirectMessage
    }

    public let id: String
    public let name: String?
    public let kind: Kind
    public let isArchived: Bool
    /// The other person in a direct message.
    public let userID: String?
    public let topic: String?

    public init(id: String, name: String?, kind: Kind, isArchived: Bool = false,
                userID: String? = nil, topic: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isArchived = isArchived
        self.userID = userID
        self.topic = topic
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        userID = try c.decodeIfPresent(String.self, forKey: .user)
        topic = try c.decodeIfPresent(Topic.self, forKey: .topic)?.value.nilIfEmpty
        if try c.decodeIfPresent(Bool.self, forKey: .isIM) == true {
            kind = .directMessage
        } else if try c.decodeIfPresent(Bool.self, forKey: .isMPIM) == true {
            kind = .groupDirectMessage
        } else if try c.decodeIfPresent(Bool.self, forKey: .isPrivate) == true
                    || c.decodeIfPresent(Bool.self, forKey: .isGroup) == true {
            kind = .privateChannel
        } else {
            kind = .channel
        }
    }

    /// Sidebar name: `#general`, the other person for a DM, the other members of a group DM
    /// (by name when `members` is known, else the handles in Slack's `mpdm-…` name).
    public func displayName(userName: (String) -> String?, members: [String]? = nil,
                            ownUserID: String? = nil) -> String {
        switch kind {
        case .channel, .privateChannel:
            return "#" + (name ?? id)
        case .directMessage:
            return userID.flatMap(userName) ?? userID ?? id
        case .groupDirectMessage:
            if let others = members?.filter({ $0 != ownUserID }), !others.isEmpty {
                let names = others.compactMap(userName)
                if names.count == others.count {
                    return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.joined(separator: ", ")
                }
            }
            // Slack names these `mpdm-alice--bob--carol-1`.
            guard let name, let members = name.wholeMatch(of: /mpdm-(.+)-\d+/)?.1 else { return name ?? id }
            return members.split(separator: "--").joined(separator: ", ")
        }
    }

    private enum Keys: String, CodingKey {
        case id, name, user, topic
        case isArchived = "is_archived"
        case isIM = "is_im"
        case isMPIM = "is_mpim"
        case isPrivate = "is_private"
        case isGroup = "is_group"
    }

    private struct Topic: Decodable {
        let value: String
    }
}

public struct SlackMessage: Decodable, Hashable, Identifiable, Sendable {
    /// Slack's message ID: seconds since 1970 with a microsecond fraction, as a string.
    public let ts: String
    public let userID: String?
    public let botID: String?
    /// Display name sent with bot and integration messages.
    public let username: String?
    public let text: String
    public let subtype: String?
    public let threadTS: String?
    public let replyCount: Int
    public let isEdited: Bool
    public internal(set) var reactions: [SlackReaction]
    public let files: [SlackFile]
    public let attachments: [SlackAttachment]
    /// What to show as the message body: `text`, or its blocks when they say more.
    public let markup: String

    public var id: String { ts }
    public var date: Date { Date(timeIntervalSince1970: Double(ts) ?? 0) }

    public init(ts: String, userID: String?, text: String, botID: String? = nil, username: String? = nil,
                subtype: String? = nil, threadTS: String? = nil, replyCount: Int = 0, isEdited: Bool = false,
                reactions: [SlackReaction] = [], files: [SlackFile] = [], attachments: [SlackAttachment] = []) {
        self.ts = ts
        self.userID = userID
        self.botID = botID
        self.username = username
        self.text = text
        self.subtype = subtype
        self.threadTS = threadTS
        self.replyCount = replyCount
        self.isEdited = isEdited
        self.reactions = reactions
        self.files = files
        self.attachments = attachments
        markup = text
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        ts = try c.decode(String.self, forKey: .ts)
        userID = try c.decodeIfPresent(String.self, forKey: .user)
        botID = try c.decodeIfPresent(String.self, forKey: .botID)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        subtype = try c.decodeIfPresent(String.self, forKey: .subtype)
        threadTS = try c.decodeIfPresent(String.self, forKey: .threadTS)
        replyCount = try c.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0
        isEdited = c.contains(.edited)
        reactions = try c.decodeIfPresent([SlackReaction].self, forKey: .reactions) ?? []
        // Files Slack has deleted or hidden come back with only an ID; skip those.
        files = (try c.decodeIfPresent([Failable<SlackFile>].self, forKey: .files) ?? []).compactMap(\.value)
        attachments = (try c.decodeIfPresent([Failable<SlackAttachment>].self, forKey: .attachments) ?? [])
            .compactMap(\.value)
        // `text` summarises layout blocks from bots and apps, so show the blocks instead.
        let blocks = (try? c.decodeIfPresent([JSONValue].self, forKey: .blocks)) ?? []
        markup = text.isEmpty || BlockKit.hasLayoutBlocks(blocks) ? BlockKit.markup(blocks).nilIfEmpty ?? text : text
    }

    private enum Keys: String, CodingKey {
        case ts, user, username, text, subtype, edited, reactions, files, attachments, blocks
        case botID = "bot_id"
        case threadTS = "thread_ts"
        case replyCount = "reply_count"
    }
}

public struct SlackUser: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let realName: String
    public let avatarURL: URL?
    public let isBot: Bool
    public let isDeleted: Bool

    /// What Slack shows: display name, else real name, else the handle.
    public var preferredName: String {
        displayName.nilIfEmpty ?? realName.nilIfEmpty ?? name
    }

    public init(id: String, name: String, displayName: String = "", realName: String = "",
                avatarURL: URL? = nil, isBot: Bool = false, isDeleted: Bool = false) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.realName = realName
        self.avatarURL = avatarURL
        self.isBot = isBot
        self.isDeleted = isDeleted
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let profile = try c.decodeIfPresent(Profile.self, forKey: .profile)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        displayName = profile?.displayName ?? ""
        realName = profile?.realName ?? ""
        avatarURL = profile?.image72.flatMap(URL.init(string:))
        isBot = try c.decodeIfPresent(Bool.self, forKey: .isBot) ?? false
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    private enum Keys: String, CodingKey {
        case id, name, profile, deleted
        case isBot = "is_bot"
    }

    private struct Profile: Decodable {
        let displayName: String?
        let realName: String?
        let image72: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case realName = "real_name"
            case image72 = "image_72"
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
