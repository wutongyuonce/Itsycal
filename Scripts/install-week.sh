#!/bin/bash
# Build and replace the local development app without retaining an old widget process.
set -euo pipefail
cd "$(dirname "$0")/.."

app='/Applications/Itsycal.app'
bundle_id='com.wutongyuonce.Itsycal'
legacy_bundle_ids=('com.wutongyuonce.ItsycalWeek' 'com.local.ItsycalWeekApp' 'com.mowglii.ItsycalApp')
derived="${TMPDIR:-/tmp}/itsycal-week-install"
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

if [[ ! -f Local.xcconfig ]]; then
    echo 'Create Local.xcconfig from Local.xcconfig.example and configure development signing first.' >&2
    exit 1
fi
if [[ -e "$app" ]]; then
    installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
    if [[ "$installed_id" != "$bundle_id" && ! " ${legacy_bundle_ids[*]} " =~ " $installed_id " ]]; then
        echo "Refusing to replace a different app at $app" >&2
        exit 1
    fi
fi

# Increasing the local build version invalidates WidgetKit's previous archives.
# Keep the upstream marketing/build version out of source control changes.
version=$(date +%Y%m%d%H%M%S)
xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$derived" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$version" build
product="$derived/Build/Products/Debug/Itsycal.app"
codesign --verify --deep --strict "$product"

stage=$(mktemp -d '/Applications/.itsycal-week-install.XXXXXX')
backup=$(mktemp -d "${TMPDIR:-/tmp}/itsycal-week-backup.XXXXXX")
ditto "$product" "$stage/.new.app"
# Stop processes, swap and roll back as one signal-deferred transaction. A
# suspended extension would otherwise submit an old-version timeline after
# replacement and be rejected by WidgetKit's archive validation.
if ! python3 Scripts/install-week.py --app "$app" --stage "$stage/.new.app" --backup "$backup"; then
    rm -rf "$stage"
    if [[ -e "$backup/Itsycal.app" ]]; then
        echo "Install failed; previous app preserved at $backup/Itsycal.app" >&2
    else
        rm -rf "$backup"
    fi
    exit 1
fi
rm -rf "$stage" "$backup"
codesign --verify --deep --strict "$app"
# Prefer the installed bundle over the duplicate registered during xcodebuild.
"$lsregister" -u "$product"
"$lsregister" -f "$app"
# chronod can retain the old extension registration even after the old process
# is stopped (Unknown extension process). Restart its per-user cache service.
# Other widgets briefly reload; do not reset their databases or preferences.
killall chronod 2>/dev/null || true
open "$app"
printf '\nInstalled %s (build %s).\n' "$app" "$version"
printf 'Add 本周日程 from the widget gallery; medium and extra-large are supported.\n'
