import Foundation

@main
struct WeekModelCheck {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1 // System preference must not change Monday-first output.
        let formatter = ISO8601DateFormatter()
        func instant(_ value: String) -> Date { formatter.date(from: value)! }

        let sunday = instant("2026-10-25T12:00:00-07:00")
        let days = WeekDates.days(containing: sunday, weekStart: 1, calendar: calendar)
        assert(WeekDates.key(days[0], calendar: calendar) == "2026-10-19")
        assert(WeekDates.key(days[6], calendar: calendar) == "2026-10-25")
        let newYear = WeekDates.days(containing: instant("2027-01-01T12:00:00-08:00"), weekStart: 1, calendar: calendar)
        assert(WeekDates.key(newYear[0], calendar: calendar) == "2026-12-28")
        assert(WeekDates.key(newYear[6], calendar: calendar) == "2027-01-03")

        let sundayStart = WeekDates.days(containing: sunday, weekStart: 0, calendar: calendar)
        assert(WeekDates.key(sundayStart[0], calendar: calendar) == "2026-10-25")
        assert(WeekDates.key(sundayStart[6], calendar: calendar) == "2026-10-31")
        let wednesdayStart = WeekDates.days(containing: instant("2026-10-22T12:00:00-07:00"), weekStart: 3, calendar: calendar)
        assert(WeekDates.key(wednesdayStart[0], calendar: calendar) == "2026-10-21")
        assert(WeekDates.key(wednesdayStart[6], calendar: calendar) == "2026-10-27")

        let dst = WeekDates.timelineDates(from: instant("2026-03-07T12:00:00-08:00"), calendar: calendar)
        assert(dst.count == 15)
        assert(calendar.component(.hour, from: dst[2]) == 0)
        assert(dst[2].timeIntervalSince(dst[1]) == 23 * 3600, "DST must advance by a local day, not 24 hours")
        assert(WeekDates.capacity(height: 148) == 4)
        assert(WeekDates.capacity(height: 1000) == 4, "Never show more than four events per day")
        assert(WeekDates.capacity(height: 30) == 0)
        assert(WeekDates.capacity(height: 148, compact: false) == 2)
        assert(WeekDates.capacity(height: 300, compact: false) == 4)
        let end = instant("2026-10-21T02:00:00-07:00")
        let overnight = WeekEvent(id: "night", title: "Overnight", start: instant("2026-10-20T22:00:00-07:00").timeIntervalSince1970,
                                  end: end.timeIntervalSince1970, allDay: false, spansDay: false,
                                  startsHere: false, endsHere: true, continues: false, color: [])
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        assert(overnight.timeLabel == "→ " + timeFormatter.string(from: end))
        assert(WeekDates.link(days[0], calendar: calendar).absoluteString == "itsycal-week://date/2026-10-19?widget=1")

        let monday = days[0]
        let coverageEnd = calendar.date(byAdding: .day, value: 14, to: monday)!
        let buckets = Dictionary(uniqueKeysWithValues: days.map { (WeekDates.key($0, calendar: calendar), [WeekEvent]()) })
        let good = WeekSnapshot(version: 2, generatedAt: sunday.timeIntervalSince1970, timeZone: calendar.timeZone.identifier,
                                start: monday.timeIntervalSince1970, end: coverageEnd.timeIntervalSince1970, status: "ready", weekStart: 1, days: buckets)
        func weekIssue(_ snapshot: WeekSnapshot, _ date: Date, _ cal: Calendar = calendar) -> String? {
            snapshot.message(for: .week, containing: date, calendar: cal)
        }
        assert(weekIssue(good, sunday) == nil)
        let nextSunday = calendar.date(byAdding: .day, value: 7, to: sunday)!
        assert(weekIssue(good, nextSunday) != nil, "Missing buckets must not become an empty week")
        let later = calendar.date(byAdding: .day, value: 14, to: sunday)!
        assert(weekIssue(good, later) != nil, "Missing data must not become an empty week")
        var otherZone = calendar
        otherZone.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        assert(weekIssue(good, sunday, otherZone) != nil)

        // Month grids: whole weeks, starting on the configured weekday.
        let november = MonthDates.grid(containing: instant("2026-11-15T12:00:00-08:00"), weekStart: 1, calendar: calendar)
        assert(november.count == 6 && november.allSatisfy { $0.count == 7 })
        assert(WeekDates.key(november[0][0], calendar: calendar) == "2026-10-26")
        assert(WeekDates.key(november[5][6], calendar: calendar) == "2026-12-06")
        let february = MonthDates.grid(containing: instant("2027-02-10T12:00:00-08:00"), weekStart: 1, calendar: calendar)
        assert(february.count == 4, "Feb 2027 starts on Monday: exactly four rows")
        let sundayFirst = MonthDates.grid(containing: instant("2026-11-15T12:00:00-08:00"), weekStart: 0, calendar: calendar)
        assert(WeekDates.key(sundayFirst[0][0], calendar: calendar) == "2026-11-01" && sundayFirst.count == 5)

        // Next-period view: one period ahead, expires, and is a timeline boundary.
        let navigation = PeriodNavigation.next(.week, from: sunday, calendar: calendar)
        assert(!WidgetPeriod.week.isSame(navigation.shown(at: sunday), as: sunday, weekStart: 1, calendar: calendar))
        assert(WidgetPeriod.week.isSame(nextSunday, as: navigation.shown(at: sunday), weekStart: 1, calendar: calendar))
        assert(navigation.shown(at: navigation.until) == navigation.until, "Expired navigation returns to the current period")
        let navigated = WeekDates.timelineDates(from: sunday, calendar: calendar, navigation: navigation)
        assert(navigated.count == 16 && navigated.contains(navigation.until) && navigated == navigated.sorted())
        assert(WeekDates.timelineDates(from: navigation.until, calendar: calendar, navigation: navigation).count == 15)
        // A click just before the week starts keeps that absolute week, which then is the current week.
        let lateSunday = instant("2026-10-25T23:55:00-07:00")
        let earlyMonday = instant("2026-10-26T00:05:00-07:00")
        let late = PeriodNavigation.next(.week, from: lateSunday, calendar: calendar).shown(at: earlyMonday)
        assert(WidgetPeriod.week.isSame(late, as: earlyMonday, weekStart: 1, calendar: calendar))
        // Next month from Jan 31 is February, not March.
        let january31 = instant("2027-01-31T12:00:00-08:00")
        assert(calendar.component(.month, from: PeriodNavigation.next(.month, from: january31, calendar: calendar).target) == 2)

        // › is offered only when every bucket of the next period is present and the snapshot is ready.
        assert(!PeriodNavigation.canShowNext(.week, snapshot: nil, today: sunday, calendar: calendar))
        assert(!PeriodNavigation.canShowNext(.week, snapshot: good, today: sunday, calendar: calendar))
        assert(!PeriodNavigation.canShowNext(.month, snapshot: good, today: sunday, calendar: calendar))
        let full = WeekSnapshot.preview(at: sunday, calendar: calendar)
        assert(PeriodNavigation.canShowNext(.week, snapshot: full, today: sunday, calendar: calendar))
        assert(PeriodNavigation.canShowNext(.month, snapshot: full, today: sunday, calendar: calendar))
        assert(full.message(for: .month, containing: sunday, calendar: calendar) == nil)
        let denied = WeekSnapshot(version: 2, generatedAt: full.generatedAt, timeZone: full.timeZone, start: full.start,
                                  end: full.end, status: "permission", weekStart: 1, days: full.days)
        assert(!PeriodNavigation.canShowNext(.week, snapshot: denied, today: sunday, calendar: calendar))
        // The month view needs the trailing days of next month's grid, not just the month itself.
        var trimmed = full.days
        let nextMonthDays = WidgetPeriod.month.days(containing: WidgetPeriod.month.next(after: sunday, calendar: calendar),
                                                    weekStart: 1, calendar: calendar)
        trimmed[WeekDates.key(nextMonthDays.last!, calendar: calendar)] = nil
        let gap = WeekSnapshot(version: 2, generatedAt: full.generatedAt, timeZone: full.timeZone, start: full.start,
                               end: full.end, status: "ready", weekStart: 1, days: trimmed)
        assert(!PeriodNavigation.canShowNext(.month, snapshot: gap, today: sunday, calendar: calendar))

        // Field names and types written by Itsycal/WeekSnapshot.m.
        let written = """
        {"version":2,"generatedAt":1.5,"timeZone":"America/Los_Angeles","start":0,"end":1,"status":"ready",
         "weekStart":1,"days":{"2026-10-19":[{"id":"e/1","title":"T","start":0,"end":1,"allDay":false,
         "spansDay":false,"startsHere":true,"endsHere":false,"continues":false,"color":[0.1,0.2,0.3]}]}}
        """
        let decoded = try JSONDecoder().decode(WeekSnapshot.self, from: Data(written.utf8))
        assert(decoded.days["2026-10-19"]?.first?.title == "T")
        print("WeekModel checks passed: week start, year boundary, DST, capacity, links, coverage, timezone, month grid, next-period view and snapshot format")
    }
}
