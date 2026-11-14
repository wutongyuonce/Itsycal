# ItsycalMobile：iOS / iPadOS 端规格与设计

本文是 `ItsycalMobile`（iOS / iPadOS 日历与 AI 助手应用）的现行行为契约与模块设计。代码与本文冲突时以代码为事实，并同步修正本文。

## 1. 范围

- 与 macOS 端同仓库：`Itsycal.xcodeproj` 中的 `ItsycalMobile` Target，直接编译共享的 `Itsycal/AIAssistant.swift`（AI 配置、多协议客户端、`JavaScriptCore` CodeMode 沙箱），不复制代码。
- 数据全部来自系统 EventKit（日历与提醒事项），不另建存储。
- 非目标：不支持 Mac Catalyst 运行。

## 2. 用户可见行为

### 布局

- **按窗口自身的横竖选布局**，iPhone 与 iPad 同一规则，分屏、Slide Over、台前调度窗口同样适用：
  - 横向窗口（宽 > 高且宽 ≥ 560pt）：月视图在左，议程列在右，宽为窗口的 30%（限制在 260–380pt）。
  - 其他：月视图在上占 60% 高度，议程在下。
- 顶栏右侧依次为：撤销（`⌘Z`）、新建（`⌘N`）、AI 助手（`⌘K`）、设置。
- 日历与提醒事项列表的显示勾选只在「设置」中，主界面不放筛选列表。

### 月视图（参照桌面月视图小组件）

- 显示覆盖整月的完整周（4–6 行），一周起始日跟随设置，可选显示周数。
- 标题行：左上角年份（如「2026年」）与月份（如「11月」）可分别点击弹出菜单直选任意年份和 1–12 月（月底如 1 月 31 日切到 2 月时自动收敛至当月最后一天 2 月 28/29 日，不跨月溢出）；右侧为「今天」按钮（`⌘T`，回到今天所在月并选中今天）、上/下月（`⌘←` / `⌘→`）；在网格上左右滑动也可切换月份。
- 每格左上角为日期，今天用强调色填充；选中日浅色底；非本月日期淡化到 30%，已过去日期 55%。
- 格内按可用高度显示条目：全天日程为着色块，定时日程为色条加标题，提醒事项为圆圈加标题（已完成的半透明）；放不下的条目以 `+N` 显示在日期旁。格子矮到放不下任何条目时，改为最多 3 个日历色点。
- 点击某天即选中，议程跟随更新；点击其他月份的日期会切到该月。

### 议程

- 从选中日开始，初始显示设置中的天数（1/3/7/14/31 天，默认 7 天），按天分组，组内排序与 macOS 端一致；选中今天时顶部显示可折叠的「已过期」提醒。
- **底部智能向后展开**：自动向后探测未来 365 天的日程与提醒：
  - 若紧邻的下一周有条目，底部显示「展开下一周（N 项）」，点击后增加 7 天；
  - 若紧邻的下一周为空、但更后面有条目，底部显示「下周无日程 · 展开至 M月D日（N 项）」，点击后直接跨过空白周展开到该周，并在列表中以「已略过中间无日程的 X 天」提示跨度；
  - 若后续无更多条目，底部显示「后续暂无更多日程」；切换选中日期或月份时自动复位回初始显示天数。
- 提醒前的圆圈可勾选完成；含视频会议链接的日程显示加入按钮；左滑删除（只读日历不提供，重复日程先询问「仅此日程」或「所有将来日程」）。
- **点击任一日程或提醒事项进入编辑**。

### 新建与编辑

- 同一表单：类型（仅新建时可选）、标题、位置（日程）、全天、开始/结束（或提醒日期）、重复、日历/列表、备注；已有条目可在表单底部删除。
- 新建日程默认从今天的下一个整点开始（其他选中日为 9:00），时长 1 小时，日历为系统默认可写日历。修改开始时间时保持时长。
- 重复日程保存或删除时询问「仅此日程」或「所有将来日程」；修改了重复频率时不询问，直接作用于整个系列。
- 只读日历（订阅、节假日、生日）或已不存在的条目以只读方式打开，不显示保存和删除。
- 重复规则超出选择器能表达的（如每周多天）显示为「自定义」并原样保留；只有改了重复频率才会重写规则。

### 撤销

- 新建、编辑、删除、勾选提醒、AI 批量执行都可通过顶栏按钮或 `⌘Z` 多级撤销；撤销栈只在本次运行期间有效，不提供重做入口。
- 目标条目已在别处被删除或修改导致撤销、左滑删除失败时，弹窗告知原因，不会改到同名的其他条目。
- 已知限制：撤销「删除所有将来日程」时，重复规则按选择器能表达的频率和结束日期恢复，自定义规则或按次数结束的规则会被简化。

### AI 助手与外观

- AI 助手面板用系统玻璃材质（`glassEffect`）：对话气泡、待执行卡片、底部悬浮的输入栏与确认按钮；待执行项点整张卡片勾选/取消。设置中提供清理会话缓存与清除 Keychain API Key 按钮（卸载前点一次即可不留 Keychain 残留）。
- App 图标与桌面端同一张图（`ItsycalMobile/AppIcon.icon`），放大到铺满 iOS 的圆角方形。

### 小组件

- 与 Mac 端同一套小组件：「本周日程」（中号；iPad 另有超大号）和「本月日程」（大号；iPad 另有超大号，iPhone 没有超大号尺寸）。外观、`‹ ›` 切换下周/下月、15 分钟后自动回到当前周期，均与 [桌面小组件规格](WEEK_WIDGET_SPEC.md) 相同。
- 点击某一天或标题打开 App 并选中那一天（`itsycal-week://date/yyyy-MM-dd`）。
- 数据来源与 Mac 不同：个人（免费）开发者团队不能使用 App Group，App 无法把快照共享给小组件，所以小组件自己读 EventKit 生成同格式的快照，覆盖本月第一周到下月最后一周。因此 iOS 小组件**显示全部日历**，**一周起始日跟随系统**，不读取 App 内的这两项设置。
- App 每次检测到日历变化（包括自己的写入）都会请求小组件刷新；此外小组件每小时及每天零点自动更新。
- 小组件没有日历权限时显示「打开 Itsycal，允许访问日历」。

## 3. 规则与不变量

| ID | 规则 | 权威位置 |
|---|---|---|
| M1 | `AIAssistant.swift` 只依赖 `Foundation` / `Security` / `JavaScriptCore`，被两端共同编译 | `Itsycal/AIAssistant.swift` |
| M2 | 月网格、月格可容纳条目数各只有一处实现；跨日拆分与同日排序只在 `DayItems`，App 与 iOS 小组件共用 | `MobileCalendarCore`、`DayItems` |
| M6 | iOS 小组件的快照与 Mac 端 `WeekSnapshot.m` 同格式、同标记规则（每天都有桶，空天也有），共享的小组件视图不区分平台 | `WidgetSnapshotBuilder` |
| M3 | 所有写入经 `MobileEventStore`：批量增删一次提交，失败 `reset()` 回滚；每次成功写入只登记一个逆操作作为撤销 | `MobileEventStore` |
| M4 | 定位条目时优先匹配「标识符 + 开始时间」的那一次发生，避免重复日程误改第一次；只有没有标识符的 AI 提议才按标题匹配 | `MobileEventStore.resolveEvent` / `resolveReminder` |
| M5 | 提醒事项的抓取结果只在仍是最新一次刷新时生效，快速切换日期不会被旧结果覆盖 | `MobileEventStore.reloadVisibleRange` |

## 4. 模块

```text
Itsycal/AIAssistant.swift          两端共享的 AI 引擎
ItsycalWidgets/                    Mac 与 iOS 共用的小组件视图、时间线、切换按钮、快照格式
ItsycalMobile/
  DayItems.swift                   跨日拆分与同日排序（App 与 iOS 小组件共用）
  EventKitHelpers.swift            提醒截止时间、日历颜色（App 与 iOS 小组件共用）
  MobileCalendarModel.swift        纯算法：月网格、月格条目布局、会议链接识别、小组件链接解析
  MobileEventStore.swift           EventKit：权限、抓取、导航、编辑、批量事务、撤销、AI 宿主上下文、通知小组件刷新
  MobileCalendarViews.swift        月视图与议程视图
  MobileItemEditor.swift           新建/编辑/删除表单
  ItsycalMobileApp.swift           入口、根布局、AI 助手面板、设置、打开小组件链接
ItsycalMobileWidgets/              iOS 小组件扩展（同时编译 ItsycalWidgets/ 全部源文件）
  WidgetSnapshotBuilder.swift      纯算法：快照区间与按天的标记、排序
  WidgetEventSource.swift          从 EventKit 读取日程与未完成提醒，生成快照
```

## 5. 验证

| 义务 | 证据 |
|---|---|
| 月网格、跨日拆分、排序、月格布局、会议链接、小组件链接 | `Tests/MobileCalendarCheck.swift`（`bash Tests/check-week.sh`） |
| iOS 小组件快照：区间、空天桶、同日顺序、跨日标记、无权限 | `Tests/MobileWidgetCheck.swift` |
| 共享 AI 引擎 | `Tests/AIAssistantCheck.swift` |
| iOS 编译 | `xcodebuild -project Itsycal.xcodeproj -target ItsycalMobile -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build` |
| 布局、编辑、撤销等交互，小组件读取权限与刷新 | 真机验收（iPhone 竖/横屏，iPad 全屏、分屏、Slide Over；添加两种小组件） |
