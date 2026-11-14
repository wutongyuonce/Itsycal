import Foundation

public struct MobileAgendaItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let targetIdentifier: String
    public let kind: AIProposedKind
    public let title: String
    public let day: Date
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let isRealAllDay: Bool
    public let hasTime: Bool
    public let isCompleted: Bool
    public let isOverdue: Bool
    public let calendarID: String
    public let calendarTitle: String
    public let colorRGB: [Double]
    public let location: String?
    public let notes: String?
    public let meetingURL: URL?
    /// False when the item's calendar or list is read-only (subscriptions, holidays, birthdays).
    public let isEditable: Bool
    public let isRecurring: Bool

    public init(
        id: String,
        targetIdentifier: String,
        kind: AIProposedKind,
        title: String,
        day: Date,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        isRealAllDay: Bool,
        hasTime: Bool,
        isCompleted: Bool = false,
        isOverdue: Bool = false,
        calendarID: String,
        calendarTitle: String,
        colorRGB: [Double] = [0.2, 0.5, 0.95],
        location: String? = nil,
        notes: String? = nil,
        meetingURL: URL? = nil,
        isEditable: Bool = true,
        isRecurring: Bool = false
    ) {
        self.id = id
        self.targetIdentifier = targetIdentifier
        self.kind = kind
        self.title = title
        self.day = day
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.isRealAllDay = isRealAllDay
        self.hasTime = hasTime
        self.isCompleted = isCompleted
        self.isOverdue = isOverdue
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.colorRGB = colorRGB
        self.location = location
        self.notes = notes
        self.meetingURL = meetingURL
        self.isEditable = isEditable
        self.isRecurring = isRecurring
    }
}

public enum MobileCalendarCore {
    // Month cell metrics, shared by the layout rule below and the month view.
    public static let cellTopInset = 3.0
    public static let dayNumberHeight = 20.0
    public static let chipHeight = 14.0
    public static let chipSpacing = 1.0

    /// How many item chips fit in a month cell of `cellHeight`, and how many
    /// are left over for the "+N" count. Zero visible means the cell is too
    /// short for chips and shows colour dots instead.
    public static func chipLayout(cellHeight: Double, itemCount: Int) -> (visible: Int, hidden: Int) {
        let room = cellHeight - cellTopInset - dayNumberHeight - chipSpacing * 2
        let rows = max(0, Int(room / (chipHeight + chipSpacing)))
        let visible = min(itemCount, rows)
        return (visible, itemCount - visible)
    }

    /// Returns whole weeks (4 to 6 rows of 7 days) covering the month containing `monthDate`.
    /// `weekStartDOW` uses Itsycal's convention: 0 = Sunday, 1 = Monday, ..., 6 = Saturday.
    public static func monthGrid(containing monthDate: Date, weekStartDOW: Int, calendar: Calendar) -> [[Date]] {
        let components = calendar.dateComponents([.year, .month], from: monthDate)
        let firstOfMonth = calendar.date(from: components)!
        let range = calendar.range(of: .day, in: .month, for: firstOfMonth)!
        let lastOfMonth = calendar.date(byAdding: .day, value: range.count - 1, to: firstOfMonth)!

        let clampedStart = min(max(weekStartDOW, 0), 6)
        let firstWeekdayOffset = (calendar.component(.weekday, from: firstOfMonth) - 1 - clampedStart + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -firstWeekdayOffset, to: firstOfMonth)!

        let lastWeekdayOffset = (calendar.component(.weekday, from: lastOfMonth) - 1 - clampedStart + 7) % 7
        let gridEnd = calendar.date(byAdding: .day, value: 6 - lastWeekdayOffset, to: lastOfMonth)!

        var weeks: [[Date]] = []
        var cursor = gridStart
        while cursor <= gridEnd {
            let week = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: cursor)! }
            weeks.append(week)
            cursor = calendar.date(byAdding: .day, value: 7, to: cursor)!
        }
        return weeks
    }

    /// Splits a potentially multi-day event across each covered day in `[rangeStart, rangeEnd)`,
    /// matching Itsycal's `[start, end)` half-open midnight semantics.
    public static func coveredDays(
        eventStart: Date,
        eventEnd: Date,
        isAllDay: Bool,
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> [(day: Date, spansWholeDay: Bool)] {
        let clampedStart = max(eventStart, rangeStart)
        let clampedEnd = min(eventEnd, rangeEnd)
        var day = calendar.startOfDay(for: clampedStart)
        var pointEvent = eventStart == eventEnd && eventStart >= rangeStart && eventStart < rangeEnd
        var results: [(day: Date, spansWholeDay: Bool)] = []

        while day < clampedEnd || pointEvent {
            pointEvent = false
            let nextDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: day)!)
            let spansWholeDay = isAllDay || (eventStart < day && eventEnd >= nextDay)
            results.append((day: day, spansWholeDay: spansWholeDay))
            day = nextDay
        }
        return results
    }

    /// Sorts items on the same day following Itsycal's `CompareItemsOnDay` order:
    /// real all-day items first (incomplete reminders after events at tie), then spanning all-day items,
    /// then timed items by start time, incomplete before completed, and finally localized title.
    public static func sortItemsOnDay(_ items: [MobileAgendaItem]) -> [MobileAgendaItem] {
        items.sorted { e1, e2 in
            if e1.isRealAllDay && e2.isRealAllDay {
                if e1.isCompleted != e2.isCompleted { return !e1.isCompleted }
                let calCmp = e1.calendarTitle.localizedStandardCompare(e2.calendarTitle)
                if calCmp != .orderedSame { return calCmp == .orderedAscending }
            } else if e1.isRealAllDay != e2.isRealAllDay {
                return e1.isRealAllDay
            } else if e1.isAllDay && e2.isAllDay {
                let calCmp = e1.calendarTitle.localizedStandardCompare(e2.calendarTitle)
                if calCmp != .orderedSame { return calCmp == .orderedAscending }
            } else if e1.isAllDay != e2.isAllDay {
                return e1.isAllDay
            } else {
                if e1.startDate != e2.startDate { return e1.startDate < e2.startDate }
                if e1.isCompleted != e2.isCompleted { return !e1.isCompleted }
            }
            return e1.title.localizedStandardCompare(e2.title) == .orderedAscending
        }
    }

    /// Detects the first virtual meeting link (Zoom, Google Meet, Microsoft Teams, Webex, Feishu/Lark, Tencent Meeting) in text.
    public static func detectMeetingURL(in texts: [String?]) -> URL? {
        let combined = texts.compactMap { $0 }.joined(separator: "\n")
        guard !combined.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(combined.startIndex..<combined.endIndex, in: combined)
        var found: URL?
        detector.enumerateMatches(in: combined, options: [], range: range) { match, _, stop in
            guard let url = match?.url, let host = url.host?.lowercased() else { return }
            let meetingDomains = ["zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "feishu.cn", "larksuite.com", "meeting.tencent.com", "wemeet.qq.com"]
            if meetingDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                found = url
                stop.pointee = true
            }
        }
        return found
    }
}
