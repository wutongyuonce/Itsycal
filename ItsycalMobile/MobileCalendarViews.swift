import SwiftUI

extension Color {
    /// sRGB components as stored on calendars and agenda items.
    init(rgb: [Double]) {
        self.init(
            red: rgb.count > 0 ? rgb[0] : 0.2,
            green: rgb.count > 1 ? rgb[1] : 0.5,
            blue: rgb.count > 2 ? rgb[2] : 0.95
        )
    }
}

// MARK: - Month

/// Month grid modelled on the desktop month widget: whole weeks, each day
/// with as many item chips as fit and a +N count for the rest. Tapping a
/// day selects it; swiping sideways changes the month.
struct MobileMonthView: View {
    @ObservedObject var eventStore: MobileEventStore
    private let calendar = Calendar.autoupdatingCurrent
    private let weekNumberWidth: CGFloat = 18
    /// Cell content inset; the header and weekday labels use it too so
    /// month title, weekday labels and day numbers share one leading edge.
    private let cellInset: CGFloat = 3
    private let dayNumberWidth: CGFloat = 22

    var body: some View {
        let weeks = MobileCalendarCore.monthGrid(
            containing: eventStore.visibleMonth,
            weekStartDOW: eventStore.weekStartDOW,
            calendar: calendar
        )
        VStack(spacing: 8) {
            header
            weekdayRow
            GeometryReader { geometry in
                let rowHeight = geometry.size.height / CGFloat(max(weeks.count, 1))
                VStack(spacing: 0) {
                    ForEach(weeks, id: \.self) { week in
                        HStack(spacing: 0) {
                            if eventStore.showWeeks, let first = week.first {
                                Text("\(calendar.component(.weekOfYear, from: first))")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: weekNumberWidth)
                                    .padding(.top, 7)
                                    .frame(maxHeight: .infinity, alignment: .top)
                            }
                            ForEach(week, id: \.self) { day in
                                cell(day, height: rowHeight)
                            }
                        }
                        .frame(height: rowHeight)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            // High priority so a recognised swipe cancels the day cell's tap
            // instead of also selecting a day (which could undo the month change).
            .highPriorityGesture(
                DragGesture(minimumDistance: 30).onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height) * 1.5 else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        eventStore.shiftMonth(by: dx < 0 ? 1 : -1)
                    }
                }
            )
        }
    }

    private var header: some View {
        let currentYear = calendar.component(.year, from: eventStore.visibleMonth)
        let currentMonth = calendar.component(.month, from: eventStore.visibleMonth)
        let realYear = calendar.component(.year, from: Date())
        let minYear = min(currentYear - 10, realYear - 10)
        let maxYear = max(currentYear + 10, realYear + 10)

        return HStack(spacing: 10) {
            HStack(spacing: 4) {
                Menu {
                    Picker("年份", selection: Binding(
                        get: { currentYear },
                        set: { newYear in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                eventStore.setYearMonth(year: newYear, month: currentMonth)
                            }
                        }
                    )) {
                        ForEach(minYear...maxYear, id: \.self) { year in
                            Text("\(String(year))年").tag(year)
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("\(String(currentYear))年")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择年份")

                Menu {
                    Picker("月份", selection: Binding(
                        get: { currentMonth },
                        set: { newMonth in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                eventStore.setYearMonth(year: currentYear, month: newMonth)
                            }
                        }
                    )) {
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)月").tag(month)
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("\(currentMonth)月")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择月份")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 8)
            Button("今天") {
                withAnimation(.easeInOut(duration: 0.2)) { eventStore.goToToday() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("t", modifiers: .command)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { eventStore.shiftMonth(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .accessibilityLabel("上个月")
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { eventStore.shiftMonth(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .accessibilityLabel("下个月")
        }
        .font(.body.weight(.semibold))
        .padding(.leading, (eventStore.showWeeks ? weekNumberWidth : 0) + cellInset)
        .padding(.trailing, cellInset)
    }

    private var weekdayRow: some View {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return HStack(spacing: 0) {
            if eventStore.showWeeks {
                Color.clear.frame(width: weekNumberWidth, height: 1)
            }
            ForEach(0..<7, id: \.self) { offset in
                // Centred over the day number below it.
                Text(symbols[(eventStore.weekStartDOW + offset) % 7])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: dayNumberWidth)
                    .padding(.leading, cellInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func cell(_ day: Date, height: CGFloat) -> some View {
        let items = eventStore.itemsByDay[calendar.startOfDay(for: day)] ?? []
        let layout = MobileCalendarCore.chipLayout(cellHeight: Double(height), itemCount: items.count)
        let inMonth = calendar.isDate(day, equalTo: eventStore.visibleMonth, toGranularity: .month)
        let past = day < calendar.startOfDay(for: Date())
        let selected = calendar.isDate(day, inSameDayAs: eventStore.selectedDate)
        return Button {
            eventStore.select(day)
        } label: {
            VStack(alignment: .leading, spacing: MobileCalendarCore.chipSpacing) {
                HStack(spacing: 2) {
                    dayNumber(day)
                    Spacer(minLength: 0)
                    if layout.visible > 0 && layout.hidden > 0 {
                        Text("+\(layout.hidden)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if layout.visible == 0 {
                    dots(items)
                } else {
                    ForEach(items.prefix(layout.visible)) { chip($0) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, cellInset)
            .padding(.top, MobileCalendarCore.cellTopInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .opacity(!inMonth ? 0.3 : (past ? 0.55 : 1))
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.14)).padding(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(items.isEmpty ? "" : "\(items.count) 项")
    }

    private func dayNumber(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        return Text("\(calendar.component(.day, from: day))")
            .font(.system(size: 13, weight: today ? .bold : .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(today ? Color.white : Color.primary)
            .frame(minWidth: dayNumberWidth, minHeight: MobileCalendarCore.dayNumberHeight)
            .background {
                if today { RoundedRectangle(cornerRadius: 6).fill(Color.accentColor) }
            }
    }

    /// All-day events as a tinted block, timed events as a colour bar and
    /// title, reminders with a circle, as in the desktop month widget.
    private func chip(_ item: MobileAgendaItem) -> some View {
        let tint = Color(rgb: item.colorRGB)
        let block = item.kind == .event && item.isAllDay
        return HStack(spacing: 3) {
            if item.kind == .reminder {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(tint)
            } else if !block {
                RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 2, height: 9)
            }
            Text(item.title)
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .padding(.horizontal, block ? 4 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: MobileCalendarCore.chipHeight)
        .background {
            if block { RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.25)) }
        }
        .opacity(item.isCompleted ? 0.5 : 1)
    }

    /// Up to three calendar colours for cells too short for chips.
    private func dots(_ items: [MobileAgendaItem]) -> some View {
        var colors: [[Double]] = []
        for item in items where colors.count < 3 && !colors.contains(item.colorRGB) {
            colors.append(item.colorRGB)
        }
        return HStack(spacing: 3) {
            ForEach(colors.indices, id: \.self) { index in
                Circle().fill(Color(rgb: colors[index])).frame(width: 5, height: 5)
            }
        }
        .padding(.leading, 6)
    }
}

// MARK: - Agenda

/// Compact agenda for the selected day and the following `agendaDays`, with
/// overdue reminders on top when today is selected. Tapping a row edits it.
struct MobileAgendaView: View {
    @ObservedObject var eventStore: MobileEventStore
    let onEdit: (MobileAgendaItem) -> Void

    @State private var overdueExpanded = true
    @State private var recurringDelete: MobileAgendaItem?
    @Environment(\.openURL) private var openURL
    private let calendar = Calendar.autoupdatingCurrent
    /// One inset for rows and section headers so their leading edges align.
    private let rowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)

    var body: some View {
        let start = calendar.startOfDay(for: eventStore.selectedDate)
        let days = (0..<max(1, eventStore.agendaDays)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
        let showOverdue = calendar.isDateInToday(eventStore.selectedDate) && !eventStore.overdueReminders.isEmpty
        let isEmpty = !showOverdue && days.allSatisfy { (eventStore.itemsByDay[$0] ?? []).isEmpty }

        List {
            if !eventStore.calendarAuthorized {
                Text("请在“设置 › 隐私与安全性 › 日历”中允许 Itsycal 访问日历。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowInsets(rowInsets)
            }
            if showOverdue {
                Section {
                    if overdueExpanded {
                        ForEach(eventStore.overdueReminders) { row($0) }
                    }
                } header: {
                    Button {
                        withAnimation { overdueExpanded.toggle() }
                    } label: {
                        HStack {
                            Text("已过期 · \(eventStore.overdueReminders.count)")
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: overdueExpanded ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(rowInsets)
                }
            }
            ForEach(days, id: \.self) { day in
                if let items = eventStore.itemsByDay[day], !items.isEmpty {
                    Section {
                        ForEach(items) { row($0) }
                    } header: {
                        dayHeader(day).listRowInsets(rowInsets)
                    }
                }
            }
            if isEmpty && eventStore.calendarAuthorized {
                Text("没有日程")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 36)
        .confirmationDialog(
            "这是一个重复日程",
            isPresented: Binding(get: { recurringDelete != nil }, set: { if !$0 { recurringDelete = nil } }),
            titleVisibility: .visible,
            presenting: recurringDelete
        ) { item in
            Button("仅删除此日程", role: .destructive) { delete(item, futureOccurrences: false) }
            Button("删除所有将来日程", role: .destructive) { delete(item, futureOccurrences: true) }
        }
    }

    private func delete(_ item: MobileAgendaItem, futureOccurrences: Bool) {
        do {
            try eventStore.delete(item.ref, futureOccurrences: futureOccurrences)
        } catch {
            eventStore.report(error)
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        return HStack(spacing: 6) {
            Text(day.formatted(.dateTime.month().day().weekday(.wide)))
                .foregroundStyle(today ? Color.accentColor : Color.secondary)
            if today {
                Text("今天")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .font(.caption.weight(.semibold))
    }

    private func row(_ item: MobileAgendaItem) -> some View {
        let tint = Color(rgb: item.colorRGB)
        return HStack(spacing: 8) {
            if item.kind == .reminder {
                Button {
                    eventStore.toggleReminderCompletion(item)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(tint)
                }
                .buttonStyle(.borderless)
                .disabled(!item.isEditable)
                .accessibilityLabel(item.isCompleted ? "标记为未完成" : "标记为完成")
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(tint).frame(width: 3, height: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                Text(subtitle(item))
                    .font(.caption)
                    .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let url = item.meetingURL {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "video.fill").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .accessibilityLabel("加入会议")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit(item) }
        .listRowInsets(rowInsets)
        .swipeActions(edge: .trailing) {
            if item.isEditable {
                Button(role: .destructive) {
                    if item.kind == .event && item.isRecurring {
                        recurringDelete = item
                    } else {
                        delete(item, futureOccurrences: false)
                    }
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func subtitle(_ item: MobileAgendaItem) -> String {
        let time: String
        if item.kind == .reminder {
            let date = item.isOverdue ? item.startDate.formatted(.dateTime.month().day()) + " " : ""
            time = date + (item.hasTime ? item.startDate.formatted(date: .omitted, time: .shortened) : "全天")
        } else if item.isAllDay {
            time = "全天"
        } else {
            time = item.startDate.formatted(date: .omitted, time: .shortened)
                + " – " + item.endDate.formatted(date: .omitted, time: .shortened)
        }
        guard let location = item.location, !location.isEmpty else { return time }
        return time + " · " + location
    }
}
