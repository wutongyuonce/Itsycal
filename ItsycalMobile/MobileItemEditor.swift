import SwiftUI

/// Creates an event or reminder, or edits and deletes an existing one.
/// Recurring events ask whether a change applies to this or all future
/// occurrences; items in read-only calendars are shown but not editable.
struct MobileItemEditor: View {
    @ObservedObject var eventStore: MobileEventStore
    let existing: MobileAgendaItem?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AIProposedItem
    @State private var pendingSpanAction: Action?
    @State private var errorMessage: String?
    private let isRecurring: Bool
    private let hasCustomRepeat: Bool
    private let isMissing: Bool
    private let originalRepeat: AIRepeatFrequency

    private enum Action { case save, delete }

    /// `editable` is resolved once by the presenter, so re-renders while the
    /// sheet is open (or closing after a delete) don't query EventKit again.
    init(eventStore: MobileEventStore, existing: MobileAgendaItem?, editable: MobileEventStore.EditableItem?) {
        self.eventStore = eventStore
        self.existing = existing
        _draft = State(initialValue: editable?.draft ?? Self.newDraft(eventStore))
        isRecurring = editable?.isRecurring ?? false
        hasCustomRepeat = editable?.hasCustomRepeat ?? false
        isMissing = existing != nil && editable == nil
        originalRepeat = editable?.draft.repeatFrequency ?? .none
    }

    private var isReadOnly: Bool { isMissing || existing?.isEditable == false }
    private var trimmedTitle: String { draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var noun: String { draft.kind == .event ? "日程" : "提醒事项" }

    var body: some View {
        NavigationStack {
            Form {
                if isReadOnly {
                    Section {
                        Label(isMissing ? "该项目已不存在。" : "该日历为只读，无法修改。", systemImage: "lock")
                            .foregroundStyle(.secondary)
                    }
                }
                // Inputs are disabled individually: disabling the Form would also stop it scrolling.
                if existing == nil {
                    Picker("类型", selection: $draft.kind) {
                        Text("日程").tag(AIProposedKind.event)
                        Text("提醒事项").tag(AIProposedKind.reminder)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField("标题", text: $draft.title)
                    if draft.kind == .event {
                        TextField("位置或视频会议链接", text: optionalText(\.location))
                    }
                }
                .disabled(isReadOnly)
                Section {
                    Toggle("全天", isOn: allDay)
                    DatePicker(draft.kind == .event ? "开始" : "日期", selection: $draft.startDate, displayedComponents: dateComponents)
                    if draft.kind == .event {
                        DatePicker("结束", selection: $draft.endDate, in: draft.startDate..., displayedComponents: dateComponents)
                    }
                    if hasCustomRepeat {
                        LabeledContent("重复", value: "自定义")
                    } else {
                        Picker("重复", selection: $draft.repeatFrequency) {
                            Text("永不").tag(AIRepeatFrequency.none)
                            ForEach(AIRepeatFrequency.allCases.filter { $0 != .none }, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                    }
                }
                .disabled(isReadOnly)
                Section {
                    Picker(draft.kind == .event ? "日历" : "列表", selection: $draft.calendarID) {
                        ForEach(calendarOptions) { cal in
                            Label {
                                Text(cal.title)
                            } icon: {
                                Image(systemName: "circle.fill").foregroundStyle(Color(rgb: cal.colorRGB))
                            }
                            .tag(cal.id)
                        }
                    }
                }
                .disabled(isReadOnly)
                Section("备注") {
                    TextField("添加备注…", text: optionalText(\.notes), axis: .vertical)
                        .lineLimit(3...8)
                }
                .disabled(isReadOnly)
                if existing != nil && !isReadOnly {
                    Section {
                        Button("删除\(noun)", role: .destructive) { request(.delete) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil ? "新建\(noun)" : (isReadOnly ? noun : "编辑\(noun)"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: draft.startDate) { old, new in
                // Keep the event's duration when its start moves.
                draft.endDate = max(new, draft.endDate.addingTimeInterval(new.timeIntervalSince(old)))
            }
            .onChange(of: draft.kind) { _, kind in
                Task {
                    if kind == .reminder && !eventStore.remindersAuthorized {
                        _ = await eventStore.requestRemindersAccess()
                    }
                    draft.calendarID = eventStore.defaultCalendarID(for: kind)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isReadOnly ? "关闭" : "取消") { dismiss() }
                }
                if !isReadOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(existing == nil ? "添加" : "完成") { request(.save) }
                            .disabled(trimmedTitle.isEmpty)
                    }
                }
            }
            .confirmationDialog("这是一个重复日程", isPresented: isPresented($pendingSpanAction), titleVisibility: .visible) {
                let action = pendingSpanAction ?? .save
                let deleting = action == .delete
                Button(deleting ? "仅删除此日程" : "仅保存此日程", role: deleting ? .destructive : nil) {
                    perform(action, futureOccurrences: false)
                }
                Button(deleting ? "删除所有将来日程" : "保存所有将来日程", role: deleting ? .destructive : nil) {
                    perform(action, futureOccurrences: true)
                }
            }
            .alert("无法完成操作", isPresented: isPresented($errorMessage)) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// Writable calendars for the kind, plus the item's own calendar when it is read-only.
    private var calendarOptions: [MobileEventStore.CalendarSourceEntry] {
        let writable = eventStore.writableCalendars(for: draft.kind)
        guard !writable.contains(where: { $0.id == draft.calendarID }),
              let own = eventStore.calendars.first(where: { $0.id == draft.calendarID }) else { return writable }
        return [own] + writable
    }

    private var dateComponents: DatePickerComponents {
        draft.isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private var allDay: Binding<Bool> {
        Binding(
            get: { draft.isAllDay },
            set: {
                draft.isAllDay = $0
                draft.hasTime = !$0
            }
        )
    }

    private func optionalText(_ keyPath: WritableKeyPath<AIProposedItem, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func isPresented<T>(_ value: Binding<T?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    /// Recurring events ask for a span, except when saving a changed repeat,
    /// which always applies to the whole series.
    private func request(_ action: Action) {
        let repeatChanged = action == .save && draft.repeatFrequency != originalRepeat
        if existing != nil && isRecurring && draft.kind == .event && !repeatChanged {
            pendingSpanAction = action
        } else {
            perform(action, futureOccurrences: false)
        }
    }

    private func perform(_ action: Action, futureOccurrences: Bool) {
        var item = draft
        item.title = trimmedTitle
        let cal = Calendar.autoupdatingCurrent
        if item.kind == .reminder {
            item.endDate = item.startDate
        } else if item.isAllDay {
            item.startDate = cal.startOfDay(for: item.startDate)
            item.endDate = max(item.startDate, cal.startOfDay(for: item.endDate))
        } else {
            item.endDate = max(item.startDate, item.endDate)
        }
        Task {
            do {
                if item.kind == .reminder && !eventStore.remindersAuthorized {
                    _ = await eventStore.requestRemindersAccess()
                }
                switch (action, existing) {
                case (.save, nil):
                    try eventStore.applyBatchChanges([item])
                case (.save, let existing?):
                    try eventStore.update(existing.ref, to: item, futureOccurrences: futureOccurrences)
                case (.delete, let existing?):
                    try eventStore.delete(existing.ref, futureOccurrences: futureOccurrences)
                case (.delete, nil):
                    break
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// A one-hour event starting at the next whole hour today, or 9:00 on another selected day.
    private static func newDraft(_ store: MobileEventStore) -> AIProposedItem {
        let cal = Calendar.autoupdatingCurrent
        let day = store.selectedDate
        let start = cal.isDateInToday(day)
            ? (cal.nextDate(after: Date(), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? Date())
            : (cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day)
        return AIProposedItem(
            kind: .event,
            title: "",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            calendarID: store.defaultCalendarID(for: .event),
            calendarTitle: ""
        )
    }
}
