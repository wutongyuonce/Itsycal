import Combine
import EventKit
import Foundation
import SwiftUI
import WidgetKit

/// Identifies one item in the store: an event occurrence (by identifier and
/// start) or a reminder. The title is a fallback when the identifier is gone.
struct MobileItemRef: Equatable {
    let kind: AIProposedKind
    let id: String
    let start: Date
    let title: String
}

extension MobileAgendaItem {
    var ref: MobileItemRef { MobileItemRef(kind: kind, id: targetIdentifier, start: startDate, title: title) }
}

@MainActor
final class MobileEventStore: ObservableObject {
    struct CalendarSourceEntry: Identifiable, Equatable {
        let id: String
        let title: String
        let sourceTitle: String
        let allowsEvents: Bool
        let allowsReminders: Bool
        let allowsModifications: Bool
        let colorRGB: [Double]
        var isSelected: Bool
    }

    /// An item's current values for the editor, plus what the editor must know about it.
    struct EditableItem {
        var draft: AIProposedItem
        let isRecurring: Bool
        /// A recurrence the simple repeat picker can't represent; it is kept as is.
        let hasCustomRepeat: Bool
    }

    @Published private(set) var calendarAuthorized = false
    @Published private(set) var remindersAuthorized = false
    @Published var calendars: [CalendarSourceEntry] = []
    @Published private(set) var visibleMonth = Date()
    @Published private(set) var selectedDate = Date()
    @Published var weekStartDOW: Int = {
        let saved = UserDefaults.standard.object(forKey: "WeekStartDOW") as? Int
        return saved ?? max(0, min(6, Calendar.current.firstWeekday - 1))
    }() {
        didSet {
            UserDefaults.standard.set(weekStartDOW, forKey: "WeekStartDOW")
            reloadVisibleRange()
        }
    }
    @Published var agendaDays: Int = (UserDefaults.standard.object(forKey: "MobileAgendaDays") as? Int) ?? 7 {
        didSet {
            extraAgendaDays = 0
            UserDefaults.standard.set(agendaDays, forKey: "MobileAgendaDays")
            reloadVisibleRange()
        }
    }
    /// Extra days revealed by tapping the bottom "Expand" button in the agenda;
    /// resets whenever the user selects a date or changes months.
    @Published private(set) var extraAgendaDays = 0
    var totalAgendaDays: Int { max(1, agendaDays) + extraAgendaDays }
    var lookaheadHorizonDays: Int { max(MobileCalendarCore.agendaLookaheadDays, totalAgendaDays + 30) }
    @Published var showWeeks: Bool = UserDefaults.standard.bool(forKey: "ShowWeeks") {
        didSet { UserDefaults.standard.set(showWeeks, forKey: "ShowWeeks") }
    }
    @Published var showCompletedReminders: Bool = UserDefaults.standard.bool(forKey: "ShowCompletedReminders") {
        didSet {
            UserDefaults.standard.set(showCompletedReminders, forKey: "ShowCompletedReminders")
            reloadVisibleRange()
        }
    }
    @Published private(set) var itemsByDay: [Date: [MobileAgendaItem]] = [:]
    @Published private(set) var overdueReminders: [MobileAgendaItem] = []
    @Published private(set) var topUndoSummary: String?
    var canUndo: Bool { topUndoSummary != nil }
    /// A failed write the user didn't start from a form (undo, swipe delete), shown as an alert.
    @Published var lastError: String?

    private struct UndoEntry {
        let summary: String
        let perform: (MobileEventStore) -> Void
    }

    private let store = EKEventStore()
    private let selectedCalendarsKey = "SelectedCalendars"
    private var undoStack: [UndoEntry] = [] {
        didSet { topUndoSummary = undoStack.last?.summary }
    }
    private var isPerformingUndo = false
    private var storeObserver: NSObjectProtocol?
    /// Bumped on every reload so a slow reminder fetch can't overwrite a newer one.
    private var reloadGeneration = 0

    init() {
        refreshAuthorizationStatus()
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadAll()
            }
        }
    }

    deinit {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
    }

    // MARK: - Access

    func refreshAuthorizationStatus() {
        calendarAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func requestInitialAccess() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        reloadAll()
    }

    func requestRemindersAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        reloadAll()
        return remindersAuthorized
    }

    // MARK: - Navigation

    func select(_ day: Date) {
        extraAgendaDays = 0
        selectedDate = day
        if !Calendar.autoupdatingCurrent.isDate(day, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = day
        }
        reloadVisibleRange()
    }

    func shiftMonth(by months: Int) {
        guard let month = Calendar.autoupdatingCurrent.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        extraAgendaDays = 0
        visibleMonth = month
        reloadVisibleRange()
    }

    func setYearMonth(year: Int, month: Int) {
        let cal = Calendar.autoupdatingCurrent
        let target = MobileCalendarCore.date(bySettingYear: year, month: month, of: selectedDate, calendar: cal)
        extraAgendaDays = 0
        visibleMonth = target
        selectedDate = target
        reloadVisibleRange()
    }

    func expandAgenda(by days: Int) {
        guard days > 0 else { return }
        let oldHorizon = lookaheadHorizonDays
        extraAgendaDays += days
        if lookaheadHorizonDays > oldHorizon {
            reloadVisibleRange()
        }
    }

    func goToToday() {
        select(Date())
    }

    // MARK: - Calendars

    func toggleCalendarSelection(id: String) {
        guard let idx = calendars.firstIndex(where: { $0.id == id }) else { return }
        calendars[idx].isSelected.toggle()
        UserDefaults.standard.set(calendars.filter(\.isSelected).map(\.id), forKey: selectedCalendarsKey)
        reloadVisibleRange()
    }

    func writableCalendars(for kind: AIProposedKind) -> [CalendarSourceEntry] {
        calendars.filter { $0.allowsModifications && (kind == .event ? $0.allowsEvents : $0.allowsReminders) }
    }

    /// The system default calendar or list for new items, if writable, else the first writable one.
    func defaultCalendarID(for kind: AIProposedKind) -> String {
        let systemDefault = kind == .event
            ? store.defaultCalendarForNewEvents?.calendarIdentifier
            : store.defaultCalendarForNewReminders()?.calendarIdentifier
        let options = writableCalendars(for: kind)
        if let systemDefault, options.contains(where: { $0.id == systemDefault }) { return systemDefault }
        return options.first?.id ?? ""
    }

    /// Also runs on every EventKit change, including the app's own writes,
    /// so it is where the iOS widgets are told to rebuild their snapshot.
    func reloadAll() {
        refreshAuthorizationStatus()
        loadCalendars()
        reloadVisibleRange()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadCalendars() {
        let savedIDs = Set(UserDefaults.standard.stringArray(forKey: selectedCalendarsKey) ?? [])
        let hasSavedPreference = UserDefaults.standard.object(forKey: selectedCalendarsKey) != nil
        var entries: [CalendarSourceEntry] = []
        var seen = Set<String>()

        func append(_ type: EKEntityType, sourceSuffix: String) {
            let sorted = store.calendars(for: type).sorted {
                if $0.source.sourceIdentifier == $1.source.sourceIdentifier {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.source.title.localizedStandardCompare($1.source.title) == .orderedAscending
            }
            for cal in sorted where seen.insert(cal.calendarIdentifier).inserted {
                entries.append(CalendarSourceEntry(
                    id: cal.calendarIdentifier,
                    title: cal.title,
                    sourceTitle: cal.source.title + sourceSuffix,
                    allowsEvents: type == .event,
                    allowsReminders: cal.allowedEntityTypes.contains(.reminder),
                    allowsModifications: cal.allowsContentModifications,
                    colorRGB: cal.rgb,
                    isSelected: hasSavedPreference ? savedIDs.contains(cal.calendarIdentifier) : true
                ))
            }
        }
        if calendarAuthorized { append(.event, sourceSuffix: "") }
        if remindersAuthorized { append(.reminder, sourceSuffix: " 提醒事项") }

        calendars = entries
        if !hasSavedPreference && !entries.isEmpty {
            UserDefaults.standard.set(entries.map(\.id), forKey: selectedCalendarsKey)
        }
    }

    // MARK: - Fetching

    /// Fetches the visible month grid plus the agenda days after the selected date.
    func reloadVisibleRange() {
        reloadGeneration += 1
        let generation = reloadGeneration
        let cal = Calendar.autoupdatingCurrent
        let gridWeeks = MobileCalendarCore.monthGrid(containing: visibleMonth, weekStartDOW: weekStartDOW, calendar: cal)
        guard let firstGridDay = gridWeeks.first?.first, let lastGridDay = gridWeeks.last?.last else { return }

        let selectedStart = cal.startOfDay(for: selectedDate)
        let agendaEnd = cal.date(byAdding: .day, value: lookaheadHorizonDays, to: selectedStart)!
        let rangeStart = min(firstGridDay, selectedStart)
        let rangeEnd = max(cal.date(byAdding: .day, value: 1, to: lastGridDay)!, agendaEnd)
        let selectedCalIDs = Set(calendars.filter(\.isSelected).map(\.id))
        var bucket: [Date: [MobileAgendaItem]] = [:]

        if calendarAuthorized {
            let ekCals = store.calendars(for: .event).filter { selectedCalIDs.contains($0.calendarIdentifier) }
            if !ekCals.isEmpty {
                let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: ekCals)
                for ev in store.events(matching: predicate) {
                    let targetID = Self.identifier(of: ev)
                    let rgb = ev.calendar.rgb
                    let meeting = MobileCalendarCore.detectMeetingURL(in: [ev.location, ev.url?.absoluteString, ev.notes])
                    let covered = DayItems.coveredDays(
                        start: ev.startDate,
                        end: ev.endDate,
                        isAllDay: ev.isAllDay,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        calendar: cal
                    )
                    for cov in covered {
                        bucket[cov.day, default: []].append(MobileAgendaItem(
                            id: "\(targetID)-\(ev.startDate.timeIntervalSince1970)-\(cov.day.timeIntervalSince1970)",
                            targetIdentifier: targetID,
                            kind: .event,
                            title: ev.title ?? "",
                            day: cov.day,
                            startDate: ev.startDate,
                            endDate: ev.endDate,
                            isAllDay: cov.spansWholeDay,
                            isRealAllDay: ev.isAllDay,
                            hasTime: !ev.isAllDay,
                            calendarID: ev.calendar.calendarIdentifier,
                            calendarTitle: ev.calendar.title,
                            colorRGB: rgb,
                            location: ev.location,
                            notes: ev.notes,
                            meetingURL: meeting,
                            isEditable: ev.calendar.allowsContentModifications,
                            isRecurring: ev.hasRecurrenceRules
                        ))
                    }
                }
            }
        }

        let remLists = remindersAuthorized
            ? store.calendars(for: .reminder).filter { selectedCalIDs.contains($0.calendarIdentifier) }
            : []
        guard !remLists.isEmpty else {
            finalizeBuckets(bucket, overdue: [])
            return
        }
        Task {
            let reminders = await fetchReminders(in: remLists, includeCompleted: showCompletedReminders)
            guard generation == reloadGeneration else { return }
            mergeReminders(reminders, rangeStart: rangeStart, rangeEnd: rangeEnd, baseBucket: bucket)
        }
    }

    private func fetchReminders(in lists: [EKCalendar], includeCompleted: Bool) async -> [EKReminder] {
        let incomplete: [EKReminder] = await withCheckedContinuation { cont in
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        guard includeCompleted else { return incomplete }
        let completed: [EKReminder] = await withCheckedContinuation { cont in
            let pred = store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: lists)
            store.fetchReminders(matching: pred) { cont.resume(returning: $0 ?? []) }
        }
        return incomplete + completed
    }

    private func mergeReminders(_ reminders: [EKReminder], rangeStart: Date, rangeEnd: Date, baseBucket: [Date: [MobileAgendaItem]]) {
        let cal = Calendar.autoupdatingCurrent
        let todayStart = cal.startOfDay(for: Date())
        var bucket = baseBucket
        var overdue: [MobileAgendaItem] = []

        for rem in reminders {
            guard let (dueDate, hasTime) = rem.dueDateAndHasTime else { continue }
            let day = cal.startOfDay(for: dueDate)
            let isOverdue = !rem.isCompleted && dueDate < todayStart
            func item(id: String, overdue: Bool) -> MobileAgendaItem {
                MobileAgendaItem(
                    id: id,
                    targetIdentifier: rem.calendarItemIdentifier,
                    kind: .reminder,
                    title: rem.title ?? "",
                    day: day,
                    startDate: dueDate,
                    endDate: dueDate,
                    isAllDay: !hasTime,
                    isRealAllDay: !hasTime,
                    hasTime: hasTime,
                    isCompleted: rem.isCompleted,
                    isOverdue: overdue,
                    calendarID: rem.calendar.calendarIdentifier,
                    calendarTitle: rem.calendar.title,
                    colorRGB: rem.calendar.rgb,
                    location: rem.location,
                    notes: rem.notes,
                    isEditable: rem.calendar.allowsContentModifications,
                    isRecurring: rem.hasRecurrenceRules
                )
            }
            if isOverdue {
                overdue.append(item(id: "overdue-\(rem.calendarItemIdentifier)", overdue: true))
            }
            if day >= rangeStart && day < rangeEnd {
                bucket[day, default: []].append(item(id: "rem-\(rem.calendarItemIdentifier)", overdue: false))
            }
        }
        overdue.sort { $0.startDate > $1.startDate }
        finalizeBuckets(bucket, overdue: overdue)
    }

    private func finalizeBuckets(_ raw: [Date: [MobileAgendaItem]], overdue: [MobileAgendaItem]) {
        itemsByDay = raw.mapValues { DayItems.sorted($0) }
        overdueReminders = overdue
    }

    // MARK: - Editing

    func toggleReminderCompletion(_ item: MobileAgendaItem) {
        guard item.kind == .reminder,
              let rem = store.calendarItem(withIdentifier: item.targetIdentifier) as? EKReminder else { return }
        rem.isCompleted.toggle()
        let summary = "\(rem.isCompleted ? "勾选完成" : "取消完成")提醒事项「\(item.title)」"
        do {
            try store.save(rem, commit: true)
            registerUndo(summary: summary) { $0.toggleReminderCompletion(item) }
        } catch {
            store.reset()
            report(error)
        }
        reloadVisibleRange()
    }

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    func editableItem(for ref: MobileItemRef) -> EditableItem? {
        switch resolve(ref) {
        case let ev as EKEvent:
            let rule = ev.recurrenceRules?.first
            return EditableItem(
                draft: Self.snapshot(from: ev),
                isRecurring: ev.hasRecurrenceRules,
                hasCustomRepeat: rule != nil && Self.repeatFrequency(of: rule) == nil
            )
        case let rem as EKReminder:
            let rule = rem.recurrenceRules?.first
            return EditableItem(
                draft: Self.snapshot(from: rem),
                isRecurring: rem.hasRecurrenceRules,
                hasCustomRepeat: rule != nil && Self.repeatFrequency(of: rule) == nil
            )
        default:
            return nil
        }
    }

    /// Saves `draft` over the item. The recurrence is only rewritten when its
    /// frequency changed, so rules the editor can't represent survive edits.
    func update(_ ref: MobileItemRef, to draft: AIProposedItem, futureOccurrences: Bool) throws {
        guard let object = resolve(ref) else {
            throw AICodeModeError.llmError("未找到「\(ref.title)」，它可能已被删除。")
        }
        let previous: AIProposedItem
        do {
            switch object {
            case let ev as EKEvent:
                previous = Self.snapshot(from: ev)
                guard draft.hasMeaningfulChanges(comparedTo: previous, calendar: .autoupdatingCurrent) else { return }
                // A changed repeat always applies to the series; EventKit can't
                // give a single occurrence its own recurrence.
                let repeatChanged = draft.repeatFrequency != previous.repeatFrequency
                let span: EKSpan = (futureOccurrences || repeatChanged) && ev.hasRecurrenceRules ? .futureEvents : .thisEvent
                try fill(ev, from: draft, updateRecurrence: repeatChanged)
                try store.save(ev, span: span, commit: true)
            case let rem as EKReminder:
                previous = Self.snapshot(from: rem)
                guard draft.hasMeaningfulChanges(comparedTo: previous, calendar: .autoupdatingCurrent) else { return }
                try fill(rem, from: draft, updateRecurrence: draft.repeatFrequency != previous.repeatFrequency)
                try store.save(rem, commit: true)
            default:
                return
            }
        } catch {
            store.reset()
            reloadVisibleRange()
            throw error
        }
        let updated = MobileItemRef(kind: ref.kind, id: Self.identifier(of: object), start: draft.startDate, title: draft.title)
        let noun = ref.kind == .reminder ? "提醒事项" : "日程"
        registerUndo(summary: "修改\(noun)「\(draft.title)」") { store in
            do { try store.update(updated, to: previous, futureOccurrences: futureOccurrences) } catch { store.report(error) }
        }
        select(draft.startDate)
    }

    func delete(_ ref: MobileItemRef, futureOccurrences: Bool) throws {
        try applyBatchChanges([AIProposedItem(
            operation: .delete,
            kind: ref.kind,
            targetIdentifier: ref.id,
            deleteFutureOccurrences: futureOccurrences,
            title: ref.title,
            startDate: ref.start,
            endDate: ref.start,
            calendarID: "",
            calendarTitle: ""
        )])
    }

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        isPerformingUndo = true
        defer { isPerformingUndo = false }
        entry.perform(self)
    }

    /// Creates and deletes `items` in one commit, or none of them. Registers the
    /// inverse batch as the undo; undoing it registers the redo the same way.
    func applyBatchChanges(_ items: [AIProposedItem]) throws {
        guard !items.isEmpty else { return }
        var inverse: [AIProposedItem] = []
        var created: [(object: EKCalendarItem, item: AIProposedItem)] = []

        do {
            for item in items {
                if item.operation == .delete {
                    let ref = MobileItemRef(kind: item.kind, id: item.targetIdentifier ?? "", start: item.startDate, title: item.title)
                    switch resolve(ref) {
                    case let ev as EKEvent:
                        let future = item.deleteFutureOccurrences && ev.hasRecurrenceRules
                        var restore = Self.snapshot(from: ev)
                        if !future {
                            restore.repeatFrequency = .none
                            restore.repeatEndDate = nil
                        }
                        inverse.append(restore)
                        try store.remove(ev, span: future ? .futureEvents : .thisEvent, commit: false)
                    case let rem as EKReminder:
                        inverse.append(Self.snapshot(from: rem))
                        try store.remove(rem, commit: false)
                    default:
                        throw AICodeModeError.llmError("未找到要删除的「\(item.title)」")
                    }
                } else if item.kind == .event {
                    let ev = EKEvent(eventStore: store)
                    try fill(ev, from: item, updateRecurrence: true)
                    try store.save(ev, span: .thisEvent, commit: false)
                    created.append((ev, item))
                } else {
                    let rem = EKReminder(eventStore: store)
                    try fill(rem, from: item, updateRecurrence: true)
                    try store.save(rem, commit: false)
                    created.append((rem, item))
                }
            }
            try store.commit()
        } catch {
            store.reset()
            reloadVisibleRange()
            throw error
        }

        // Identifiers are assigned on commit.
        for (object, item) in created {
            inverse.append(AIProposedItem(
                operation: .delete,
                kind: item.kind,
                targetIdentifier: Self.identifier(of: object),
                deleteFutureOccurrences: item.repeatFrequency != .none,
                title: item.title,
                startDate: (object as? EKEvent)?.startDate ?? item.startDate,
                endDate: item.endDate,
                calendarID: "",
                calendarTitle: ""
            ))
        }
        registerUndo(summary: Self.undoSummary(for: items)) { store in
            do { try store.applyBatchChanges(inverse) } catch { store.report(error) }
        }
        if let first = items.first {
            select(first.startDate)
        }
    }

    private func registerUndo(summary: String, _ action: @escaping (MobileEventStore) -> Void) {
        guard !isPerformingUndo else { return }
        undoStack.append(UndoEntry(summary: summary, perform: action))
    }

    private static func undoSummary(for items: [AIProposedItem]) -> String {
        if items.count == 1, let item = items.first {
            let verb = item.operation == .delete ? "删除" : "新建"
            let noun = item.kind == .reminder ? "提醒事项" : "日程"
            return "\(verb)\(noun)「\(item.title)」"
        }
        let addCount = items.filter { $0.operation == .create }.count
        let delCount = items.filter { $0.operation == .delete }.count
        var parts: [String] = []
        if addCount > 0 { parts.append("新增 \(addCount) 项") }
        if delCount > 0 { parts.append("删除 \(delCount) 项") }
        let firstTitle = items.first.map { "「\($0.title)」等" } ?? ""
        return "批量操作（\(parts.joined(separator: "、")) \(firstTitle)）"
    }

    private func fill(_ ev: EKEvent, from item: AIProposedItem, updateRecurrence: Bool) throws {
        guard let calendar = writableEKCalendar(id: item.calendarID, kind: .event) else {
            throw AICodeModeError.llmError("未找到可写入的日历")
        }
        ev.calendar = calendar
        ev.title = item.title
        ev.location = item.location
        ev.url = item.urlString.flatMap(URL.init(string:))
        ev.notes = item.notes
        ev.isAllDay = item.isAllDay
        ev.startDate = item.startDate
        ev.endDate = item.endDate
        if item.isAllDay {
            ev.timeZone = nil
        } else if ev.timeZone == nil {
            ev.timeZone = .current
        }
        if updateRecurrence {
            ev.recurrenceRules = Self.makeRecurrenceRule(frequency: item.repeatFrequency, endDate: item.repeatEndDate).map { [$0] }
        }
        if let minutes = item.alertMinutesBefore {
            ev.alarms = [EKAlarm(relativeOffset: TimeInterval(-minutes * 60))]
        }
    }

    private func fill(_ rem: EKReminder, from item: AIProposedItem, updateRecurrence: Bool) throws {
        guard let list = writableEKCalendar(id: item.calendarID, kind: .reminder) else {
            throw AICodeModeError.llmError("未找到可写入的提醒事项列表")
        }
        rem.calendar = list
        rem.title = item.title
        rem.url = item.urlString.flatMap(URL.init(string:))
        rem.notes = item.notes
        rem.priority = item.priority
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        var units: Set<Calendar.Component> = [.year, .month, .day]
        if item.hasTime { units.formUnion([.hour, .minute]) }
        var due = gregorian.dateComponents(units, from: item.startDate)
        due.calendar = gregorian
        if item.hasTime { due.timeZone = .current }
        rem.dueDateComponents = due
        if updateRecurrence {
            let rule = Self.makeRecurrenceRule(frequency: item.repeatFrequency, endDate: item.repeatEndDate)
            rem.recurrenceRules = rule.map { [$0] }
        }
        rem.startDateComponents = rem.hasRecurrenceRules ? due : nil
        if let minutes = item.alertMinutesBefore {
            rem.alarms = [EKAlarm(absoluteDate: item.startDate.addingTimeInterval(TimeInterval(-minutes * 60)))]
        }
    }

    private func writableEKCalendar(id: String, kind: AIProposedKind) -> EKCalendar? {
        let writable = store.calendars(for: kind == .event ? .event : .reminder).filter(\.allowsContentModifications)
        let systemDefault = kind == .event ? store.defaultCalendarForNewEvents : store.defaultCalendarForNewReminders()
        return writable.first { $0.calendarIdentifier == id }
            ?? writable.first { $0.calendarIdentifier == systemDefault?.calendarIdentifier }
            ?? writable.first
    }

    private func resolve(_ ref: MobileItemRef) -> EKCalendarItem? {
        switch ref.kind {
        case .event: return resolveEvent(ref)
        case .reminder: return resolveReminder(ref)
        }
    }

    /// Prefers the exact occurrence, since every occurrence of a recurring event
    /// shares one identifier and `event(withIdentifier:)` returns the first.
    /// Matching by title is only for refs without an identifier (AI proposals);
    /// a known identifier that no longer resolves means the item is gone.
    private func resolveEvent(_ ref: MobileItemRef) -> EKEvent? {
        let predicate = store.predicateForEvents(withStart: ref.start.addingTimeInterval(-1), end: ref.start.addingTimeInterval(86_400), calendars: nil)
        let candidates = store.events(matching: predicate)
        guard !ref.id.isEmpty else {
            return candidates.first { $0.title == ref.title }
        }
        return candidates.first { Self.identifier(of: $0) == ref.id && $0.startDate == ref.start }
            ?? store.event(withIdentifier: ref.id)
    }

    private func resolveReminder(_ ref: MobileItemRef) -> EKReminder? {
        guard ref.id.isEmpty else {
            return store.calendarItem(withIdentifier: ref.id) as? EKReminder
        }
        let cal = Calendar.autoupdatingCurrent
        let known = itemsByDay.values.joined().filter { $0.kind == .reminder } + overdueReminders
        guard let match = known.first(where: { $0.title == ref.title && cal.isDate($0.startDate, inSameDayAs: ref.start) }) else {
            return nil
        }
        return store.calendarItem(withIdentifier: match.targetIdentifier) as? EKReminder
    }

    // MARK: - AI Host Bridge (3-year chunked range queries)

    func buildAIHostContext(currentDrafts: [AIProposedItem]) -> AICodeModeHostContext {
        let defaultEventID = store.defaultCalendarForNewEvents?.calendarIdentifier
        let defaultReminderID = store.defaultCalendarForNewReminders()?.calendarIdentifier
        let descriptors = calendars.filter(\.allowsModifications).map { c in
            AICalendarDescriptor(
                id: c.id,
                title: c.title,
                source: c.sourceTitle,
                allowsEvents: c.allowsEvents,
                allowsReminders: c.allowsReminders,
                isDefaultEvent: c.id == defaultEventID,
                isDefaultReminder: c.id == defaultReminderID,
                colorRGB: c.colorRGB
            )
        }

        var existing: [AIExistingEventSnapshot] = []
        var seen = Set<String>()
        for item in itemsByDay.values.joined() + overdueReminders
        where seen.insert("\(item.targetIdentifier)-\(item.startDate.timeIntervalSince1970)").inserted {
            existing.append(AIExistingEventSnapshot(
                id: item.targetIdentifier,
                title: item.title,
                start: item.startDate,
                end: item.endDate,
                isAllDay: item.isRealAllDay,
                calendarID: item.calendarID,
                calendarTitle: item.calendarTitle,
                colorRGB: item.colorRGB,
                kind: item.kind
            ))
        }

        let storeRef = store
        let isCalAuth = calendarAuthorized
        return AICodeModeHostContext(
            now: Date(),
            selectedDate: selectedDate,
            timeZone: .current,
            calendars: descriptors,
            existingEvents: existing,
            currentDrafts: currentDrafts,
            sessions: AISessionStore.loadArchive().sessions,
            queryRangeProvider: { [existing] start, end in
                guard start < end else { return [] }
                var snaps: [AIExistingEventSnapshot] = []
                if isCalAuth {
                    let cals = storeRef.calendars(for: .event)
                    if !cals.isEmpty {
                        let cal = Calendar.autoupdatingCurrent
                        var seenKeys = Set<String>()
                        var chunkStart = start
                        // EventKit truncates a single query to 4 years.
                        while chunkStart < end {
                            let chunkEnd = min(cal.date(byAdding: .year, value: 3, to: chunkStart) ?? end, end)
                            let pred = storeRef.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: cals)
                            for ev in storeRef.events(matching: pred) {
                                let id = Self.identifier(of: ev)
                                guard seenKeys.insert("\(id)-\(ev.startDate.timeIntervalSince1970)").inserted else { continue }
                                snaps.append(AIExistingEventSnapshot(
                                    id: id,
                                    title: ev.title ?? "",
                                    start: ev.startDate,
                                    end: ev.endDate,
                                    isAllDay: ev.isAllDay,
                                    calendarID: ev.calendar.calendarIdentifier,
                                    calendarTitle: ev.calendar.title,
                                    colorRGB: ev.calendar.rgb,
                                    kind: .event
                                ))
                            }
                            chunkStart = chunkEnd
                        }
                    }
                }
                for rem in existing where rem.kind == .reminder && rem.start >= start && rem.start < end {
                    snaps.append(rem)
                }
                return snaps
            }
        )
    }

    // MARK: - Conversions

    nonisolated private static func identifier(of object: EKCalendarItem) -> String {
        (object as? EKEvent)?.eventIdentifier ?? object.calendarItemIdentifier
    }

    private static func snapshot(from ev: EKEvent) -> AIProposedItem {
        let rule = ev.recurrenceRules?.first
        return AIProposedItem(
            kind: .event,
            title: ev.title ?? "",
            startDate: ev.startDate,
            endDate: ev.endDate,
            isAllDay: ev.isAllDay,
            hasTime: !ev.isAllDay,
            calendarID: ev.calendar.calendarIdentifier,
            calendarTitle: ev.calendar.title,
            calendarColorRGB: ev.calendar.rgb,
            location: ev.location,
            urlString: ev.url?.absoluteString,
            notes: ev.notes,
            repeatFrequency: repeatFrequency(of: rule) ?? AIRepeatFrequency.none,
            repeatEndDate: rule?.recurrenceEnd?.endDate
        )
    }

    private static func snapshot(from rem: EKReminder) -> AIProposedItem {
        let (due, hasTime) = rem.dueDateAndHasTime ?? (Date(), false)
        let rule = rem.recurrenceRules?.first
        return AIProposedItem(
            kind: .reminder,
            title: rem.title ?? "",
            startDate: due,
            endDate: due,
            isAllDay: !hasTime,
            hasTime: hasTime,
            calendarID: rem.calendar.calendarIdentifier,
            calendarTitle: rem.calendar.title,
            calendarColorRGB: rem.calendar.rgb,
            urlString: rem.url?.absoluteString,
            notes: rem.notes,
            repeatFrequency: repeatFrequency(of: rule) ?? AIRepeatFrequency.none,
            repeatEndDate: rule?.recurrenceEnd?.endDate,
            priority: rem.priority
        )
    }

    /// The picker frequency for a rule; `.none` without a rule, nil when the rule
    /// has extra constraints (several weekdays, set positions…) the picker can't show.
    private static func repeatFrequency(of rule: EKRecurrenceRule?) -> AIRepeatFrequency? {
        guard let rule else { return AIRepeatFrequency.none }
        guard (rule.daysOfTheWeek?.count ?? 0) <= 1,
              rule.daysOfTheMonth == nil,
              rule.daysOfTheYear == nil,
              rule.weeksOfTheYear == nil,
              rule.monthsOfTheYear == nil,
              rule.setPositions == nil,
              (rule.recurrenceEnd?.occurrenceCount ?? 0) == 0 else { return nil }
        switch (rule.frequency, rule.interval) {
        case (.daily, 1): return .daily
        case (.weekly, 1): return .weekly
        case (.weekly, 2): return .biweekly
        case (.monthly, 1): return .monthly
        case (.yearly, 1): return .yearly
        default: return nil
        }
    }

    private static func makeRecurrenceRule(frequency: AIRepeatFrequency, endDate: Date?) -> EKRecurrenceRule? {
        let end = endDate.map { EKRecurrenceEnd(end: $0) }
        switch frequency {
        case .none: return nil
        case .daily: return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: end)
        case .weekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: end)
        case .biweekly: return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: end)
        case .monthly: return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: end)
        case .yearly: return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: end)
        }
    }

}
