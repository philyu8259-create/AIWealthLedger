#!/bin/sh
set -eu

MODE="${1:-prepare}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
RUNNER_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

write_strings() {
  file_path="$1"
  display_name="$2"
  speech_text="$3"
  mic_text="$4"
  camera_text="$5"
  photo_text="$6"

  mkdir -p "$(dirname "$file_path")"
  cat > "$file_path" <<EOF
CFBundleDisplayName = "$display_name";
CFBundleName = "$display_name";
NSSpeechRecognitionUsageDescription = "$speech_text";
NSMicrophoneUsageDescription = "$mic_text";
NSCameraUsageDescription = "$camera_text";
NSPhotoLibraryUsageDescription = "$photo_text";
EOF
}

prepare_localizations() {
  ZH_NAME="AI财富记账本"
  ZH_SPEECH="AI财富记账本需要使用语音识别权限，将您的语音转换为文字用于智能记账分析。"
  ZH_MIC="AI财富记账本需要使用麦克风录制语音，用于语音转文字记账。"
  ZH_CAMERA="AI财富记账本需要使用相机拍摄票据进行 OCR 识别。"
  ZH_PHOTO="AI财富记账本需要访问相册，选择票据图片进行 OCR 识别。"

  EN_NAME="AI Wealth Tracker"
  EN_SPEECH="AI Wealth Tracker uses speech recognition to convert your voice into text for expense analysis and bookkeeping."
  EN_MIC="AI Wealth Tracker uses the microphone to capture your voice for speech-to-text bookkeeping."
  EN_CAMERA="AI Wealth Tracker uses the camera to scan receipts for OCR recognition."
  EN_PHOTO="AI Wealth Tracker accesses your photo library so you can choose receipt images for OCR recognition."

  write_strings "$RUNNER_DIR/Base.lproj/InfoPlist.strings" "$EN_NAME" "$EN_SPEECH" "$EN_MIC" "$EN_CAMERA" "$EN_PHOTO"
  write_strings "$RUNNER_DIR/zh-Hans.lproj/InfoPlist.strings" "$ZH_NAME" "$ZH_SPEECH" "$ZH_MIC" "$ZH_CAMERA" "$ZH_PHOTO"
  write_strings "$RUNNER_DIR/en.lproj/InfoPlist.strings" "$EN_NAME" "$EN_SPEECH" "$EN_MIC" "$EN_CAMERA" "$EN_PHOTO"
}

finalize_bundle_name() {
  # Keep localized bundle names resolved by InfoPlist.strings.
  exit 0
}

case "$MODE" in
  prepare)
    prepare_localizations
    ;;
  finalize)
    finalize_bundle_name
    ;;
  *)
    echo "Unsupported mode: $MODE" >&2
    exit 1
    ;;
esac
