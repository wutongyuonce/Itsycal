import Foundation

extension WeekSnapshot {
    /// Synthetic this-week and next-week data for the widget gallery and
    /// offline renders; never requires calendar permission.
    static func preview(at date: Date, calendar: Calendar = WeekDates.calendar) -> WeekSnapshot {
        let weekStart = 1
        let first = WeekDates.weekStartDate(containing: date, weekStart: weekStart, calendar: calendar)
        let titles = [["项目复盘", "整理本周计划"], ["设计讨论"], ["团队例会", "产品评审"],
                      ["专注工作", "与客户沟通", "设计走查", "方案评审", "整理反馈", "阅读"], ["周度回顾"], [], ["下周计划"],
                      [], ["需求评审"], [], ["版本发布"], [], ["家庭聚会"], []]
        var days: [String: [WeekEvent]] = [:]
        for (index, dayTitles) in titles.enumerated() {
            let day = calendar.date(byAdding: .day, value: index, to: first)!
            days[WeekDates.key(day, calendar: calendar)] = dayTitles.enumerated().map { row, title in
                let start = calendar.date(bySettingHour: 8 + row * 2, minute: 30, second: 0, of: day)!
                return WeekEvent(id: "\(index)-\(row)", title: title, start: start.timeIntervalSince1970,
                                 end: start.addingTimeInterval(3600).timeIntervalSince1970,
                                 allDay: index == 4 && row == 0, spansDay: false, startsHere: true,
                                 endsHere: false, continues: false,
                                 color: row.isMultiple(of: 2) ? [0.25, 0.48, 0.75] : [0.35, 0.62, 0.49])
            }
        }
        return WeekSnapshot(version: 2, generatedAt: date.timeIntervalSince1970,
                            timeZone: calendar.timeZone.identifier, start: first.timeIntervalSince1970,
                            end: calendar.date(byAdding: .day, value: titles.count, to: first)!.timeIntervalSince1970,
                            status: "ready", weekStart: weekStart, days: days)
    }
}
