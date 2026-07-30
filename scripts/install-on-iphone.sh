#!/usr/bin/env bash
# install-on-iphone.sh — build Widgets and install it on a connected iPhone.
#
# Prereqs (all interactive, one-time):
#   1. Sign into Xcode with your Apple ID:  Xcode → Settings → Accounts → +
#      A free personal team works (apps expire after 7 days; paid lasts a year).
#   2. Plug your iPhone in via USB (or wireless after first pairing).
#      Trust the computer when iOS asks.
#   3. Make sure Developer Mode is on:  Settings → Privacy & Security → Developer Mode.
#
# Then run:  ./scripts/install-on-iphone.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT/ios"

echo "→ Looking for connected iPhone…"
DEVICES_JSON="$(xcrun devicectl list devices --json-output - 2>/dev/null || echo '{}')"
DEVICE_UDID="$(printf '%s' "$DEVICES_JSON" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for dev in data.get("result", {}).get("devices", []):
    if dev.get("connectionProperties", {}).get("transportType") in ("usb", "wired", "wireless"):
        if dev.get("hardwareProperties", {}).get("platform") == "iOS":
            print(dev["identifier"])
            break
')"

if [ -z "$DEVICE_UDID" ]; then
    echo "✗ No iPhone detected."
    echo "  Plug your iPhone in via USB and trust the computer, then re-run."
    exit 1
fi
echo "  Found device: $DEVICE_UDID"

echo "→ Reading your Xcode developer team…"
TEAM_ID="$(defaults read com.apple.dt.Xcode IDEProvisioningTeams 2>/dev/null \
  | grep -E '"teamID"' \
  | head -1 \
  | sed -E 's/.*"teamID" = "([^"]+)".*/\1/' \
  || true)"

if [ -z "$TEAM_ID" ]; then
    echo "✗ No Apple Developer team configured in Xcode."
    echo "  Open Xcode → Settings → Accounts → + and sign in with your Apple ID."
    exit 1
fi
echo "  Team: $TEAM_ID"

echo "→ Patching project.yml with your team…"
python3 - "$TEAM_ID" <<'PY'
import re, sys
team = sys.argv[1]
with open("project.yml", "r") as f:
    text = f.read()
text = re.sub(r"DEVELOPMENT_TEAM:\s*''?", f"DEVELOPMENT_TEAM: '{team}'", text)
with open("project.yml", "w") as f:
    f.write(text)
print(f"  DEVELOPMENT_TEAM = {team}")
PY

echo "→ Regenerating Xcode project…"
xcodegen generate >/dev/null

echo "→ Building and installing on device (this can take a couple minutes)…"
xcodebuild \
    -project Widgets.xcodeproj \
    -scheme Widgets \
    -destination "id=$DEVICE_UDID" \
    -configuration Debug \
    -allowProvisioningUpdates \
    build install \
    2>&1 | tail -20

echo ""
echo "✓ Installed. Launch Widgets from your home screen."
echo ""
echo "Tips:"
echo "  - Trust the developer cert: iPhone → Settings → General → VPN & Device Management → tap your team → Trust"
echo "  - First launch: tap + → Steps → grant Apple Health permission"
echo "  - Add the widget: long-press home screen → + → search Widgets"
