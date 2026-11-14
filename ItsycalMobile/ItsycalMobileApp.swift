import Combine
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
                // Tapping a day (or the title) in a widget opens that day.
                .onOpenURL { url in
                    if let day = MobileCalendarCore.day(fromWidgetURL: url, calendar: .autoupdatingCurrent) {
                        eventStore.select(day)
                    }
                }
        }
    }
}

// MARK: - Root Layout

/// The month view leads. Landscape windows put a ~30% agenda column beside
/// it; portrait ones stack the agenda under a month view taking 60% of the
/// height. The same rule on iPhone and iPad, decided from the window's own
/// shape, so Split View, Slide Over and Stage Manager windows follow it too.
struct MobileRootView: View {
    @ObservedObject var eventStore: MobileEventStore

    @State private var editorRequest: EditorRequest?
    @State private var showAISheet = false
    @State private var showSettingsSheet = false

    private struct EditorRequest: Identifiable {
        let id = UUID()
        let item: MobileAgendaItem?
        let editable: MobileEventStore.EditableItem?
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let size = geometry.size
                if size.width > size.height && size.width >= 560 {
                    HStack(spacing: 0) {
                        MobileMonthView(eventStore: eventStore)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        Divider()
                        agenda
                            .frame(width: min(380, max(260, size.width * 0.3)))
                    }
                } else {
                    VStack(spacing: 0) {
                        MobileMonthView(eventStore: eventStore)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                            .frame(height: size.height * 0.6)
                        Divider()
                        agenda
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        eventStore.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!eventStore.canUndo)
                    .keyboardShortcut("z", modifiers: .command)
                    .accessibilityLabel("撤销")

                    Button {
                        editorRequest = EditorRequest(item: nil, editable: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("新建日程或提醒事项")

                    Button {
                        showAISheet = true
                    } label: {
                        Image(systemName: "sparkles")
                    }
                    .keyboardShortcut("k", modifiers: .command)
                    .accessibilityLabel("AI 日程助手")

                    Button {
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .sheet(item: $editorRequest) { request in
                MobileItemEditor(eventStore: eventStore, existing: request.item, editable: request.editable)
            }
            .sheet(isPresented: $showAISheet) {
                MobileAIAssistantSheet(eventStore: eventStore)
            }
            .sheet(isPresented: $showSettingsSheet) {
                MobileSettingsSheet(eventStore: eventStore)
            }
            .alert(
                "无法完成操作",
                isPresented: Binding(get: { eventStore.lastError != nil }, set: { if !$0 { eventStore.lastError = nil } })
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(eventStore.lastError ?? "")
            }
        }
    }

    private var agenda: some View {
        MobileAgendaView(eventStore: eventStore) { item in
            editorRequest = EditorRequest(item: item, editable: eventStore.editableItem(for: item.ref))
        }
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

/// Chat and the proposed changes in one scroll, on the system glass material:
/// glass bubbles and cards, with the input and confirm actions floating at the bottom.
struct MobileAIAssistantSheet: View {
    @ObservedObject var eventStore: MobileEventStore
    @StateObject private var vm = MobileAIAssistantViewModel()
    @Environment(\.dismiss) private var dismiss

    private var canSend: Bool {
        !vm.isLoading && !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if vm.bubbles.isEmpty && vm.drafts.isEmpty {
                        Text("用自然语言批量创建或删除日程与提醒事项，例如：“下周一开始每隔两天下午 3 点排算法复习，共 3 次”。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(vm.bubbles, content: bubble)
                    if vm.isLoading {
                        Label {
                            Text("正在编排日程…")
                        } icon: {
                            ProgressView()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    if !vm.drafts.isEmpty {
                        Text("待执行 \(vm.selectedCount)/\(vm.drafts.count) 项 · 可继续发话调整")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                        ForEach($vm.drafts) { draftCard($0) }
                    }
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle("AI 日程与提醒助手")
            .navigationBarTitleDisplayMode(.inline)
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

    private func bubble(_ bubble: MobileAIAssistantViewModel.Bubble) -> some View {
        let tint: Color? = bubble.isError ? .red : (bubble.isUser ? .accentColor : nil)
        return Text(bubble.text)
            .font(.subheadline)
            .foregroundStyle(bubble.isUser ? .white : .primary)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: bubble.isUser ? .trailing : .leading)
            .padding(bubble.isUser ? .leading : .trailing, 40)
    }

    private func draftCard(_ item: Binding<AIProposedItem>) -> some View {
        let draft = item.wrappedValue
        return Button {
            item.wrappedValue.selected.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: draft.selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(draft.selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if draft.operation == .delete {
                            Text("删除").font(.caption2.weight(.bold)).foregroundStyle(.red)
                        }
                        Text(draft.title)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(draft.operation == .delete)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(draft.calendarTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(Self.timeText(draft)).font(.caption).foregroundStyle(.secondary)
                    if !draft.conflictTitles.isEmpty {
                        Text("与「\(draft.conflictTitles.joined(separator: "、"))」时间冲突")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(in: .rect(cornerRadius: 16))
        .opacity(draft.selected ? 1 : 0.6)
        .accessibilityAddTraits(draft.selected ? .isSelected : [])
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if !vm.drafts.isEmpty {
                    HStack {
                        Button("放弃") {
                            vm.clear()
                            dismiss()
                        }
                        .buttonStyle(.glass)
                        Spacer()
                        Button("确认执行 \(vm.selectedCount) 项", action: confirm)
                            .buttonStyle(.glassProminent)
                            .disabled(vm.selectedCount == 0 || vm.isLoading)
                    }
                }
                HStack(spacing: 8) {
                    TextField(vm.drafts.isEmpty ? "输入日程或提醒事项…" : "输入调整意见…", text: $vm.inputText)
                        .submitLabel(.send)
                        .onSubmit { vm.sendPrompt(using: eventStore) }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .glassEffect(in: .capsule)
                    Button {
                        vm.sendPrompt(using: eventStore)
                    } label: {
                        Image(systemName: "arrow.up").font(.body.weight(.semibold)).padding(4)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!canSend)
                    .accessibilityLabel("发送")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func confirm() {
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

    private static func timeText(_ draft: AIProposedItem) -> String {
        let day = draft.startDate.formatted(.dateTime.month().day().weekday(.abbreviated))
        if draft.kind == .reminder || draft.isAllDay {
            return draft.hasTime ? day + " " + draft.startDate.formatted(date: .omitted, time: .shortened) : day + " 全天"
        }
        return day + " " + draft.startDate.formatted(date: .omitted, time: .shortened)
            + " – " + draft.endDate.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Settings Sheet (AI, Display & Calendars)

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
                                    .foregroundStyle(Color(rgb: cal.colorRGB))
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
            .navigationBarTitleDisplayMode(.inline)
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
