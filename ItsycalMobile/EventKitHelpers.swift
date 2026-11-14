import EventKit

// EventKit conversions shared by the app and the iOS widgets.

extension EKReminder {
    /// The due date as an instant, and whether it has a time of day.
    /// Nil for reminders without a due date, which don't go on the calendar.
    var dueDateAndHasTime: (date: Date, hasTime: Bool)? {
        guard var components = dueDateComponents else { return nil }
        let hasTime = components.hour != nil && components.hour != NSDateComponentUndefined
        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        calendar.timeZone = (hasTime ? components.timeZone : nil) ?? .current
        components.calendar = nil
        components.timeZone = nil
        return calendar.date(from: components).map { ($0, hasTime) }
    }
}

extension EKCalendar {
    /// sRGB components of the calendar's colour.
    var rgb: [Double] {
        guard let color = cgColor,
              let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = srgb.components, components.count >= 3 else {
            return [0.2, 0.5, 0.95]
        }
        return components.prefix(3).map(Double.init)
    }
}
