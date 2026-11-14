import AppKit
import Combine
import EventKit
import SwiftUI

// MARK: - Objective-C Bridge Models for EventCenter Integration

@objc public final class AICalendarOptionObjC: NSObject {
    @objc public let identifier: String
    @objc public let title: String
    @objc public let source: String
    @objc public let allowsEvents: Bool
    @objc public let allowsReminders: Bool
    @objc public let isDefaultEvent: Bool
    @objc public let isDefaultReminder: Bool
    @objc public let color: NSColor

    @objc public init(
        identifier: String,
        title: String,
        source: String,
        allowsEvents: Bool,
        allowsReminders: Bool,
        isDefaultEvent: Bool,
        isDefaultReminder: Bool,
        color: NSColor
    ) {
        self.identifier = identifier
        self.title = title
        self.source = source
        self.allowsEvents = allowsEvents
        self.allowsReminders = allowsReminders
        self.isDefaultEvent = isDefaultEvent
        self.isDefaultReminder = isDefaultReminder
        self.color = color
    }
}

@objc public final class AIExistingItemObjC: NSObject {
    @objc public let title: String
    @objc public let startDate: Date
    @objc public let endDate: Date
    @objc public let isAllDay: Bool
    @objc public let calendarTitle: String
    @objc public let isReminder: Bool

    @objc public init(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        isReminder: Bool
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.isReminder = isReminder
    }
}

@objc public final class AICommitItemObjC: NSObject {
    @objc public let isReminder: Bool
    @objc public let title: String
    @objc public let startDate: Date
    @objc public let endDate: Date
    @objc public let isAllDay: Bool
    @objc public let hasTime: Bool
    @objc public let calendarID: String
    @objc public let location: String?
    @objc public let notes: String?
    @objc public let repeatFrequency: String
    @objc public let repeatEndDate: Date?
    @objc public let alertMinutes: NSNumber?
    @objc public let priority: Int

    public init(from item: AIProposedItem) {
        self.isReminder = item.kind == .reminder
        self.title = item.title
        self.startDate = item.startDate
        self.endDate = item.endDate
        self.isAllDay = item.isAllDay
        self.hasTime = item.hasTime
        self.calendarID = item.calendarID
        self.location = item.location
        self.notes = item.notes
        self.repeatFrequency = item.repeatFrequency.rawValue
        self.repeatEndDate = item.repeatEndDate
        self.alertMinutes = item.alertMinutesBefore.map(NSNumber.init(value:))
        self.priority = item.priority
    }
}

@objc public protocol AIAssistantHostDelegate: AnyObject {
    func aiSelectedDate() -> Date
    func aiAvailableCalendars() -> [AICalendarOptionObjC]
    func aiExistingItems() -> [AIExistingItemObjC]
    func aiCommitItems(_ items: [AICommitItemObjC], completion: @escaping (Bool, String?) -> Void)
    func aiOpenSettings()
    func aiClosePopover()
}

// MARK: - ViewModel for AI Chat & Staging List

@MainActor
final class AIAssistantViewModel: ObservableObject {
    struct ChatBubble: Identifiable, Equatable {
        let id = UUID()
        let isUser: Bool
        let text: String
        let isError: Bool
    }

    @Published var inputText: String = ""
    @Published var bubbles: [ChatBubble] = []
    @Published var drafts: [AIProposedItem] = []
    @Published var isLoading: Bool = false
    @Published var isCommitting: Bool = false

    weak var hostDelegate: AIAssistantHostDelegate?
    private var conversationHistory: [AIChatMessage] = []
    private var currentTask: Task<Void, Never>?

    var selectedDraftCount: Int {
        drafts.filter(\.selected).count
    }

    func sendPrompt() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        inputText = ""
        bubbles.append(ChatBubble(isUser: true, text: text, isError: false))

        let config = AIConfigStore.shared.load()
        guard config.isConfigured else {
            bubbles.append(ChatBubble(
                isUser: false,
                text: AICodeModeError.notConfigured.localizedDescription,
                isError: true
            ))
            return
        }

        let hostContext = buildHostContext()
        isLoading = true

        currentTask = Task {
            defer {
                isLoading = false
                currentTask = nil
            }
            do {
                let result = try await executeCodeModeRound(
                    userText: text,
                    config: config,
                    hostContext: hostContext
                )
                guard !Task.isCancelled else { return }
                conversationHistory.append(AIChatMessage(role: .user, content: text))
                conversationHistory.append(AIChatMessage(role: .assistant, content: result.reply))
                drafts = result.items
                bubbles.append(ChatBubble(isUser: false, text: result.reply, isError: false))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                bubbles.append(ChatBubble(
                    isUser: false,
                    text: error.localizedDescription,
                    isError: true
                ))
            }
        }
    }

    func cancelCurrentRequest() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
    }

    func clearOrDiscard() {
        cancelCurrentRequest()
        drafts.removeAll()
        conversationHistory.removeAll()
        bubbles.removeAll()
    }

    func confirmSelectedItems() {
        let chosen = drafts.filter(\.selected)
        guard !chosen.isEmpty, !isCommitting, let delegate = hostDelegate else { return }
        isCommitting = true
        let payload = chosen.map { AICommitItemObjC(from: $0) }
        delegate.aiCommitItems(payload) { [weak self] success, errorMessage in
            Task { @MainActor in
                guard let self else { return }
                self.isCommitting = false
                if success {
                    self.drafts.removeAll()
                    self.conversationHistory.removeAll()
                    self.bubbles.removeAll()
                    delegate.aiClosePopover()
                } else if let errorMessage, !errorMessage.isEmpty {
                    self.bubbles.append(ChatBubble(isUser: false, text: errorMessage, isError: true))
                }
            }
        }
    }

    private func buildHostContext() -> AICodeModeHostContext {
        let selectedDate = hostDelegate?.aiSelectedDate() ?? Date()
        let rawCalendars = hostDelegate?.aiAvailableCalendars() ?? []
        let calendars = rawCalendars.map { c -> AICalendarDescriptor in
            let srgb = c.color.usingColorSpace(.sRGB) ?? c.color
            var r: CGFloat = 0.2, g: CGFloat = 0.5, b: CGFloat = 0.95, a: CGFloat = 1
            srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
            return AICalendarDescriptor(
                id: c.identifier,
                title: c.title,
                source: c.source,
                allowsEvents: c.allowsEvents,
                allowsReminders: c.allowsReminders,
                isDefaultEvent: c.isDefaultEvent,
                isDefaultReminder: c.isDefaultReminder,
                colorRGB: [Double(r), Double(g), Double(b)]
            )
        }
        let rawExisting = hostDelegate?.aiExistingItems() ?? []
        let existing = rawExisting.map { item in
            AIExistingEventSnapshot(
                title: item.title,
                start: item.startDate,
                end: item.endDate,
                isAllDay: item.isAllDay,
                calendarTitle: item.calendarTitle,
                kind: item.isReminder ? .reminder : .event
            )
        }
        return AICodeModeHostContext(
            now: Date(),
            selectedDate: selectedDate,
            timeZone: .current,
            calendars: calendars,
            existingEvents: existing,
            currentDrafts: drafts
        )
    }

    private func executeCodeModeRound(
        userText: String,
        config: AIConfig,
        hostContext: AICodeModeHostContext
    ) async throws -> AICodeModeResult {
        let sysPrompt = AILLMClient.systemPrompt(host: hostContext, customInstructions: config.customInstructions)
        var msgs = conversationHistory
        msgs.append(AIChatMessage(role: .user, content: userText))

        let firstRaw = try await sendLLMRequest(config: config, systemPrompt: sysPrompt, messages: msgs)
        let firstScript = AILLMClient.extractJSCode(from: firstRaw)

        do {
            return try AICodeModeRunner.run(script: firstScript, host: hostContext)
        } catch let firstErr as AICodeModeError {
            // Self-heal once if the generated JS script threw an exception.
            if case .scriptException(let jsError) = firstErr {
                var retryMsgs = msgs
                retryMsgs.append(AIChatMessage(role: .assistant, content: firstRaw))
                retryMsgs.append(AIChatMessage(
                    role: .user,
                    content: "Your JavaScript threw a runtime error: \(jsError). Please fix the script and output ONLY the corrected ```javascript block."
                ))
                let retryRaw = try await sendLLMRequest(config: config, systemPrompt: sysPrompt, messages: retryMsgs)
                let retryScript = AILLMClient.extractJSCode(from: retryRaw)
                return try AICodeModeRunner.run(script: retryScript, host: hostContext)
            }
            throw firstErr
        }
    }

    private func sendLLMRequest(
        config: AIConfig,
        systemPrompt: String,
        messages: [AIChatMessage]
    ) async throws -> String {
        let request = try AILLMClient.buildRequest(config: config, systemPrompt: systemPrompt, messages: messages)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            _ = try AILLMClient.parseResponse(data: data, protocolKind: config.protocolKind)
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw AICodeModeError.llmError("HTTP \(http.statusCode): \(bodyText.prefix(240))")
        }
        return try AILLMClient.parseResponse(data: data, protocolKind: config.protocolKind)
    }
}

// MARK: - SwiftUI Popover View

struct AIAssistantPopoverView: View {
    @ObservedObject var vm: AIAssistantViewModel

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd EEE HH:mm"
        return f
    }()

    private static let dayOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd EEE"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            contentArea
            if !vm.drafts.isEmpty {
                Divider()
                stagingSection
            }
            Divider()
            inputBar
        }
        .frame(width: 340)
        .frame(minHeight: 280, maxHeight: 520)
    }

    private var headerBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 13, weight: .semibold))
            Text("AI 日程与提醒助手")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !vm.bubbles.isEmpty || !vm.drafts.isEmpty {
                Button("清空") {
                    vm.clearOrDiscard()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Button {
                vm.hostDelegate?.aiOpenSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("AI 设置")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var contentArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if vm.bubbles.isEmpty && vm.drafts.isEmpty {
                        emptyPromptHint
                    }
                    ForEach(vm.bubbles) { bubble in
                        chatBubbleView(bubble)
                            .id(bubble.id)
                    }
                    if vm.isLoading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在通过 CodeMode 编排日程…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("取消") {
                                vm.cancelCurrentRequest()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
                .padding(10)
            }
            .frame(minHeight: vm.drafts.isEmpty ? 160 : 95, maxHeight: vm.drafts.isEmpty ? 280 : 140)
            .onChange(of: vm.bubbles.count) { _, _ in
                if let lastID = vm.bubbles.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyPromptHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("用自然语言创建日程或提醒事项（支持批量与周期排期）：")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("• “明天下午 3 点产品评审 1 小时，提前 15 分钟提醒”")
                Text("• “从下周一开始每隔两天下午 4 点算法复习，连续 4 次”")
                Text("• “帮我加两个提醒事项：今晚 8 点交周报、周五买机票”")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
        .padding(6)
    }

    private func chatBubbleView(_ bubble: AIAssistantViewModel.ChatBubble) -> some View {
        HStack {
            if bubble.isUser { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 4) {
                Text(bubble.text)
                    .font(.system(size: 12))
                    .foregroundStyle(bubble.isError ? Color.red : (bubble.isUser ? Color.white : Color.primary))
                    .textSelection(.enabled)
                if bubble.isError && bubble.text.contains("设置") {
                    Button("打开 AI 设置…") {
                        vm.hostDelegate?.aiOpenSettings()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(bubble.isError ? Color.red.opacity(0.12) : (bubble.isUser ? Color.accentColor : Color.primary.opacity(0.07)))
            )
            if !bubble.isUser { Spacer(minLength: 32) }
        }
    }

    private var stagingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("待创建清单（\(vm.selectedDraftCount)/\(vm.drafts.count)）")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("可继续发话微调")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach($vm.drafts) { $item in
                        draftCardView(item: $item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            .frame(maxHeight: 200)

            HStack(spacing: 8) {
                Button("放弃") {
                    vm.clearOrDiscard()
                    vm.hostDelegate?.aiClosePopover()
                }
                .controlSize(.small)

                Spacer()

                Button {
                    vm.confirmSelectedItems()
                } label: {
                    Text(vm.isCommitting ? "正在添加…" : "确认添加 (\(vm.selectedDraftCount))")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(vm.selectedDraftCount == 0 || vm.isCommitting || vm.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(Color.primary.opacity(0.02))
    }

    private func draftCardView(item: Binding<AIProposedItem>) -> some View {
        let val = item.wrappedValue
        let tint = Color(
            red: val.calendarColorRGB.indices.contains(0) ? val.calendarColorRGB[0] : 0.2,
            green: val.calendarColorRGB.indices.contains(1) ? val.calendarColorRGB[1] : 0.5,
            blue: val.calendarColorRGB.indices.contains(2) ? val.calendarColorRGB[2] : 0.95
        )
        return HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: item.selected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 2)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(tint)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: val.kind == .reminder ? "checklist" : "calendar")
                        .font(.system(size: 10))
                        .foregroundStyle(tint)
                    Text(val.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(val.calendarTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(formatItemTime(val))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if val.repeatFrequency != .none {
                        Text(val.repeatFrequency.label)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    if let loc = val.location, !loc.isEmpty {
                        Text(loc)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                if !val.conflictTitles.isEmpty {
                    Text("⚠️ 与「\(val.conflictTitles.joined(separator: "、"))」时间冲突")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(val.selected ? 0.05 : 0.02))
        )
        .opacity(val.selected ? 1.0 : 0.55)
    }

    private func formatItemTime(_ item: AIProposedItem) -> String {
        if item.kind == .reminder {
            return item.hasTime
                ? "截止：\(Self.dateTimeFormatter.string(from: item.startDate))"
                : "截止：\(Self.dayOnlyFormatter.string(from: item.startDate))（全天）"
        }
        if item.isAllDay {
            let s = Self.dayOnlyFormatter.string(from: item.startDate)
            let e = Self.dayOnlyFormatter.string(from: item.endDate)
            return s == e ? "\(s)（全天）" : "\(s) → \(e)（全天）"
        }
        let startStr = Self.dateTimeFormatter.string(from: item.startDate)
        let endClock = DateFormatter()
        endClock.dateFormat = Calendar.current.isDate(item.startDate, inSameDayAs: item.endDate) ? "HH:mm" : "MM-dd HH:mm"
        return "\(startStr) – \(endClock.string(from: item.endDate))"
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            TextField(
                vm.drafts.isEmpty ? "输入日程或提醒事项…" : "输入调整意见（如：推迟 1 小时）…",
                text: $vm.inputText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .onSubmit {
                vm.sendPrompt()
            }

            Button {
                vm.sendPrompt()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading
                            ? Color.secondary.opacity(0.4)
                            : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

// MARK: - Objective-C Popover & Settings Controllers

@objc public final class AIAssistantBridge: NSObject {
    @MainActor
    @objc public static func makePopoverViewController(delegate: AIAssistantHostDelegate) -> NSViewController {
        let vm = AIAssistantViewModel()
        vm.hostDelegate = delegate
        return NSHostingController(rootView: AIAssistantPopoverView(vm: vm))
    }

    @objc public static func toolbarIcon(for identifier: String) -> NSImage? {
        if identifier == "PrefsAIVC" {
            return NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI")
        }
        return nil
    }

    @objc public static func buttonIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Assistant")?.withSymbolConfiguration(config)
        img?.isTemplate = true
        return img
    }

    private static let allProtocols = AIProtocolKind.allCases

    @objc public static func currentProtocolIndex() -> Int {
        let cfg = AIConfigStore.shared.load()
        return allProtocols.firstIndex(of: cfg.protocolKind) ?? 0
    }

    @objc public static func currentBaseURL() -> String {
        AIConfigStore.shared.load().baseURL
    }

    @objc public static func currentModel() -> String {
        AIConfigStore.shared.load().model
    }

    @objc public static func currentAPIKey() -> String {
        AIConfigStore.shared.load().apiKey
    }

    @objc public static func currentCustomInstructions() -> String {
        AIConfigStore.shared.load().customInstructions
    }

    @objc public static func defaultBaseURL(forProtocolIndex index: Int) -> String {
        let kind = allProtocols.indices.contains(index) ? allProtocols[index] : .openAICompatible
        return kind.defaultBaseURL
    }

    @objc public static func defaultModel(forProtocolIndex index: Int) -> String {
        let kind = allProtocols.indices.contains(index) ? allProtocols[index] : .openAICompatible
        return kind.defaultModel
    }

    @objc public static func switchProtocolIndex(_ index: Int) {
        let kind = allProtocols.indices.contains(index) ? allProtocols[index] : .openAICompatible
        var cfg = AIConfigStore.shared.load()
        cfg.switchProtocol(to: kind)
        AIConfigStore.shared.save(cfg)
    }

    @objc public static func saveConfig(
        protocolIndex: Int,
        baseURL: String,
        model: String,
        apiKey: String,
        customInstructions: String
    ) {
        let kind = allProtocols.indices.contains(protocolIndex) ? allProtocols[protocolIndex] : .openAICompatible
        let cfg = AIConfig(
            protocolKind: kind,
            baseURL: baseURL,
            model: model,
            apiKey: apiKey,
            customInstructions: customInstructions
        )
        AIConfigStore.shared.save(cfg)
    }
}
