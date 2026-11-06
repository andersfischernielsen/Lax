import Testing
@testable import LaxKit

@Test func framesFollowTheClockAndLoop() {
    let durations = [0.1, 0.2, 0.1]
    #expect(FrameTiming.frame(at: 0, durations: durations) == 0)
    #expect(FrameTiming.frame(at: 0.15, durations: durations) == 1)
    #expect(FrameTiming.frame(at: 0.35, durations: durations) == 2)
    #expect(FrameTiming.frame(at: 0.45, durations: durations) == 0, "loops after 0.4 s")
}

@Test func instantFramesGetATenthOfASecond() {
    #expect(FrameTiming.frame(at: 0.15, durations: [0, 0]) == 1)
}

@Test func noFramesOrNegativeTimesStayInRange() {
    #expect(FrameTiming.frame(at: 3, durations: []) == 0)
    #expect(FrameTiming.frame(at: -0.05, durations: [0.1, 0.1]) == 1)
}
