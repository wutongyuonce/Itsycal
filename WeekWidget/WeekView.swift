import AppIntents
import SwiftUI

struct WeekView: View {
    let date: Date  // Now: drives today, past dimming and staleness.
    let shown: Date // Any date inside the displayed week.
    let snapshot: WeekSnapshot?
    var compact = true

    private let accent = Color(red: 0.19, green: 0.39, blue: 0.84)
    private var calendar: Calendar { WeekDates.calendar }
    private var weekStart: Int { min(max(snapshot?.weekStart ?? 1, 0), 6) }
    private var dates: [Date] { WeekDates.days(containing: shown, weekStart: weekStart, calendar: calendar) }
    private var nextWeek: Bool { WeekDates.isNextWeek(shown, today: date, weekStart: weekStart, calendar: calendar) }
    private var issue: String? {
        guard let snapshot else { return "打开 Itsycal 设置日程" }
        return snapshot.message(for: shown, calendar: calendar)
    }
    private var canShowNextWeek: Bool {
        snapshot?.message(for: calendar.date(byAdding: .day, value: 7, to: date)!, calendar: calendar) == nil
    }
    private var stale: Bool {
        guard let snapshot else { return false }
        return date.timeIntervalSince1970 - snapshot.generatedAt > 86400
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            header
            columns
        }
        .padding(compact ? 8 : 16)
    }

    private var header: some View {
        HStack(spacing: compact ? 6 : 8) {
            Link(destination: WeekDates.link(nextWeek ? dates[0] : date, calendar: calendar)) {
                HStack(alignment: .firstTextBaseline, spacing: compact ? 4 : 6) {
                    Text(nextWeek ? "下周" : "本周").font(.system(size: compact ? 11 : 12, weight: .semibold))
                    Text(rangeLabel).font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 2) {
                switchButton("chevron.left", next: false, enabled: nextWeek, label: "回到本周")
                switchButton("chevron.right", next: true, enabled: !nextWeek && canShowNextWeek, label: "查看下周")
            }
            Spacer(minLength: 4)
            if issue == nil {
                Text(compact ? "\(totalCount) 项" : "\(totalCount) 项日程")
                    .font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary)
            }
        }
        .frame(height: compact ? 16 : 18)
        .padding(.horizontal, 3)
    }

    @ViewBuilder
    private func switchButton(_ symbol: String, next: Bool, enabled: Bool, label: String) -> some View {
        let icon = Image(systemName: symbol)
            .font(.system(size: compact ? 8 : 9, weight: .bold))
            .frame(width: compact ? 16 : 18, height: compact ? 14 : 16)
            .background(Color.primary.opacity(enabled ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 4))
        if enabled {
            Button(intent: SwitchWeekIntent(next: next)) { icon.foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
        } else {
            icon.foregroundStyle(.quaternary).accessibilityHidden(true)
        }
    }

    private var rangeLabel: String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateTemplate = compact ? "MMMd" : "yMMMd"
        return formatter.string(from: dates[0], to: dates[6])
    }

    private var totalCount: Int {
        dates.reduce(0) { $0 + (snapshot?.days[WeekDates.key($1, calendar: calendar)]?.count ?? 0) }
    }

    private var columns: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(dates.enumerated()), id: \.offset) { index, day in
                    dayColumn(day, index: index, capacity: WeekDates.capacity(height: geometry.size.height, compact: compact))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            if index > 0 {
                                Rectangle().fill(Color.primary.opacity(0.07))
                                    .frame(width: 0.5).padding(.top, compact ? 32 : 36)
                            }
                        }
                }
            }
            .overlay {
                if let issue {
                    Link(destination: WeekDates.link(date, calendar: calendar)) {
                        Text(issue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12).padding(.top, 30)
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if stale && issue == nil {
                    Link(destination: WeekDates.link(date, calendar: calendar)) {
                        Image(systemName: "arrow.clockwise.circle")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("日程可能已过期，打开 Itsycal 更新")
                }
            }
        }
    }

    private func dayColumn(_ day: Date, index: Int, capacity: Int) -> some View {
        let today = calendar.isDate(day, inSameDayAs: date)
        let past = day < calendar.startOfDay(for: date)
        let events = snapshot?.days[WeekDates.key(day, calendar: calendar)] ?? []
        let hidden = max(0, events.count - capacity)
        let link = WeekDates.link(day, calendar: calendar)
        return VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            Link(destination: link) {
                let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
                                     : AnyLayout(HStackLayout(spacing: 4))
                layout {
                    Text(WeekDates.weekdayLabel(day, calendar: calendar))
                        .font(.system(size: compact ? 8 : 10, weight: today ? .semibold : .regular))
                        .foregroundStyle(today ? accent : Color.secondary)
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: compact ? 12 : 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(today ? .white : Color.primary)
                        .frame(minWidth: compact ? 20 : 26, minHeight: compact ? 17 : 24)
                        .background {
                            if today { RoundedRectangle(cornerRadius: compact ? 5 : 7).fill(accent) }
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: compact ? 28 : 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted))\(today ? "，今天" : "")")

            if issue == nil {
                VStack(alignment: .leading, spacing: 0) {
                    if events.isEmpty {
                        Text("无日程").font(.system(size: compact ? 9 : 10)).foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(events.prefix(capacity).enumerated()), id: \.offset) { _, event in
                            Link(destination: link) { eventRow(event) }.buttonStyle(.plain)
                        }
                        if hidden > 0 {
                            Link(destination: link) {
                                Text(compact ? "还有\(hidden)项" : "还有 \(hidden) 项")
                                    .font(.system(size: compact ? 8 : 10, weight: .medium))
                                    .foregroundStyle(today ? accent : Color.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(height: compact ? 14 : 18, alignment: .topLeading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 3 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(past ? 0.5 : 1)
    }

    private func eventRow(_ event: WeekEvent) -> some View {
        HStack(alignment: .top, spacing: compact ? 3 : 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(red: event.color[safe: 0] ?? 0.3,
                            green: event.color[safe: 1] ?? 0.5,
                            blue: event.color[safe: 2] ?? 0.8))
                .frame(width: compact ? 1.5 : 2, height: compact ? 19 : 23)
                .padding(.top, compact ? 1 : 2)
            ViewThatFits(in: .horizontal) {
                if !compact {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(event.timeLabel).font(.system(size: 9)).foregroundStyle(.secondary)
                        Text(event.title).font(.system(size: 10))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                    Text(event.timeLabel).font(.system(size: compact ? 8 : 9)).foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(event.title).font(.system(size: 10))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: WeekDates.eventPitch(compact: compact), alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
