# ItsycalMobile：iOS / iPadOS 端规格与架构设计契约

本文是 Itsycal 跨端演进（Phase 2：iOS / iPadOS 端封装日历与 AI 助手应用 `ItsycalMobile`）的现行行为契约与模块架构设计。代码与本文冲突时以代码为事实，并同步修正本文。

## Part A：SPEC —— 系统必须满足什么

### 1. 背景与问题

- **当前用户可见行为**：Itsycal 原本仅作为 macOS 菜单栏应用存在，其标志性的“上方紧凑月历网格 + 下方多日议程与提醒混排列表 + CodeMode AI 自然语言日程助手”无法在 iPhone 与 iPad 上使用。
- **工程组织决策（同仓库多 Target vs 新建独立仓库）**：
  - `Itsycal/AIAssistant.swift`（AI 配置存储、Keychain、多协议 LLM 客户端、`JavaScriptCore` CodeMode 沙箱执行器）以及日期网格算法完全只依赖跨平台的 `Foundation`、`Security`、`JavaScriptCore`。
  - **在同一个 `Itsycal.xcodeproj` 中新增 `ItsycalMobile` (iOS/iPadOS) Target** 可以 100% 零拷贝共享 `Itsycal/AIAssistant.swift`，避免跨仓库同步双份 AI 引擎与协议代码，同时互不干扰 macOS 主应用的 AppKit 编译配置。

### 2. 目标行为

1. **自适应双端布局（iPhone & iPad）**：
   - **iPhone（紧凑单栏）**：延续 macOS 菜单栏弹窗的经典上下分栏结构——上方为紧凑月历网格（支持切换月份、显示周数、彩色事件圆点、高亮今日与选中日期），下方为议程与提醒事项混排列表（含已过期提醒折叠分组、按天分组的日程、会议一键加入按钮），底部工具栏提供“今天”、“新建 (`+`)”、“AI 助手 (`✨`)”与“设置”。
   - **iPad（宽屏自适应双栏）**：左侧固定展示月历网格与快捷操作栏，右侧展示宽屏多日议程详情与内嵌/抽屉式 AI 助手面板，并支持外接键盘快捷键（`⌘N` 新建、`⌘K` AI 助手、`⌘T` 回到今天）。
2. **原生 EventKit 日历与提醒事项完整接入**：
   - 支持请求日历与提醒事项完整权限、按日历/提醒列表勾选过滤、跨天事件切分、重复提醒展开、勾选/取消完成提醒事项、手动新建事件/提醒事项，以及 `UndoManager` 多级撤销与重做。
3. **共享 CodeMode AI 自然语言助手**：
   - 直接共享 `Itsycal/AIAssistant.swift`，支持在 iOS/iPadOS 端通过自然语言批量创建或删除日历事件与提醒事项、按任意历史/未来区间（自动 3 年分片）查询 EventKit、展示待执行确认卡片清单、多轮对话微调、以及会话缓存清理。

### 3. 产品 RULE 与不变量

| ID | Rule / invariant | 适用场景 | 违反时的结果 |
|---|---|---|---|
| M1 | `Itsycal/AIAssistant.swift` 保持纯跨平台依赖（`Foundation` / `Security` / `JavaScriptCore`），同时被 `Itsycal`（macOS）与 `ItsycalMobile`（iOS/iPadOS）编译，严禁复制成两份文件。 | 双端编译与演进 | 杜绝双端 AI 协议或沙箱逻辑漂移 |
| M2 | 月历网格（4–6 周整行计算）、每日事件与提醒排序规则（全天在前、随后按开始时间与标题排序、未完成提醒在前）与 macOS 端保持一致。 | 月历与议程展示 | 跨端视觉与日程顺序一致 |
| M3 | 批量增删事务提交同样采用两阶段提交（逐项 `commit:false` + 最终一次 `store.commit()`），失败时 `store.reset()` 回滚，并注册 `UndoManager` 撤销栈。 | AI 批量执行与手动新建/删除 | 保证原子性与多级撤销 |

### 4. 验收标准

| Obligation | 可观察证据 | 验证层级 |
|---|---|---|
| MO1：移动端月历网格、跨日拆分与每日混排排序逻辑 | 给定任意月份、一周起始日与跨日/全天/提醒数据，网格行数与每日排序结果准确 | Owner unit test (`Tests/MobileCalendarCheck.swift`) |
| MO2：macOS 与 iOS/iPadOS 双端共享编译通过 | `bash Tests/check-week.sh` 通过，且 `xcodebuild -scheme Itsycal` (macOS) 与 `xcodebuild -scheme ItsycalMobile -destination 'generic/platform=iOS Simulator'` 均编译成功 | Workspace build check |

## Part B：设计报告 —— module 如何满足 SPEC

### 1. 模块与文件结构

```text
Itsycal/AIAssistant.swift          <── macOS 与 iOS/iPadOS 共同编译（零重复）
ItsycalMobile/
  ├── Info.plist                   <── iOS/iPadOS 权限声明与自适应配置
  ├── MobileCalendarModel.swift    <── 纯算法层：月历网格计算、跨日拆分、每日排序（可独立单测）
  ├── MobileEventStore.swift       <── iOS/iPadOS EventKit 管理器（日历/提醒拉取、3年分片查询、批量原子提交与 Undo）
  └── ItsycalMobileApp.swift       <── SwiftUI 视图层：iPhone 上下分栏 / iPad 左右双栏、新建表单、AI 助手抽屉、设置页
```

### 2. Authority、interface 与 seam

| Rule/state/error/resource | Authority module | Interface/seam | Callers | Evidence |
|---|---|---|---|---|
| AI 配置、多协议客户端、CodeMode 沙箱 | `Itsycal/AIAssistant.swift` | `AIConfigStore`, `AILLMClient`, `AICodeModeRunner`, `AISessionStore` | macOS & iOS UI | `Tests/AIAssistantCheck.swift` |
| 移动端月历网格、跨日区间拆分与每日排序 | `MobileCalendarCore` (`ItsycalMobile/MobileCalendarModel.swift`) | `monthGrid(...)`, `expandAndSortDayItems(...)` | `MobileEventStore`, `ItsycalMobileApp` | `Tests/MobileCalendarCheck.swift` |
| 移动端 EventKit 权限、查询与批量事务 | `MobileEventStore` (`ItsycalMobile/MobileEventStore.swift`) | `applyBatchChanges(...)`, `queryItems(from:to:)` | `ItsycalMobileApp` | iOS Simulator build |
