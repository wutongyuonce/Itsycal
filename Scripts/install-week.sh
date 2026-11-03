#!/bin/bash
# Build and replace the local development app without retaining an old widget process.
set -euo pipefail
cd "$(dirname "$0")/.."

app="${INSTALL_APP_PATH:-/Applications/Itsycal.app}"
derived="${TMPDIR:-/tmp}/itsycal-week-install"
lsregister='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

if [[ ! -f Local.xcconfig ]]; then
    echo 'Create Local.xcconfig from Local.xcconfig.example and configure development signing first.' >&2
    exit 1
fi
# Increasing the local build version invalidates WidgetKit's previous archives.
# Keep the upstream marketing/build version out of source control changes.
version=$(date +%Y%m%d%H%M%S)
xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$derived" \
    -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$version" build
product="$derived/Build/Products/Release/Itsycal.app"
codesign --verify --deep --strict "$product"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$product/Contents/Info.plist")
if [[ -e "$app" ]]; then
    installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")
    if [[ "$installed_id" != "$bundle_id" ]]; then
        echo "Refusing to replace a different app at $app (found $installed_id, built $bundle_id)." >&2
        echo "Set INSTALL_APP_PATH to another location or remove the existing app." >&2
        exit 1
    fi
fi

parent=$(dirname "$app")
mkdir -p "$parent"
stage=$(mktemp -d "$parent/.itsycal-week-install.XXXXXX")
backup=$(mktemp -d "$parent/.itsycal-week-backup.XXXXXX")
# Until the installer runs, both directories only hold the new copy.
trap 'rm -rf "$stage" "$backup"' EXIT
ditto "$product" "$stage/.new.app"
trap - EXIT
# Stop processes, swap and roll back without INT/TERM interruption. A
# suspended extension would otherwise submit an old-version timeline after
# replacement and be rejected by WidgetKit's archive validation.
if ! python3 Scripts/install-week.py --app "$app" --stage "$stage/.new.app" --backup "$backup"; then
    # The installer cleans up after itself; anything left may be the only
    # copy of the previous app (e.g. after SIGKILL), so never delete it here.
    rmdir "$stage" "$backup" 2>/dev/null || true
    for leftover in "$stage" "$backup"; do
        [[ -e "$leftover" ]] && echo "Install failed; bundles kept for manual recovery in $leftover" >&2
    done
    # The installer may have stopped the previous app before failing.
    [[ -e "$app" ]] && open "$app"
    exit 1
fi
rm -rf "$stage" "$backup"
codesign --verify --deep --strict "$app"
# Every build (this one, Debug builds, old derived data) registers another copy
# with the same bundle ID. chronod may then read widget descriptors from a stale
# copy, so new widgets never reach the gallery. Keep only the installed bundle.
"$lsregister" -dump 2>/dev/null | awk -v id="$bundle_id" -v keep="$app" '
    /^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
    /^identifier:/ && $2 == id && path != keep { print path; path = "" }' | sort -u |
while IFS= read -r stale; do "$lsregister" -u "$stale" 2>/dev/null || true; done
"$lsregister" -f "$app"
# chronod can retain the old extension registration even after the old process
# is stopped (Unknown extension process). Restart its per-user cache service.
# Other widgets briefly reload; do not reset their databases or preferences.
killall chronod 2>/dev/null || true
open "$app"
printf '\nInstalled %s (build %s).\n' "$app" "$version"
printf 'Add 本周日程 (medium/extra large) or 本月日程 (extra large) from the widget gallery.\n'
