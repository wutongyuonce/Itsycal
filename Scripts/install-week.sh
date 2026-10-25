#!/bin/bash
# Build and replace the local development app without retaining an old widget process.
set -euo pipefail
cd "$(dirname "$0")/.."

app='/Applications/Itsycal Week.app'
bundle_id='com.local.ItsycalWeekApp'
derived="${TMPDIR:-/tmp}/itsycal-week-install"
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

if [[ ! -f Local.xcconfig ]]; then
    echo 'Create Local.xcconfig from Local.xcconfig.example and configure development signing first.' >&2
    exit 1
fi
if [[ -e "$app" ]]; then
    installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
    if [[ "$installed_id" != "$bundle_id" ]]; then
        echo "Refusing to replace a different app at $app" >&2
        exit 1
    fi
fi

# Increasing the local build version invalidates WidgetKit's previous archives.
# Keep the upstream marketing/build version out of source control changes.
version=$(date +%s)
xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$derived" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$version" build
product="$derived/Build/Products/Debug/Itsycal.app"
codesign --verify --deep --strict "$product"

stage=$(mktemp -d '/Applications/.itsycal-week-install.XXXXXX')
backup=$(mktemp -d "${TMPDIR:-/tmp}/itsycal-week-backup.XXXXXX")
replaced=false
installed=false
finished=false
cleanup() {
    if [[ "$finished" == false ]]; then
        if [[ "$installed" == true ]]; then rm -rf "$app"; fi
        if [[ "$replaced" == true ]]; then mv "$backup/Itsycal Week.app" "$app"; fi
    fi
    rm -rf "$stage"
    if [[ ! -e "$backup/Itsycal Week.app" || "$finished" == true ]]; then
        rm -rf "$backup"
    else
        echo "Previous app preserved at $backup/Itsycal Week.app" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$product" "$stage/Itsycal Week.app"
# A suspended extension survives quitting the containing app. Stop both BEFORE
# replacing the bundle, or its old version will fail WidgetKit archive validation.
pids=$(pgrep -f '^/Applications/Itsycal Week[.]app/Contents/(MacOS/Itsycal|PlugIns/WeekWidget[.]appex/Contents/MacOS/WeekWidget)( |$)' || true)
if [[ -n "$pids" ]]; then
    while IFS= read -r pid; do
        kill "$pid" 2>/dev/null || true
        for attempt in {1..30}; do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid"; fi
        for attempt in {1..20}; do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "Old process $pid did not exit; refusing to replace the app." >&2
            exit 1
        fi
    done <<< "$pids"
fi
if [[ -e "$app" ]]; then
    mv "$app" "$backup/Itsycal Week.app"
    replaced=true
fi
mv "$stage/Itsycal Week.app" "$app"
installed=true
codesign --verify --deep --strict "$app"
# Prefer the installed bundle over the duplicate registered during xcodebuild.
"$lsregister" -u "$product"
"$lsregister" -f "$app"
# chronod can retain the old extension registration even after the old process
# is stopped (Unknown extension process). Restart its per-user cache service.
# Other widgets briefly reload; do not reset their databases or preferences.
killall chronod 2>/dev/null || true
open "$app"
finished=true
printf '\nInstalled %s (build %s).\n' "$app" "$version"
printf 'Add 本周日程 from the widget gallery; medium and extra-large are supported.\n'
