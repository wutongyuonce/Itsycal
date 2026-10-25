# 构建、安装与刷新排查

此 fork 的小组件改动位于 `feature/week-widget`。当前上游基线要求 macOS 27 / Xcode 27。

## 配置本机签名

首次复制配置，保留已有文件：

```sh
cp -n Local.xcconfig.example Local.xcconfig
```

在 Xcode → Settings → Accounts 登录账号，Manage Certificates 中创建 Apple Development 证书。编辑被忽略的 Local.xcconfig：

```xcconfig
DEVELOPMENT_TEAM = 你的团队ID
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_STYLE = Automatic
ENABLE_HARDENED_RUNTIME = YES
WEEK_APP_GROUP = 你的团队ID.com.local.ItsycalWeek
```

两端均使用这个团队前缀共享组。Apple 支持 macOS 的 `团队ID.组名` 格式，无需单独注册这种 App Group。实际能力以 Xcode 签名结果为准。不要把证书、私钥、profile 或 Local.xcconfig 提交到仓库。

若已创建证书但 `security find-identity -v -p codesigning` 仍为零，先用签名日志定位。开发期间遇到过 WWDR G3 中间证书缺失：从 Apple 官方 `https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer` 导入中间证书后恢复，没有修改系统信任设置。不要将所有签名错误都按此原因处理。

## 安装或更新

```sh
bash Scripts/install-week.sh
```

脚本使用本机配置构建 Debug App，赋予递增本地 build number，验证嵌套签名；停止旧主应用和 Widget 扩展进程后替换 `/Applications/Itsycal Week.app`，重新注册，重启用户 chronod 缓存服务并打开。更新时其他小组件会短暂重载；不重置系统数据库或偏好。不会覆盖官方 `/Applications/Itsycal.app`。已有不同 bundle ID 的同名 App 会被拒绝替换。脚本会等待旧进程退出，必要时结束仍存活的本 App 进程，确认退出后才替换；普通失败和终止信号会恢复旧版本。它不是断电安全的事务安装器：若在移动旧版和放入新版之间断电或被 SIGKILL，旧版保留在输出所用临时目录下的 `itsycal-week-backup.*`，需手动恢复。

主应用首次需要允许日历访问，并在设置 Events 页选日历。桌面右键“编辑小组件”，搜索“本周日程”或“Itsycal Week”。中号和超大号都支持；已有实例不会自动变换尺寸。

安装实测已确认开发签名可运行、共享组访问获准、14 天 ready 快照可写出、系统扩展 timeline 返回 15 条。中号与超大号可以加入图库。后续日历编辑同步、各点击路径与跨时区行为仍应按下方清单验收。

## 灰色占位或更新后不刷新

先区分数据没更新和更新安装留下的旧进程：

```sh
/usr/bin/log show --last 5m --style compact \
  --predicate 'process == "chronod" AND eventMessage CONTAINS "com.local.ItsycalWeekApp"' \
  | tail -60
```

若出现 `Bundle version did not match; LaunchServices DB may need to be rebuilt`，可能是覆盖安装后旧的 suspended Widget 进程还活着。它拿旧版本提交时间线，系统按新版验证就会拒绝，画面退回占位。安装脚本在替换前停止扩展以避免这种情况。

本次故障的验证依据：旧扩展进程启动时间早于新 App 安装；停止该扩展、清理本构建的重复注册并刷新 chronod 后，新进程的 `reload: succeeded with 15 entries` 恢复。本机新注册还曾触发 `Unknown extension process`，刷新 chronod 后恢复，因此安装脚本也会在重新注册后重启用户 chronod 服务。若仍卡住，可以退出 Itsycal Week、重新打开，并关闭重开小组件图库；检查新进程日志，不能只看安装命令退出码。

`pluginkit` 能查到扩展不代表图库、时间线和渲染都成功；以实际日志和画面为准。单条 `purging ... isApple? false` 也不足以证明签名被拒绝，开发期间真实签名在刷新缓存后成功运行。

无签名构建随后临时深签会丢失必要的 extension sandbox entitlement，可能导致 `plug-ins must be sandboxed`。应使用完整 Xcode 签名构建。共享组拒绝时检查两端 entitlement、团队身份和实际 `WeekAppGroup` 值。

## 离线验证

```sh
bash Tests/check-week.sh
xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/itsycal-week-build \
  CODE_SIGNING_ALLOWED=NO build
```

离线检查使用合成数据，不读取个人日历或写桌面快照。无签名编译成功不能证明小组件可运行。

渲染与扩展相同 SwiftUI View 的示例画面：

```sh
swiftc WeekWidget/WeekModel.swift WeekWidget/WeekView.swift \
  Tests/RenderWeek.swift -o /tmp/itsycal-render-week
/tmp/itsycal-render-week /tmp/itsycal-week-previews
```

`week-light.png` / `week-dark.png` 是超大号，带 `-compact` 的是中号；这些为合成数据预览。

## 真机验收

- 周一至周日固定排列；过去整列弱化，当天强调。
- 中号无顶部信息，超大号有日期范围与总数；两者最多四项。
- 主应用翻到其他月份后，小组件仍显示本周。
- 修改日历事件或已选日历，等待系统刷新后同步；主应用需要保持运行。
- 点击日期和溢出入口打开完整当天，主应用原议程隐藏偏好不妨碍这个入口。
- 休眠跨午夜、周日跨周一、改变时区时，日期与日程一致更新。
- 撤销权限、不选日历、主应用退出导致快照过期时，显示相应状态。

上游同步方法见 [README](../README.md)。源码同步与已安装 App 更新是两件事，同步后需重跑安装脚本。
