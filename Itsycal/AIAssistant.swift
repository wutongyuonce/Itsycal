import Foundation
import JavaScriptCore
import Security

public enum AIProtocolKind: String, CaseIterable, Codable, Sendable {
    case openAICompatible = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"

    public var label: String {
        switch self {
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropic: return "Anthropic (Claude)"
        case .gemini: return "Google Gemini"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openAICompatible: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAICompatible: return "gpt-4o-mini"
        case .anthropic: return "claude-3-5-sonnet-latest"
        case .gemini: return "gemini-2.0-flash"
        }
    }
}

public struct AIConfig: Equatable, Sendable {
    public var protocolKind: AIProtocolKind
    public var baseURL: String
    public var model: String
    public var apiKey: String
    public var customInstructions: String

    public init(
        protocolKind: AIProtocolKind = .openAICompatible,
        baseURL: String? = nil,
        model: String? = nil,
        apiKey: String = "",
        customInstructions: String = ""
    ) {
        self.protocolKind = protocolKind
        let trimmedBase = (baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = trimmedBase.isEmpty ? protocolKind.defaultBaseURL : trimmedBase
        self.model = trimmedModel.isEmpty ? protocolKind.defaultModel : trimmedModel
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customInstructions = customInstructions
    }

    public mutating func switchProtocol(to newKind: AIProtocolKind) {
        let oldKind = protocolKind
        protocolKind = newKind
        if baseURL == oldKind.defaultBaseURL || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseURL = newKind.defaultBaseURL
        }
        if model == oldKind.defaultModel || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model = newKind.defaultModel
        }
    }

    public var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public protocol AIKeychainStoring {
    func readKey(account: String) -> String
    func writeKey(_ value: String, account: String)
}

public struct SystemAIKeychainStore: AIKeychainStoring {
    private let service = "com.wutongyuonce.Itsycal.AI"

    public init() {}

    public func readKey(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    public func writeKey(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

public final class AIConfigStore {
    public static let shared = AIConfigStore()

    private let defaults: UserDefaults
    private let keychain: AIKeychainStoring

    private let kProtocol = "AIProtocolKind"
    private let kBaseURL = "AIBaseURL"
    private let kModel = "AIModel"
    private let kCustomInstructions = "AICustomInstructions"

    public init(defaults: UserDefaults = .standard, keychain: AIKeychainStoring = SystemAIKeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    public func load() -> AIConfig {
        let rawKind = defaults.string(forKey: kProtocol) ?? AIProtocolKind.openAICompatible.rawValue
        let kind = AIProtocolKind(rawValue: rawKind) ?? .openAICompatible
        let baseURL = defaults.string(forKey: kBaseURL)
        let model = defaults.string(forKey: kModel)
        let instructions = defaults.string(forKey: kCustomInstructions) ?? ""
        let apiKey = keychain.readKey(account: "default")
        return AIConfig(protocolKind: kind, baseURL: baseURL, model: model, apiKey: apiKey, customInstructions: instructions)
    }

    public func save(_ config: AIConfig) {
        defaults.set(config.protocolKind.rawValue, forKey: kProtocol)
        defaults.set(config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: kBaseURL)
        defaults.set(config.model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: kModel)
        defaults.set(config.customInstructions, forKey: kCustomInstructions)
        keychain.writeKey(config.apiKey, account: "default")
    }
}

// MARK: - CodeMode Data Models

public enum AIProposedKind: String, Codable, Sendable {
    case event
    case reminder
}

public enum AIRepeatFrequency: String, Codable, CaseIterable, Sendable {
    case none
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly

    public var label: String {
        switch self {
        case .none: return ""
        case .daily: return "每天"
        case .weekly: return "每周"
        case .biweekly: return "每两周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
}

public struct AIProposedItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: AIProposedKind
    public var selected: Bool
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var hasTime: Bool
    public var calendarID: String
    public var calendarTitle: String
    public var calendarColorRGB: [Double]
    public var location: String?
    public var notes: String?
    public var repeatFrequency: AIRepeatFrequency
    public var repeatEndDate: Date?
    public var alertMinutesBefore: Int?
    public var priority: Int
    public var conflictTitles: [String]

    public init(
        id: UUID = UUID(),
        kind: AIProposedKind,
        selected: Bool = true,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        hasTime: Bool = true,
        calendarID: String,
        calendarTitle: String,
        calendarColorRGB: [Double] = [0.2, 0.5, 0.95],
        location: String? = nil,
        notes: String? = nil,
        repeatFrequency: AIRepeatFrequency = .none,
        repeatEndDate: Date? = nil,
        alertMinutesBefore: Int? = nil,
        priority: Int = 0,
        conflictTitles: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.selected = selected
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.hasTime = hasTime
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColorRGB = calendarColorRGB
        self.location = location
        self.notes = notes
        self.repeatFrequency = repeatFrequency
        self.repeatEndDate = repeatEndDate
        self.alertMinutesBefore = alertMinutesBefore
        self.priority = priority
        self.conflictTitles = conflictTitles
    }
}

public struct AICalendarDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let source: String
    public let allowsEvents: Bool
    public let allowsReminders: Bool
    public let isDefaultEvent: Bool
    public let isDefaultReminder: Bool
    public let colorRGB: [Double]

    public init(
        id: String,
        title: String,
        source: String,
        allowsEvents: Bool,
        allowsReminders: Bool,
        isDefaultEvent: Bool = false,
        isDefaultReminder: Bool = false,
        colorRGB: [Double] = [0.2, 0.5, 0.95]
    ) {
        self.id = id
        self.title = title
        self.source = source
        self.allowsEvents = allowsEvents
        self.allowsReminders = allowsReminders
        self.isDefaultEvent = isDefaultEvent
        self.isDefaultReminder = isDefaultReminder
        self.colorRGB = colorRGB
    }
}

public struct AIExistingEventSnapshot: Codable, Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let kind: AIProposedKind

    public init(title: String, start: Date, end: Date, isAllDay: Bool, calendarTitle: String, kind: AIProposedKind = .event) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.kind = kind
    }
}

public struct AICodeModeHostContext: Sendable {
    public let now: Date
    public let selectedDate: Date
    public let timeZone: TimeZone
    public let calendars: [AICalendarDescriptor]
    public let existingEvents: [AIExistingEventSnapshot]
    public let currentDrafts: [AIProposedItem]

    public init(
        now: Date,
        selectedDate: Date,
        timeZone: TimeZone = .current,
        calendars: [AICalendarDescriptor],
        existingEvents: [AIExistingEventSnapshot],
        currentDrafts: [AIProposedItem] = []
    ) {
        self.now = now
        self.selectedDate = selectedDate
        self.timeZone = timeZone
        self.calendars = calendars
        self.existingEvents = existingEvents
        self.currentDrafts = currentDrafts
    }
}

public struct AICodeModeResult: Equatable, Sendable {
    public let reply: String
    public let items: [AIProposedItem]
}

public enum AICodeModeError: LocalizedError, Equatable {
    case notConfigured
    case invalidEndpoint(String)
    case scriptException(String)
    case emptyScript
    case llmError(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "请先在“设置 › AI”中填写 API URL、Model 和 API Key。"
        case .invalidEndpoint(let url):
            return "无效的 API 地址：\(url)"
        case .scriptException(let msg):
            return "AI 工具脚本执行出错：\(msg)"
        case .emptyScript:
            return "AI 未返回可执行的日程脚本。"
        case .llmError(let msg):
            return msg
        }
    }
}

// MARK: - JavaScriptCore CodeMode Sandbox Runner

public enum AICodeModeRunner {
    public static let maxProposedItems = 50

    public static func run(script: String, host: AICodeModeHostContext) throws -> AICodeModeResult {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AICodeModeError.emptyScript }

        guard let jsContext = JSContext() else {
            throw AICodeModeError.scriptException("无法创建 JavaScriptContext")
        }

        var capturedException: String?
        jsContext.exceptionHandler = { _, exception in
            capturedException = exception?.toString() ?? "Unknown JS error"
        }

        var proposed: [AIProposedItem] = []
        var assistantMessage = ""

        var calFormat = Calendar(identifier: .gregorian)
        calFormat.timeZone = host.timeZone

        let localISO = DateFormatter()
        localISO.locale = Locale(identifier: "en_US_POSIX")
        localISO.calendar = calFormat
        localISO.timeZone = host.timeZone
        localISO.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let dayOnlyISO = DateFormatter()
        dayOnlyISO.locale = Locale(identifier: "en_US_POSIX")
        dayOnlyISO.calendar = calFormat
        dayOnlyISO.timeZone = host.timeZone
        dayOnlyISO.dateFormat = "yyyy-MM-dd"

        let shortTime = DateFormatter()
        shortTime.locale = Locale(identifier: "en_US_POSIX")
        shortTime.calendar = calFormat
        shortTime.timeZone = host.timeZone
        shortTime.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let isoWithOffset = ISO8601DateFormatter()
        isoWithOffset.formatOptions = [.withInternetDateTime]

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ raw: Any?, defaultHour: Int = 9) -> (date: Date, hasExplicitTime: Bool)? {
            guard let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return nil
            }
            if text.count == 10, let d = dayOnlyISO.date(from: text) {
                return (d, false)
            }
            if let d = localISO.date(from: text) {
                return (d, true)
            }
            if let d = shortTime.date(from: text) {
                return (d, true)
            }
            if let d = isoWithOffset.date(from: text) {
                return (d, true)
            }
            if let d = isoWithFractional.date(from: text) {
                return (d, true)
            }
            // Fallback for "yyyy-MM-dd HH:mm" or "yyyy-MM-dd HH:mm:ss"
            let normalized = text.replacingOccurrences(of: " ", with: "T")
            if let d = localISO.date(from: normalized) ?? shortTime.date(from: normalized) {
                return (d, true)
            }
            return nil
        }

        func resolveEventCalendar(_ requested: String?) -> AICalendarDescriptor {
            let eventCals = host.calendars.filter { $0.allowsEvents }
            if let req = requested?.trimmingCharacters(in: .whitespacesAndNewlines), !req.isEmpty {
                if let exact = eventCals.first(where: { $0.id == req || $0.title.caseInsensitiveCompare(req) == .orderedSame }) {
                    return exact
                }
                if let partial = eventCals.first(where: { $0.title.localizedCaseInsensitiveContains(req) }) {
                    return partial
                }
            }
            if let def = eventCals.first(where: { $0.isDefaultEvent }) { return def }
            return eventCals.first ?? AICalendarDescriptor(id: "default-event", title: "日历", source: "Local", allowsEvents: true, allowsReminders: false)
        }

        func resolveReminderCalendar(_ requested: String?) -> AICalendarDescriptor {
            let remCals = host.calendars.filter { $0.allowsReminders }
            if let req = requested?.trimmingCharacters(in: .whitespacesAndNewlines), !req.isEmpty {
                if let exact = remCals.first(where: { $0.id == req || $0.title.caseInsensitiveCompare(req) == .orderedSame }) {
                    return exact
                }
                if let partial = remCals.first(where: { $0.title.localizedCaseInsensitiveContains(req) }) {
                    return partial
                }
            }
            if let def = remCals.first(where: { $0.isDefaultReminder }) { return def }
            return remCals.first ?? AICalendarDescriptor(id: "default-reminder", title: "提醒事项", source: "Local", allowsEvents: false, allowsReminders: true)
        }

        func detectConflicts(start: Date, end: Date, isAllDay: Bool) -> [String] {
            guard !isAllDay else { return [] }
            var conflicts: [String] = []
            for ev in host.existingEvents where ev.kind == .event && !ev.isAllDay {
                if start < ev.end && end > ev.start {
                    if !conflicts.contains(ev.title) {
                        conflicts.append(ev.title)
                    }
                }
            }
            return conflicts
        }

        let getContextBlock: @convention(block) () -> NSDictionary = {
            let weekdaySymbols = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            let wd = max(1, min(7, calFormat.component(.weekday, from: host.now)))
            return [
                "now": localISO.string(from: host.now),
                "today": dayOnlyISO.string(from: host.now),
                "selectedDate": dayOnlyISO.string(from: host.selectedDate),
                "weekday": weekdaySymbols[wd - 1],
                "timeZone": host.timeZone.identifier,
            ]
        }

        let listCalendarsBlock: @convention(block) () -> NSArray = {
            let mapped = host.calendars.map { cal -> [String: Any] in
                [
                    "id": cal.id,
                    "title": cal.title,
                    "source": cal.source,
                    "allowsEvents": cal.allowsEvents,
                    "allowsReminders": cal.allowsReminders,
                    "isDefaultEvent": cal.isDefaultEvent,
                    "isDefaultReminder": cal.isDefaultReminder,
                ]
            }
            return mapped as NSArray
        }

        let queryEventsBlock: @convention(block) (JSValue?, JSValue?) -> NSArray = { startVal, endVal in
            let startDate = parseDate(startVal?.toString())?.date ?? calFormat.startOfDay(for: host.now)
            let endDate = parseDate(endVal?.toString())?.date ?? calFormat.date(byAdding: .day, value: 14, to: startDate)!
            let matches = host.existingEvents.filter { ev in
                ev.start < endDate && ev.end >= startDate
            }.map { ev -> [String: Any] in
                [
                    "title": ev.title,
                    "start": ev.isAllDay ? dayOnlyISO.string(from: ev.start) : localISO.string(from: ev.start),
                    "end": ev.isAllDay ? dayOnlyISO.string(from: ev.end) : localISO.string(from: ev.end),
                    "isAllDay": ev.isAllDay,
                    "calendar": ev.calendarTitle,
                    "kind": ev.kind.rawValue,
                ]
            }
            return matches as NSArray
        }

        let getDraftsBlock: @convention(block) () -> NSArray = {
            let list = host.currentDrafts.map { item -> [String: Any] in
                [
                    "kind": item.kind.rawValue,
                    "title": item.title,
                    "start": item.isAllDay ? dayOnlyISO.string(from: item.startDate) : localISO.string(from: item.startDate),
                    "end": item.isAllDay ? dayOnlyISO.string(from: item.endDate) : localISO.string(from: item.endDate),
                    "isAllDay": item.isAllDay,
                    "hasTime": item.hasTime,
                    "calendar": item.calendarTitle,
                    "location": item.location ?? "",
                    "notes": item.notes ?? "",
                    "repeat": item.repeatFrequency.rawValue,
                ]
            }
            return list as NSArray
        }

        let proposeEventBlock: @convention(block) (JSValue?) -> Bool = { rawVal in
            guard proposed.count < Self.maxProposedItems,
                  let dict = rawVal?.toDictionary() as? [String: Any] else {
                return false
            }
            let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return false }

            guard let parsedStart = parseDate(dict["start"] ?? dict["startDate"]) else {
                return false
            }
            let explicitAllDay = (dict["isAllDay"] as? Bool) ?? (dict["allDay"] as? Bool)
            let isAllDay = explicitAllDay ?? (!parsedStart.hasExplicitTime)
            let startDate = isAllDay ? calFormat.startOfDay(for: parsedStart.date) : parsedStart.date

            let endDate: Date
            if let parsedEnd = parseDate(dict["end"] ?? dict["endDate"]) {
                let candidate = isAllDay ? calFormat.startOfDay(for: parsedEnd.date) : parsedEnd.date
                endDate = candidate >= startDate ? candidate : startDate.addingTimeInterval(isAllDay ? 0 : 3600)
            } else if let durationMinutes = (dict["durationMinutes"] as? NSNumber)?.doubleValue, durationMinutes > 0 {
                endDate = isAllDay ? startDate : startDate.addingTimeInterval(durationMinutes * 60)
            } else {
                endDate = isAllDay ? startDate : startDate.addingTimeInterval(3600)
            }

            let calDesc = resolveEventCalendar((dict["calendarId"] as? String) ?? (dict["calendar"] as? String))
            let location = (dict["location"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = (dict["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let repeatRaw = ((dict["repeat"] as? String) ?? "none").lowercased()
            let repeatFreq = AIRepeatFrequency(rawValue: repeatRaw) ?? .none
            let repeatEnd = parseDate(dict["repeatEnd"] ?? dict["repeatEndDate"])?.date
            let alertMinutes = (dict["alertMinutes"] as? NSNumber)?.intValue

            let item = AIProposedItem(
                kind: .event,
                selected: true,
                title: title,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                hasTime: !isAllDay,
                calendarID: calDesc.id,
                calendarTitle: calDesc.title,
                calendarColorRGB: calDesc.colorRGB,
                location: (location?.isEmpty == false) ? location : nil,
                notes: (notes?.isEmpty == false) ? notes : nil,
                repeatFrequency: repeatFreq,
                repeatEndDate: repeatEnd,
                alertMinutesBefore: alertMinutes,
                priority: 0,
                conflictTitles: detectConflicts(start: startDate, end: endDate, isAllDay: isAllDay)
            )
            proposed.append(item)
            return true
        }

        let proposeReminderBlock: @convention(block) (JSValue?) -> Bool = { rawVal in
            guard proposed.count < Self.maxProposedItems,
                  let dict = rawVal?.toDictionary() as? [String: Any] else {
                return false
            }
            let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return false }

            let parsedDue = parseDate(dict["due"] ?? dict["dueDate"] ?? dict["start"])
            let explicitHasTime = dict["hasTime"] as? Bool
            let hasTime = explicitHasTime ?? (parsedDue?.hasExplicitTime ?? false)
            let baseDue = parsedDue?.date ?? calFormat.startOfDay(for: host.selectedDate)
            let dueDate = hasTime ? baseDue : calFormat.startOfDay(for: baseDue)

            let calDesc = resolveReminderCalendar((dict["listId"] as? String) ?? (dict["list"] as? String) ?? (dict["calendar"] as? String))
            let notes = (dict["notes"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let repeatRaw = ((dict["repeat"] as? String) ?? "none").lowercased()
            let repeatFreq = AIRepeatFrequency(rawValue: repeatRaw) ?? .none
            let repeatEnd = parseDate(dict["repeatEnd"] ?? dict["repeatEndDate"])?.date
            let alertMinutes = (dict["alertMinutes"] as? NSNumber)?.intValue
            let priority = (dict["priority"] as? NSNumber)?.intValue ?? 0

            let item = AIProposedItem(
                kind: .reminder,
                selected: true,
                title: title,
                startDate: dueDate,
                endDate: dueDate,
                isAllDay: !hasTime,
                hasTime: hasTime,
                calendarID: calDesc.id,
                calendarTitle: calDesc.title,
                calendarColorRGB: calDesc.colorRGB,
                location: nil,
                notes: (notes?.isEmpty == false) ? notes : nil,
                repeatFrequency: repeatFreq,
                repeatEndDate: repeatEnd,
                alertMinutesBefore: alertMinutes,
                priority: priority,
                conflictTitles: []
            )
            proposed.append(item)
            return true
        }

        let setReplyBlock: @convention(block) (JSValue?) -> Void = { val in
            if let text = val?.toString(), text != "undefined", text != "null" {
                assistantMessage = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        jsContext.setObject(getContextBlock, forKeyedSubscript: "__itsycalGetContext" as NSString)
        jsContext.setObject(listCalendarsBlock, forKeyedSubscript: "__itsycalListCalendars" as NSString)
        jsContext.setObject(queryEventsBlock, forKeyedSubscript: "__itsycalQueryEvents" as NSString)
        jsContext.setObject(getDraftsBlock, forKeyedSubscript: "__itsycalGetDrafts" as NSString)
        jsContext.setObject(proposeEventBlock, forKeyedSubscript: "__itsycalProposeEvent" as NSString)
        jsContext.setObject(proposeReminderBlock, forKeyedSubscript: "__itsycalProposeReminder" as NSString)
        jsContext.setObject(setReplyBlock, forKeyedSubscript: "__itsycalSetReply" as NSString)

        let prelude = """
        const calendar = {
            getContext: () => __itsycalGetContext(),
            listCalendars: () => __itsycalListCalendars(),
            queryEvents: (start, end) => __itsycalQueryEvents(start, end),
            getDrafts: () => __itsycalGetDrafts(),
            proposeEvent: (item) => __itsycalProposeEvent(item),
            proposeReminder: (item) => __itsycalProposeReminder(item),
            proposeBatch: (items) => {
                if (!Array.isArray(items)) return 0;
                let count = 0;
                for (const it of items) {
                    if (it && it.kind === 'reminder') {
                        if (__itsycalProposeReminder(it)) count++;
                    } else if (it) {
                        if (__itsycalProposeEvent(it)) count++;
                    }
                }
                return count;
            },
            reply: (msg) => __itsycalSetReply(msg)
        };
        """
        jsContext.evaluateScript(prelude)
        let evalResult = jsContext.evaluateScript(trimmed)

        if let err = capturedException {
            throw AICodeModeError.scriptException(err)
        }

        if assistantMessage.isEmpty,
           let str = evalResult?.toString(),
           str != "undefined", str != "null", str != "true", str != "false",
           !str.hasPrefix("[object ") {
            assistantMessage = str.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if assistantMessage.isEmpty {
            if proposed.isEmpty {
                assistantMessage = "未生成待办日程，请补充具体时间或事件内容。"
            } else {
                let eventCount = proposed.filter { $0.kind == .event }.count
                let remCount = proposed.filter { $0.kind == .reminder }.count
                var parts: [String] = []
                if eventCount > 0 { parts.append("\(eventCount) 个日程") }
                if remCount > 0 { parts.append("\(remCount) 个提醒事项") }
                assistantMessage = "已为您生成 " + parts.joined(separator: "、") + "，请确认或继续微调："
            }
        }

        return AICodeModeResult(reply: assistantMessage, items: proposed)
    }
}

// MARK: - Multi-Protocol LLM Client

public struct AIChatMessage: Equatable, Sendable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }
    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public enum AILLMClient {
    public static func systemPrompt(host: AICodeModeHostContext, customInstructions: String) -> String {
        var calFormat = Calendar(identifier: .gregorian)
        calFormat.timeZone = host.timeZone

        let localISO = DateFormatter()
        localISO.locale = Locale(identifier: "en_US_POSIX")
        localISO.calendar = calFormat
        localISO.timeZone = host.timeZone
        localISO.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.calendar = calFormat
        dayOnly.timeZone = host.timeZone
        dayOnly.dateFormat = "yyyy-MM-dd"

        let weekdaySymbols = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let wd = max(1, min(7, calFormat.component(.weekday, from: host.now)))

        let calLines = host.calendars.map { c in
            var tags: [String] = []
            if c.allowsEvents { tags.append("event") }
            if c.allowsReminders { tags.append("reminder") }
            if c.isDefaultEvent { tags.append("defaultEvent") }
            if c.isDefaultReminder { tags.append("defaultReminder") }
            return "- \(c.title) (id: \(c.id), types: \(tags.joined(separator: ",")))"
        }.joined(separator: "\n")

        var draftsSection = ""
        if !host.currentDrafts.isEmpty {
            let draftLines = host.currentDrafts.enumerated().map { idx, d in
                let startStr = d.isAllDay ? dayOnly.string(from: d.startDate) : localISO.string(from: d.startDate)
                let endStr = d.isAllDay ? dayOnly.string(from: d.endDate) : localISO.string(from: d.endDate)
                return "\(idx + 1). [\(d.kind.rawValue)] title=\"\(d.title)\", start=\"\(startStr)\", end=\"\(endStr)\", isAllDay=\(d.isAllDay), hasTime=\(d.hasTime), calendar=\"\(d.calendarTitle)\", repeat=\"\(d.repeatFrequency.rawValue)\", location=\"\(d.location ?? "")\", notes=\"\(d.notes ?? "")\""
            }.joined(separator: "\n")
            draftsSection = """

            Current pending drafts (when the user asks to modify/adjust/delete items, output a complete updated draft list using calendar.proposeEvent / calendar.proposeReminder):
            \(draftLines)
            """
        }

        let extra = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraSection = extra.isEmpty ? "" : "\nUser custom preferences:\n\(extra)\n"

        return """
        You are Itsycal's calendar & reminders CodeMode assistant.
        Respond with a single ```javascript code block that uses the built-in `calendar` sandbox object to propose events or reminders.

        Context:
        - Current local time: \(localISO.string(from: host.now)) (\(weekdaySymbols[wd - 1]), TimeZone: \(host.timeZone.identifier))
        - Selected calendar date in UI: \(dayOnly.string(from: host.selectedDate))
        - Available calendars & reminder lists:
        \(calLines.isEmpty ? "(default system calendar)" : calLines)\(draftsSection)\(extraSection)

        Available synchronous JS APIs on `calendar`:
        - `calendar.getContext()` -> `{ now, today, selectedDate, weekday, timeZone }`
        - `calendar.listCalendars()` -> `Array<{ id, title, source, allowsEvents, allowsReminders, isDefaultEvent, isDefaultReminder }>`
        - `calendar.queryEvents(startISO, endISO)` -> `Array<{ title, start, end, isAllDay, calendar, kind }>`
        - `calendar.getDrafts()` -> current staged drafts array
        - `calendar.proposeEvent({ title, start, end, durationMinutes, isAllDay, calendar, location, notes, repeat, repeatEnd, alertMinutes })`
          - `start` / `end`: local ISO string `"YYYY-MM-DDTHH:mm:ss"` (or `"YYYY-MM-DD"` for all-day).
          - `repeat`: `"none" | "daily" | "weekly" | "biweekly" | "monthly" | "yearly"`.
        - `calendar.proposeReminder({ title, due, hasTime, list, notes, repeat, repeatEnd, alertMinutes, priority })`
          - `due`: `"YYYY-MM-DDTHH:mm:ss"` when `hasTime: true`, or `"YYYY-MM-DD"` when `hasTime: false`.
        - `calendar.reply("short summary in user's language")`

        Rules:
        1. Output ONLY valid JavaScript inside a ```javascript ... ``` block. Do not use external imports or async/await.
        2. Use loops or date arithmetic in JS when the user asks for multiple or batch events.
        3. Use `calendar.proposeReminder` when the user mentions reminders/todos (提醒/待办), and `calendar.proposeEvent` for calendar events/meetings/schedules (日程/会议/安排).
        4. Always call `calendar.reply(...)` with a concise, friendly confirmation message in the user's language.
        """
    }

    public static func buildRequest(
        config: AIConfig,
        systemPrompt: String,
        messages: [AIChatMessage]
    ) throws -> URLRequest {
        guard config.isConfigured else { throw AICodeModeError.notConfigured }
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)

        switch config.protocolKind {
        case .openAICompatible:
            let urlString = base.hasSuffix("/chat/completions") ? base : "\(base)/chat/completions"
            guard let url = URL(string: urlString), url.scheme != nil, url.host != nil else {
                throw AICodeModeError.invalidEndpoint(config.baseURL)
            }
            var req = URLRequest(url: url, timeoutInterval: 45)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

            var payloadMessages: [[String: String]] = [["role": "system", "content": systemPrompt]]
            for m in messages {
                payloadMessages.append(["role": m.role.rawValue, "content": m.content])
            }
            let body: [String: Any] = [
                "model": config.model,
                "messages": payloadMessages,
                "temperature": 0.1,
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req

        case .anthropic:
            let urlString = base.hasSuffix("/messages") ? base : "\(base)/messages"
            guard let url = URL(string: urlString), url.scheme != nil, url.host != nil else {
                throw AICodeModeError.invalidEndpoint(config.baseURL)
            }
            var req = URLRequest(url: url, timeoutInterval: 45)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            let payloadMessages = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
            let body: [String: Any] = [
                "model": config.model,
                "max_tokens": 2048,
                "system": systemPrompt,
                "messages": payloadMessages,
                "temperature": 0.1,
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req

        case .gemini:
            let encodedModel = config.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.model
            let endpoint: String
            if base.contains(":generateContent") {
                endpoint = base
            } else if base.hasSuffix("/models") {
                endpoint = "\(base)/\(encodedModel):generateContent"
            } else {
                endpoint = "\(base)/models/\(encodedModel):generateContent"
            }
            var components = URLComponents(string: endpoint)
            var queryItems = components?.queryItems ?? []
            if !queryItems.contains(where: { $0.name == "key" }) {
                queryItems.append(URLQueryItem(name: "key", value: config.apiKey))
            }
            components?.queryItems = queryItems
            guard let url = components?.url, url.scheme != nil, url.host != nil else {
                throw AICodeModeError.invalidEndpoint(config.baseURL)
            }
            var req = URLRequest(url: url, timeoutInterval: 45)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let contents = messages.map { m -> [String: Any] in
                [
                    "role": m.role == .assistant ? "model" : "user",
                    "parts": [["text": m.content]],
                ]
            }
            let body: [String: Any] = [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": contents,
                "generationConfig": ["temperature": 0.1],
            ]
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            return req
        }
    }

    public static func parseResponse(data: Data, protocolKind: AIProtocolKind) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "Invalid JSON"
            throw AICodeModeError.llmError("无法解析接口响应：\(raw.prefix(200))")
        }
        if let errDict = json["error"] as? [String: Any],
           let msg = errDict["message"] as? String {
            throw AICodeModeError.llmError("接口返回错误：\(msg)")
        }

        switch protocolKind {
        case .openAICompatible:
            if let choices = json["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        case .anthropic:
            if let contentArr = json["content"] as? [[String: Any]] {
                let texts = contentArr.compactMap { $0["text"] as? String }
                if !texts.isEmpty { return texts.joined(separator: "\n") }
            }
        case .gemini:
            if let candidates = json["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let content = first["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                let texts = parts.compactMap { $0["text"] as? String }
                if !texts.isEmpty { return texts.joined(separator: "\n") }
            }
        }
        throw AICodeModeError.llmError("接口未返回有效文本内容。")
    }

    public static func extractJSCode(from responseText: String) -> String {
        let pattern = "```(?:javascript|js)?\\s*\\n([\\s\\S]*?)```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let nsRange = NSRange(responseText.startIndex..<responseText.endIndex, in: responseText)
            if let match = regex.firstMatch(in: responseText, options: [], range: nsRange),
               let codeRange = Range(match.range(at: 1), in: responseText) {
                return String(responseText[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return responseText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
