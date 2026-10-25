import SwiftUI
import WidgetKit

struct WeekEntry: TimelineEntry {
    let date: Date
    let snapshot: WeekSnapshot?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        completion(WeekEntry(date: .now, snapshot: context.isPreview ? .preview : .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let now = Date()
        let snapshot = WeekSnapshot.load()
        let entries = WeekDates.timelineDates(from: now, calendar: WeekDates.calendar)
            .map { WeekEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

private struct WeekWidgetContent: View {
    let entry: WeekEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WeekView(date: entry.date, snapshot: entry.snapshot, compact: family == .systemMedium)
    }
}

@main
struct ItsycalWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ItsycalWeek", provider: WeekProvider()) { entry in
            WeekWidgetContent(entry: entry)
                .privacySensitive()
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("本周日程")
        .description("从周一到周日，一眼查看每天的安排。")
        .supportedFamilies([.systemMedium, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

extension WeekSnapshot {
    // Gallery data is synthetic and never requires calendar permission.
    static var preview: WeekSnapshot {
        let calendar = WeekDates.calendar
        let now = Date()
        let monday = WeekDates.monday(containing: now, calendar: calendar)
        let titles = [["项目复盘", "整理本周计划"], ["设计讨论"], ["团队例会", "产品评审", "方案同步", "整理反馈", "阅读"], ["专注工作", "与客户沟通"], ["周度回顾"], [], ["下周计划"]]
        var days: [String: [WeekEvent]] = [:]
        for (index, day) in WeekDates.days(containing: now, calendar: calendar).enumerated() {
            days[WeekDates.key(day, calendar: calendar)] = titles[index].enumerated().map { item, title in
                let start = calendar.date(bySettingHour: 9 + item * 2, minute: 0, second: 0, of: day)!
                return WeekEvent(id: "\(index)-\(item)", title: title, start: start.timeIntervalSince1970,
                                 end: start.addingTimeInterval(3600).timeIntervalSince1970,
                                 allDay: false, spansDay: false, startsHere: true,
                                 endsHere: false, continues: false,
                                 color: item.isMultiple(of: 2) ? [0.25, 0.48, 0.75] : [0.35, 0.62, 0.49])
            }
        }
        return WeekSnapshot(version: 1, generatedAt: now.timeIntervalSince1970,
                            timeZone: calendar.timeZone.identifier, start: monday.timeIntervalSince1970,
                            end: calendar.date(byAdding: .day, value: 7, to: monday)!.timeIntervalSince1970,
                            status: "ready", days: days)
    }
}
