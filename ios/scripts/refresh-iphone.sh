#!/bin/zsh
# Rebuilds Clockwise and reinstalls it on the iPhone over Wi-Fi, renewing the free 7-day signing.
# Installing over the existing app keeps its data. Run by the launch agent in scripts/com.tan.clockwise.refresh.plist.
set -euo pipefail

DEVICE="00008120-001C752C3A90201E"
LOG="${HOME}/Library/Logs/clockwise-refresh.log"
cd "$(dirname "$0")/.."

notify() {
    local title="$1" message="$2"
    /usr/bin/osascript -e "display notification \"${message}\" with title \"${title}\"" >/dev/null 2>&1 || true
}

device_state() {
    local json
    json="$(mktemp -t clockwise-devices)"
    if ! xcrun devicectl list devices --timeout 30 --json-output "$json" >/dev/null 2>&1; then
        rm -f "$json"
        echo "unknown"
        return
    fi
    /usr/bin/python3 - "$json" "$DEVICE" <<'PY'
import json, sys
path, udid = sys.argv[1], sys.argv[2]
data = json.load(open(path))
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties") or {}
    props = (d.get("properties") or {}).get("hardware") or {}
    if hw.get("udid") == udid or props.get("udid") == udid:
        conn = d.get("connectionProperties") or {}
        state = ((d.get("properties") or {}).get("connection") or {}).get("state")
        print(state or conn.get("tunnelState") or "unknown")
        break
else:
    print("missing")
PY
    rm -f "$json"
}

wait_for_device() {
    local attempts="${1:-12}" delay="${2:-15}" state
    echo "Waiting for device ${DEVICE} (up to $((attempts * delay))s)…"
    for ((i = 1; i <= attempts; i++)); do
        state="$(device_state)"
        echo "  attempt ${i}/${attempts}: state=${state}"
        case "$state" in
            connected|available) return 0 ;;
        esac
        sleep "$delay"
    done
    return 1
}

install_app() {
    local attempts="${1:-6}" delay="${2:-20}"
    local app="build/refresh/Build/Products/Release-iphoneos/Clockwise.app"
    for ((i = 1; i <= attempts; i++)); do
        echo "Install attempt ${i}/${attempts}…"
        if xcrun devicectl device install app --device "$DEVICE" --timeout 120 "$app"; then
            return 0
        fi
        echo "  install failed; sleeping ${delay}s"
        sleep "$delay"
    done
    return 1
}

echo "=== $(date) ==="

echo "Building…"
xcodebuild -project Clockwise.xcodeproj -scheme Clockwise -configuration Release \
    -destination generic/platform=iOS -derivedDataPath build/refresh \
    -allowProvisioningUpdates -quiet build

if ! wait_for_device 12 15; then
    echo "ERROR: iPhone not reachable (locked, asleep, or not on the same Wi-Fi as this Mac)."
    notify "Clockwise refresh failed" "Unlock the iPhone on this Wi-Fi (or plug it in), then run: ios/scripts/refresh-iphone.sh"
    exit 1
fi

if ! install_app 6 20; then
    echo "ERROR: install failed after retries. See ${LOG}"
    notify "Clockwise refresh failed" "Build OK but install failed. Unlock/plug in the iPhone and re-run the refresh script."
    exit 1
fi

echo "Installed."
notify "Clockwise refreshed" "7-day signing renewed on jonathan's iPhone."
