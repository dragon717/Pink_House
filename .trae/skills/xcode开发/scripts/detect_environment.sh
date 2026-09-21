#!/usr/bin/env bash
# 开工自检：把"会漂移的环境事实"一次性取出来，供后续命令拼装。
#   scripts/detect_environment.sh            # 打印全部事实
#   scripts/detect_environment.sh --sim-name # 只打印建议的模拟器名（供 build.sh -d 用）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

only_sim=0
[ "${1:-}" = "--sim-name" ] && only_sim=1

sim_name() {
  # 1) 已开机的 iPhone 优先
  local booted
  booted="$(xcrun simctl list devices 2>/dev/null | awk -F'[()]' '/\(Booted\)/ && /iPhone/ {gsub(/^ +| +$/,"",$1); print $1; exit}')"
  [ -n "$booted" ] && { printf '%s' "$booted"; return; }

  # 2) 否则取**最后一个运行时分组**里的第一台 iPhone。
  #    本工程 scheme 只认 iOS 27 runtime：选 iOS 26.3 的 iPhone 17 Pro 会直接 exit 70。
  local newest
  newest="$(xcrun simctl list devices available 2>/dev/null | awk '
    /^-- /            { first = "" }
    /iPhone/ && first == "" { s = $0; sub(/^ +/, "", s); sub(/ *\(.*/, "", s); first = s }
    END { print first }')"
  printf '%s' "${newest:-iPhone 18 Pro}"
}

if [ "$only_sim" -eq 1 ]; then
  sim_name
  exit 0
fi

echo "REPO_ROOT=$REPO_ROOT"
echo "GIT_TOPLEVEL=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null)"

echo "XCODE_SELECT=$(xcode-select -p 2>/dev/null)"
if [ -d /Applications/Xcode.app ]; then
  echo "XCODE_APP=/Applications/Xcode.app"
  echo "XCODE_VERSION=$(/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -version 2>/dev/null | tr '\n' ' ')"
fi
if [ -d /Applications/Xcode-beta.app ]; then
  echo "XCODE_BETA=/Applications/Xcode-beta.app (存在)"
else
  echo "XCODE_BETA=(不存在，不要设 DEVELOPER_DIR 指向它)"
fi

echo "SIM_SUGGESTED=$(sim_name)"
echo "--- 可用 iPhone 模拟器 ---"
xcrun simctl list devices available 2>/dev/null | grep -E "iPhone" | sed 's/^/  /'

BUNDLE_ID="$(grep -m1 PRODUCT_BUNDLE_IDENTIFIER "$REPO_ROOT/ItemManager.xcodeproj/project.pbxproj" 2>/dev/null | awk -F'= ' '{print $2}' | tr -d ';" ')"
echo "BUNDLE_ID=${BUNDLE_ID:-<未取到，手工确认>}"

echo "SCHEMES=$(ls "$REPO_ROOT/ItemManager.xcodeproj/xcshareddata/xcschemes/" 2>/dev/null | tr '\n' ' ')"
echo "OBJECT_VERSION=$(grep -m1 objectVersion "$REPO_ROOT/ItemManager.xcodeproj/project.pbxproj" 2>/dev/null | sed -E 's/.*= *([0-9]+).*/\1/')"
echo "DEFAULT_ACTOR_ISOLATION=$(grep -m1 SWIFT_DEFAULT_ACTOR_ISOLATION "$REPO_ROOT/ItemManager.xcodeproj/project.pbxproj" 2>/dev/null | sed -E 's/.*= *([A-Za-z]+).*/\1/')"

echo "APP_PRODUCT=$REPO_ROOT/build/sym/Debug-iphonesimulator/ItemManager.app"
