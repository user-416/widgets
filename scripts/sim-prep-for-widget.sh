#!/usr/bin/env bash
# sim-prep-for-widget.sh — install Widgets into the iPhone Simulator with the
# correct App Group entitlement (xcodebuild's auto-sign strips it), seed sample
# data, and bring the Simulator window forward so you can manually add the
# widget to the home screen.
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
echo "→ Using simulator: $SIMULATOR_ID"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT/ios"

echo "→ Booting simulator…"
xcrun simctl boot "${SIMULATOR_ID}" 2>/dev/null || true
sleep 1
open -a Simulator

echo "→ Building app for simulator…"
xcodebuild -project Widgets.xcodeproj -scheme Widgets \
    -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
    build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3

APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData/Widgets-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name 'Widgets.app' 2>/dev/null | head -1)"
WIDGET_PATH="${APP_PATH}/PlugIns/WidgetsWidget.appex"
if [ ! -d "${APP_PATH}" ]; then
    echo "✗ Widgets.app not found"; exit 1
fi

echo "→ Re-signing with App-Group-only entitlement…"
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
codesign --force --sign - --entitlements "$SIM_ENT" "${WIDGET_PATH}"
codesign --force --sign - --entitlements "$SIM_ENT" "${APP_PATH}"
rm -f "$SIM_ENT"

echo "→ Reinstalling and launching with seed data…"
xcrun simctl terminate "${SIMULATOR_ID}" io.github.user-416.widgets 2>/dev/null || true
xcrun simctl uninstall "${SIMULATOR_ID}" io.github.user-416.widgets 2>/dev/null || true
xcrun simctl install "${SIMULATOR_ID}" "${APP_PATH}"
xcrun simctl launch "${SIMULATOR_ID}" io.github.user-416.widgets --seed-sample-data
sleep 4

SNAPSHOT="$(find ~/Library/Developer/CoreSimulator/Devices/${SIMULATOR_ID}/data/Containers/Shared/AppGroup -name snapshot.json 2>/dev/null | head -1)"
if [ -n "$SNAPSHOT" ]; then
    python3 -c "
import json
d = json.load(open('${SNAPSHOT}'))
print(f'✓ Snapshot written: {len(d[\"metrics\"])} metrics')
for m in d['metrics']:
    print(f'    {m[\"name\"]:<14} ({m[\"color\"]:<13}) — {len(m[\"days\"])} days')
"
else
    echo "✗ No snapshot file. Entitlement may be wrong."; exit 1
fi

echo "→ Pressing home (Cmd+Shift+H) to bring up the home screen…"
osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
sleep 1
osascript -e 'tell application "System Events" to keystroke "h" using {command down, shift down}' 2>/dev/null || true
sleep 1

cat <<'STEPS'

=================================================================
NOW IN THE SIMULATOR WINDOW, ADD THE WIDGET MANUALLY:

  1. Click + hold an empty area on the home screen for ~1.5 seconds
     (long-press). Icons start jiggling.
  2. Click "Edit" in the top-left → "Add Widget" from the popup.
  3. Scroll the gallery and tap "KPI Grid" (or use Search).
  4. Pick a size — Small, Medium, or Large — then click "Add Widget".
  5. Click "Done" in the top-right.

The widget renders today's count + the seeded heatmap. To switch which
metric it shows: long-press the placed widget → "Edit Widget" → select
Sales calls / Deep focus / Workouts.

For lock-screen widget: Settings → Wallpaper → Customize Lock Screen
→ tap a widget slot → search "KPI Grid" → choose the rectangular size.
=================================================================
STEPS
