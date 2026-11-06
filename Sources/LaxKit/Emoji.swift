import Foundation

/// Slack's built-in emoji shortcodes (`:tada:` → 🎉), from `Resources/emoji.json`
/// (see `scripts/generate_emoji.py`).
public enum Emoji {
    public static let shortcodes: [String: String] = {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let table = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return table
    }()

    /// The character for a shortcode name, including skin tones (`+1::skin-tone-2` → 👍🏻).
    /// nil for names Slack doesn't define, such as a workspace's custom emoji.
    public static func character(for name: String) -> String? {
        let parts = name.split(separator: "::", maxSplits: 1).map(String.init)
        guard let base = shortcodes[parts[0]] else { return nil }
        guard parts.count == 2, let tone = shortcodes[parts[1]] else { return base }
        // A skin tone replaces the "show as emoji" selector rather than following it.
        return base.replacing("\u{FE0F}", with: "") + tone
    }
}

/// What a shortcode stands for in a workspace: a character, or a custom image.
public enum SlackEmoji: Hashable, Sendable {
    case character(String)
    case image(URL)
}

extension Emoji {
    /// Resolves `emoji.list` (name → image URL or `alias:other`). Aliases may point at
    /// other custom emoji or at standard ones; unresolvable entries are dropped.
    public static func resolveCustom(_ raw: [String: String]) -> [String: SlackEmoji] {
        func resolve(_ name: String, depth: Int) -> SlackEmoji? {
            guard depth < 8 else { return nil }
            guard let value = raw[name] else { return character(for: name).map(SlackEmoji.character) }
            if value.hasPrefix("alias:") { return resolve(String(value.dropFirst(6)), depth: depth + 1) }
            return URL(string: value).map(SlackEmoji.image)
        }
        return raw.keys.reduce(into: [:]) { result, name in result[name] = resolve(name, depth: 0) }
    }
}

extension SlackAPIClient {
    /// The workspace's custom emoji.
    public func customEmoji() async throws -> [String: SlackEmoji] {
        let response: EmojiListResponse = try await call("emoji.list")
        return Emoji.resolveCustom(response.emoji)
    }
}

private struct EmojiListResponse: Decodable {
    let emoji: [String: String]
}

extension Emoji {
    /// Shortcode names for a picker: standard names (one per emoji) and custom ones,
    /// filtered by `query`, names starting with it first.
    public static func pickerNames(matching query: String, custom: [String: SlackEmoji]) -> [String] {
        let query = query.lowercased().trimmingCharacters(in: .whitespaces)
        var seen: Set<String> = []
        let standard = shortcodes.keys.sorted().filter { name in
            guard !name.hasPrefix("skin-tone"), let character = shortcodes[name] else { return false }
            return seen.insert(character).inserted
        }
        let customImages = custom.compactMap { name, emoji -> String? in
            if case .image = emoji { name } else { nil }
        }.sorted()
        let all = standard + customImages
        guard !query.isEmpty else { return all }
        let matches = all.filter { $0.contains(query) }
        return matches.filter { $0.hasPrefix(query) } + matches.filter { !$0.hasPrefix(query) }
    }
}
