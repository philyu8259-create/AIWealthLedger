#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <device_udid> <flavor:cn|intl> <route> <overlay:none|ai|quickadd|ocrhud|reportsmock|predictionmock> <output_png>" >&2
  exit 1
fi

DEVICE_UDID="$1"
FLAVOR="$2"
ROUTE="$3"
OVERLAY="$4"
OUTPUT_PNG_INPUT="$5"
APP_ID="com.phil.AIAccountant"
WORKDIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$WORKDIR/tmp/capture_$(date +%s%N).log"

if [[ "$OUTPUT_PNG_INPUT" = /* ]]; then
  OUTPUT_PNG="$OUTPUT_PNG_INPUT"
else
  OUTPUT_PNG="$WORKDIR/$OUTPUT_PNG_INPUT"
fi

mkdir -p "$(dirname "$OUTPUT_PNG")" "$WORKDIR/tmp"

xcrun simctl boot "$DEVICE_UDID" >/dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$DEVICE_UDID" >/dev/null 2>&1 || true

APP_DATA="$(xcrun simctl get_app_container "$DEVICE_UDID" "$APP_ID" data 2>/dev/null || true)"
if [[ -n "$APP_DATA" && -f "$APP_DATA/Library/Preferences/$APP_ID.plist" ]]; then
  python3 "$WORKDIR/tool/configure_screenshot_prefs.py" "$APP_DATA/Library/Preferences/$APP_ID.plist" --flavor "$FLAVOR" >/dev/null
fi

DEFINE_ARGS=("--dart-define=APP_FLAVOR=$FLAVOR")
if [[ -n "${SCREENSHOT_SELECTED_YEAR:-}" ]]; then
  DEFINE_ARGS+=("--dart-define=SCREENSHOT_SELECTED_YEAR=$SCREENSHOT_SELECTED_YEAR")
fi
if [[ -n "${SCREENSHOT_SELECTED_MONTH:-}" ]]; then
  DEFINE_ARGS+=("--dart-define=SCREENSHOT_SELECTED_MONTH=$SCREENSHOT_SELECTED_MONTH")
fi
if [[ -n "${SCREENSHOT_AUTO_LOAD:-}" ]]; then
  DEFINE_ARGS+=("--dart-define=SCREENSHOT_AUTO_LOAD=$SCREENSHOT_AUTO_LOAD")
fi
if [[ -n "${SCREENSHOT_TARGET_ROUTE:-}" ]]; then
  DEFINE_ARGS+=("--dart-define=SCREENSHOT_TARGET_ROUTE=$SCREENSHOT_TARGET_ROUTE")
fi
if [[ "$OVERLAY" != "none" ]]; then
  case "$OVERLAY" in
    ai|quickadd|ocrhud)
      DEFINE_ARGS+=("--dart-define=SCREENSHOT_OVERLAY=$OVERLAY")
      ;;
    reportsmock)
      DEFINE_ARGS+=("--dart-define=SCREENSHOT_REPORTS_MOCK=1")
      ;;
    predictionmock)
      DEFINE_ARGS+=("--dart-define=SCREENSHOT_PREDICTION_MOCK=1")
      ;;
  esac
fi

(
  cd "$WORKDIR"
  flutter run -d "$DEVICE_UDID" --debug "${DEFINE_ARGS[@]}" --route="$ROUTE" >"$LOG_FILE" 2>&1
) &
RUN_PID=$!

cleanup() {
  kill "$RUN_PID" >/dev/null 2>&1 || true
  wait "$RUN_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

READY=0
for _ in {1..90}; do
  if grep -q "A Dart VM Service on" "$LOG_FILE" || grep -q "Syncing files to device" "$LOG_FILE"; then
    READY=1
    break
  fi
  sleep 1
  APP_DATA="$(xcrun simctl get_app_container "$DEVICE_UDID" "$APP_ID" data 2>/dev/null || true)"
  if [[ -n "$APP_DATA" && -f "$APP_DATA/Library/Preferences/$APP_ID.plist" ]]; then
    python3 "$WORKDIR/tool/configure_screenshot_prefs.py" "$APP_DATA/Library/Preferences/$APP_ID.plist" --flavor "$FLAVOR" >/dev/null || true
  fi
done

if [[ "$READY" -ne 1 ]]; then
  echo "capture failed, app did not become ready" >&2
  tail -n 120 "$LOG_FILE" >&2 || true
  exit 1
fi

sleep 4
if [[ "$OVERLAY" == "ai" || "$OVERLAY" == "quickadd" || "$OVERLAY" == "ocrhud" ]]; then
  sleep 3
fi
xcrun simctl io "$DEVICE_UDID" screenshot "$OUTPUT_PNG" >/dev/null

echo "Saved screenshot to $OUTPUT_PNG"
