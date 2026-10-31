#!/bin/zsh
# Builds PencilReader and reinstalls it on the connected iPad (library and OCR are kept).
# Usage: connect the iPad with a cable, unlock it and run  ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="com.christianrauso.PencilReader"
APP="build/Build/Products/Debug-iphoneos/PencilReader.app"

echo "→ Looking for the connected iPad…"
JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1
DEVICE=$(/usr/bin/python3 -c '
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
for d in devices:
    props = d.get("hardwareProperties", {})
    if props.get("platform") == "iOS" and props.get("reality") == "physical" \
       and d.get("connectionProperties", {}).get("tunnelState") != "unavailable":
        print(props["udid"]); break
' "$JSON")
rm -f "$JSON"
if [[ -z "$DEVICE" ]]; then
    echo "✗ No iPad found: connect it with a cable, unlock it and try again."
    exit 1
fi

if command -v xcodegen >/dev/null; then
    xcodegen generate --quiet
fi

echo "→ Building (the first build can take a few minutes)…"
xcodebuild -project PencilReader.xcodeproj -scheme PencilReader \
    -destination "id=$DEVICE" -derivedDataPath build \
    -allowProvisioningUpdates -quiet build

echo "→ Installing on the iPad…"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null

echo "→ Launching the app…"
if ! xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "  (The iPad was locked: open the app from the Home Screen.)"
fi

# The expiry is the signing profile's, which Xcode renews only when it is about to expire.
EXPIRY=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null || true)
if [[ -n "$EXPIRY" ]]; then
    echo "✓ Done. Valid until $(LC_TIME=en_US.UTF-8 date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$EXPIRY" +%s | xargs -I{} env LC_TIME=en_US.UTF-8 date -r {} '+%A %d %B, %H:%M')."
else
    echo "✓ Done."
fi
