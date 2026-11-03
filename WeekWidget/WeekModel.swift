import Foundation

struct WeekEvent: Codable {
    let id: String
    let title: String
    let start: TimeInterval
    let end: TimeInterval
    let allDay: Bool
    let spansDay: Bool
    let startsHere: Bool
    let endsHere: Bool
    let continues: Bool
    let color: [Double]

    var timeLabel: String {
        if allDay { return "全天" }
        if spansDay && !startsHere { return "跨日" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        if endsHere { return "→ " + formatter.string(from: Date(timeIntervalSince1970: end)) }
        let time = formatter.string(from: Date(timeIntervalSince1970: start))
        return continues ? time + " →" : time
    }
}

enum WeekShared {
    static let kind = "ItsycalWeek" // Must match WeekWidgetReloader in the main app.
    static var group: String? { Bundle.main.object(forInfoDictionaryKey: "WeekAppGroup") as? String }
}

struct WeekSnapshot: Codable {
    let version: Int
    let generatedAt: TimeInterval
    let timeZone: String
    let start: TimeInterval
    let end: TimeInterval
    let status: String
    let weekStart: Int
    let days: [String: [WeekEvent]]

    static func load() -> WeekSnapshot? {
        guard let group = WeekShared.group,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: container.appendingPathComponent("week.json")),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.version == 2 else { return nil }
        return snapshot
    }

    /// Why the week containing `shown` cannot be displayed, or nil when it can.
    func message(for shown: Date, calendar: Calendar) -> String? {
        if status == "permission" { return "打开 Itsycal，允许访问日历" }
        if status == "calendars" { return "在 Itsycal 中选择要显示的日历" }
        guard status == "ready" else { return "打开 Itsycal 更新日程" }
        guard (0...6).contains(weekStart) else { return "打开 Itsycal 更新日程" }
        if timeZone != calendar.timeZone.identifier { return "时区已改变，打开 Itsycal 更新日程" }
        let first = WeekDates.weekStartDate(containing: shown, weekStart: weekStart, calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 7, to: first)!
        if first.timeIntervalSince1970 < start || next.timeIntervalSince1970 > end {
            return "打开 Itsycal 获取这一周的日程"
        }
        // Missing buckets mean incomplete data, never an empty calendar.
        if WeekDates.days(containing: shown, weekStart: weekStart, calendar: calendar)
            .contains(where: { days[WeekDates.key($0, calendar: calendar)] == nil }) {
            return "打开 Itsycal 更新日程"
        }
        return nil
    }
}

/// Next-week view chosen in the widget. Shared by every widget instance and
/// expires, so the widget always falls back to the current week.
struct WeekNavigation {
    static let idle: TimeInterval = 15 * 60

    let week: Date   // An instant inside the shown week.
    let until: Date

    func shown(at date: Date) -> Date { date < until ? week : date }

    static func nextWeek(from now: Date, calendar: Calendar) -> WeekNavigation {
        WeekNavigation(week: calendar.date(byAdding: .day, value: 7, to: now)!,
                       until: now.addingTimeInterval(idle))
    }

    /// Next week is offered only when the snapshot can display all of it.
    static func canShowNextWeek(_ snapshot: WeekSnapshot?, today: Date, calendar: Calendar) -> Bool {
        guard let snapshot else { return false }
        return snapshot.message(for: calendar.date(byAdding: .day, value: 7, to: today)!, calendar: calendar) == nil
    }

    // One key, [week, until], so readers never see half of an update.
    private static let key = "navigation"
    private static var defaults: UserDefaults? { WeekShared.group.flatMap(UserDefaults.init(suiteName:)) }

    static func load() -> WeekNavigation? {
        guard let value = defaults?.array(forKey: key) as? [TimeInterval], value.count == 2 else { return nil }
        return WeekNavigation(week: Date(timeIntervalSince1970: value[0]), until: Date(timeIntervalSince1970: value[1]))
    }

    /// nil returns to the current week.
    static func store(_ navigation: WeekNavigation?) {
        if let navigation {
            defaults?.set([navigation.week.timeIntervalSince1970, navigation.until.timeIntervalSince1970], forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }
}

enum WeekDates {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func weekStartDate(containing date: Date, weekStart: Int, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let start = min(max(weekStart, 0), 6)
        let offset = (calendar.component(.weekday, from: day) - 1 - start + 7) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    static func days(containing date: Date, weekStart: Int, calendar: Calendar) -> [Date] {
        let first = weekStartDate(containing: date, weekStart: weekStart, calendar: calendar)
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: first)! }
    }

    static func isNextWeek(_ shown: Date, today: Date, weekStart: Int, calendar: Calendar) -> Bool {
        let thisWeek = weekStartDate(containing: today, weekStart: weekStart, calendar: calendar)
        return calendar.isDate(weekStartDate(containing: shown, weekStart: weekStart, calendar: calendar),
                               inSameDayAs: calendar.date(byAdding: .day, value: 7, to: thisWeek)!)
    }

    static func key(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func link(_ date: Date, calendar: Calendar) -> URL {
        URL(string: "itsycal-week://date/\(key(date, calendar: calendar))?widget=1")!
    }

    static func weekdayLabel(_ date: Date, calendar: Calendar) -> String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: date) - 1]
    }

    static func eventPitch(compact: Bool) -> Double { compact ? 25 : 36 }
    static func reservedHeight(compact: Bool) -> Double {
        compact ? 46 : 54 // Date, gap and overflow; header lives outside the columns.
    }

    static func capacity(height: Double, compact: Bool = true) -> Int {
        min(4, max(0, Int((height - reservedHeight(compact: compact)) / eventPitch(compact: compact))))
    }

    /// Now, each of the next 14 local midnights and, if later than now, the
    /// moment the next-week view expires.
    static func timelineDates(from date: Date, calendar: Calendar, navigation: WeekNavigation? = nil) -> [Date] {
        let midnight = calendar.startOfDay(for: date)
        var dates = [date] + (1...14).map { calendar.date(byAdding: .day, value: $0, to: midnight)! }
        if let until = navigation?.until, until > date { dates.append(until) }
        return dates.sorted()
    }
}
