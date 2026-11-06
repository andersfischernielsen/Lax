import Foundation

/// Decides when to tell Slack the user is typing: at most once per conversation every
/// few seconds, which is how often Slack's clients repeat it.
public struct TypingThrottle: Equatable, Sendable {
    public static let interval: TimeInterval = 3

    private var lastSent: [String: Date] = [:]

    public init() {}

    /// Whether to send now; records the send when it says yes.
    public mutating func shouldSend(in channel: String, at date: Date = .now) -> Bool {
        if let last = lastSent[channel], date.timeIntervalSince(last) < Self.interval { return false }
        lastSent[channel] = date
        return true
    }
}
