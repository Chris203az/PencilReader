#!/bin/zsh
# Compila PencilReader e lo reinstalla sull'iPad collegato (libreria e OCR restano).
# Uso: collega l'iPad con il cavo, sbloccalo e lancia  ./installa.sh
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID="com.christianrauso.PencilReader"
APP="build/Build/Products/Debug-iphoneos/PencilReader.app"

echo "→ Cerco l'iPad collegato…"
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
    echo "✗ Nessun iPad trovato: collegalo con il cavo, sbloccalo e riprova."
    exit 1
fi

if command -v xcodegen >/dev/null; then
    xcodegen generate --quiet
fi

echo "→ Compilo (il primo build può richiedere qualche minuto)…"
xcodebuild -project PencilReader.xcodeproj -scheme PencilReader \
    -destination "id=$DEVICE" -derivedDataPath build \
    -allowProvisioningUpdates -quiet build

echo "→ Installo sull'iPad…"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null

echo "→ Avvio l'app…"
if ! xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1; then
    echo "  (L'iPad era bloccato: aprila tu dalla schermata Home.)"
fi

# La scadenza è quella del profilo di firma, che Xcode rinnova solo quando sta per scadere.
EXPIRY=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null || true)
if [[ -n "$EXPIRY" ]]; then
    echo "✓ Fatto. Valida fino a $(LC_TIME=it_IT.UTF-8 date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$EXPIRY" +%s | xargs -I{} env LC_TIME=it_IT.UTF-8 date -r {} '+%A %d %B, %H:%M')."
else
    echo "✓ Fatto."
fi
