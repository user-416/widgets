#!/usr/bin/env bash
# run-ui-tests.sh — build, re-sign with entitlements, then run UI tests.
#
# xcodebuild's automatic signing in iOS Simulator strips the HealthKit
# entitlement when building without a real Team. This wrapper re-signs
# both the app and widget extension after build, then runs tests using
# `test-without-building` so the re-signed bundle is used.
set -euo pipefail

# Resolve a simulator UDID:
#   1. honor $SIMULATOR_ID if explicitly set
#   2. else use any booted iPhone simulator
#   3. else the first available iPhone 15+ simulator
#   4. else fall back to a documented hardcoded UDID (last resort, may not exist)
detect_simulator_id() {
  if [ -n "${SIMULATOR_ID:-}" ]; then echo "$SIMULATOR_ID"; return; fi
  if command -v jq >/dev/null 2>&1; then
    local id
    id=$(xcrun simctl list devices booted -j 2>/dev/null \
      | jq -r '.devices[][] | select(.state=="Booted" and (.name|test("^iPhone"))) | .udid' \
      | head -1)
    if [ -n "$id" ]; then echo "$id"; return; fi
    id=$(xcrun simctl list devices available -j 2>/dev/null \
      | jq -r '.devices | to_entries[] | select(.key|test("iOS")) | .value[] | select(.name|test("iPhone 1[5-9]|iPhone 2[0-9]")) | .udid' \
      | head -1)
    if [ -n "$id" ]; then echo "$id"; return; fi
  fi
  echo "97AC1F14-548F-4D10-96E1-8B1595FA60B2"
}
SIMULATOR_ID="$(detect_simulator_id)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT/ios"

ONLY_TESTING_FLAGS=()
if [ $# -gt 0 ]; then
  for spec in "$@"; do
    ONLY_TESTING_FLAGS+=("-only-testing:$spec")
  done
fi

echo "→ Building app + tests for testing…"
xcodebuild \
    -project Widgets.xcodeproj \
    -scheme Widgets \
    -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
    -configuration Debug \
    build-for-testing CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3

DD="$(xcodebuild -project Widgets.xcodeproj -scheme Widgets -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" -showBuildSettings 2>/dev/null | awk -F= '/^[ ]+BUILT_PRODUCTS_DIR =/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')"
APP="${DD}/Widgets.app"
WIDGET="${APP}/PlugIns/WidgetsWidget.appex"

echo "→ Re-signing with app-group-only entitlements (HealthKit entitlement is rejected by Simulator without a real Team)…"
SIM_ENT="$(mktemp -t widgets-sim-ent.XXXXXX).plist"
cat > "$SIM_ENT" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.io.github.user-416.widgets</string>
    </array>
</dict>
</plist>
EOF
if [ -d "${WIDGET}" ]; then
    codesign --force --sign - --entitlements "$SIM_ENT" "${WIDGET}"
fi
codesign --force --sign - --entitlements "$SIM_ENT" "${APP}"
rm -f "$SIM_ENT"

echo "→ Verifying app entitlements…"
codesign -d --entitlements - "${APP}" 2>&1 | tail -3

echo "→ Running tests…"
xcodebuild \
    -project Widgets.xcodeproj \
    -scheme Widgets \
    -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
    -configuration Debug \
    "${ONLY_TESTING_FLAGS[@]}" \
    test-without-building CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
