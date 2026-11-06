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
