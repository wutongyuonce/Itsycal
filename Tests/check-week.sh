#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/itsycal-week-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
swiftc ItsycalWidgets/WeekModel.swift ItsycalWidgets/WeekPreview.swift Tests/WeekModelCheck.swift -o "$check_dir/model"
"$check_dir/model"
swiftc Itsycal/AIAssistant.swift Tests/AIAssistantCheck.swift -o "$check_dir/ai"
"$check_dir/ai"
swiftc Itsycal/AIAssistant.swift ItsycalMobile/MobileCalendarModel.swift Tests/MobileCalendarCheck.swift -o "$check_dir/mobile"
"$check_dir/mobile"
clang -fobjc-arc -fmodules -I Tests/Stubs -I Itsycal -I Itsycal/MoCode \
  Itsycal/EventCenter.m Itsycal/ReminderRecurrence.m Itsycal/WeekSnapshot.m Itsycal/Itsycal.m Itsycal/MoCode/MoDate.m Tests/EventCenterCheck.m \
  -framework AppKit -framework EventKit -o "$check_dir/events"
python3 Tests/install-check.py
TZ=Asia/Shanghai "$check_dir/events" # Expected dates are written in +08:00.
