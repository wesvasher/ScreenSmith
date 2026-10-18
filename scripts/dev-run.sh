#!/bin/bash
# Rebuild ScreenSmith and relaunch it, but only if sources changed since the last successful build.
# Used as a Claude Code Stop hook (.claude/settings.json); also fine to run by hand.
# Pass --force to rebuild even when nothing changed.

set -u
cd "$(dirname "$0")/.." || exit 1

BUILD_DIR="build/DerivedData"
APP="$BUILD_DIR/Build/Products/Debug/ScreenSmith.app"
STAMP="build/.last-successful-build"
LOG="build/last-build.log"

# When run as a Stop hook, Claude Code sends JSON on stdin. stop_hook_active is true when
# Claude is already continuing because of this hook, so don't block a second time.
HOOK_ACTIVE=false
if [ ! -t 0 ]; then
    HOOK_ACTIVE=$(jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
fi

if [ "${1:-}" != "--force" ] && [ -f "$STAMP" ] && [ -d "$APP" ]; then
    # Folders too: deleting a file only updates its folder's modification time.
    changed=$(find ScreenSmith ScreenSmith.xcodeproj -newer "$STAMP" -not -path '*/xcuserdata/*' | head -1)
    [ -z "$changed" ] && exit 0
fi

mkdir -p build
touch build/.build-started

if ! xcodebuild -project ScreenSmith.xcodeproj -scheme ScreenSmith -configuration Debug \
        -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates build > "$LOG" 2>&1; then
    errors=$(grep -E "error:" "$LOG" | sort -u | head -20)
    if [ "$HOOK_ACTIVE" = "true" ]; then
        jq -n --arg m "ScreenSmith build failed again; see build/last-build.log" '{systemMessage: $m}'
        exit 0
    fi
    echo "ScreenSmith build failed. Fix these errors (full log: build/last-build.log):" >&2
    echo "${errors:-$(tail -20 "$LOG")}" >&2
    exit 2
fi

mv build/.build-started "$STAMP"

# Quit the running copy (whichever build it came from) and start the fresh one.
pkill -x ScreenSmith
for _ in $(seq 1 20); do pgrep -x ScreenSmith > /dev/null || break; sleep 0.25; done
# Launch Services occasionally refuses (error -600) while the old copy is still shutting down, so retry.
for _ in 1 2 3; do
    open "$APP" 2>/dev/null
    sleep 1
    pgrep -x ScreenSmith > /dev/null && break
done

if ! pgrep -x ScreenSmith > /dev/null; then
    jq -n '{systemMessage: "ScreenSmith rebuilt but failed to launch; run scripts/dev-run.sh --force"}'
    exit 0
fi

jq -n '{systemMessage: "ScreenSmith rebuilt and relaunched"}'
