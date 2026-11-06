import Foundation

/// Who is typing where. Slack sends `user_typing` every few seconds while someone
/// types and nothing when they stop, so entries expire on their own.
public struct TypingTracker: Equatable, Sendable {
    public static let expiry: TimeInterval = 6

    private var lastSeen: [String: [String: Date]] = [:]

    public init() {}

    public mutating func record(userID: String, in channel: String, at date: Date = .now) {
        lastSeen[channel, default: [:]][userID] = date
    }

    /// Someone who posted has stopped typing.
    public mutating func clear(userID: String, in channel: String) {
        lastSeen[channel]?[userID] = nil
    }

    public func typingUserIDs(in channel: String, at date: Date = .now) -> [String] {
        (lastSeen[channel] ?? [:])
            .filter { date.timeIntervalSince($0.value) < Self.expiry }
            .sorted { $0.value < $1.value }
            .map(\.key)
    }

    /// "Jane is typing…", "Jane and Bob are typing…", "Several people are typing…".
    public static func summary(_ names: [String]) -> String? {
        switch names.count {
        case 0: nil
        case 1: "\(names[0]) is typing…"
        case 2: "\(names[0]) and \(names[1]) are typing…"
        case 3: "\(names[0]), \(names[1]) and \(names[2]) are typing…"
        default: "Several people are typing…"
        }
    }
}
