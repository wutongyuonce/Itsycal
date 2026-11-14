import Combine
import EventKit
import SwiftUI

@main
struct ItsycalMobileApp: App {
    @StateObject private var eventStore = MobileEventStore()

    var body: some Scene {
        WindowGroup {
            MobileRootView(eventStore: eventStore)
                .task {
                    await eventStore.requestInitialAccess()
                }
        }
    }
}

// MARK: - Root Adaptive Layout (iPhone Compact Column vs iPad Split View)

struct MobileRootView: View {
    enum LayoutPreviewMode: String, CaseIterable {
        case auto = "自适应"
        case iPhone = "iPhone 布局"
        case iPad = "iPad 布局"
    }

    @ObservedObject var eventStore: MobileEventStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var previewMode: LayoutPreviewMode = .auto
    @State private var showNewSheet = false
    @State private var showAISheet = false
    @State private var showSettingsSheet = false
    @State private var overdueExpanded = true

    private var useSplitLayout: Bool {
        switch previewMode {
        case .iPhone: return false
        case .iPad: return true
        case .auto:
            #if os(macOS)
            return true
            #else
            return horizontalSizeClass == .regular
            #endif
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if useSplitLayout {
                    iPadSplitLayout
                } else {
                    iPhoneCompactLayout
                }
            }
            .frame(minWidth: previewMode == .iPhone ? 390 : 360, maxWidth: previewMode == .iPhone ? 430 : .infinity, minHeight: 620)
            .navigationTitle("Itsycal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    #if os(macOS)
                    Picker("预览模式", selection: $previewMode) {
                        ForEach(LayoutPreviewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                    #endif

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            let now = Date()
                            eventStore.selectedDate = now
                            eventStore.visibleMonth = now
                            eventStore.reloadVisibleRange()
                        }
                    } label: {
                        Image(systemName: "calendar.circle")
                    }
                    .help("回到今天")
                    .keyboardShortcut("t", modifiers: [.command])

                    Button {
                        eventStore.undoManager.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!eventStore.undoManager.canUndo)
                    .help("撤销")

                    Button {
                        showNewSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("新建日程或提醒")
                    .keyboardShortcut("n", modifiers: [.command])

                    Button {
                        showAISheet = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .help("AI 日程助手")
                    .keyboardShortcut("k", modifiers: [.command])

                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("设置")
                }
            }
            .sheet(isPresented: $showNewSheet) {
                MobileNewItemSheet(eventStore: eventStore)
            }
            .sheet(isPresented: $showAISheet) {
                MobileAIAssistantSheet(eventStore: eventStore)
            }
            .sheet(isPresented: $showSettingsSheet) {
                MobileSettingsSheet(eventStore: eventStore)
            }
        }
    }

    private var iPhoneCompactLayout: some View {
        VStack(spacing: 0) {
            MobileMonthGridView(eventStore: eventStore)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.03))
            Divider()
            MobileAgendaListView(eventStore: eventStore, overdueExpanded: $overdueExpanded)
        }
    }

    private var iPadSplitLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                MobileMonthGridView(eventStore: eventStore)
                    .padding(16)
                Divider()
                calendarQuickFilterList
            }
            .frame(width: 340)
            .background(Color.primary.opacity(0.02))

            Divider()

            MobileAgendaListView(eventStore: eventStore, overdueExpanded: $overdueExpanded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var calendarQuickFilterList: some View {
        List {
            Section("日历与提醒列表") {
                ForEach(eventStore.calendars) { cal in
                    Button {
                        eventStore.toggleCalendarSelection(id: cal.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: cal.isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(rgbColor(cal.colorRGB))
                            Text(cal.title)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(cal.sourceTitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Compact Itsycal Month Grid View

struct MobileMonthGridView: View {
    @ObservedObject var eventStore: MobileEventStore

    private var calendar: Calendar { Calendar.autoupdatingCurrent }

    private var weeks: [[Date]] {
        MobileCalendarCore.monthGrid(
            containing: eventStore.visibleMonth,
            weekStartDOW: eventStore.weekStartDOW,
            calendar: calendar
        )
    }

    private static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        return f
    }()

    var body: some View {
        VStack(spacing: 8) {
            monthHeader
            weekdayHeader
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 2) {
                    if eventStore.showWeeks, let firstDay = week.first {
                        Text("\(calendar.component(.weekOfYear, from: firstDay))")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 20)
                    }
                    ForEach(week, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(Self.monthTitleFormatter.string(from: eventStore.visibleMonth))
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 14) {
                Button {
                    if let prev = calendar.date(byAdding: .month, value: -1, to: eventStore.visibleMonth) {
                        eventStore.visibleMonth = prev
                        eventStore.reloadVisibleRange()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button {
                    let now = Date()
                    eventStore.visibleMonth = now
                    eventStore.selectedDate = now
                    eventStore.reloadVisibleRange()
                } label: {
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                }
                .buttonStyle(.plain)

                Button {
                    if let next = calendar.date(byAdding: .month, value: 1, to: eventStore.visibleMonth) {
                        eventStore.visibleMonth = next
                        eventStore.reloadVisibleRange()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
    }

    private var weekdayHeader: some View {
        let firstWeek = weeks.first ?? []
        return HStack(spacing: 2) {
            if eventStore.showWeeks {
                Spacer().frame(width: 20)
            }
            ForEach(firstWeek, id: \.self) { day in
                Text(shortWeekdaySymbol(for: day))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: eventStore.selectedDate)
        let isCurrentMonth = calendar.isDate(day, equalTo: eventStore.visibleMonth, toGranularity: .month)
        let dayStart = calendar.startOfDay(for: day)
        let items = eventStore.itemsByDay[dayStart] ?? []
        let dotColors = uniqueDotColors(for: items)

        return Button {
            eventStore.selectedDate = day
            if !isCurrentMonth {
                eventStore.visibleMonth = day
            }
            eventStore.reloadVisibleRange()
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: (isToday || isSelected) ? .bold : .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : (isCurrentMonth ? Color.primary : Color.secondary.opacity(0.4)))
                    .frame(width: 28, height: 24)
                    .background {
                        if isToday {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor)
                        } else if isSelected {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        }
                    }

                HStack(spacing: 3) {
                    if dotColors.isEmpty {
                        Circle().fill(Color.clear).frame(width: 4, height: 4)
                    } else {
                        ForEach(Array(dotColors.prefix(3).enumerated()), id: \.offset) { _, rgb in
                            Circle()
                                .fill(rgbColor(rgb))
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func uniqueDotColors(for items: [MobileAgendaItem]) -> [[Double]] {
        var result: [[Double]] = []
        for item in items {
            if !result.contains(item.colorRGB) {
                result.append(item.colorRGB)
                if result.count == 3 { break }
            }
        }
        return result
    }

    private func shortWeekdaySymbol(for date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }
}

// MARK: - Agenda + Overdue Reminders List View

struct MobileAgendaListView: View {
    @ObservedObject var eventStore: MobileEventStore
    @Binding var overdueExpanded: Bool
    @Environment(\.openURL) private var openURL

    private var calendar: Calendar { Calendar.autoupdatingCurrent }

    private var agendaDaysList: [Date] {
        let start = calendar.startOfDay(for: eventStore.selectedDate)
        return (0..<max(1, eventStore.agendaDays)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMddEEEE")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        List {
            if !eventStore.calendarAuthorized {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("未授权访问日历")
                            .font(.system(size: 14, weight: .semibold))
                        Text("请在系统设置中允许 Itsycal 访问日历与提醒事项。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if calendar.isDateInToday(eventStore.selectedDate) && !eventStore.overdueReminders.isEmpty {
                Section {
                    if overdueExpanded {
                        ForEach(eventStore.overdueReminders) { item in
                            agendaRow(item)
                        }
                    }
                } header: {
                    Button {
                        withAnimation { overdueExpanded.toggle() }
                    } label: {
                        HStack {
                            Text("已过期 (\(eventStore.overdueReminders.count))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: overdueExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(agendaDaysList, id: \.self) { day in
                let items = eventStore.itemsByDay[day] ?? []
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            agendaRow(item)
                        }
                    } header: {
                        HStack {
                            Text(Self.dayHeaderFormatter.string(from: day))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.secondary)
                            if calendar.isDateInToday(day) {
                                Text("今天")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func agendaRow(_ item: MobileAgendaItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if item.kind == .reminder {
                Button {
                    eventStore.toggleReminderCompletion(item)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15))
                        .foregroundStyle(rgbColor(item.colorRGB))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(rgbColor(item.colorRGB))
                    .frame(width: 4, height: 32)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(timeDescription(for: item))
                        .font(.system(size: 12))
                        .foregroundStyle(item.isOverdue ? Color.red : Color.secondary)

                    if let loc = item.location, !loc.isEmpty {
                        Text("· \(loc)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if let meetingURL = item.meetingURL {
                Button {
                    openURL(meetingURL)
                } label: {
                    Label("加入", systemImage: "video.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                eventStore.deleteSingleItem(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private func timeDescription(for item: MobileAgendaItem) -> String {
        if item.kind == .reminder {
            return item.hasTime ? Self.timeFormatter.string(from: item.startDate) : "全天提醒"
        }
        if item.isAllDay {
            return "全天"
        }
        return "\(Self.timeFormatter.string(from: item.startDate)) – \(Self.timeFormatter.string(from: item.endDate))"
    }
}

// MARK: - Mobile AI Assistant Sheet (Reusing Shared AIAssistant.swift)

@MainActor
final class MobileAIAssistantViewModel: ObservableObject {
    struct Bubble: Identifiable, Equatable {
        let id = UUID()
        let isUser: Bool
        let text: String
        let isError: Bool
    }

    @Published var inputText: String = ""
    @Published var bubbles: [Bubble] = []
    @Published var drafts: [AIProposedItem] = []
    @Published var isLoading: Bool = false

    private var history: [AIChatMessage] = []
    private var currentTask: Task<Void, Never>?

    var selectedCount: Int { drafts.filter(\.selected).count }

    init() {
        let snap = AISessionStore.load()
        history = snap.history
        bubbles = snap.bubbles.map { Bubble(isUser: $0.isUser, text: $0.text, isError: $0.isError) }
        drafts = snap.drafts
    }

    func sendPrompt(using eventStore: MobileEventStore) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        inputText = ""
        bubbles.append(Bubble(isUser: true, text: text, isError: false))

        let config = AIConfigStore.shared.load()
        guard config.isConfigured else {
            bubbles.append(Bubble(isUser: false, text: AICodeModeError.notConfigured.localizedDescription, isError: true))
            persist()
            return
        }

        let hostContext = eventStore.buildAIHostContext(currentDrafts: drafts)
        isLoading = true

        currentTask = Task {
            defer {
                isLoading = false
                currentTask = nil
            }
            do {
                let result = try await AILLMClient.executeCodeModeRound(
                    userText: text,
                    config: config,
                    history: history,
                    hostContext: hostContext
                )

                guard !Task.isCancelled else { return }
                history.append(AIChatMessage(role: .user, content: text))
                history.append(AIChatMessage(role: .assistant, content: result.reply))
                drafts = result.items
                bubbles.append(Bubble(isUser: false, text: result.reply, isError: false))
                persist()
            } catch {
                guard !Task.isCancelled else { return }
                bubbles.append(Bubble(isUser: false, text: error.localizedDescription, isError: true))
                persist()
            }
        }
    }

    func clear() {
        currentTask?.cancel()
        isLoading = false
        drafts.removeAll()
        history.removeAll()
        bubbles.removeAll()
        AISessionStore.save(AISessionSnapshot())
    }

    private func persist() {
        let records = bubbles.suffix(40).map {
            AISessionSnapshot.BubbleRecord(isUser: $0.isUser, text: $0.text, isError: $0.isError)
        }
        AISessionStore.save(AISessionSnapshot(history: Array(history.suffix(40)), bubbles: records, drafts: drafts))
    }
}

struct MobileAIAssistantSheet: View {
    @ObservedObject var eventStore: MobileEventStore
    @StateObject private var vm = MobileAIAssistantViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if vm.bubbles.isEmpty && vm.drafts.isEmpty {
                            Text("输入自然语言即可批量创建或删除日程与提醒事项（例如：“下周一开始每隔两天下午 3 点排算法复习，共 3 次”）。")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                        ForEach(vm.bubbles) { b in
                            HStack {
                                if b.isUser { Spacer(minLength: 40) }
                                Text(b.text)
                                    .font(.system(size: 14))
                                    .foregroundStyle(b.isError ? Color.red : (b.isUser ? Color.white : Color.primary))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(b.isError ? Color.red.opacity(0.12) : (b.isUser ? Color.accentColor : Color.primary.opacity(0.07)))
                                    )
                                if !b.isUser { Spacer(minLength: 40) }
                            }
                        }
                        if vm.isLoading {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在通过 CodeMode 编排日程…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                        }
                    }
                    .padding(14)
                }

                if !vm.drafts.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("待执行清单 (\(vm.selectedCount)/\(vm.drafts.count)) — 可继续发话调整")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 8)

                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach($vm.drafts) { $item in
                                    HStack(spacing: 10) {
                                        Toggle("", isOn: $item.selected)
                                            .labelsHidden()
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                if item.operation == .delete {
                                                    Text("删除")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .foregroundStyle(.red)
                                                }
                                                Text(item.title)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .strikethrough(item.operation == .delete)
                                                Spacer()
                                                Text(item.calendarTitle)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !item.conflictTitles.isEmpty {
                                                Text("⚠️ 与「\(item.conflictTitles.joined(separator: "、"))」时间冲突")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.orange)
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                                }
                            }
                            .padding(.horizontal, 14)
                        }
                        .frame(maxHeight: 220)

                        HStack {
                            Button("放弃") {
                                vm.clear()
                                dismiss()
                            }
                            Spacer()
                            Button("确认执行 (\(vm.selectedCount))") {
                                Task {
                                    let chosen = vm.drafts.filter(\.selected)
                                    if chosen.contains(where: { $0.kind == .reminder }) && !eventStore.remindersAuthorized {
                                        _ = await eventStore.requestRemindersAccess()
                                    }
                                    do {
                                        try eventStore.applyBatchChanges(chosen)
                                        vm.clear()
                                        dismiss()
                                    } catch {
                                        vm.bubbles.append(.init(isUser: false, text: error.localizedDescription, isError: true))
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(vm.selectedCount == 0 || vm.isLoading)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                    }
                }

                Divider()
                HStack(spacing: 8) {
                    TextField("输入日程或提醒事项…", text: $vm.inputText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { vm.sendPrompt(using: eventStore) }
                    Button {
                        vm.sendPrompt(using: eventStore)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                    }
                    .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
                }
                .padding(12)
            }
            .navigationTitle("AI 日程与提醒助手")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if !vm.bubbles.isEmpty || !vm.drafts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("清空") { vm.clear() }
                    }
                }
            }
        }
    }
}

// MARK: - Manual New Event / Reminder Sheet

struct MobileNewItemSheet: View {
    @ObservedObject var eventStore: MobileEventStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: AIProposedKind = .event
    @State private var title: String = ""
    @State private var location: String = ""
    @State private var isAllDay: Bool = false
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var repeatFrequency: AIRepeatFrequency = .none
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("类型", selection: $kind) {
                    Text("日程").tag(AIProposedKind.event)
                    Text("提醒事项").tag(AIProposedKind.reminder)
                }
                .pickerStyle(.segmented)

                Section {
                    TextField("标题", text: $title)
                    if kind == .event {
                        TextField("位置或视频会议链接", text: $location)
                    }
                }

                Section {
                    Toggle("全天", isOn: $isAllDay)
                    DatePicker(
                        kind == .event ? "开始" : "截止",
                        selection: $startDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    if kind == .event {
                        DatePicker(
                            "结束",
                            selection: $endDate,
                            in: startDate...,
                            displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                        )
                    }
                    Picker("重复", selection: $repeatFrequency) {
                        Text("不重复").tag(AIRepeatFrequency.none)
                        ForEach(AIRepeatFrequency.allCases.filter { $0 != .none }, id: \.self) { freq in
                            Text(freq.label).tag(freq)
                        }
                    }
                }

                Section("备注") {
                    TextField("添加备注…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(kind == .event ? "新建日程" : "新建提醒事项")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                startDate = eventStore.selectedDate
                endDate = eventStore.selectedDate.addingTimeInterval(3600)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if kind == .reminder && !eventStore.remindersAuthorized {
                                _ = await eventStore.requestRemindersAccess()
                            }
                            let item = AIProposedItem(
                                operation: .create,
                                kind: kind,
                                selected: true,
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                startDate: startDate,
                                endDate: kind == .event ? max(startDate, endDate) : startDate,
                                isAllDay: isAllDay,
                                hasTime: !isAllDay,
                                calendarID: "",
                                calendarTitle: "",
                                location: location.isEmpty ? nil : location,
                                notes: notes.isEmpty ? nil : notes,
                                repeatFrequency: repeatFrequency
                            )
                            try? eventStore.applyBatchChanges([item])
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: - Settings Sheet (Calendars, Appearance & AI Config)

struct MobileSettingsSheet: View {
    @ObservedObject var eventStore: MobileEventStore
    @Environment(\.dismiss) private var dismiss

    @State private var aiConfig: AIConfig = AIConfigStore.shared.load()
    @State private var cacheSize: String = AISessionStore.cacheSizeDescription()

    private let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    var body: some View {
        NavigationStack {
            Form {
                Section("AI 日程助手") {
                    Picker("协议", selection: Binding(
                        get: { aiConfig.protocolKind },
                        set: { newKind in
                            aiConfig.switchProtocol(to: newKind)
                            AIConfigStore.shared.save(aiConfig)
                        }
                    )) {
                        ForEach(AIProtocolKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    TextField("接口地址 (API URL)", text: $aiConfig.baseURL)
                        .autocorrectionDisabled()
                    TextField("模型 (Model)", text: $aiConfig.model)
                        .autocorrectionDisabled()
                    SecureField("API Key", text: $aiConfig.apiKey)
                    TextField("偏好说明（选填）", text: $aiConfig.customInstructions)

                    HStack {
                        Text("会话缓存")
                        Spacer()
                        Text(cacheSize)
                            .foregroundStyle(.secondary)
                        Button("清理缓存") {
                            AISessionStore.clearCache()
                            cacheSize = "已清理 (0 KB)"
                        }
                    }
                }

                Section("日历显示偏好") {
                    Picker("一周开始于", selection: $eventStore.weekStartDOW) {
                        ForEach(0..<7, id: \.self) { idx in
                            Text(weekdayNames[idx]).tag(idx)
                        }
                    }
                    Picker("议程显示天数", selection: $eventStore.agendaDays) {
                        Text("1 天").tag(1)
                        Text("3 天").tag(3)
                        Text("7 天").tag(7)
                        Text("14 天").tag(14)
                        Text("31 天").tag(31)
                    }
                    Toggle("显示周数", isOn: $eventStore.showWeeks)
                    Toggle("显示已完成的提醒事项", isOn: $eventStore.showCompletedReminders)
                }

                Section("日历与提醒事项列表") {
                    if !eventStore.remindersAuthorized {
                        Button("启用提醒事项访问…") {
                            Task { _ = await eventStore.requestRemindersAccess() }
                        }
                    }
                    ForEach(eventStore.calendars) { cal in
                        Button {
                            eventStore.toggleCalendarSelection(id: cal.id)
                        } label: {
                            HStack {
                                Image(systemName: cal.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(rgbColor(cal.colorRGB))
                                Text(cal.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(cal.sourceTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onDisappear {
                AIConfigStore.shared.save(aiConfig)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        AIConfigStore.shared.save(aiConfig)
                        dismiss()
                    }
                }
            }
        }
    }
}

private func rgbColor(_ rgb: [Double]) -> Color {
    Color(
        red: rgb.indices.contains(0) ? rgb[0] : 0.2,
        green: rgb.indices.contains(1) ? rgb[1] : 0.5,
        blue: rgb.indices.contains(2) ? rgb[2] : 0.95
    )
}
