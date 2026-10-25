#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d /tmp/itsycal-week-check.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
swiftc WeekWidget/WeekModel.swift Tests/WeekModelCheck.swift -o "$check_dir/model"
"$check_dir/model"
clang -fobjc-arc -fmodules -I Itsycal -I Itsycal/MoCode \
  Itsycal/EventCenter.m Itsycal/MoCode/MoDate.m Tests/EventCenterCheck.m \
  -framework AppKit -framework EventKit -o "$check_dir/events"
python3 Tests/install-check.py
"$check_dir/events"
