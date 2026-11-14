# Itsycal：AI 自然语言日程助手规格与设计契约

本文是 Itsycal macOS 端 AI 自然语言日程助手（Phase 1）的现行行为契约与模块架构设计。代码与本文冲突时以代码为事实，并同步修正本文。

## Part A：SPEC —— 系统必须满足什么

### 1. 背景与问题

- **当前用户可见行为**：Itsycal 仅提供基于传统表单的单个日程新建弹窗（`EventViewController`），且提醒事项（`EKReminder`）仅支持查看与勾选完成，不支持创建或批量创建。
- **造成的问题**：当用户需要通过自然语言快速排期、按复杂规则批量插入多个日程或提醒事项（例如“下周一开始每隔两天下午三点排一次复习，共 4 次，同时加一个明天上午十点的提醒事项”）时，只能逐条手动点击表单创建，且无法直接创建提醒事项。
- **受影响的用户或调用方**：使用 Itsycal 菜单栏弹窗管理日常日程与提醒事项的 macOS 用户。

### 2. 目标行为

1. 用户可在 **设置 › AI** 标签页中配置最常用的大模型协议（OpenAI 兼容接口、Anthropic Messages API、Google Gemini API）的 `Base URL`、`API Key` 与 `Model`。
2. 用户可在主窗口工具栏点击 AI 按钮（或按 `⌘K`）拉起 AI 对话小窗口，用自然语言描述想要创建的日程（`EKEvent`）或提醒事项（`EKReminder`）。
3. AI 通过内置的 **CodeMode（JavaScriptCore 沙箱工具脚本）** 查询用户当前的日历/提醒列表、检查已有日程并生成待创建的事件/提醒事项草稿清单。
4. 对话小窗口以可视化卡片清单展示将要创建的事件与提醒事项（支持勾选/取消单项、提示时间冲突），用户可执行以下任一动作：
   - **确认添加**：原子化批量写入系统 EventKit（日历与提醒事项），并支持在主窗口通过一次 `⌘Z` 整批撤回；
   - **继续发话调整**：在输入框继续发送自然语言修改意见，AI 基于当前草稿清单更新预览卡片；
   - **放弃**：清空待确认草稿或关闭弹窗，不修改任何系统日历数据。

### 3. 范围与主要场景

- **场景 1：配置 AI 服务**
  - 参与者：用户、`PrefsAIVC`、`AIConfigStore`。
  - 前置状态：未配置或已配置 AI 参数。
  - 操作顺序：打开设置窗口切换到 AI 标签页 -> 选择协议（切换协议时若 URL/Model 为上一协议的默认值则自动填入新协议默认值） -> 输入 Base URL、Model 与 API Key。
  - 结果：协议、URL、Model 存入 `NSUserDefaults`，API Key 存入 macOS Keychain（无文件明文残留）。
- **场景 2：自然语言生成日程与提醒草稿（CodeMode）**
  - 参与者：用户、`AIAssistantPopover`、`AIAssistantEngine`、`AICodeModeRunner`、`EventCenter`。
  - 前置状态：已完成 AI 配置，且拥有至少一个可修改的日历或提醒事项列表。
  - 操作顺序：点击主窗口 AI 按钮（`⌘K`）打开弹窗 -> 输入自然语言需求并发送 -> LLM 生成 JavaScript 代码 -> `AICodeModeRunner` 在内存隔离的 `JSContext` 中执行脚本，调用宿主提供的只读查询工具（`getContext`、`listCalendars`、`queryEvents`）与草稿提议工具（`proposeEvent`、`proposeReminder`） -> UI 展示待创建的卡片列表。
  - 结果：未写入 `EKEventStore`，仅在弹窗中展示结构化预览卡片（区分日程与提醒、显示目标日历颜色、时间、重复规则及冲突标记）。
- **场景 3：多轮自然语言微调草稿**
  - 参与者：用户、`AIAssistantPopover`、`AIAssistantEngine`。
  - 前置状态：当前对话窗口已有待确认的草稿清单。
  - 操作顺序：用户直接输入调整指令（如“把全部会议推迟 1 小时，删掉最后一个”）并发送。
  - 结果：AI 结合当前草稿状态执行新一轮脚本，原地替换待确认草稿清单。
- **场景 4：确认批量写入与一键撤销**
  - 参与者：用户、`AIAssistantPopover`、`EventCenter`。
  - 前置状态：草稿清单中至少有 1 项被勾选。
  - 操作顺序：点击“确认添加”按钮 -> `EventCenter` 将所有勾选项转为 `EKEvent` / `EKReminder` 并通过一次 `[_store commit:&error]` 批量提交 -> 注册合并的 `NSUndoManager` 撤销动作 -> 关闭弹窗并刷新月历与议程列表。
  - 结果：所有勾选的日程与提醒事项写入系统日历；用户在主窗口按 `⌘Z` 可一次性撤回整批新增项（若某项已在外部被修改则跳过该项或蜂鸣提示）。

### 4. 产品 RULE 与不变量

| ID | Rule / invariant | 适用场景 | 违反时的结果 |
|---|---|---|---|
| R1 | AI 脚本执行阶段严禁直接写入 `EKEventStore`；只有用户显式点击“确认添加”才能触发持久化写入。 | 所有自然语言对话与调整 | 拒绝隐式写盘，保证零误操作污染 |
| R2 | 批量提交采用两阶段事务（逐项 `commit:NO` + 最终一次 `[_store commit:&error]`）。 | 确认添加多个日程/提醒 | 任一环节失败时执行 `[_store reset]` 回滚未提交变更，不留半成品 |
| R3 | 提醒事项（`EKReminder`）无具体时间时 `dueDateComponents` 的 `hour/minute` 必须为 `NSDateComponentUndefined`；全天日程（`EKEvent.allDay = YES`）的 `timeZone` 必须为 `nil`。 | 生成与保存日程/提醒 | 严格对齐 EventKit 与 Calendar.app 语义，避免全天日程跨时区错位 |
| R4 | CodeMode 沙箱仅暴露纯内存宿主桥接函数，不暴露文件系统、Shell 或任意网络访问，且单次脚本提议条数上限为 50 条。 | CodeMode 脚本执行 | 超出上限自动截断；语法或运行时错误转为可读错误反馈 |
| R5 | API Key 仅存储在系统 Keychain（测试环境可注入内存 stub），不写入 `NSUserDefaults`。 | 设置保存与读取 | 防止偏好设置 plist 泄露密钥 |

### 5. 失败、取消和恢复语义

- **未配置 API Key 或 URL 无效**：点击发送时立即在弹窗内显示明确错误提示，并提供一键打开“设置 › AI”的入口。
- **网络请求失败或用户取消**：支持随时取消进行中的请求；失败时保留用户已输入的文本和上一轮有效的草稿清单，允许重试。
- **CodeMode 脚本语法/运行时异常**：若 LLM 返回的代码执行报错，`AIAssistantEngine` 自动携带错误信息发起最多 1 次自愈重试；若仍失败，向用户展示错误摘要。
- **EventKit 权限缺失或无目标列表**：若脚本提议了提醒事项但用户尚未授权提醒事项，在确认添加前自動调用 `requestRemindersAccessWithCompletion:` 请求授权；若最终无可写日历/列表，回滚事务并弹窗报错。

### 6. 并发、资源与性能约束

- **线程模型**：LLM 网络请求在 `URLSession` 异步任务中执行；`JSContext` 脚本求值与 `EventCenter` 查询/提交在主线程协调（读取 `EventCenter` 的线程安全快照 `-sourcesAndCalendars` 与 `-filteredEventsForDate`），避免阻塞 UI 渲染。
- **资源边界**：单次 CodeMode 提议最多保留 50 个草稿项；HTTP 请求超时设为 45 秒。

### 7. 非目标

- 不在 Phase 1 中支持通过 AI 修改或删除用户日历中**已存在**的历史事件（仅限查询已有事件以辅助排期，并创建新事件/新提醒，确保绝对安全）。
- 不引入第三方重型 SDK、Python/Node 外部进程或本地向量数据库。

### 8. 验收标准

| Obligation | 可观察证据 | 验证层级 |
|---|---|---|
| O1：多协议配置与 Keychain 存储 | 切换协议默认值正确，URL/Model 持久化，API Key 读写正确 | Owner unit test (`Tests/AIAssistantCheck.swift`) |
| O2：三类协议（OpenAI / Anthropic / Gemini）请求构建与响应代码提取 | 给定配置与消息能生成符合各协议规范的 HTTP 请求，并从 Markdown 代码块或裸文本中提取 JS 代码 | Owner unit test (`Tests/AIAssistantCheck.swift`) |
| O3：CodeMode 沙箱查询与批量提议（含循环排期、冲突检测、上限截断） | `AICodeModeRunner` 执行 JS 脚本后准确产出 `ProposedEvent` 与 `ProposedReminder` 数组，并标记时间冲突 | Owner unit test (`Tests/AIAssistantCheck.swift`) |
| O4：EventCenter 批量保存日程与提醒事项及一键 Undo/Redo | `-saveBatchEvents:reminders:undoManager:error:` 原子提交并能通过一次 `undo` / `redo` 完整撤回和恢复 | Owner unit test (`Tests/EventCenterCheck.m`) |
| O5：Xcode 完整构建与现有回归测试全部通过 | `bash Tests/check-week.sh` 与 `xcodebuild` Release 构建通过，并成功安装替换本机 `/Applications/Itsycal.app` | Workspace integration & live app |

## Part B：设计报告 —— module 如何满足 SPEC

### 1. 当前架构和数据流

```text
PrefsAIVC ──> AIAssistantBridge ──> AIConfigStore (NSUserDefaults + Keychain)
                                          │
                                          ▼
ViewController (✨ 按钮 / ⌘K)
  ──> AIAssistantPopoverView (SwiftUI + NSHostingController)
        ├── 1. 自然语言输入 / 多轮微调 ──> AIAssistantViewModel
        │                                   ├── AILLMClient (OpenAI / Anthropic / Gemini)
        │                                   └── AICodeModeRunner (JSContext 沙箱)
        │                                         ├── 只读桥接: getContext / listCalendars / queryEvents / getDrafts
        │                                         └── 草稿桥接: proposeEvent / proposeReminder / proposeBatch / reply
        ├── 2. 渲染待确认卡片清单 (勾选、冲突高亮、放弃)
        └── 3. 确认添加 ──> ViewController (-aiCommitItems:completion:)
                              ──> EventCenter (-saveBatchEvents:reminders:undoManager:error:)
                                    ──> EKEventStore 一次 commit + NSUndoManager 整批撤销
```

### 2. Authority、interface 与 seam

| Rule/state/error/resource | Authority module | Interface/seam | Callers | Evidence |
|---|---|---|---|---|
| EventKit 实例创建、批量原子提交、批量 Undo/Redo | `EventCenter` (`Itsycal/EventCenter.h/.m`) | `-newReminder`, `-defaultReminderCalendarIdentifier`, `-saveBatchEvents:reminders:undoManager:error:` | `ViewController` | `Tests/EventCenterCheck.m` |
| AI 协议、URL、Model 与 API Key 存储 | `AIConfigStore` (`Itsycal/AIAssistant.swift`) | `AIConfigStore.load()`, `AIConfigStore.save(_:)` | `AIAssistantBridge`, `AIAssistantViewModel` | `Tests/AIAssistantCheck.swift` |
| 三大 LLM 协议请求编码与响应解析 | `AILLMClient` (`Itsycal/AIAssistant.swift`) | `AILLMClient.buildRequest(...)`, `AILLMClient.parseResponse(...)`, `AILLMClient.extractJSCode(...)` | `AIAssistantViewModel` | `Tests/AIAssistantCheck.swift` |
| CodeMode JS 沙箱桥接、草稿校验与冲突标记 | `AICodeModeRunner` (`Itsycal/AIAssistant.swift`) | `AICodeModeRunner.run(script:host:)` | `AIAssistantViewModel` | `Tests/AIAssistantCheck.swift` |
| 设置页 AI 标签页与主窗口 Popover 挂载 | `PrefsAIVC` / `ViewController` / `AIAssistantBridge` | `PrefsVC` 子控制器、`-showAIAssistant:`、`AIAssistantHostDelegate` | 用户交互 | `xcodebuild` 编译与实机验证 |

### 3. 失败和资源处理

- **JS 沙箱异常**：`JSContext.exceptionHandler` 捕获脚本语法或运行时错误，转换为 `AICodeModeError.scriptException(String)`。`AIAssistantViewModel` 捕获后自动将报错回传给 LLM 自愈重试一次。
- **EventKit 提交回滚**：`-saveBatchEvents:reminders:undoManager:error:` 内部对每个 `EKEvent` 和 `EKReminder` 调用 `commit:NO`；若任意一项返回 `NO` 或最终 `[_store commit:error]` 失败，立即在 `_queueWork` 上同步执行 `[_store reset]` 丢弃未提交缓冲，随后触发 `-refetchAll`。

### 4. 实现机制

- **最小文件组织**：
  - `Itsycal/EventCenter.h` / `Itsycal/EventCenter.m`：新增 `-newReminder`、`-defaultReminderCalendarIdentifier` 与 `-saveBatchEvents:reminders:undoManager:error:`。
  - `Itsycal/AIAssistant.swift`：集中承载 `AIConfigStore`、`AILLMClient` 与 `AICodeModeRunner`（`JavaScriptCore`），纯 Foundation/Security/JavaScriptCore 依赖，便于独立单测与未来跨端复用。
  - `Itsycal/AIAssistantViews.swift`：承载 SwiftUI 实现的 `AIAssistantPopoverView`、`AIAssistantViewModel` 以及供 Objective-C 调用的桥接层 `AIAssistantBridge` / `AIAssistantHostDelegate`。
  - `Itsycal/Prefs/PrefsAIVC.h` / `Itsycal/Prefs/PrefsAIVC.m`：与现有 `PrefsGeneralVC` / `PrefsEventsVC` 一致采用原生 AppKit + `MoVFLHelper` 布局，保证设置窗口宽度与动态高度切换动画完全一致。
- **Xcode FileSystemSynchronizedRootGroup**：工程采用 Xcode 16+ 同步目录组（`Itsycal/` 下新增的 `.swift` 文件自动纳入 `Itsycal` Target 编译，无需手工膨胀 `project.pbxproj` 的文件引用表）。

### 5. 已接受的取舍

- **取舍 1：不在 JS 沙箱中提供异步 `fetch` 网络能力**。原因：日历排期所需上下文（当前时间、日历列表、近期日程）均可由宿主同步注入，禁用沙箱网络可彻底杜绝 prompt injection 数据外泄。
- **取舍 2：采用全量返回 CodeMode 脚本生成最终草稿，而非流式拼接 JSON**。原因：JS 脚本本身极其短小（通常 5–20 行），执行耗时 < 2ms，一次性求值可保证草稿卡片原子出现且无半截 JSON 闪烁。

### 6. 义务到测试的映射

| Obligation | Authority | Test | 为什么在这一层验证 |
|---|---|---|---|
| O1：配置与协议默认值 | `AIConfigStore` | `Tests/AIAssistantCheck.swift` | 直接验证协议切换与配置读写不变量 |
| O2：OpenAI / Anthropic / Gemini 编解码与代码提取 | `AILLMClient` | `Tests/AIAssistantCheck.swift` | 无需真实外网即可确定性验证三类协议报文格式 |
| O3：CodeMode 沙箱执行、批量生成、冲突检测与异常捕获 | `AICodeModeRunner` | `Tests/AIAssistantCheck.swift` | 直接在真实 `JSContext` 上验证脚本桥接与边界保护 |
| O4：EventCenter 批量日程/提醒提交与一键 Undo/Redo | `EventCenter` | `Tests/EventCenterCheck.m` | 在内存 `EKEventStore` 上验证事务提交与 Undo/Redo 指纹校验 |

### 7. 验证计划和当前结果

- `bash Tests/check-week.sh`：包含原有的 `WeekModelCheck`、`EventCenterCheck`、`install-check.py` 以及新增的 `AIAssistantCheck` 和 `EventCenter` 批量提交/撤销测试。
- `xcodebuild` Release 构建与 `bash Scripts/install-week.sh` 本机安装验证。

### 8. 当前实现状态

- 已完成 SPEC 与架构设计契约，随代码与测试同步交付。
