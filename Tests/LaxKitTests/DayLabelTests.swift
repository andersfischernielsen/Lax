import Foundation
import Testing
@testable import LaxKit

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func label(_ value: Date) -> String {
    DayLabel.text(for: value, now: date(2026, 11, 6), calendar: calendar, locale: Locale(identifier: "en_GB"))
}

@Test func relativeDayNames() {
    #expect(label(date(2026, 11, 6, 1)) == "Today")
    #expect(label(date(2026, 11, 5, 23)) == "Yesterday")
}

@Test func olderDaysAreSpelledOut() {
    #expect(label(date(2026, 11, 2)) == "Monday 2 November")
    #expect(label(date(2025, 12, 24)).contains("2025"))
}

@Test func dividersBetweenDays() {
    #expect(DayLabel.startsNewDay(date(2026, 11, 6), after: nil, calendar: calendar))
    #expect(!DayLabel.startsNewDay(date(2026, 11, 6, 15), after: date(2026, 11, 6, 9), calendar: calendar))
    #expect(DayLabel.startsNewDay(date(2026, 11, 6, 0), after: date(2026, 11, 5, 23), calendar: calendar))
}
