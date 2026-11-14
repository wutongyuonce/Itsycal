import Foundation

final class MemoryKeychainStore: AIKeychainStoring {
    var storage: [String: String] = [:]
    func readKey(account: String) -> String { storage[account] ?? "" }
    func writeKey(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { storage.removeValue(forKey: account) }
        else { storage[account] = trimmed }
    }
}

@main
enum AIAssistantCheck {
    static func main() throws {
        try checkConfigStoreAndProtocolSwitch()
        try checkMultiProtocolRequestsAndParsing()
        try checkCodeModeSandboxAndConflicts()
        print("AIAssistant checks passed: protocol config, multi-protocol request/response, CodeMode sandbox, batch loop, conflict detection and cap")
    }

    static func checkConfigStoreAndProtocolSwitch() throws {
        let suiteName = "com.wutongyuonce.Itsycal.AICheck.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keychain = MemoryKeychainStore()
        let store = AIConfigStore(defaults: defaults, keychain: keychain)

        var cfg = store.load()
        assert(cfg.protocolKind == .openAICompatible)
        assert(cfg.baseURL == "https://api.openai.com/v1")
        assert(cfg.model == "gpt-4o-mini")
        assert(!cfg.isConfigured)

        // Switching protocol while using default URL/model updates to the new protocol's defaults.
        cfg.switchProtocol(to: .anthropic)
        assert(cfg.baseURL == "https://api.anthropic.com/v1")
        assert(cfg.model == "claude-3-5-sonnet-latest")

        // Custom URL is preserved across protocol switches.
        cfg.baseURL = "https://my-proxy.example.com/v1"
        cfg.switchProtocol(to: .gemini)
        assert(cfg.baseURL == "https://my-proxy.example.com/v1")
        assert(cfg.model == "gemini-2.0-flash")

        cfg.apiKey = "sk-test-secret-123"
        cfg.customInstructions = "Default 45m meetings"
        store.save(cfg)

        // API key is stored in keychain only, never in UserDefaults.
        assert(keychain.readKey(account: "default") == "sk-test-secret-123")
        assert(defaults.string(forKey: "AIAPIKey") == nil)

        let loaded = store.load()
        assert(loaded == cfg && loaded.isConfigured)
    }

    static func checkMultiProtocolRequestsAndParsing() throws {
        let messages = [AIChatMessage(role: .user, content: "Schedule team sync tomorrow at 10am")]

        // 1. OpenAI Compatible
        let openAICfg = AIConfig(protocolKind: .openAICompatible, baseURL: "https://api.deepseek.com/v1/", model: "deepseek-chat", apiKey: "sk-oa")
        let openAIReq = try AILLMClient.buildRequest(config: openAICfg, systemPrompt: "SYS", messages: messages)
        assert(openAIReq.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        assert(openAIReq.value(forHTTPHeaderField: "Authorization") == "Bearer sk-oa")
        let openAIRespData = #"{"choices":[{"message":{"content":"Here is the code:\n```javascript\ncalendar.reply('ok');\n```"}}]}"#.data(using: .utf8)!
        let openAIText = try AILLMClient.parseResponse(data: openAIRespData, protocolKind: .openAICompatible)
        assert(AILLMClient.extractJSCode(from: openAIText) == "calendar.reply('ok');")

        // 2. Anthropic
        let claudeCfg = AIConfig(protocolKind: .anthropic, baseURL: "https://api.anthropic.com/v1", model: "claude-3-5-sonnet-latest", apiKey: "sk-ant")
        let claudeReq = try AILLMClient.buildRequest(config: claudeCfg, systemPrompt: "SYS", messages: messages)
        assert(claudeReq.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        assert(claudeReq.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        let claudeRespData = #"{"content":[{"type":"text","text":"```js\ncalendar.proposeEvent({title:'A',start:'2026-11-15T10:00:00'});\n```"}]}"#.data(using: .utf8)!
        let claudeText = try AILLMClient.parseResponse(data: claudeRespData, protocolKind: .anthropic)
        assert(AILLMClient.extractJSCode(from: claudeText).contains("calendar.proposeEvent"))

        // 3. Gemini
        let geminiCfg = AIConfig(protocolKind: .gemini, baseURL: "https://generativelanguage.googleapis.com/v1beta", model: "gemini-2.0-flash", apiKey: "gk-123")
        let geminiReq = try AILLMClient.buildRequest(config: geminiCfg, systemPrompt: "SYS", messages: messages)
        assert(geminiReq.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=gk-123")
        let geminiRespData = #"{"candidates":[{"content":{"parts":[{"text":"calendar.reply('done');"}]}}]}"#.data(using: .utf8)!
        let geminiText = try AILLMClient.parseResponse(data: geminiRespData, protocolKind: .gemini)
        assert(AILLMClient.extractJSCode(from: geminiText) == "calendar.reply('done');")

        // 4. Error payload surfaces as AICodeModeError.llmError
        let errData = #"{"error":{"message":"Invalid API key"}}"#.data(using: .utf8)!
        var caughtLLMError = false
        do {
            _ = try AILLMClient.parseResponse(data: errData, protocolKind: .openAICompatible)
        } catch AICodeModeError.llmError(let msg) {
            caughtLLMError = msg.contains("Invalid API key")
        }
        assert(caughtLLMError, "Error JSON must throw AICodeModeError.llmError")
    }

    static func checkCodeModeSandboxAndConflicts() throws {
        let tz = TimeZone(identifier: "Asia/Shanghai")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9, minute: 0))!
        let existingStart = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 15, minute: 0))!
        let existingEnd = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 16, minute: 0))!

        let host = AICodeModeHostContext(
            now: now,
            selectedDate: now,
            timeZone: tz,
            calendars: [
                AICalendarDescriptor(id: "cal-work", title: "工作", source: "iCloud", allowsEvents: true, allowsReminders: false, isDefaultEvent: true),
                AICalendarDescriptor(id: "rem-todo", title: "待办", source: "iCloud", allowsEvents: false, allowsReminders: true, isDefaultReminder: true),
            ],
            existingEvents: [
                AIExistingEventSnapshot(title: "产品周会", start: existingStart, end: existingEnd, isAllDay: false, calendarTitle: "工作", kind: .event),
            ]
        )

        let script = """
        const ctx = calendar.getContext();
        const existing = calendar.queryEvents('2026-11-16', '2026-11-17');
        for (let i = 0; i < 3; i++) {
            const day = 16 + i;
            calendar.proposeEvent({
                title: `算法复习 #${i + 1}`,
                start: `2026-11-${day}T15:00:00`,
                durationMinutes: 60,
                calendar: '工作',
                location: '书房',
                alertMinutes: 15
            });
        }
        calendar.proposeReminder({
            title: '提交周报',
            due: '2026-11-15',
            hasTime: false,
            list: '待办'
        });
        calendar.reply(`已根据 ${ctx.today} 生成计划（检测到当天已有 ${existing.length} 个日程）`);
        """

        let result = try AICodeModeRunner.run(script: script, host: host)
        assert(result.items.count == 4, "Should propose 3 events and 1 reminder")
        assert(result.reply.contains("2026-11-14") && result.reply.contains("已有 1 个日程"))

        let firstEvent = result.items[0]
        assert(firstEvent.kind == .event && firstEvent.title == "算法复习 #1")
        assert(firstEvent.calendarID == "cal-work")
        assert(firstEvent.conflictTitles == ["产品周会"], "Overlapping event on Nov 16 15:00 must report conflict")
        assert(result.items[1].conflictTitles.isEmpty, "Nov 17 event has no conflict")

        let reminder = result.items[3]
        assert(reminder.kind == .reminder && reminder.title == "提交周报")
        assert(!reminder.hasTime && reminder.isAllDay)
        assert(reminder.calendarID == "rem-todo")

        // Cap check: proposing 100 items is capped at maxProposedItems (50).
        let capScript = """
        for (let i = 0; i < 80; i++) {
            calendar.proposeEvent({ title: `Item ${i}`, start: '2026-11-20T10:00:00' });
        }
        """
        let capped = try AICodeModeRunner.run(script: capScript, host: host)
        assert(capped.items.count == AICodeModeRunner.maxProposedItems)

        // Exception handling check.
        var didThrow = false
        do {
            _ = try AICodeModeRunner.run(script: "throw new Error('boom');", host: host)
        } catch AICodeModeError.scriptException(let msg) {
            didThrow = msg.contains("boom")
        }
        assert(didThrow, "JS exception must surface as AICodeModeError.scriptException")
    }
}
