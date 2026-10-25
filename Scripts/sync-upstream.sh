#!/bin/bash
# Merge upstream into the feature branch, preserving the fork's widget changes.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(git branch --show-current)" != 'feature/week-widget' ]]; then
    echo 'Switch to feature/week-widget before syncing.' >&2
    exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo 'Commit or stash local changes before syncing.' >&2
    exit 1
fi
if [[ "$(git remote get-url upstream)" != 'https://github.com/sfsam/Itsycal.git' ]]; then
    echo 'Expected upstream to be https://github.com/sfsam/Itsycal.git' >&2
    exit 1
fi

git fetch upstream master
# Fast-forward only: master stays a clean mirror; never overwrite custom history.
git fetch origin master
if git merge-base --is-ancestor origin/master upstream/master; then
    git push origin upstream/master:master
else
    echo 'Fork master has diverged; leaving it unchanged.' >&2
fi
if ! git merge --no-edit upstream/master; then
    echo 'Resolve the merge conflicts, run bash Tests/check-week.sh, then commit and push.' >&2
    echo 'To cancel the merge: git merge --abort' >&2
    exit 1
fi
bash Tests/check-week.sh
xcodebuild -project Itsycal.xcodeproj -scheme Itsycal -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "${TMPDIR:-/tmp}/itsycal-week-sync" \
    CODE_SIGNING_ALLOWED=NO build

git push origin HEAD:feature/week-widget
printf '\nSynced upstream. To update the installed app: bash Scripts/install-week.sh\n'
