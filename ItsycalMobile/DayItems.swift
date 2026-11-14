import Foundation

/// What `DayItems.sorted` needs to know about an item placed on one day.
protocol DayItem {
    /// A real all-day event, or a reminder without a time.
    var isRealAllDay: Bool { get }
    /// Real all-day, or a timed event that covers the whole of this day.
    var isAllDay: Bool { get }
    var startDate: Date { get }
    var isCompleted: Bool { get }
    var calendarTitle: String { get }
    var title: String { get }
}

/// How calendar items are placed on days. Shared by the app's month view and
/// agenda and by the iOS widgets, and matching the Mac app's EventCenter.
enum DayItems {
    /// The days an item covers within `[rangeStart, rangeEnd)`, with `[start, end)`
    /// half-open midnight semantics: an event ending at midnight doesn't reach
    /// the next day, and a zero-length item still appears on its day.
    static func coveredDays(
        start: Date,
        end: Date,
        isAllDay: Bool,
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> [(day: Date, spansWholeDay: Bool)] {
        let clampedEnd = min(end, rangeEnd)
        var day = calendar.startOfDay(for: max(start, rangeStart))
        var pointItem = start == end && start >= rangeStart && start < rangeEnd
        var results: [(day: Date, spansWholeDay: Bool)] = []
        while day < clampedEnd || pointItem {
            pointItem = false
            let nextDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day)!)
            results.append((day: day, spansWholeDay: isAllDay || (start < day && end >= nextDay)))
            day = nextDay
        }
        return results
    }

    /// Itsycal's order within a day (`CompareItemsOnDay`): real all-day items
    /// (incomplete first, then by calendar), then items spanning the day (by
    /// calendar), then timed items by start (incomplete first); title last.
    static func sorted<Item: DayItem>(_ items: [Item]) -> [Item] {
        items.sorted { a, b in
            if a.isRealAllDay && b.isRealAllDay {
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                let byCalendar = a.calendarTitle.localizedStandardCompare(b.calendarTitle)
                if byCalendar != .orderedSame { return byCalendar == .orderedAscending }
            } else if a.isRealAllDay != b.isRealAllDay {
                return a.isRealAllDay
            } else if a.isAllDay && b.isAllDay {
                let byCalendar = a.calendarTitle.localizedStandardCompare(b.calendarTitle)
                if byCalendar != .orderedSame { return byCalendar == .orderedAscending }
            } else if a.isAllDay != b.isAllDay {
                return a.isAllDay
            } else {
                if a.startDate != b.startDate { return a.startDate < b.startDate }
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}
