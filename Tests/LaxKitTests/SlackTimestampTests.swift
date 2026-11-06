import Testing

@testable import LaxKit

@Test func justBeforeStepsBackOneMicrosecond() {
    #expect(SlackTimestamp.justBefore("1700000000.000200") == "1700000000.000199")
    #expect(SlackTimestamp.justBefore("1700000000.000000") == "1699999999.999999")
}

@Test func justBeforeRejectsOtherShapes() {
    #expect(SlackTimestamp.justBefore("1700000000") == nil)
    #expect(SlackTimestamp.justBefore("1.5") == nil)
    #expect(SlackTimestamp.justBefore("0.000000") == nil)
}

@Test func comparesTimestampsAsNumbers() {
    #expect(SlackTimestamp.isBefore("999.000000", "1000.000000"))
    #expect(!SlackTimestamp.isBefore("2.0", "2.0"))
    #expect(SlackTimestamp.later(nil, "5.0") == "5.0")
    #expect(SlackTimestamp.later("9.0", "10.0") == "10.0")
    #expect(SlackTimestamp.later("10.0", "9.0") == "10.0")
}
