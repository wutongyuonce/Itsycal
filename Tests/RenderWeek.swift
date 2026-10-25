import AppKit
import SwiftUI

// Render the same SwiftUI view as the extension, without calendar permission.
@main
struct RenderWeek {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = CommandLine.arguments.dropFirst().first ?? "/tmp/itsycal-week-previews"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let calendar = WeekDates.calendar
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        let weekStart = 1
        let monday = WeekDates.weekStartDate(containing: date, weekStart: weekStart, calendar: calendar)
        let titles = [["项目复盘", "整理本周计划"], ["设计讨论"], ["团队例会", "产品评审"],
                      ["专注工作", "与客户沟通", "设计走查", "方案评审", "整理反馈", "阅读"], ["周度回顾"], [], ["下周计划"]]
        var buckets: [String: [WeekEvent]] = [:]
        for (index, day) in WeekDates.days(containing: date, weekStart: weekStart, calendar: calendar).enumerated() {
            buckets[WeekDates.key(day, calendar: calendar)] = titles[index].enumerated().map { row, title in
                let start = calendar.date(bySettingHour: 8 + row * 2, minute: 30, second: 0, of: day)!
                return WeekEvent(id: "\(index)-\(row)", title: title, start: start.timeIntervalSince1970,
                                 end: start.addingTimeInterval(3600).timeIntervalSince1970,
                                 allDay: row == 0 && index == 4, spansDay: false, startsHere: true,
                                 endsHere: false, continues: false, color: row.isMultiple(of: 2) ? [0.25, 0.48, 0.75] : [0.35, 0.62, 0.49])
            }
        }
        let snapshot = WeekSnapshot(version: 2, generatedAt: date.timeIntervalSince1970,
                                    timeZone: calendar.timeZone.identifier, start: monday.timeIntervalSince1970,
                                    end: calendar.date(byAdding: .day, value: 7, to: monday)!.timeIntervalSince1970,
                                    status: "ready", weekStart: weekStart, days: buckets)
        for (width, height, suffix) in [(704.0, 344.0, ""), (344.0, 164.0, "-compact")] {
        for dark in [false, true] {
            let view = WeekView(date: date, snapshot: snapshot, compact: !suffix.isEmpty)
                .frame(width: width, height: height)
                .background(dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = suffix.isEmpty ? 2 : 1
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Render failed") }
            let url = URL(fileURLWithPath: folder).appendingPathComponent("week-\(dark ? "dark" : "light")\(suffix).png")
            try data.write(to: url)
            print(url.path)
        }
        }
    }
}
