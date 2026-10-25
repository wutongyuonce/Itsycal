import Foundation

struct WeekEvent: Codable, Identifiable {
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

struct WeekSnapshot: Codable {
    let version: Int
    let generatedAt: TimeInterval
    let timeZone: String
    let start: TimeInterval
    let end: TimeInterval
    let status: String
    let days: [String: [WeekEvent]]

    static func load() -> WeekSnapshot? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "WeekAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: container.appendingPathComponent("week.json")),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data),
              snapshot.version == 1 else { return nil }
        return snapshot
    }

    func message(at date: Date, calendar: Calendar) -> String? {
        if status == "permission" { return "打开 Itsycal，允许访问日历" }
        if status == "calendars" { return "在 Itsycal 中选择要显示的日历" }
        guard status == "ready" else { return "打开 Itsycal 更新日程" }
        if timeZone != calendar.timeZone.identifier { return "时区已改变，打开 Itsycal 更新日程" }
        let monday = WeekDates.monday(containing: date, calendar: calendar)
        let next = calendar.date(byAdding: .day, value: 7, to: monday)!
        if monday.timeIntervalSince1970 < start || next.timeIntervalSince1970 > end {
            return "打开 Itsycal 获取本周日程"
        }
        // Missing buckets mean incomplete data, never an empty calendar.
        if WeekDates.days(containing: date, calendar: calendar).contains(where: { days[WeekDates.key($0, calendar: calendar)] == nil }) {
            return "打开 Itsycal 更新日程"
        }
        return nil
    }
}

enum WeekDates {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func monday(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: day)!
    }

    static func days(containing date: Date, calendar: Calendar) -> [Date] {
        let start = monday(containing: date, calendar: calendar)
        return (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
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

    static func eventPitch(compact: Bool) -> Double { compact ? 25 : 36 }
    static func reservedHeight(compact: Bool) -> Double {
        compact ? 46 : 54 // Date, gap and overflow; header lives outside the columns.
    }

    static func capacity(height: Double, compact: Bool = true) -> Int {
        min(4, max(0, Int((height - reservedHeight(compact: compact)) / eventPitch(compact: compact))))
    }

    static func timelineDates(from date: Date, calendar: Calendar) -> [Date] {
        let midnight = calendar.startOfDay(for: date)
        return [date] + (1...14).map { calendar.date(byAdding: .day, value: $0, to: midnight)! }
    }
}
