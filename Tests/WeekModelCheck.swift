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
        assert(good.message(at: sunday, calendar: calendar) == nil)
        let later = calendar.date(byAdding: .day, value: 14, to: sunday)!
        assert(good.message(at: later, calendar: calendar) != nil, "Missing data must not become an empty week")
        var otherZone = calendar
        otherZone.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        assert(good.message(at: sunday, calendar: otherZone) != nil)
        let roundtrip = try JSONDecoder().decode(WeekSnapshot.self, from: JSONEncoder().encode(good))
        assert(roundtrip.days.count == 7)
        print("WeekModel checks passed: configurable week start, year boundary, DST, capacity, links, coverage and timezone")
    }
}
