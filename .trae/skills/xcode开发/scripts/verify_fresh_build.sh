#!/usr/bin/env bash
# 防"假绿"：xcodebuild 可能误判产物最新而完全不重编，用旧产物跑出全绿。
# 校验产物 mtime 是否晚于本轮构建起点。
#
#   START=$(date +%s); scripts/build.sh app; scripts/verify_fresh_build.sh "$START"
#   scripts/verify_fresh_build.sh "$START" /path/to/ItemManager.app
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

START_TS="${1:-}"
APP="${2:-$REPO_ROOT/build/sym/Debug-iphonesimulator/ItemManager.app}"

if [ -z "$START_TS" ]; then
  echo "usage: verify_fresh_build.sh <start_epoch> [ItemManager.app 路径]" >&2
  exit 2
fi

if [ ! -d "$APP" ]; then
  echo "FAIL 产物不存在: $APP" >&2
  exit 1
fi

# 用起点时间戳造一个参照文件，再问 find 有没有比它更新的产物文件。
# （debug 代码在 .debug.dylib，主二进制常常只有几十 KB 且不更新，所以扫整个 bundle）
MARKER="$(mktemp /private/tmp/ph-verify-marker.XXXXXX)"
trap 'rm -f "$MARKER"' EXIT
touch -t "$(date -r "$START_TS" '+%Y%m%d%H%M.%S')" "$MARKER" 2>/dev/null || {
  echo "FAIL 无法构造时间参照文件" >&2; exit 1;
}

# 注意：BSD stat 对多文件 + 带空格的 format 会退化成 filesystem 模式，所以只 stat 单个文件。
NEWEST_FILE="$(find "$APP" -type f -newer "$MARKER" -print -quit 2>/dev/null)"
NEWEST_TS=""
[ -n "$NEWEST_FILE" ] && NEWEST_TS="$(stat -f %m "$NEWEST_FILE" 2>/dev/null)"

if [ -z "$NEWEST_TS" ] || [ "$NEWEST_TS" -lt "$START_TS" ]; then
  echo "STALE 产物早于本轮起点 —— 极可能跑的是旧产物，结果不可信。" >&2
  echo "  起点=$(date -r "$START_TS" '+%Y-%m-%d %H:%M:%S')" >&2
  echo "  处理：touch 改过的源文件后重新 build，真有编译错误会立刻暴露。" >&2
  exit 1
fi

echo "OK 产物新于本轮起点 (产物=$(date -r "$NEWEST_TS" '+%H:%M:%S') 起点=$(date -r "$START_TS" '+%H:%M:%S'))"
exit 0
