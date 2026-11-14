import Foundation

/// One event or reminder as the iOS widgets read it from EventKit.
struct WidgetSourceItem {
    let id: String
    let title: String
    let start: Date
    let end: Date
    /// A real all-day event, or a reminder without a time.
    let isRealAllDay: Bool
    let calendarTitle: String
    let color: [Double]
}

/// Builds the same `WeekSnapshot` the Mac app publishes from its EventCenter
/// (Itsycal/WeekSnapshot.m), so the shared widget views draw it unchanged.
enum WidgetSnapshotBuilder {
    /// Whole weeks from the one containing the first of this month to the one
    /// containing the last day of next month: what the week and month widgets,
    /// including their next-period view, can show.
    static func interval(containing date: Date, weekStart: Int, calendar: Calendar) -> DateInterval {
        let monthStart = calendar.dateInterval(of: .month, for: date)!.start
        let afterNext = calendar.date(byAdding: .month, value: 2, to: monthStart)!
        let lastDay = calendar.date(byAdding: .day, value: -1, to: afterNext)!
        let start = WeekDates.weekStartDate(containing: monthStart, weekStart: weekStart, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7,
                                to: WeekDates.weekStartDate(containing: lastDay, weekStart: weekStart, calendar: calendar))!
        return DateInterval(start: start, end: end)
    }

    /// A snapshot with a bucket for every day of `interval` (empty days too,
    /// since a missing bucket means incomplete data), or an empty one with
    /// the status explaining why there is no data.
    static func snapshot(
        items: [WidgetSourceItem],
        interval: DateInterval,
        weekStart: Int,
        status: String,
        calendar: Calendar,
        generatedAt: Date
    ) -> WeekSnapshot {
        var placed: [String: [Placed]] = [:]
        if status == "ready" {
            var day = interval.start
            while day < interval.end {
                placed[WeekDates.key(day, calendar: calendar)] = []
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            for item in items {
                let covered = DayItems.coveredDays(
                    start: item.start, end: item.end, isAllDay: item.isRealAllDay,
                    rangeStart: interval.start, rangeEnd: interval.end, calendar: calendar
                )
                for (day, spansDay) in covered {
                    placed[WeekDates.key(day, calendar: calendar)]?.append(Placed(item: item, day: day, isAllDay: spansDay))
                }
            }
        }
        return WeekSnapshot(
            version: 2,
            generatedAt: generatedAt.timeIntervalSince1970,
            timeZone: calendar.timeZone.identifier,
            start: interval.start.timeIntervalSince1970,
            end: interval.end.timeIntervalSince1970,
            status: status,
            weekStart: weekStart,
            days: placed.mapValues { DayItems.sorted($0).map { $0.event(calendar: calendar) } }
        )
    }

    /// An item on one day, with the flags EventCenter computes per day.
    private struct Placed: DayItem {
        let item: WidgetSourceItem
        let day: Date
        let isAllDay: Bool

        var isRealAllDay: Bool { item.isRealAllDay }
        var startDate: Date { item.start }
        var isCompleted: Bool { false } // Widgets leave completed reminders out.
        var calendarTitle: String { item.calendarTitle }
        var title: String { item.title }

        func event(calendar: Calendar) -> WeekEvent {
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let startsHere = calendar.isDate(day, inSameDayAs: item.start)
            return WeekEvent(
                id: "\(item.id)/\(Int(item.start.timeIntervalSince1970))",
                title: item.title.isEmpty ? "无标题日程" : item.title,
                start: item.start.timeIntervalSince1970,
                end: item.end.timeIntervalSince1970,
                allDay: item.isRealAllDay,
                spansDay: isAllDay,
                startsHere: startsHere,
                endsHere: calendar.isDate(day, inSameDayAs: item.end) && item.start < day,
                continues: startsHere && item.end >= next,
                color: item.color
            )
        }
    }
}
