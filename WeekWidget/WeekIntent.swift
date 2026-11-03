import AppIntents

/// Widget button action: show next week, or return to the current week.
struct SwitchWeekIntent: AppIntent {
    static let title: LocalizedStringResource = "切换本周/下周"
    static let isDiscoverable = false

    @Parameter(title: "显示下周", default: false) var next: Bool

    init() {}
    init(next: Bool) { self.next = next }

    func perform() async throws -> some IntentResult {
        WeekNavigation.store(next ? .nextWeek(from: .now, calendar: WeekDates.calendar) : nil)
        return .result() // WidgetKit reloads the timeline after a widget intent.
    }
}
