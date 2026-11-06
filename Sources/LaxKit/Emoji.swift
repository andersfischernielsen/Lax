import Foundation

/// Slack's built-in emoji shortcodes (`:tada:` → 🎉), from `Resources/emoji.json`
/// (see `scripts/generate_emoji.py`).
public enum Emoji {
    public static let shortcodes: [String: String] = {
        guard let url = Bundle.module.url(forResource: "emoji", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
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
