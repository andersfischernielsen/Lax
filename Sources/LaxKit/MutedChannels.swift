import Foundation

/// The user's mute settings. Slack keeps them in user prefs, in an older comma-separated
/// `muted_channels` list and in the newer `all_notifications_prefs` JSON; either may be
/// present, and `pref_change` events update one at a time.
public struct MutePrefs: Equatable, Sendable {
    public var mutedChannels: String?
    public var allNotificationsPrefs: String?

    public init(mutedChannels: String? = nil, allNotificationsPrefs: String? = nil) {
        self.mutedChannels = mutedChannels
        self.allNotificationsPrefs = allNotificationsPrefs
    }

    /// Muted conversation IDs: the legacy list, then per-channel overrides from the JSON.
    public var muted: Set<String> {
        var muted = Set((mutedChannels ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        muted.remove("")
        if let json = allNotificationsPrefs?.data(using: .utf8),
           let prefs = try? JSONDecoder().decode(NotificationPrefs.self, from: json) {
            for (id, channel) in prefs.channels ?? [:] {
                if channel.muted == true { muted.insert(id) } else if channel.muted == false { muted.remove(id) }
            }
        }
        return muted
    }

    /// Applies a `pref_change` event; other prefs are ignored.
    public mutating func apply(prefChange name: String, value: String) {
        switch name {
        case "muted_channels": mutedChannels = value
        case "all_notifications_prefs": allNotificationsPrefs = value
        default: break
        }
    }

    private struct NotificationPrefs: Decodable {
        struct Channel: Decodable {
            let muted: Bool?
        }

        let channels: [String: Channel]?
    }
}

extension SlackAPIClient {
    public func mutePrefs() async throws -> MutePrefs {
        let response: PrefsResponse = try await call("users.prefs.get")
        return MutePrefs(mutedChannels: response.prefs.mutedChannels,
                         allNotificationsPrefs: response.prefs.allNotificationsPrefs)
    }

    /// Mutes or unmutes a conversation for the user, the way Slack's web client does.
    public func setMuted(_ muted: Bool, channel: String) async throws {
        let _: PrefsAck = try await call("users.prefs.setNotifications", [
            "name": "muted", "value": muted ? "true" : "false", "channel_id": channel, "global": "false",
        ])
    }
}

private struct PrefsResponse: Decodable {
    struct Prefs: Decodable {
        let mutedChannels: String?
        let allNotificationsPrefs: String?

        enum CodingKeys: String, CodingKey {
            case mutedChannels = "muted_channels"
            case allNotificationsPrefs = "all_notifications_prefs"
        }
    }

    let prefs: Prefs
}

private struct PrefsAck: Decodable {}
