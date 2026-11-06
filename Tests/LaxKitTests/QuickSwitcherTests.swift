import Testing

@testable import LaxKit

private let candidates = [
    QuickSwitcher.Candidate(id: "C1", name: "#payments-fleet-alerts"),
    QuickSwitcher.Candidate(id: "C2", name: "#payments"),
    QuickSwitcher.Candidate(id: "C3", name: "#dev-payments-alerts", isUnread: true),
    QuickSwitcher.Candidate(id: "D1", name: "Andreas Robertson"),
    QuickSwitcher.Candidate(id: "C4", name: "#engineering", isUnread: true),
]

@Test func exactAndPrefixMatchesComeFirst() {
    #expect(QuickSwitcher.rank(candidates, query: "payments").prefix(2) == ["C2", "C1"])
    #expect(QuickSwitcher.rank(candidates, query: "#payments").first == "C2")
}

@Test func wordStartsBeatSubstrings() {
    #expect(QuickSwitcher.rank(candidates, query: "rob") == ["D1"])
    #expect(QuickSwitcher.rank(candidates, query: "alerts") == ["C3", "C1"])
}

@Test func lettersInOrderMatchLoosely() {
    #expect(QuickSwitcher.rank(candidates, query: "pfa").first == "C1")
    #expect(QuickSwitcher.rank(candidates, query: "zzz").isEmpty)
}

@Test func emptyQueryListsUnreadFirst() {
    #expect(QuickSwitcher.rank(candidates, query: " ") == ["C3", "C4", "D1", "C2", "C1"])
}
