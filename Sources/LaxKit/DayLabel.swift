import Foundation

/// Headings for the day dividers in a conversation.
public enum DayLabel {
    /// "Today", "Yesterday", "Monday 3 November", or with the year when it isn't this year.
    public static func text(
        for date: Date, now: Date = .now, calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        var style = Date.FormatStyle(
            date: .omitted, time: .omitted, locale: locale, calendar: calendar,
            timeZone: calendar.timeZone
        )
        .weekday(.wide).day().month(.wide)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        return date.formatted(style)
    }

    /// Whether a divider goes before `date`, given the message before it.
    public static func startsNewDay(_ date: Date, after previous: Date?, calendar: Calendar = .current) -> Bool {
        guard let previous else { return true }
        return !calendar.isDate(date, inSameDayAs: previous)
    }
}
