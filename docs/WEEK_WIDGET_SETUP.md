# 构建、安装与排查

本文负责签名、安装与排查步骤；行为契约见 [WEEK_WIDGET_SPEC.md](WEEK_WIDGET_SPEC.md)。要求 macOS 27 / Xcode 27，在 `master` 分支开发。

## 配置签名

```sh
cp -n Local.xcconfig.example Local.xcconfig
```

在 Xcode → Settings → Accounts 登录账号，在 Manage Certificates 中创建 Apple Development 证书，然后编辑被 Git 忽略的 `Local.xcconfig`：

```xcconfig
DEVELOPMENT_TEAM = 你的团队ID
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_STYLE = Automatic
ENABLE_HARDENED_RUNTIME = YES
ITSYCAL_BUNDLE_ID = com.你的名字.Itsycal
WEEK_APP_GROUP = 你的团队ID.com.你的名字.Itsycal
```

- 两个 target 都读取这份配置。扩展的 Bundle ID 自动为 `$(ITSYCAL_BUNDLE_ID).WeekWidget`。Bundle ID 在 Apple 账号间唯一，因此除本仓库维护者外都要换成自己的。
- macOS 支持 `团队ID.组名` 格式的 App Group，无需单独注册。实际能力以 Xcode 签名结果为准。
- 不要提交证书、私钥、profile 或 `Local.xcconfig`。

**签名边界：** `CODE_SIGNING_ALLOWED=NO` 只能验证编译；原生小组件需要沙盒、App Group 和有效签名，未签名或 ad-hoc 构建无法正常注册。公开分发需要自己的 Developer ID 并 notarize。仓库不含更新器。

若已创建证书但 `security find-identity -v -p codesigning` 仍为零，先查看签名日志。若日志指向中间证书缺失，可从 Apple 官方 `https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer` 导入 WWDR G3，无需修改系统信任设置。

## 安装或更新

```sh
bash Scripts/install-week.sh
# 安装到其他位置：
INSTALL_APP_PATH="$HOME/Applications/Itsycal.app" bash Scripts/install-week.sh
```

脚本用 `Local.xcconfig` 构建 Release，以当前时间作为 build number（让 WidgetKit 放弃旧版本的时间线归档）并验证嵌套签名。然后替换安装位置（默认 `/Applications/Itsycal.app`），重新注册，重启用户的 chronod 缓存服务，并打开 App。其他小组件会短暂重载，系统数据库和偏好不会被重置。

替换由 `Scripts/install-week.py` 完成：

- 先检查两种情况：安装位置有 Bundle ID 不同的同名 App，或产物与已安装版本的 build 相同。遇到任何一种都拒绝安装，已安装的 App 不受影响。
- 按完整路径停止当前用户的旧主应用和 Widget 扩展进程，必要时发送 SIGKILL。确认进程退出后，用一次原子操作交换新旧目录，避免挂起的旧扩展提交旧版本时间线。
- 交换后签名验证失败会删除新版并恢复旧版；任何失败后都会重新打开保留下来的 App。
- 整个过程忽略 INT/TERM/HUP，不会停在半途。它不是断电安全的事务安装器：若被 SIGKILL，脚本不删除任何残留，旧版留在安装位置同目录的 `.itsycal-week-install.*` 或 `.itsycal-week-backup.*` 中，失败信息会列出路径。

首次使用：打开 Itsycal 允许日历访问，在设置 → Events 中选择日历，再在桌面右键 → 编辑小组件中搜索 Itsycal，添加“本周日程”或“本月日程”。

## 小组件灰色占位或不刷新

查看系统日志（把 Bundle ID 换成你的）：

```sh
/usr/bin/log show --last 5m --style compact \
  --predicate 'process == "chronod" AND eventMessage CONTAINS "com.wutongyuonce.Itsycal"' \
  | tail -60
```

- 正常时 `ItsycalWeek` 和 `ItsycalMonth` 各自 `reload: succeeded`，条目数见[规格第 4 节](WEEK_WIDGET_SPEC.md#4-数据状态与刷新)。
- `Bundle version did not match` 或 `Unknown extension process`：旧扩展进程或旧注册仍在。重新运行安装脚本；若仍不行，退出并重开 Itsycal，然后关闭并重开小组件图库。
- `plug-ins must be sandboxed`：构建后又做过临时 ad-hoc 深签，丢失了扩展的 sandbox entitlement。请用完整 Xcode 签名构建。
- 共享组被拒绝：检查两端 entitlement、团队身份和实际的 `WeekAppGroup` 值。
- `pluginkit` 能查到扩展，或出现单条 `purging ... isApple? false`，都不足以说明成功或失败，以日志和桌面画面为准。

## 离线验证

```sh
bash Tests/check-week.sh
xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/itsycal-week-build \
  CODE_SIGNING_ALLOWED=NO build
```

检查只用合成数据，不读取个人日历，也不写桌面快照。无签名编译成功不能证明小组件可运行。

生成与扩展相同 SwiftUI View 的预览图（合成数据，不是系统截图；README 使用真实桌面截图）：

```sh
swiftc WeekWidget/WeekModel.swift WeekWidget/WeekPreview.swift WeekWidget/WidgetChrome.swift \
  WeekWidget/WeekView.swift WeekWidget/MonthView.swift WeekWidget/WeekIntent.swift \
  Tests/RenderWeek.swift -o /tmp/itsycal-render-week
/tmp/itsycal-render-week /tmp/itsycal-week-previews
```

## 真机验收

- 七列按设置的一周起始日排列；修改设置后自动刷新。过去的日期整列弱化，今天强调显示。
- 周视图两种尺寸的顶栏和每日条数符合规格。
- 月视图显示整月（含前后补齐的日期），放不下时显示剩余数量；点任一格打开当天。
- 点 `›` 切到下周/下月、点 `‹` 回来，不打开主应用；到期后自动回来；同一小组件的多个实例同步切换，周和月互不影响。
- 主应用翻到其他月份后，小组件仍显示本周。
- 修改日历事件或已选日历后，等系统刷新即同步；主应用需要保持运行。
- 点击日期和溢出入口打开完整当天，包括 Itsycal 未运行时的冷启动；议程隐藏偏好不妨碍这个入口。
- 休眠跨午夜、跨过一周起始日、改变时区时，日期与日程一致更新。
- 撤销权限、不选日历、主应用退出导致快照过期时，显示相应状态。
