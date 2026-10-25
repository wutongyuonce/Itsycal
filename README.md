# Itsycal（本周日程小组件分支）

基于 [Itsycal](https://github.com/sfsam/Itsycal) 的独立分支，增加原生 macOS 桌面周视图小组件：一眼看到本周七天，以及每天最多四项日程。

| 中号 | 超大号 |
| --- | --- |
| ![中号周视图小组件](docs/previews/week-medium.png) | ![超大号周视图小组件](docs/previews/week-extra-large.png) |

## 功能

- 中号和超大号两种原生横向小组件。中号紧凑，超大号带日期范围与日程总数。
- 七列显示当前一周，日期排列**跟随 Itsycal 设置中的“一周从周几开始”**。
- 在设置 → Appearance 修改“一周从周几开始”后，主应用会重新生成共享数据并请求小组件刷新，无需重建。
- 今天突出显示；已过去的日期和其下列表整列变暗。
- 每天最多显示四项，超出显示“还有 N 项”，点击进入主应用查看完整当天。
- 支持全天事件、跨日事件、重复事件和本地时区/夏令时。
- 跟随系统浅色/深色外观。日历数据只保存在本机。

## 系统要求

当前工程要求 **macOS 27 / Xcode 27**。WidgetKit 本身支持更早系统，但基础代码来自要求 macOS 27 的上游版本，尚未在旧系统验证。

## 构建与安装

首次复制本地签名配置：

```sh
cp -n Local.xcconfig.example Local.xcconfig
```

在 Xcode 中登录开发账号，给 **Itsycal** 与 **WeekWidget** 选择同一团队、Apple Development 签名，并启用同一个 App Group，例如：

```xcconfig
WEEK_APP_GROUP = 你的团队ID.com.wutongyuonce.Itsycal
```

`Local.xcconfig` 已被 Git 忽略，不要提交证书、团队 ID 或 profile。

构建并安装 Release 版本：

```sh
bash Scripts/install-week.sh
```

脚本会构建 Release、递增 build 号、等待旧主应用和小组件进程退出，以可恢复的原子替换安装到 `/Applications/Itsycal.app`，然后重新注册并刷新小组件服务。其他桌面小组件在安装时会短暂重载。

安装后：

1. 打开 Itsycal，允许日历访问。
2. 在设置 → Events 中选择要显示的日历。
3. 桌面右键 → 编辑小组件 → 搜索“本周日程” → 添加中号或超大号。
4. 若修改“一周从周几开始”，留在设置中即可，小组件会自动刷新为新排列。

主应用退出后小组件仍显示已有快照，但新的日程修改要等主应用再次运行才同步。系统决定实际刷新时机，不保证秒级更新。

## 版本号

- `MARKETING_VERSION`（用户看到的版本）在 `Itsycal.xcodeproj/project.pbxproj` 的两个 target 中，目前为 `1.1.0`。
- `CURRENT_PROJECT_VERSION` 是默认 build 号。
- 主应用和 Widget 的 `Info.plist` 使用 `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`。
- 本地安装脚本会用当前时间覆盖 build 号，避免 WidgetKit 继续使用旧版本的时间线归档。

## 检查

```sh
bash Tests/check-week.sh
```

检查使用合成数据，不读取个人日历。覆盖：

- 可配置的一周起始日、跨年、夏令时
- 14 天共享数据范围
- 四项容量与溢出
- 日期链接与缺失数据
- 真实 EventCenter 的交叠查询、跨午夜和零时长事件
- 安装替换、失败回滚和首次安装

## 上游与许可

本项目从 [sfsam/Itsycal](https://github.com/sfsam/Itsycal) 的 `1a31050555a97e3b7aac5470ec147abfe7aa0d6a`（0.27.3）派生，之后独立演进，不再自动合并上游。

原始代码采用 MIT 许可，版权归 © 2016 Sanjay Madan；详见 [LICENSE.txt](LICENSE.txt)。本项目保留原作者署名，新增的周视图与安装代码由 wutongyuonce 维护。

更多细节：

- [行为与架构说明](docs/WEEK_WIDGET_SPEC.md)
- [安装、刷新排查与真机验收](docs/WEEK_WIDGET_SETUP.md)
