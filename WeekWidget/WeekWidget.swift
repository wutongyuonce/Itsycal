import SwiftUI
import WidgetKit

struct WeekEntry: TimelineEntry {
    let date: Date
    let shown: Date // A date inside the displayed week.
    let snapshot: WeekSnapshot?
}

struct WeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekEntry {
        WeekEntry(date: .now, shown: .now, snapshot: .preview(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekEntry) -> Void) {
        let now = Date()
        if context.isPreview { return completion(WeekEntry(date: now, shown: now, snapshot: .preview(at: now))) }
        completion(WeekEntry(date: now, shown: WeekNavigation.load()?.shown(at: now) ?? now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekEntry>) -> Void) {
        let now = Date()
        let snapshot = WeekSnapshot.load()
        let navigation = WeekNavigation.load()
        let entries = WeekDates.timelineDates(from: now, calendar: WeekDates.calendar, navigation: navigation)
            .map { WeekEntry(date: $0, shown: navigation?.shown(at: $0) ?? $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

private struct WeekWidgetContent: View {
    let entry: WeekEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WeekView(date: entry.date, shown: entry.shown, snapshot: entry.snapshot, compact: family == .systemMedium)
    }
}

@main
struct ItsycalWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WeekShared.kind, provider: WeekProvider()) { entry in
            WeekWidgetContent(entry: entry)
                .privacySensitive()
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("本周日程")
        .description("按设置的一周起始日，一眼查看每天的安排，可切换到下周。")
        .supportedFamilies([.systemMedium, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}
