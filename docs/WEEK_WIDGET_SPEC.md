# Itsycal：本周日程小组件规格

本文是桌面小组件的现行行为契约。代码与本文冲突时以代码为事实，并同步修正本文。构建、安装与排查见 [WEEK_WIDGET_SETUP.md](WEEK_WIDGET_SETUP.md)。

上游基线：`sfsam/Itsycal` `1a31050555a97e3b7aac5470ec147abfe7aa0d6a`（0.27.3）。要求 macOS 27 / Xcode 27。

## 1. 范围与非目标

- 原生 macOS 桌面小组件，显示 Itsycal 已选日历中的日程，按天分列，不做小时网格。
- 显示包含今天的一周七天；第一列跟随 Itsycal 的“一周从周几开始”（`WeekStartDOW`，0=周日…6=周六）。
- 顶栏可在本周与下周之间切换并返回本周。
- 非目标：翻到下周以外的周、提醒事项、完成勾选、事件编辑、农历或节气、小组件内滚动、独立于主应用的日历配置。

## 2. 布局

支持 `systemMedium`（约 344 × 164 pt）和 `systemExtraLarge`（约 704 × 344 pt），按 WidgetFamily 选择样式，不按容器宽度猜测。已有实例不会自动改变尺寸。

**顶栏：** 左侧为“本周/下周”与日期范围，紧随其右为 `‹ ›` 切换按钮，最右为该周日程总数（有提示时隐藏）。中号顶栏 16 pt 高、标题 11 pt、范围不含年份、总数写作“N 项”；超大号 18 pt、标题 12 pt、范围含年份、总数写作“N 项日程”。

**七列：** 中号星期在上、日期在下，8 pt 内容边距；超大号星期日期同行，16 pt 内容边距。今天以蓝色圆角日期标识，过去的日期整列 opacity 0.5，仍可点击。今天已结束的事件不单独变暗。

**每日列表：** 全天事件在前，随后按开始时间排列，开始时间相同时按标题、事件标识稳定排序。标题 10 pt 单行省略；中号时间 8 pt、上下排列、每行 25 pt；超大号时间 9 pt、放得下时同行、每行 36 pt。`WeekDates.capacity` 按列区实际高度计算（中号预留 46 pt、超大号 54 pt，每天最多四项）：中号每天显示三项，超大号四项。超出显示“还有 N 项”，没有事件显示“无日程”。

**跨日事件：** 每个覆盖日独立显示，不画跨列长条。全天跨日显示“全天”；计时跨夜起始日显示 `22:00 →`，完整中间日显示“跨日”，结束日显示 `→ 02:00`。区间为 `[start, end)`：00:00 结束不占用结束日；零时长事件归入开始日。重复事件使用 EventKit 生成的实例。

## 3. 交互

**打开主应用：** 点击日期、事件或溢出入口，经 `itsycal-week://date/yyyy-MM-dd?widget=1` 打开该日完整议程；点击“本周”标题打开今天，点击“下周”标题打开下周首日。Itsycal 未运行时，链接在启动完成后处理。主应用收到 `widget=1` 时临时显示一天议程，不修改议程隐藏偏好；窗口关闭、用户选择别的日期或修改议程设置后恢复常规行为。日历未授权或没有已选日历时同时打开设置窗口；判断在本次重新获取日历之后进行。

**本周/下周切换：** 按钮是交互式小组件按钮（`Button(intent:)` + `SwitchWeekIntent`），在扩展进程内执行，不打开主应用。

- 显示本周时 `›` 可点、`‹` 置灰。快照无法完整显示下周（无快照、未授权、未选日历、时区不符、覆盖或日期桶缺失）时 `›` 也置灰，不会切到一张提示卡。
- 显示下周时 `‹` 可点（回到本周）、`›` 置灰。今天高亮和过去变暗仍按真实今天计算。
- 选择存于 App Group `UserDefaults` 的单个键 `navigation`（`[下周内的时间点, 到期时间]`），所有实例共享；点击后扩展请求重载所有实例的时间线。
- 切到下周 15 分钟后自动回到本周。到期时间从点击 `›` 起固定计算，不因其他操作续期，不可配置；timeline 在到期时刻插入一条本周条目。
- 记录的是绝对日期：到期前跨过一周起始日时，原“下周”自然成为本周，不会跳到更远的周。
- App Group 不可用时切换不生效，小组件保持本周。

## 4. 数据、状态与刷新

主应用是 `week.json` 的唯一写入方，扩展只读。快照覆盖从当前起始日起的本周和下周共 14 个本地日期，携带 `weekStart`，与菜单栏月历翻到哪个月无关。schema 版本为 2；字段名见 `Itsycal/WeekSnapshot.m`，`Tests/WeekModelCheck.swift` 以同样的 JSON 校验解码。

| 情况 | 小组件表现 |
| --- | --- |
| 没有快照或读取/解码失败 | 保留日期外壳，提示打开 Itsycal 设置 |
| 日历未授权 | 不导出事件，提示允许访问日历 |
| 没有已选日历 | 提示在主应用中选择日历 |
| 正常但无事件 | 七列显示“无日程” |
| 时区与快照不符 | 提示打开主应用更新，不伪造当前时区的空日程 |
| 覆盖不足或日期桶缺失 | 提示获取这一周的日程；缺桶不当作空日 |
| 快照生成超过 24 小时 | 保留列表，右下角显示可点击的刷新图标 |
| 共享容器不可用或写入失败 | 主应用记日志并保留上一个完整文件 |

**刷新：** 事件变化、日历选择变化、一周起始日变化、跨日、时区或系统时钟变化、唤醒和重新激活时，主应用重新查询并发布快照。文件每次原子重写，以保持 `generatedAt` 新鲜；只有内容（除 `generatedAt` 外）变化时才请求 WidgetCenter 重载，避免耗尽系统重载预算。TimelineProvider 生成现在、未来 14 个本地午夜，以及（若有）下周视图到期时刻的条目，并申请一小时后重载。

**限制：** 主应用退出后，已有快照仍按 timeline 推进日期，但不再同步新的编辑；超出覆盖范围或快照过期时明确提示。实际重载与渲染时机由系统决定。撤销权限后，主应用观察到变化才会清除导出内容。小组件使用 `.privacySensitive()`，在系统隐私状态下内容会被遮蔽。

## 5. 规则归属

```mermaid
flowchart LR
    EK[EventKit] --> EC[EventCenter\n查询、过滤、跨日分组]
    EC --> UI[菜单栏月历与议程]
    EC --> EX[WeekSnapshot\n14 日范围与导出]
    EX --> SH[(App Group\nweek.json)]
    EX --> WR[WeekWidgetReloader]
    SH --> TP[WeekProvider\n时间线]
    NI[SwitchWeekIntent] --> ND[(App Group\nnavigation)]
    ND --> TP
    TP --> WV[WeekView]
    WV --> DL[日期链接] --> UI
```

| 规则 | 权威位置 |
| --- | --- |
| 事件查询、筛选、分日、缓存覆盖；“已选日历”判定 | `EventCenter.m`（`hasSelectedCalendars`） |
| 快照 14 日范围、状态、导出与重载去抖 | `WeekSnapshot.m` |
| 读端周起始与覆盖校验、日期 key、容量、链接、timeline 日期 | `WeekModel.swift`（`WeekDates`、`WeekSnapshot.message`） |
| 本周/下周状态、到期、`›` 可用性 | `WeekModel.swift`（`WeekNavigation`）、`WeekIntent.swift` |
| 视觉与布局 | `WeekView.swift` |
| 日期链接解析与一天议程 | `AppDelegate.m`、`ViewController.m` |

周起始与 `yyyy-MM-dd` key 在主应用（Objective-C）和扩展（Swift）各有一份实现，因为二者在不同进程和 target。读端以快照的 `start`/`end`/`weekStart` 和日期桶校验，两边不一致时显示提示，不会显示错误日程。

## 6. Fork 身份

- 主应用 Bundle ID 为 `ITSYCAL_BUNDLE_ID`（默认 `com.wutongyuonce.Itsycal`），扩展为其后加 `.WeekWidget`；显示名 Itsycal，安装为 `Itsycal.app`。
- URL scheme `itsycal-week`。App Group 由 `WEEK_APP_GROUP` 决定（默认 `group.com.wutongyuonce.Itsycal`）。两者都由 `Local.xcconfig` 覆盖。
- 扩展启用 sandbox；主应用不是沙盒应用。不含更新器。保留 MIT 许可与上游署名，独立演进，不自动合并上游。

## 7. 验证

- `bash Tests/check-week.sh`：周起始（周一/周日/周三）、跨年、夏令时、timeline 日期与到期条目、容量、链接、覆盖与缺桶、时区、下周可用性与绝对日期语义、快照字段解码；真实 EventCenter 的部分缓存区间查询、跨午夜、排他午夜、零时长；安装替换、同版本拒绝、签名失败回滚、首次安装。
- `Tests/RenderWeek.swift` 只生成预览图（两种尺寸 × 本周/下周 × 浅/深色），不做断言。
- 需要真机确认：桌面实际排版、按钮点击与多实例同步、深链接、睡眠后跨周、系统刷新延迟。

## 8. Sources

- [Itsycal 上游基线](https://github.com/sfsam/Itsycal/tree/1a31050555a97e3b7aac5470ec147abfe7aa0d6a)
- [Apple：systemExtraLarge](https://developer.apple.com/documentation/widgetkit/widgetfamily/systemextralarge)
- [Apple：Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Apple：SwiftUI views for widgets](https://developer.apple.com/documentation/widgetkit/swiftui-views)
- [Apple：Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Apple：Adding interactivity to widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Apple：Configuring app groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
