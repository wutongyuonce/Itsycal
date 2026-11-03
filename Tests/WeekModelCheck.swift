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
        assert(good.message(for: sunday, calendar: calendar) == nil)
        let nextSunday = calendar.date(byAdding: .day, value: 7, to: sunday)!
        assert(good.message(for: nextSunday, calendar: calendar) != nil, "Missing buckets must not become an empty week")
        let later = calendar.date(byAdding: .day, value: 14, to: sunday)!
        assert(good.message(for: later, calendar: calendar) != nil, "Missing data must not become an empty week")
        var otherZone = calendar
        otherZone.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        assert(good.message(for: sunday, calendar: otherZone) != nil)

        // Next-week view: one week ahead, expires, and is a timeline boundary.
        let navigation = WeekNavigation.nextWeek(from: sunday, calendar: calendar)
        assert(WeekDates.isNextWeek(navigation.shown(at: sunday), today: sunday, weekStart: 1, calendar: calendar))
        assert(!WeekDates.isNextWeek(sunday, today: sunday, weekStart: 1, calendar: calendar))
        assert(navigation.shown(at: navigation.until) == navigation.until, "Expired navigation returns to the current week")
        let navigated = WeekDates.timelineDates(from: sunday, calendar: calendar, navigation: navigation)
        assert(navigated.count == 16 && navigated.contains(navigation.until) && navigated == navigated.sorted())
        assert(WeekDates.timelineDates(from: navigation.until, calendar: calendar, navigation: navigation).count == 15)
        // A click just before the week starts keeps that absolute week, which then is the current week.
        let lateSunday = instant("2026-10-25T23:55:00-07:00")
        let earlyMonday = instant("2026-10-26T00:05:00-07:00")
        let late = WeekDates.days(containing: WeekNavigation.nextWeek(from: lateSunday, calendar: calendar).shown(at: earlyMonday),
                                  weekStart: 1, calendar: calendar)
        assert(late == WeekDates.days(containing: earlyMonday, weekStart: 1, calendar: calendar))

        // › is offered only when every next-week bucket is present and the snapshot is ready.
        assert(!WeekNavigation.canShowNextWeek(nil, today: sunday, calendar: calendar))
        assert(!WeekNavigation.canShowNextWeek(good, today: sunday, calendar: calendar))
        let full = WeekSnapshot.preview(at: sunday, calendar: calendar)
        assert(WeekNavigation.canShowNextWeek(full, today: sunday, calendar: calendar))
        let denied = WeekSnapshot(version: 2, generatedAt: full.generatedAt, timeZone: full.timeZone, start: full.start,
                                  end: full.end, status: "permission", weekStart: 1, days: full.days)
        assert(!WeekNavigation.canShowNextWeek(denied, today: sunday, calendar: calendar))

        // Field names and types written by Itsycal/WeekSnapshot.m.
        let written = """
        {"version":2,"generatedAt":1.5,"timeZone":"America/Los_Angeles","start":0,"end":1,"status":"ready",
         "weekStart":1,"days":{"2026-10-19":[{"id":"e/1","title":"T","start":0,"end":1,"allDay":false,
         "spansDay":false,"startsHere":true,"endsHere":false,"continues":false,"color":[0.1,0.2,0.3]}]}}
        """
        let decoded = try JSONDecoder().decode(WeekSnapshot.self, from: Data(written.utf8))
        assert(decoded.days["2026-10-19"]?.first?.title == "T")
        print("WeekModel checks passed: week start, year boundary, DST, capacity, links, coverage, timezone, next-week view and snapshot format")
    }
}
