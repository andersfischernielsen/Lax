import Testing

@testable import LaxKit

@Test func backAndForwardRetraceVisits() {
    var history = NavigationHistory<String>()
    history.visit("A")
    history.visit("B")
    history.visit("C")
    #expect(history.goBack() == "B")
    #expect(history.goBack() == "A")
    #expect(history.goBack() == nil)
    #expect(history.goForward() == "B")
    #expect(history.current == "B")
    #expect(history.canGoForward)
}

@Test func visitingAfterGoingBackDropsWhatWasAhead() {
    var history = NavigationHistory<String>()
    history.visit("A")
    history.visit("B")
    _ = history.goBack()
    history.visit("D")
    #expect(!history.canGoForward)
    #expect(history.goBack() == "A")
}

@Test func revisitingTheCurrentPlaceChangesNothing() {
    var history = NavigationHistory<String>()
    history.visit("A")
    history.visit("A")
    #expect(!history.canGoBack)
}
