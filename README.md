# Itsycal (weekly widget fork)

A personal fork of [sfsam/Itsycal](https://github.com/sfsam/Itsycal) with a native macOS desktop widget showing the current week, Monday through Sunday.

![Extra-large week widget with synthetic example events](docs/previews/week-light.png)

- Seven fixed day columns using the calendars selected in Itsycal.
- Medium and extra-large widget sizes. Medium uses a compact layout; extra-large includes the week range and event count.
- Today is highlighted; past days and their events are dimmed.
- Up to four events per day. An overflow link opens the full day in the menu-bar app.
- All-day and multi-day events, light/dark appearance, and local-time week transitions.

This is an independent project built from Itsycal. Its bundle identity and URL scheme are its own; it can coexist with the official app. Automatic upstream updates are disabled. Calendar data stays on the Mac. Keep the containing app running to sync event changes; WidgetKit controls the actual refresh timing.

## Build and install

The current project baseline requires **macOS 27 and Xcode 27**. Configure your own development signing in the ignored `Local.xcconfig`:

```sh
cp -n Local.xcconfig.example Local.xcconfig
```

Select Apple Development signing and use a macOS app group matching your team, such as `TEAMID.com.wutongyuonce.ItsycalWeek`. Never commit your local signing file or certificates. See [setup instructions](docs/WEEK_WIDGET_SETUP.md) for details.

Build and install the development app:

```sh
bash Scripts/install-week.sh
```

The script replaces `/Applications/Itsycal.app` with a recoverable atomic directory swap, verifies its signature, stops the old app and widget processes first, then refreshes the per-user widget service. Other widgets briefly reload during installation. Open the app, grant calendar access, select calendars in Events settings, then add **本周日程** from the desktop widget gallery. Upgrading from the earlier `com.local.*` identity requires granting access and selecting calendars again because macOS stores them per app identity.

For a source-only build without signing:

```sh
xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/itsycal-week-build \
  CODE_SIGNING_ALLOWED=NO build
```

This checks compilation; it does not establish that the widget can run on your Mac.

## Upstream and attribution

`master` is this project's only development branch. It is no longer a mirror of upstream; there is no automatic upstream merge.

This project began as a fork of [sfsam/Itsycal](https://github.com/sfsam/Itsycal) at commit `1a31050555a97e3b7aac5470ec147abfe7aa0d6a` (0.27.3). The original code is MIT licensed, copyright © 2016 Sanjay Madan; see [LICENSE.txt](LICENSE.txt). Upstream is credited, but future upstream changes are not merged automatically. Port a specific upstream fix manually if it matters, then run the checks and build.

## Version

The user-visible version is `MARKETING_VERSION` in `Itsycal.xcodeproj/project.pbxproj`; both targets currently use `1.0.0`. `CURRENT_PROJECT_VERSION` is the build number (currently `1`). The host and widget `Info.plist` files read `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`.

`Scripts/install-week.sh` overrides the build number at build time with `YYYYMMDDHHMMSS`. A fresh build number is required because WidgetKit validates archived timelines against the installed bundle version; reusing one can leave the desktop widget on a stale/placeholder render.

## Checks and design

```sh
bash Tests/check-week.sh
```

The checks cover Monday-based dates, DST, week coverage, four-item capacity, links, overlapping EventKit queries, cross-midnight grouping, and the installer's swap/rollback path using synthetic data.

- [Behavior and architecture](docs/WEEK_WIDGET_SPEC.md)
- [Installation and refresh troubleshooting](docs/WEEK_WIDGET_SETUP.md)
- [Original upstream README](README.txt)

MIT licensed; see [LICENSE.txt](LICENSE.txt). Original Itsycal by Sanjay Madan / mowglii.com.
