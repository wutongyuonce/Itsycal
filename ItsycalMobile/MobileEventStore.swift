import Combine
import EventKit
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class MobileEventStore: ObservableObject {
    public struct CalendarSourceEntry: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let sourceTitle: String
        public let allowsEvents: Bool
        public let allowsReminders: Bool
        public let allowsModifications: Bool
        public let colorRGB: [Double]
        public var isSelected: Bool
    }

    @Published public private(set) var calendarAuthorized: Bool = false
    @Published public private(set) var remindersAuthorized: Bool = false
    @Published public var calendars: [CalendarSourceEntry] = []
    @Published public var visibleMonth: Date = Date()
    @Published public var selectedDate: Date = Date()
    @Published public var weekStartDOW: Int = {
        let saved = UserDefaults.standard.object(forKey: "WeekStartDOW") as? Int
        return saved ?? max(0, min(6, Calendar.current.firstWeekday - 1))
    }() {
        didSet {
            UserDefaults.standard.set(weekStartDOW, forKey: "WeekStartDOW")
            reloadVisibleRange()
        }
    }
    @Published public var agendaDays: Int = {
        let saved = UserDefaults.standard.object(forKey: "MobileAgendaDays") as? Int
        return saved ?? 7
    }() {
        didSet {
            UserDefaults.standard.set(agendaDays, forKey: "MobileAgendaDays")
            reloadVisibleRange()
        }
    }
    @Published public var showWeeks: Bool = UserDefaults.standard.bool(forKey: "ShowWeeks") {
        didSet { UserDefaults.standard.set(showWeeks, forKey: "ShowWeeks") }
    }
    @Published public var showCompletedReminders: Bool = UserDefaults.standard.bool(forKey: "ShowCompletedReminders") {
        didSet {
            UserDefaults.standard.set(showCompletedReminders, forKey: "ShowCompletedReminders")
            reloadVisibleRange()
        }
    }
    @Published public private(set) var itemsByDay: [Date: [MobileAgendaItem]] = [:]
    @Published public private(set) var overdueReminders: [MobileAgendaItem] = []

    private let store = EKEventStore()
    private let selectedCalendarsKey = "SelectedCalendars"
    public let undoManager = UndoManager()
    private var storeObserver: NSObjectProtocol?

    public init() {
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

    public func refreshAuthorizationStatus() {
        calendarAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    public func requestInitialAccess() async {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        refreshAuthorizationStatus()
        reloadAll()
    }

    public func requestRemindersAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        refreshAuthorizationStatus()
        reloadAll()
        return remindersAuthorized
    }

    public func toggleCalendarSelection(id: String) {
        guard let idx = calendars.firstIndex(where: { $0.id == id }) else { return }
        calendars[idx].isSelected.toggle()
        let selectedIDs = calendars.filter(\.isSelected).map(\.id)
        UserDefaults.standard.set(selectedIDs, forKey: selectedCalendarsKey)
        reloadVisibleRange()
    }

    public func reloadAll() {
        refreshAuthorizationStatus()
        loadCalendars()
        reloadVisibleRange()
    }

    private func loadCalendars() {
        let savedIDs = Set(UserDefaults.standard.stringArray(forKey: selectedCalendarsKey) ?? [])
        let hasSavedPreference = UserDefaults.standard.object(forKey: selectedCalendarsKey) != nil

        var entries: [CalendarSourceEntry] = []
        var seen = Set<String>()

        if calendarAuthorized {
            let evCals = store.calendars(for: .event).sorted {
                if $0.source.sourceIdentifier == $1.source.sourceIdentifier {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.source.title.localizedStandardCompare($1.source.title) == .orderedAscending
            }
            for cal in evCals where seen.insert(cal.calendarIdentifier).inserted {
                let rgb = Self.extractRGB(from: cal.cgColor)
                let selected = hasSavedPreference ? savedIDs.contains(cal.calendarIdentifier) : true
                entries.append(CalendarSourceEntry(
                    id: cal.calendarIdentifier,
                    title: cal.title,
                    sourceTitle: cal.source.title,
                    allowsEvents: true,
                    allowsReminders: (cal.allowedEntityTypes.contains(.reminder)),
                    allowsModifications: cal.allowsContentModifications,
                    colorRGB: rgb,
                    isSelected: selected
                ))
            }
        }

        if remindersAuthorized {
            let remCals = store.calendars(for: .reminder).sorted {
                if $0.source.sourceIdentifier == $1.source.sourceIdentifier {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return $0.source.title.localizedStandardCompare($1.source.title) == .orderedAscending
            }
            for cal in remCals where seen.insert(cal.calendarIdentifier).inserted {
                let rgb = Self.extractRGB(from: cal.cgColor)
                let selected = hasSavedPreference ? savedIDs.contains(cal.calendarIdentifier) : true
                entries.append(CalendarSourceEntry(
                    id: cal.calendarIdentifier,
                    title: cal.title,
                    sourceTitle: "\(cal.source.title) 提醒事项",
                    allowsEvents: false,
                    allowsReminders: true,
                    allowsModifications: cal.allowsContentModifications,
                    colorRGB: rgb,
                    isSelected: selected
                ))
            }
        }

        calendars = entries
        if !hasSavedPreference && !entries.isEmpty {
            UserDefaults.standard.set(entries.map(\.id), forKey: selectedCalendarsKey)
        }
    }

    public func reloadVisibleRange() {
        let cal = Calendar.autoupdatingCurrent
        let gridWeeks = MobileCalendarCore.monthGrid(containing: visibleMonth, weekStartDOW: weekStartDOW, calendar: cal)
        guard let firstGridDay = gridWeeks.first?.first,
              let lastGridDay = gridWeeks.last?.last else { return }

        let selectedStart = cal.startOfDay(for: selectedDate)
        let agendaEnd = cal.date(byAdding: .day, value: max(1, agendaDays) + 1, to: selectedStart)!
        let rangeStart = min(firstGridDay, selectedStart)
        let rangeEnd = max(cal.date(byAdding: .day, value: 1, to: lastGridDay)!, agendaEnd)

        let selectedCalIDs = Set(calendars.filter(\.isSelected).map(\.id))
        var bucket: [Date: [MobileAgendaItem]] = [:]

        if calendarAuthorized {
            let ekCals = store.calendars(for: .event).filter { selectedCalIDs.contains($0.calendarIdentifier) }
            if !ekCals.isEmpty {
                let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: ekCals)
                let fetchedEvents = store.events(matching: predicate)
                for ev in fetchedEvents {
                    let rgb = Self.extractRGB(from: ev.calendar.cgColor)
                    let meeting = MobileCalendarCore.detectMeetingURL(in: [ev.location, ev.url?.absoluteString, ev.notes])
                    let covered = MobileCalendarCore.coveredDays(
                        eventStart: ev.startDate,
                        eventEnd: ev.endDate,
                        isAllDay: ev.isAllDay,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        calendar: cal
                    )
                    let targetID = ev.eventIdentifier ?? ev.calendarItemIdentifier
                    for cov in covered {
                        let item = MobileAgendaItem(
                            id: "\(targetID)-\(cov.day.timeIntervalSince1970)",
                            targetIdentifier: targetID,
                            kind: .event,
                            title: ev.title ?? "",
                            day: cov.day,
                            startDate: ev.startDate,
                            endDate: ev.endDate,
                            isAllDay: cov.spansWholeDay,
                            isRealAllDay: ev.isAllDay,
                            hasTime: !ev.isAllDay,
                            isCompleted: false,
                            isOverdue: false,
                            calendarID: ev.calendar.calendarIdentifier,
                            calendarTitle: ev.calendar.title,
                            colorRGB: rgb,
                            location: ev.location,
                            notes: ev.notes,
                            meetingURL: meeting
                        )
                        bucket[cov.day, default: []].append(item)
                    }
                }
            }
        }

        if remindersAuthorized {
            let remLists = store.calendars(for: .reminder).filter { selectedCalIDs.contains($0.calendarIdentifier) }
            if !remLists.isEmpty {
                Task {
                    let fetchedReminders = await fetchReminders(in: remLists, includeCompleted: showCompletedReminders)
                    self.mergeReminders(fetchedReminders, rangeStart: rangeStart, rangeEnd: rangeEnd, baseBucket: bucket)
                }
                return
            }
        }

        finalizeBuckets(bucket, overdue: [])
    }

    private func fetchReminders(in lists: [EKCalendar], includeCompleted: Bool) async -> [EKReminder] {
        let incomplete: [EKReminder] = await withCheckedContinuation { cont in
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
            store.fetchReminders(matching: pred) { items in
                cont.resume(returning: items ?? [])
            }
        }
        guard includeCompleted else { return incomplete }
        let completed: [EKReminder] = await withCheckedContinuation { cont in
            let pred = store.predicateForCompletedReminders(withCompletionDateStarting: nil, ending: nil, calendars: lists)
            store.fetchReminders(matching: pred) { items in
                cont.resume(returning: items ?? [])
            }
        }
        return incomplete + completed
    }

    private func mergeReminders(_ reminders: [EKReminder], rangeStart: Date, rangeEnd: Date, baseBucket: [Date: [MobileAgendaItem]]) {
        let cal = Calendar.autoupdatingCurrent
        let todayStart = cal.startOfDay(for: Date())
        var bucket = baseBucket
        var overdue: [MobileAgendaItem] = []

        for rem in reminders {
            guard let (dueDate, hasTime) = Self.dueDate(for: rem) else { continue }
            let day = cal.startOfDay(for: dueDate)
            let rgb = Self.extractRGB(from: rem.calendar.cgColor)
            let targetID = rem.calendarItemIdentifier

            if !rem.isCompleted && dueDate < todayStart {
                overdue.append(MobileAgendaItem(
                    id: "overdue-\(targetID)",
                    targetIdentifier: targetID,
                    kind: .reminder,
                    title: rem.title ?? "",
                    day: day,
                    startDate: dueDate,
                    endDate: dueDate,
                    isAllDay: !hasTime,
                    isRealAllDay: !hasTime,
                    hasTime: hasTime,
                    isCompleted: rem.isCompleted,
                    isOverdue: true,
                    calendarID: rem.calendar.calendarIdentifier,
                    calendarTitle: rem.calendar.title,
                    colorRGB: rgb,
                    location: rem.location,
                    notes: rem.notes,
                    meetingURL: nil
                ))
            }

            if day >= rangeStart && day < rangeEnd {
                bucket[day, default: []].append(MobileAgendaItem(
                    id: "rem-\(targetID)-\(day.timeIntervalSince1970)",
                    targetIdentifier: targetID,
                    kind: .reminder,
                    title: rem.title ?? "",
                    day: day,
                    startDate: dueDate,
                    endDate: dueDate,
                    isAllDay: !hasTime,
                    isRealAllDay: !hasTime,
                    hasTime: hasTime,
                    isCompleted: rem.isCompleted,
                    isOverdue: false,
                    calendarID: rem.calendar.calendarIdentifier,
                    calendarTitle: rem.calendar.title,
                    colorRGB: rgb,
                    location: rem.location,
                    notes: rem.notes,
                    meetingURL: nil
                ))
            }
        }

        overdue.sort { $0.startDate > $1.startDate }
        finalizeBuckets(bucket, overdue: overdue)
    }

    private func finalizeBuckets(_ raw: [Date: [MobileAgendaItem]], overdue: [MobileAgendaItem]) {
        var sorted: [Date: [MobileAgendaItem]] = [:]
        for (day, list) in raw {
            sorted[day] = MobileCalendarCore.sortItemsOnDay(list)
        }
        itemsByDay = sorted
        overdueReminders = overdue
    }

    public func toggleReminderCompletion(_ item: MobileAgendaItem) {
        guard item.kind == .reminder,
              let rem = store.calendarItem(withIdentifier: item.targetIdentifier) as? EKReminder else { return }
        let newState = !rem.isCompleted
        rem.isCompleted = newState
        try? store.save(rem, commit: true)
        reloadVisibleRange()
    }

    public func deleteSingleItem(_ item: MobileAgendaItem, futureOccurrences: Bool = false) {
        let draft = AIProposedItem(
            operation: .delete,
            kind: item.kind,
            selected: true,
            targetIdentifier: item.targetIdentifier,
            deleteFutureOccurrences: futureOccurrences,
            title: item.title,
            startDate: item.startDate,
            endDate: item.endDate,
            isAllDay: item.isAllDay,
            hasTime: item.hasTime,
            calendarID: item.calendarID,
            calendarTitle: item.calendarTitle,
            calendarColorRGB: item.colorRGB
        )
        _ = try? applyBatchChanges([draft])
    }

    // MARK: - AI Host Bridge & Arbitrary-Range Query (3-Year Chunked)

    public func buildAIHostContext(currentDrafts: [AIProposedItem]) -> AICodeModeHostContext {
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
        for (_, dayItems) in itemsByDay {
            for it in dayItems {
                let key = "\(it.targetIdentifier)-\(it.startDate.timeIntervalSince1970)"
                if seen.insert(key).inserted {
                    existing.append(AIExistingEventSnapshot(
                        id: it.targetIdentifier,
                        title: it.title,
                        start: it.startDate,
                        end: it.endDate,
                        isAllDay: it.isRealAllDay,
                        calendarID: it.calendarID,
                        calendarTitle: it.calendarTitle,
                        colorRGB: it.colorRGB,
                        kind: it.kind
                    ))
                }
            }
        }
        for it in overdueReminders {
            if seen.insert(it.targetIdentifier).inserted {
                existing.append(AIExistingEventSnapshot(
                    id: it.targetIdentifier,
                    title: it.title,
                    start: it.startDate,
                    end: it.endDate,
                    isAllDay: it.isRealAllDay,
                    calendarID: it.calendarID,
                    calendarTitle: it.calendarTitle,
                    colorRGB: it.colorRGB,
                    kind: .reminder
                ))
            }
        }

        let storeRef = self.store
        let isCalAuth = self.calendarAuthorized
        return AICodeModeHostContext(
            now: Date(),
            selectedDate: selectedDate,
            timeZone: .current,
            calendars: descriptors,
            existingEvents: existing,
            currentDrafts: currentDrafts,
            queryRangeProvider: { start, end in
                guard isCalAuth, start < end else { return [] }
                let cals = storeRef.calendars(for: .event)
                guard !cals.isEmpty else { return [] }
                let cal = Calendar.autoupdatingCurrent
                var snaps: [AIExistingEventSnapshot] = []
                var seenKeys = Set<String>()
                var chunkStart = start
                while chunkStart < end {
                    let threeYears = cal.date(byAdding: .year, value: 3, to: chunkStart) ?? end
                    let chunkEnd = min(threeYears, end)
                    let pred = storeRef.predicateForEvents(withStart: chunkStart, end: chunkEnd, calendars: cals)
                    for ev in storeRef.events(matching: pred) {
                        let id = ev.eventIdentifier ?? ev.calendarItemIdentifier
                        let key = "\(id)-\(ev.startDate.timeIntervalSince1970)"
                        if seenKeys.insert(key).inserted {
                            snaps.append(AIExistingEventSnapshot(
                                id: id,
                                title: ev.title ?? "",
                                start: ev.startDate,
                                end: ev.endDate,
                                isAllDay: ev.isAllDay,
                                calendarID: ev.calendar.calendarIdentifier,
                                calendarTitle: ev.calendar.title,
                                colorRGB: Self.extractRGB(from: ev.calendar.cgColor),
                                kind: .event
                            ))
                        }
                    }
                    chunkStart = chunkEnd
                }
                return snaps
            }
        )
    }

    // MARK: - Two-Phase Atomic Batch Commit + Multi-Level Undo

    public func applyBatchChanges(_ items: [AIProposedItem]) throws {
        guard !items.isEmpty else { return }

        let eventCals = Dictionary(uniqueKeysWithValues: store.calendars(for: .event).filter(\.allowsContentModifications).map { ($0.calendarIdentifier, $0) })
        let reminderCals = Dictionary(uniqueKeysWithValues: store.calendars(for: .reminder).filter(\.allowsContentModifications).map { ($0.calendarIdentifier, $0) })
        let fallbackEventCal = store.defaultCalendarForNewEvents ?? eventCals.values.first
        let fallbackReminderCal = store.defaultCalendarForNewReminders() ?? reminderCals.values.first

        var addedEventIDs: [String] = []
        var addedReminderIDs: [String] = []
        var restoredSnapshots: [AIProposedItem] = []
        var createdSnapshots: [AIProposedItem] = []

        do {
            for item in items {
                if item.operation == .delete {
                    if item.kind == .event {
                        guard let ev = resolveEvent(for: item) else {
                            throw AICodeModeError.llmError("未找到要删除的日程「\(item.title)」")
                        }
                        restoredSnapshots.append(Self.snapshot(from: ev))
                        let span: EKSpan = (item.deleteFutureOccurrences && ev.hasRecurrenceRules) ? .futureEvents : .thisEvent
                        try store.remove(ev, span: span, commit: false)
                    } else {
                        guard let rem = resolveReminder(for: item) else {
                            throw AICodeModeError.llmError("未找到要删除的提醒事项「\(item.title)」")
                        }
                        restoredSnapshots.append(Self.snapshot(from: rem))
                        try store.remove(rem, commit: false)
                    }
                } else {
                    let rule = Self.makeRecurrenceRule(frequency: item.repeatFrequency, endDate: item.repeatEndDate)
                    if item.kind == .event {
                        guard let cal = eventCals[item.calendarID] ?? fallbackEventCal else {
                            throw AICodeModeError.llmError("未找到可写入的日历")
                        }
                        let ev = EKEvent(eventStore: store)
                        ev.title = item.title
                        ev.location = item.location
                        if let u = item.urlString, !u.isEmpty { ev.url = URL(string: u) }
                        ev.notes = item.notes
                        ev.isAllDay = item.isAllDay
                        ev.startDate = item.startDate
                        ev.endDate = item.endDate
                        ev.calendar = cal
                        ev.timeZone = item.isAllDay ? nil : .current
                        if let rule { ev.recurrenceRules = [rule] }
                        if let alertMin = item.alertMinutesBefore {
                            ev.alarms?.forEach { ev.removeAlarm($0) }
                            ev.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alertMin * 60)))
                        }
                        try store.save(ev, span: .thisEvent, commit: false)
                        addedEventIDs.append(ev.eventIdentifier ?? ev.calendarItemIdentifier)
                        createdSnapshots.append(item)
                    } else {
                        guard let list = reminderCals[item.calendarID] ?? fallbackReminderCal else {
                            throw AICodeModeError.llmError("未找到可写入的提醒事项列表")
                        }
                        let rem = EKReminder(eventStore: store)
                        rem.title = item.title
                        if let u = item.urlString, !u.isEmpty { rem.url = URL(string: u) }
                        rem.notes = item.notes
                        rem.calendar = list
                        rem.priority = item.priority
                        let cal = Calendar.autoupdatingCurrent
                        var units: Set<Calendar.Component> = [.year, .month, .day]
                        if item.hasTime { units.formUnion([.hour, .minute]) }
                        var comp = cal.dateComponents(units, from: item.startDate)
                        comp.calendar = Calendar(identifier: .gregorian)
                        if item.hasTime { comp.timeZone = .current }
                        rem.dueDateComponents = comp
                        if let rule {
                            rem.startDateComponents = comp
                            rem.recurrenceRules = [rule]
                        }
                        if let alertMin = item.alertMinutesBefore {
                            rem.alarms?.forEach { rem.removeAlarm($0) }
                            rem.addAlarm(EKAlarm(absoluteDate: item.startDate.addingTimeInterval(TimeInterval(-alertMin * 60))))
                        }
                        try store.save(rem, commit: false)
                        addedReminderIDs.append(rem.calendarItemIdentifier)
                        createdSnapshots.append(item)
                    }
                }
            }
            try store.commit()
        } catch {
            store.reset()
            reloadVisibleRange()
            throw error
        }

        // Register multi-level undo/redo
        let redoItems = createdSnapshots + restoredSnapshots.map { snap -> AIProposedItem in
            var del = snap
            del.operation = .delete
            return del
        }
        undoManager.registerUndo(withTarget: self) { target in
            for eid in addedEventIDs {
                if let ev = target.store.event(withIdentifier: eid) ?? (target.store.calendarItem(withIdentifier: eid) as? EKEvent) {
                    let span: EKSpan = ev.hasRecurrenceRules ? .futureEvents : .thisEvent
                    try? target.store.remove(ev, span: span, commit: false)
                }
            }
            for rid in addedReminderIDs {
                if let rem = target.store.calendarItem(withIdentifier: rid) as? EKReminder {
                    try? target.store.remove(rem, commit: false)
                }
            }
            try? target.store.commit()
            if !restoredSnapshots.isEmpty {
                try? target.applyBatchChanges(restoredSnapshots)
            }
            target.reloadVisibleRange()
            target.undoManager.registerUndo(withTarget: target) { redoTarget in
                try? redoTarget.applyBatchChanges(redoItems)
            }
        }

        if let firstDate = items.first?.startDate {
            selectedDate = firstDate
            visibleMonth = firstDate
        }
        reloadVisibleRange()
    }

    private func resolveEvent(for item: AIProposedItem) -> EKEvent? {
        if let tid = item.targetIdentifier, !tid.isEmpty {
            if let ev = store.event(withIdentifier: tid) ?? (store.calendarItem(withIdentifier: tid) as? EKEvent) {
                return ev
            }
        }
        let cal = Calendar.autoupdatingCurrent
        let start = cal.startOfDay(for: item.startDate)
        let end = cal.date(byAdding: .day, value: 2, to: start)!
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: store.calendars(for: .event))
        return store.events(matching: pred).first { $0.title == item.title }
    }

    private func resolveReminder(for item: AIProposedItem) -> EKReminder? {
        if let tid = item.targetIdentifier, !tid.isEmpty,
           let rem = store.calendarItem(withIdentifier: tid) as? EKReminder {
            return rem
        }
        for (_, dayList) in itemsByDay {
            if let found = dayList.first(where: { $0.kind == .reminder && $0.title == item.title }),
               let rem = store.calendarItem(withIdentifier: found.targetIdentifier) as? EKReminder {
                return rem
            }
        }
        if let found = overdueReminders.first(where: { $0.title == item.title }),
           let rem = store.calendarItem(withIdentifier: found.targetIdentifier) as? EKReminder {
            return rem
        }
        return nil
    }

    private static func snapshot(from ev: EKEvent) -> AIProposedItem {
        AIProposedItem(
            operation: .create,
            kind: .event,
            selected: true,
            title: ev.title ?? "",
            startDate: ev.startDate,
            endDate: ev.endDate,
            isAllDay: ev.isAllDay,
            hasTime: !ev.isAllDay,
            calendarID: ev.calendar.calendarIdentifier,
            calendarTitle: ev.calendar.title,
            calendarColorRGB: extractRGB(from: ev.calendar.cgColor),
            location: ev.location,
            urlString: ev.url?.absoluteString,
            notes: ev.notes
        )
    }

    private static func snapshot(from rem: EKReminder) -> AIProposedItem {
        let (due, hasTime) = dueDate(for: rem) ?? (Date(), false)
        return AIProposedItem(
            operation: .create,
            kind: .reminder,
            selected: true,
            title: rem.title ?? "",
            startDate: due,
            endDate: due,
            isAllDay: !hasTime,
            hasTime: hasTime,
            calendarID: rem.calendar.calendarIdentifier,
            calendarTitle: rem.calendar.title,
            calendarColorRGB: extractRGB(from: rem.calendar.cgColor),
            urlString: rem.url?.absoluteString,
            notes: rem.notes,
            priority: rem.priority
        )
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

    nonisolated private static func dueDate(for reminder: EKReminder) -> (Date, Bool)? {
        guard var comp = reminder.dueDateComponents else { return nil }
        let hasTime = comp.hour != nil && comp.hour != NSDateComponentUndefined
        var dueCal = comp.calendar ?? Calendar(identifier: .gregorian)
        dueCal.timeZone = (hasTime && comp.timeZone != nil) ? comp.timeZone! : .current
        comp.calendar = nil
        comp.timeZone = nil
        guard let d = dueCal.date(from: comp) else { return nil }
        return (d, hasTime)
    }

    nonisolated private static func extractRGB(from cgColor: CGColor?) -> [Double] {
        guard let cgColor,
              let converted = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let comps = converted.components, comps.count >= 3 else {
            return [0.2, 0.5, 0.95]
        }
        return [Double(comps[0]), Double(comps[1]), Double(comps[2])]
    }
}
