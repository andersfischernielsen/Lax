/// Back and forward through places visited, as in a browser: visiting somewhere new after
/// going back drops what was ahead.
public struct NavigationHistory<Place: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var current: Place?
    private var behind: [Place] = []
    private var ahead: [Place] = []
    /// Enough to retrace a session; the oldest places fall off.
    private let limit = 100

    public init() {}

    public var canGoBack: Bool { !behind.isEmpty }
    public var canGoForward: Bool { !ahead.isEmpty }

    public mutating func visit(_ place: Place) {
        guard place != current else { return }
        if let current { behind.append(current) }
        if behind.count > limit { behind.removeFirst() }
        current = place
        ahead = []
    }

    /// The place before the current one, now current; nil when there's none.
    public mutating func goBack() -> Place? {
        guard let previous = behind.popLast() else { return nil }
        if let current { ahead.append(current) }
        current = previous
        return previous
    }

    public mutating func goForward() -> Place? {
        guard let next = ahead.popLast() else { return nil }
        if let current { behind.append(current) }
        current = next
        return next
    }
}
