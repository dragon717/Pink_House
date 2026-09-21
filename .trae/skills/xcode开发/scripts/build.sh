#!/usr/bin/env bash
# Pink_House 构建入口：把三个必须一起给的沙箱开关封装好，避免每次手工拼命令。
#
#   scripts/build.sh app                       # 只编译主 target（最快，验证自己的代码能否编译）
#   scripts/build.sh testing                   # build-for-testing（验证测试文件也能编译）
#   scripts/build.sh test -o ItemManagerTests/FooTests
#   scripts/build.sh test -o ItemManagerUITests/BarUITests -r /tmp/ph_ui.xcresult
#
# 可选：
#   -d <模拟器名>   默认取 detect_environment.sh 建议值
#   -o <Target/Cls> -only-testing（斜杠语法，点语法会被拒跑）
#   -r <path>       -resultBundlePath，XCUITest 取附件必需
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
DETECT="${SCRIPT_DIR}/detect_environment.sh"

MODE="${1:-app}"; shift 2>/dev/null || true
SIM_NAME=""
ONLY=""
RESULT_BUNDLE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d) SIM_NAME="${2:-}"; shift 2;;
    -o) ONLY="${2:-}"; shift 2;;
    -r) RESULT_BUNDLE="${2:-}"; shift 2;;
    *) shift;;
  esac
done

cd "$REPO_ROOT"

if [ -z "$SIM_NAME" ] && [ -x "$DETECT" ]; then
  SIM_NAME="$("$DETECT" --sim-name)"
fi
SIM_NAME="${SIM_NAME:-iPhone 18 Pro}"

# 三个沙箱开关必须一起给，缺任意一个都会在受限沙箱里以假的代码错误形式失败。
COMMON_FLAGS=(
  -IDEPackageSupportDisableManifestSandbox=YES   # 坑 1：SwiftPM manifest 编译
  -skipPackagePluginValidation
  -skipMacroValidation
  ENABLE_USER_SCRIPT_SANDBOXING=NO               # 坑 3：用户脚本阶段
  'OTHER_SWIFT_FLAGS=$(inherited) -Xfrontend -disable-sandbox'  # 坑 2：宏插件服务
)

LOG="/tmp/xcb_${MODE}.log"
START_TS="$(date +%s)"

case "$MODE" in
  app)
    # 用 -target 时不能配 -derivedDataPath（会报 "-scheme is required"），改用 SYMROOT/OBJROOT。
    # OBJROOT 固定住可复用增量编译：首次约 6 分钟，之后几十秒。
    xcodebuild -project ItemManager.xcodeproj -target ItemManager \
      -sdk iphonesimulator -configuration Debug \
      "${COMMON_FLAGS[@]}" \
      SYMROOT="$PWD/build/sym" OBJROOT="$PWD/build/obj" \
      build > "$LOG" 2>&1
    ;;
  testing)
    xcodebuild -scheme ItemManager \
      -destination "platform=iOS Simulator,name=$SIM_NAME" \
      -derivedDataPath build/DerivedData \
      "${COMMON_FLAGS[@]}" \
      build-for-testing > "$LOG" 2>&1
    ;;
  test)
    args=(test)
    [ -n "$ONLY" ] && args+=("-only-testing:${ONLY}")
    [ -n "$RESULT_BUNDLE" ] && args+=("-resultBundlePath" "$RESULT_BUNDLE")
    xcodebuild -scheme ItemManager \
      -destination "platform=iOS Simulator,name=$SIM_NAME" \
      -derivedDataPath build/DerivedData \
      "${COMMON_FLAGS[@]}" \
      "${args[@]}" > "$LOG" 2>&1
    ;;
  *)
    echo "usage: build.sh [app|testing|test] [-d <sim>] [-o <Target/Class>] [-r <resultBundle>]" >&2
    exit 2
    ;;
esac

CODE=$?
echo "退出码=$CODE  日志=$LOG  起点时间戳=$START_TS"

# 只抓编译器诊断行。源码里 `error: error` 这类文本会让裸 grep "error:" 大量误报。
grep -nE "^/Users/.*:( error| fatal error| error:)" "$LOG" | head -40
grep -E "\*\* (TEST )?BUILD (SUCCEEDED|FAILED) \*\*" "$LOG"

exit "$CODE"
