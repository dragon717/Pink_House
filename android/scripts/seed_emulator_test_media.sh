#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_DIR="$ROOT_DIR/app/src/debug/assets/wardrobe_test_media"
ADB_BIN="${ADB_BIN:-$HOME/Library/Android/sdk/platform-tools/adb}"
TARGET_DIR="/sdcard/Pictures/PinkHouseTest"

if [[ ! -x "$ADB_BIN" ]]; then
  echo "adb not found: $ADB_BIN" >&2
  exit 1
fi

if [[ ! -d "$ASSET_DIR" ]]; then
  echo "debug test media not found: $ASSET_DIR" >&2
  exit 1
fi

"$ADB_BIN" wait-for-device
"$ADB_BIN" shell "mkdir -p '$TARGET_DIR'"
"$ADB_BIN" push "$ASSET_DIR/." "$TARGET_DIR/"
"$ADB_BIN" shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d "file://$TARGET_DIR" >/dev/null 2>&1 || true
"$ADB_BIN" shell am broadcast -a android.intent.action.MEDIA_MOUNTED -d "file:///sdcard" >/dev/null 2>&1 || true

echo "Seeded emulator media to $TARGET_DIR"
