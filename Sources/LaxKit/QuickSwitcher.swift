import Foundation

/// Ranks names against what the user typed in the ⌘K switcher.
public enum QuickSwitcher {
    public struct Candidate: Equatable, Sendable {
        public let id: String
        public let name: String
        /// Ranked first when nothing is typed.
        public let isUnread: Bool

        public init(id: String, name: String, isUnread: Bool = false) {
            self.id = id
            self.name = name
            self.isUnread = isUnread
        }
    }

    /// IDs of matching candidates, best first. With an empty query: unread first, then by name.
    public static func rank(_ candidates: [Candidate], query: String, limit: Int = 50) -> [String] {
        let query = query.lowercased().trimmingCharacters(in: .whitespaces).trimmingPrefix("#")
        // Channels and people interleave alphabetically, ignoring the "#".
        let byName: (Candidate, Candidate) -> Bool = {
            $0.name.trimmingPrefix("#").localizedStandardCompare($1.name.trimmingPrefix("#")) == .orderedAscending
        }
        guard !query.isEmpty else {
            return (candidates.filter(\.isUnread).sorted(by: byName) + candidates.filter { !$0.isUnread }.sorted(by: byName))
                .prefix(limit).map(\.id)
        }
        return candidates
            .compactMap { candidate in score(candidate.name, query: String(query)).map { (candidate, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : byName($0.0, $1.0) }
            .prefix(limit)
            .map(\.0.id)
    }

    /// Higher is better; nil when the query doesn't match at all.
    static func score(_ name: String, query: String) -> Int? {
        let name = name.lowercased().trimmingPrefix("#")
        if name == query { return 1000 }
        if name.hasPrefix(query) { return 800 - name.count }
        let words = name.split(whereSeparator: { " -_.,".contains($0) })
        if words.contains(where: { $0.hasPrefix(query) }) { return 600 - name.count }
        if name.contains(query) { return 400 - name.count }
        // Letters in order with gaps ("pfa" → "payments-fleet-alerts"); tighter is better.
        var rest = name[...]
        var gaps = 0
        for character in query {
            guard let index = rest.firstIndex(of: character) else { return nil }
            gaps += rest.distance(from: rest.startIndex, to: index)
            rest = rest[rest.index(after: index)...]
        }
        return max(1, 200 - gaps)
    }
}
