/// Slack message timestamps (`ts`): seconds and microseconds, as text like "1700000000.000200".
public enum SlackTimestamp {
    /// The position one microsecond earlier, for marking `ts` itself unread.
    public static func justBefore(_ ts: String) -> String? {
        let parts = ts.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let seconds = Int(parts[0]), let micros = Int(parts[1]), parts[1].count == 6 else {
            return nil
        }
        let total = seconds * 1_000_000 + micros - 1
        guard total >= 0 else { return nil }
        let fraction = String(total % 1_000_000)
        return "\(total / 1_000_000)." + String(repeating: "0", count: 6 - fraction.count) + fraction
    }
}
