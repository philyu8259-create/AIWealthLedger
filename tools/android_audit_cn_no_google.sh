#!/usr/bin/env bash
set -euo pipefail

APK_PATH="${1:-}"

if [ -z "${APK_PATH}" ]; then
  APK_PATH=$(find build/app/outputs -path '*/cn/release/*.apk' -name '*.apk' | head -n 1)
fi
if [ -z "${APK_PATH}" ]; then
  APK_PATH=$(find build/app/outputs -name '*.apk' | head -n 1)
fi

if [ -z "${APK_PATH}" ] || [ ! -f "${APK_PATH}" ]; then
  echo "FAIL: no APK found. Pass APK_PATH=... when calling the target."
  exit 1
fi

echo "Checking APK for google-related binaries: ${APK_PATH}"

if unzip -l "${APK_PATH}" | rg -n 'common_google_signin|play-services|firebase-encoders|com/google/android/gms'; then
  echo "FAIL: found disallowed Google/Firebase markers in APK zip entries."
  exit 1
fi

FOUND_DEX=0
while IFS= read -r entry; do
  if unzip -p "${APK_PATH}" "${entry}" | strings | rg -q 'common_google_signin|play-services|firebase-encoders|com/google/android/gms'; then
    echo "FAIL: found disallowed marker in dex: ${entry}"
    FOUND_DEX=1
    break
  fi
done < <(unzip -Z1 "${APK_PATH}" | rg '^classes[0-9]*\.dex$')

if [ "${FOUND_DEX}" -ne 0 ]; then
  exit 1
fi

echo "PASS: APK has no direct google_sign_in/play-services/firebase-encoders/com/google/android/gms artifacts."
