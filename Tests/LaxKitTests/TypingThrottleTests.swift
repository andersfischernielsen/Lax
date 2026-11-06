import Foundation
import Testing
@testable import LaxKit

@Test func typingIsSentAtMostEveryFewSeconds() {
    var throttle = TypingThrottle()
    let start = Date(timeIntervalSince1970: 0)
    let first = throttle.shouldSend(in: "C1", at: start)
    let soon = throttle.shouldSend(in: "C1", at: start.addingTimeInterval(1))
    let elsewhere = throttle.shouldSend(in: "C2", at: start.addingTimeInterval(1))
    let later = throttle.shouldSend(in: "C1", at: start.addingTimeInterval(3))
    #expect(first && !soon && elsewhere && later)
}
