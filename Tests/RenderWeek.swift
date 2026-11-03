import AppKit
import SwiftUI

// Preview generator, not a check: renders the extension's SwiftUI view with
// synthetic data in both sizes, this/next week, light and dark.
@main
struct RenderWeek {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = CommandLine.arguments.dropFirst().first ?? "/tmp/itsycal-week-previews"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let calendar = WeekDates.calendar
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let snapshot = WeekSnapshot.preview(at: date, calendar: calendar)
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: date)!
        for (width, height, size) in [(704.0, 344.0, ""), (344.0, 164.0, "-compact")] {
            for (shown, week) in [(date, ""), (nextWeek, "-next")] {
                for dark in [false, true] {
                    let view = WeekView(date: date, shown: shown, snapshot: snapshot, compact: !size.isEmpty)
                        .frame(width: width, height: height)
                        .background(dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
                        .environment(\.colorScheme, dark ? .dark : .light)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = size.isEmpty ? 2 : 1
                    guard let image = renderer.nsImage,
                          let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Render failed") }
                    let url = URL(fileURLWithPath: folder)
                        .appendingPathComponent("week-\(dark ? "dark" : "light")\(size)\(week).png")
                    try data.write(to: url)
                    print(url.path)
                }
            }
        }
    }
}
