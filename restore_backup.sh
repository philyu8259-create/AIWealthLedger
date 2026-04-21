#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <backup.tar.gz> [target_dir]" >&2
  exit 1
fi

BACKUP_PATH="$1"
TARGET_DIR="${2:-$WORKSPACE_DIR}"

if [[ ! -f "$BACKUP_PATH" ]]; then
  echo "Backup not found: $BACKUP_PATH" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
CURRENT_DIR="$TARGET_DIR/ai_accountant"
SAFETY_DIR="$TARGET_DIR/ai_accountant_before_restore_$STAMP"

mkdir -p "$TARGET_DIR"

if [[ -d "$CURRENT_DIR" ]]; then
  mv "$CURRENT_DIR" "$SAFETY_DIR"
  echo "Current project moved to: $SAFETY_DIR"
fi

tar -xzf "$BACKUP_PATH" -C "$TARGET_DIR"
echo "Restored backup into: $CURRENT_DIR"

