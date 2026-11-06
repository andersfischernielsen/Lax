import Foundation
import LaxKit

/// Formatted message text, reused until a name or emoji it shows changes.
///
/// Formatting costs about half a millisecond per message, too much to repeat for every
/// row that scrolls into view. Each entry remembers what it looked up while formatting;
/// a hit repeats those lookups (cheap reads, which also tell SwiftUI what the row depends
/// on) and reformats only if one has a different answer now.
@MainActor
final class FormattedTextCache {
    enum Lookup: Hashable {
        case user(String)
        case channel(String)
        case group(String)
        case emoji(String)
    }

    enum Answer: Equatable {
        case name(String?)
        case emoji(SlackEmoji?)
    }

    private struct Entry {
        let text: AttributedString
        let lookups: [Lookup: Answer]
    }

    /// Plenty for a session's scrolling; cleared rather than evicted one by one.
    private static let capacity = 5000
    private let resolve: (Lookup) -> Answer
    private var entries: [String: Entry] = [:]
    /// Lookups made by the formatting in progress.
    private var recorded: [Lookup: Answer] = [:]

    init(resolve: @escaping (Lookup) -> Answer) {
        self.resolve = resolve
    }

    /// `markup` formatted by `format`.
    func text(for markup: String, format: (SlackText) -> AttributedString) -> AttributedString {
        if let entry = entries[markup], entry.lookups.allSatisfy({ resolve($0.key) == $0.value }) {
            return entry.text
        }
        recorded = [:]
        let text = format(SlackText(
            userName: { id in MainActor.assumeIsolated { self.name(.user(id)) } },
            channelName: { id in MainActor.assumeIsolated { self.name(.channel(id)) } },
            subteamHandle: { id in MainActor.assumeIsolated { self.name(.group(id)) } },
            customEmoji: { name in
                MainActor.assumeIsolated {
                    if case .emoji(let emoji) = self.record(.emoji(name)) { emoji } else { nil }
                }
            }
        ))
        if entries.count >= Self.capacity { entries.removeAll() }
        entries[markup] = Entry(text: text, lookups: recorded)
        return text
    }

    private func record(_ lookup: Lookup) -> Answer {
        let answer = resolve(lookup)
        recorded[lookup] = answer
        return answer
    }

    private func name(_ lookup: Lookup) -> String? {
        if case .name(let name) = record(lookup) { name } else { nil }
    }
}
