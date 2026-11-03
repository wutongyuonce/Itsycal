import AppKit
import SwiftUI

// Preview generator, not a check: renders the extension's SwiftUI views with
// synthetic data — week (both sizes) and month (extra large), this/next
// period, light and dark.
@main
struct RenderWeek {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = CommandLine.arguments.dropFirst().first ?? "/tmp/itsycal-week-previews"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let calendar = WeekDates.calendar
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let snapshot = WeekSnapshot.preview(at: date, calendar: calendar)
        let nextWeek = WidgetPeriod.week.next(after: date, calendar: calendar)
        let nextMonth = WidgetPeriod.month.next(after: date, calendar: calendar)
        let extraLarge = CGSize(width: 704, height: 344), medium = CGSize(width: 344, height: 164)
        let renders: [(String, CGSize, AnyView)] = [
            ("week", extraLarge, AnyView(WeekView(date: date, shown: date, snapshot: snapshot, compact: false))),
            ("week-next", extraLarge, AnyView(WeekView(date: date, shown: nextWeek, snapshot: snapshot, compact: false))),
            ("week-compact", medium, AnyView(WeekView(date: date, shown: date, snapshot: snapshot, compact: true))),
            ("week-compact-next", medium, AnyView(WeekView(date: date, shown: nextWeek, snapshot: snapshot, compact: true))),
            ("month", extraLarge, AnyView(MonthView(date: date, shown: date, snapshot: snapshot))),
            ("month-next", extraLarge, AnyView(MonthView(date: date, shown: nextMonth, snapshot: snapshot))),
        ]
        for (name, size, content) in renders {
            for dark in [false, true] {
                let view = content
                    .frame(width: size.width, height: size.height)
                    .background(dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Render failed") }
                let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                try data.write(to: url)
                print(url.path)
            }
        }
    }
}
