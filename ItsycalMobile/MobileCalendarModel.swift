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

extension MobileAgendaItem: DayItem {}

public struct MobileAgendaExpansion: Equatable, Sendable {
    public let stepDays: Int
    public let skippedEmptyDays: Int
    public let nextWindowStart: Date
    public let nextWindowItemCount: Int
}

public enum MobileAgendaEntry: Equatable, Identifiable, Sendable {
    case day(Date, [MobileAgendaItem])
    case skippedEmptyDays(start: Date, count: Int)

    public var id: String {
        switch self {
        case .day(let d, _): return "day-\(d.timeIntervalSince1970)"
        case .skippedEmptyDays(let s, let c): return "skip-\(s.timeIntervalSince1970)-\(c)"
        }
    }
}

public enum MobileCalendarCore {
    /// How far ahead from `selectedDate` the store fetches so the agenda can
    /// peek and expand into upcoming weeks without re-querying EventKit.
    public static let agendaLookaheadDays = 365
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

    /// Returns a date in `(year, month)` preserving `date`'s day-of-month clamped
    /// to the target month's length (e.g. Jan 31 -> Feb 28/29 instead of overflowing to March).
    public static func date(bySettingYear year: Int, month: Int, of date: Date, calendar: Calendar) -> Date {
        let clampedMonth = min(max(month, 1), 12)
        guard let firstOfTarget = calendar.date(from: DateComponents(year: year, month: clampedMonth, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfTarget) else {
            return date
        }
        let targetDay = min(max(calendar.component(.day, from: date), dayRange.lowerBound), dayRange.count)
        return calendar.date(from: DateComponents(year: year, month: clampedMonth, day: targetDay)) ?? firstOfTarget
    }

    /// The day a widget link opens (`itsycal-week://date/yyyy-MM-dd`, built by
    /// `WeekDates.link` in the shared widget code), or nil for any other URL.
    public static func day(fromWidgetURL url: URL, calendar: Calendar) -> Date? {
        guard url.scheme == "itsycal-week", url.host == "date" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: url.lastPathComponent).map(calendar.startOfDay(for:))
    }

    /// Builds the visible agenda entries for `[selectedStart, selectedStart + shownDays)`.
    /// Runs of 7 or more consecutive empty days before an active day are summarized
    /// with a single `.skippedEmptyDays` entry so the user sees why dates jumped.
    public static func agendaEntries(
        from selectedStart: Date,
        shownDays: Int,
        itemsByDay: [Date: [MobileAgendaItem]],
        calendar: Calendar
    ) -> [MobileAgendaEntry] {
        let total = max(1, shownDays)
        var entries: [MobileAgendaEntry] = []
        var emptyStart: Date?
        var emptyCount = 0

        for offset in 0..<total {
            guard let day = calendar.date(byAdding: .day, value: offset, to: selectedStart) else { continue }
            let items = itemsByDay[day] ?? []
            if items.isEmpty {
                if emptyStart == nil { emptyStart = day }
                emptyCount += 1
            } else {
                if emptyCount >= 7, let start = emptyStart {
                    entries.append(.skippedEmptyDays(start: start, count: emptyCount))
                }
                emptyStart = nil
                emptyCount = 0
                entries.append(.day(day, items))
            }
        }
        return entries
    }

    /// Computes what the bottom "Expand" action should do after the current
    /// `[selectedStart, selectedStart + shownDays)` window, looking ahead up to
    /// `lookaheadDays` from `selectedStart`. Returns `nil` when no further items exist.
    public static func agendaExpansion(
        from selectedStart: Date,
        shownDays: Int,
        itemsByDay: [Date: [MobileAgendaItem]],
        calendar: Calendar,
        lookaheadDays: Int = agendaLookaheadDays
    ) -> MobileAgendaExpansion? {
        let clampedShown = max(1, shownDays)
        guard clampedShown < lookaheadDays,
              let windowEnd = calendar.date(byAdding: .day, value: clampedShown, to: selectedStart) else {
            return nil
        }

        var firstActiveOffset: Int?
        for offset in clampedShown..<lookaheadDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: selectedStart) else { continue }
            if !(itemsByDay[day] ?? []).isEmpty {
                firstActiveOffset = offset - clampedShown
                break
            }
        }
        guard let gap = firstActiveOffset else { return nil }

        let skipped = gap >= 7 ? gap : 0
        guard let nextStart = calendar.date(byAdding: .day, value: skipped, to: windowEnd) else { return nil }
        var count = 0
        for d in 0..<7 {
            if let day = calendar.date(byAdding: .day, value: d, to: nextStart) {
                count += (itemsByDay[day] ?? []).count
            }
        }
        return MobileAgendaExpansion(
            stepDays: skipped + 7,
            skippedEmptyDays: skipped,
            nextWindowStart: nextStart,
            nextWindowItemCount: count
        )
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
