import EventKit
import Foundation

extension WeekSnapshot {
    /// The iOS widgets read EventKit themselves instead of loading a snapshot
    /// the app published: personal (free) developer teams can't use App
    /// Groups, so there is no container to share. As a result the widgets
    /// show every calendar and start weeks on the system's first weekday.
    static func fromEventKit(now: Date) async -> WeekSnapshot {
        let calendar = WeekDates.calendar
        let weekStart = max(0, min(6, Calendar.current.firstWeekday - 1))
        let interval = WidgetSnapshotBuilder.interval(containing: now, weekStart: weekStart, calendar: calendar)
        let store = EKEventStore()
        let eventCalendars = store.calendars(for: .event)

        let status: String
        var items: [WidgetSourceItem] = []
        if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
            status = "permission"
        } else if eventCalendars.isEmpty {
            status = "calendars"
        } else {
            status = "ready"
            let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: eventCalendars)
            for event in store.events(matching: predicate) where !event.isDeclinedByCurrentUser {
                items.append(WidgetSourceItem(
                    id: event.calendarItemIdentifier,
                    title: event.title ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    isRealAllDay: event.isAllDay,
                    calendarTitle: event.calendar.title,
                    color: event.calendar.rgb
                ))
            }
            if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
                items += await incompleteReminders(in: interval, store: store, calendar: calendar)
            }
        }
        return WidgetSnapshotBuilder.snapshot(
            items: items, interval: interval, weekStart: weekStart,
            status: status, calendar: calendar, generatedAt: now
        )
    }

    private static func incompleteReminders(in interval: DateInterval, store: EKEventStore, calendar: Calendar) async -> [WidgetSourceItem] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: interval.start, ending: interval.end, calendars: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return reminders.compactMap { reminder in
            guard let (due, hasTime) = reminder.dueDateAndHasTime else { return nil }
            let date = hasTime ? due : calendar.startOfDay(for: due)
            return WidgetSourceItem(
                id: reminder.calendarItemIdentifier,
                title: reminder.title ?? "",
                start: date,
                end: date,
                isRealAllDay: !hasTime,
                calendarTitle: reminder.calendar.title,
                color: reminder.calendar.rgb
            )
        }
    }
}

private extension EKEvent {
    /// Declined invitations are left out, as in the Mac app.
    var isDeclinedByCurrentUser: Bool {
        attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }
}
