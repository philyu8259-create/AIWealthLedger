#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

print_usage() {
  echo "Usage: $0 cn|intl [--no-pub-get]" >&2
}

VARIANT="${1:-}"
if [ -z "$VARIANT" ]; then
  print_usage
  echo "Error: missing variant argument." >&2
  exit 1
fi

if [ "$VARIANT" != "cn" ] && [ "$VARIANT" != "intl" ]; then
  print_usage
  echo "Error: unknown variant '$VARIANT'. Use 'cn' or 'intl'." >&2
  exit 1
fi

NO_PUB_GET="false"
shift
for arg in "$@"; do
  case "$arg" in
    --no-pub-get)
      NO_PUB_GET="true"
      ;;
    *)
      print_usage
      echo "Error: unknown argument '$arg'." >&2
      exit 1
      ;;
  esac
done

SOURCE_FILE="$PROJECT_ROOT/pubspec.$VARIANT.yaml"
TARGET_FILE="$PROJECT_ROOT/pubspec.yaml"
SOURCE_LOCK_FILE="$PROJECT_ROOT/pubspec.$VARIANT.lock"
TARGET_LOCK_FILE="$PROJECT_ROOT/pubspec.lock"

if [ ! -f "$SOURCE_FILE" ]; then
  echo "Error: missing variant spec file: $SOURCE_FILE" >&2
  exit 1
fi

cp "$SOURCE_FILE" "$TARGET_FILE"
echo "Selected $VARIANT variant: $SOURCE_FILE -> pubspec.yaml"

if [ -f "$SOURCE_LOCK_FILE" ]; then
  cp "$SOURCE_LOCK_FILE" "$TARGET_LOCK_FILE"
  echo "Loaded $VARIANT lock: $SOURCE_LOCK_FILE -> pubspec.lock"
fi

if [ "$NO_PUB_GET" = "true" ]; then
  echo "Skipped flutter pub get for $VARIANT due --no-pub-get."
  exit 0
fi

if [ "${FLUTTER:-}" ]; then
  "$FLUTTER" pub get
else
  flutter pub get
fi

cp "$TARGET_LOCK_FILE" "$SOURCE_LOCK_FILE"
echo "Refreshed $VARIANT lock: pubspec.lock -> $SOURCE_LOCK_FILE"
