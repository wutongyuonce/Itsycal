import Foundation

@main
enum MobileCalendarCheck {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day = { (y: Int, m: Int, d: Int, h: Int) -> Date in
            cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: 0))!
        }

        // 1. Month grid row count and weekStartDOW alignment
        let nov2026 = day(2026, 11, 14, 12) // Nov 1, 2026 is Sunday
        let sunGrid = MobileCalendarCore.monthGrid(containing: nov2026, weekStartDOW: 0, calendar: cal)
        assert(sunGrid.count == 5 && sunGrid[0].count == 7)
        assert(cal.isDate(sunGrid[0][0], inSameDayAs: day(2026, 11, 1, 0)))

        let monGrid = MobileCalendarCore.monthGrid(containing: nov2026, weekStartDOW: 1, calendar: cal)
        assert(monGrid.count == 6 && monGrid[0].count == 7)
        assert(cal.isDate(monGrid[0][0], inSameDayAs: day(2026, 10, 26, 0)))

        // 2. Covered days: overnight, exclusive midnight end, zero-duration point event
        let rangeStart = day(2026, 11, 1, 0)
        let rangeEnd = day(2026, 11, 30, 0)

        let overnight = DayItems.coveredDays(
            start: day(2026, 11, 10, 22),
            end: day(2026, 11, 11, 2),
            isAllDay: false,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendar: cal
        )
        assert(overnight.count == 2)
        assert(cal.isDate(overnight[0].day, inSameDayAs: day(2026, 11, 10, 0)) && !overnight[0].spansWholeDay)
        assert(cal.isDate(overnight[1].day, inSameDayAs: day(2026, 11, 11, 0)) && !overnight[1].spansWholeDay)

        let midnightEnd = DayItems.coveredDays(
            start: day(2026, 11, 12, 20),
            end: day(2026, 11, 13, 0),
            isAllDay: false,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendar: cal
        )
        assert(midnightEnd.count == 1 && cal.isDate(midnightEnd[0].day, inSameDayAs: day(2026, 11, 12, 0)))

        let pointEvent = DayItems.coveredDays(
            start: day(2026, 11, 15, 0),
            end: day(2026, 11, 15, 0),
            isAllDay: false,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            calendar: cal
        )
        assert(pointEvent.count == 1 && cal.isDate(pointEvent[0].day, inSameDayAs: day(2026, 11, 15, 0)))

        // 3. Same-day sorting: real all-day (incomplete before completed) -> spanning all-day -> timed
        let d = day(2026, 11, 16, 0)
        let timedLate = MobileAgendaItem(id: "1", targetIdentifier: "1", kind: .event, title: "Afternoon", day: d, startDate: day(2026, 11, 16, 15), endDate: day(2026, 11, 16, 16), isAllDay: false, isRealAllDay: false, hasTime: true, calendarID: "c", calendarTitle: "Work")
        let timedDoneRem = MobileAgendaItem(id: "2", targetIdentifier: "2", kind: .reminder, title: "Morning Done", day: d, startDate: day(2026, 11, 16, 9), endDate: day(2026, 11, 16, 9), isAllDay: false, isRealAllDay: false, hasTime: true, isCompleted: true, calendarID: "c", calendarTitle: "Work")
        let timedOpenRem = MobileAgendaItem(id: "3", targetIdentifier: "3", kind: .reminder, title: "Morning Open", day: d, startDate: day(2026, 11, 16, 9), endDate: day(2026, 11, 16, 9), isAllDay: false, isRealAllDay: false, hasTime: true, isCompleted: false, calendarID: "c", calendarTitle: "Work")
        let spanning = MobileAgendaItem(id: "4", targetIdentifier: "4", kind: .event, title: "Spanning", day: d, startDate: day(2026, 11, 15, 10), endDate: day(2026, 11, 17, 10), isAllDay: true, isRealAllDay: false, hasTime: true, calendarID: "c", calendarTitle: "Work")
        let realAllDay = MobileAgendaItem(id: "5", targetIdentifier: "5", kind: .event, title: "Holiday", day: d, startDate: d, endDate: d, isAllDay: true, isRealAllDay: true, hasTime: false, calendarID: "c", calendarTitle: "Work")

        let sorted = DayItems.sorted([timedLate, timedDoneRem, spanning, realAllDay, timedOpenRem])
        assert(sorted.map(\.id) == ["5", "4", "3", "2", "1"])

        // 4. Month cell chip layout: rows that fit, overflow count, dots when too short
        // 100pt = 3 inset + 20 number + 2 spacing + 5 rows of (14 chip + 1 spacing)
        let tall = MobileCalendarCore.chipLayout(cellHeight: 100, itemCount: 7)
        assert(tall.visible == 5 && tall.hidden == 2)
        assert(MobileCalendarCore.chipLayout(cellHeight: 100, itemCount: 2) == (visible: 2, hidden: 0))
        assert(MobileCalendarCore.chipLayout(cellHeight: 30, itemCount: 3) == (visible: 0, hidden: 3))
        assert(MobileCalendarCore.chipLayout(cellHeight: 0, itemCount: 0) == (visible: 0, hidden: 0))

        // 5. Meeting link detection
        let zoomURL = MobileCalendarCore.detectMeetingURL(in: ["Room 302", "Join https://us02web.zoom.us/j/123456789 now"])
        assert(zoomURL?.host == "us02web.zoom.us")
        assert(MobileCalendarCore.detectMeetingURL(in: ["https://example.com/not-a-meeting"]) == nil)

        // 6. Widget links open their day; other URLs and invalid dates are ignored
        let link = URL(string: "itsycal-week://date/2026-11-16?widget=1")!
        assert(MobileCalendarCore.day(fromWidgetURL: link, calendar: cal) == day(2026, 11, 16, 0))
        assert(MobileCalendarCore.day(fromWidgetURL: URL(string: "itsycal-week://date/2026-02-30")!, calendar: cal) == nil)
        assert(MobileCalendarCore.day(fromWidgetURL: URL(string: "https://date/2026-11-16")!, calendar: cal) == nil)

        // 7. Year/month jump clamps end-of-month and leap-day dates without overflowing
        let jan31 = day(2026, 1, 31, 0)
        assert(cal.isDate(MobileCalendarCore.date(bySettingYear: 2026, month: 2, of: jan31, calendar: cal), inSameDayAs: day(2026, 2, 28, 0)))
        assert(cal.isDate(MobileCalendarCore.date(bySettingYear: 2024, month: 2, of: jan31, calendar: cal), inSameDayAs: day(2024, 2, 29, 0)))
        let feb29 = day(2024, 2, 29, 0)
        assert(cal.isDate(MobileCalendarCore.date(bySettingYear: 2025, month: 2, of: feb29, calendar: cal), inSameDayAs: day(2025, 2, 28, 0)))
        assert(cal.isDate(MobileCalendarCore.date(bySettingYear: 2028, month: 5, of: nov2026, calendar: cal), inSameDayAs: day(2028, 5, 14, 0)))

        print("MobileCalendar checks passed: month grid, overnight/midnight/point splitting, agenda sorting, cell chip layout, meeting detection, widget links and year/month jump")
    }
}
