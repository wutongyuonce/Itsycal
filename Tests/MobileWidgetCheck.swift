import Foundation

/// The iOS widgets' snapshot builder must produce what the Mac app's
/// WeekSnapshot.m publishes, so the shared widget views draw it the same.
@main
enum MobileWidgetCheck {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let at = { (m: Int, d: Int, h: Int) -> Date in
            cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
        }
        let key = { (m: Int, d: Int) in WeekDates.key(at(m, d, 0), calendar: cal) }

        // 1. Interval: whole weeks from this month's first through next month's last day.
        // Nov 1, 2026 is a Sunday and Dec 31 a Thursday; weeks start on Monday.
        let interval = WidgetSnapshotBuilder.interval(containing: at(11, 14, 12), weekStart: 1, calendar: cal)
        assert(interval.start == at(10, 26, 0))
        assert(interval.end == cal.date(from: DateComponents(year: 2027, month: 1, day: 4))!)

        let items = [
            WidgetSourceItem(id: "late", title: "Late", start: at(11, 16, 15), end: at(11, 16, 16),
                             isRealAllDay: false, calendarTitle: "Work", color: [1, 0, 0]),
            WidgetSourceItem(id: "night", title: "Overnight", start: at(11, 16, 22), end: at(11, 18, 2),
                             isRealAllDay: false, calendarTitle: "Work", color: [0, 1, 0]),
            WidgetSourceItem(id: "holiday", title: "", start: at(11, 16, 0), end: at(11, 17, 0),
                             isRealAllDay: true, calendarTitle: "Holidays", color: [0, 0, 1]),
            WidgetSourceItem(id: "todo", title: "Todo", start: at(11, 16, 0), end: at(11, 16, 0),
                             isRealAllDay: true, calendarTitle: "Reminders", color: [0, 0, 0]),
        ]
        let snapshot = WidgetSnapshotBuilder.snapshot(items: items, interval: interval, weekStart: 1,
                                                      status: "ready", calendar: cal, generatedAt: at(11, 14, 12))

        // 2. Every day has a bucket, empty ones included, so the widget never reports missing data.
        assert(snapshot.days.count == 70 && snapshot.days[key(11, 20)]?.isEmpty == true)
        assert(snapshot.message(for: .week, containing: at(11, 16, 12), calendar: cal) == nil)
        assert(snapshot.message(for: .month, containing: at(12, 10, 12), calendar: cal) == nil)

        // 3. Day order and per-day flags match EventCenter.
        let monday = snapshot.days[key(11, 16)]!
        assert(monday.map(\.title) == ["无标题日程", "Todo", "Late", "Overnight"])
        let night = monday[3]
        assert(night.startsHere && night.continues && !night.endsHere && !night.spansDay && !night.allDay)
        let middle = snapshot.days[key(11, 17)]!.first { $0.title == "Overnight" }!
        assert(!middle.startsHere && !middle.endsHere && middle.spansDay)
        let last = snapshot.days[key(11, 18)]!.first { $0.title == "Overnight" }!
        assert(!last.startsHere && last.endsHere && !last.spansDay)
        assert(monday[0].allDay && monday[0].spansDay && snapshot.days[key(11, 17)]!.count == 1) // holiday ends at midnight

        // 4. Without access there is no data, only the reason.
        let denied = WidgetSnapshotBuilder.snapshot(items: items, interval: interval, weekStart: 1,
                                                    status: "permission", calendar: cal, generatedAt: at(11, 14, 12))
        assert(denied.days.isEmpty && denied.message(for: .week, containing: at(11, 16, 12), calendar: cal) != nil)

        print("MobileWidget checks passed: snapshot interval, empty-day buckets, day order, multi-day flags and permission status")
    }
}
