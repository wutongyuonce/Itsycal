import AppIntents
import WidgetKit

extension WidgetPeriod: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "周期"
    static let caseDisplayRepresentations: [WidgetPeriod: DisplayRepresentation] = [.week: "周", .month: "月"]
}

/// Widget button action: show the next week/month, or return to the current one.
struct SwitchPeriodIntent: AppIntent {
    static let title: LocalizedStringResource = "切换到下一周期或返回"
    static let isDiscoverable = false

    @Parameter(title: "周期", default: .week) var period: WidgetPeriod
    @Parameter(title: "显示下一周期", default: false) var next: Bool

    init() {}
    init(_ period: WidgetPeriod, next: Bool) {
        self.period = period
        self.next = next
    }

    func perform() async throws -> some IntentResult {
        PeriodNavigation.store(next ? .next(period, from: .now, calendar: WeekDates.calendar) : nil, for: period)
        // WidgetKit reloads the tapped widget; other instances share the state.
        WidgetCenter.shared.reloadTimelines(ofKind: period.kind)
        return .result()
    }
}
