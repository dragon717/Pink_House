#!/usr/bin/env bash
set -u

export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XCODE_APP="${XCODE_APP:-/Applications/Xcode-beta.app}"
DEVELOPER_DIR="${DEVELOPER_DIR:-$XCODE_APP/Contents/Developer}"
SCHEME="${SCHEME:-ItemManager}"
SIM_NAME="${SIM_NAME:-Codex iPhone 17 Pro}"
SIM_ID="${SIM_ID:-}"
MAX_JOBS="${MAX_JOBS:-5}"
BUILD_TIMEOUT_SECONDS="${BUILD_TIMEOUT_SECONDS:-180}"
ALLOW_PARALLEL_BUILDS="${ALLOW_PARALLEL_BUILDS:-0}"

if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "Xcode toolchain not found: $DEVELOPER_DIR" >&2
  exit 64
fi

export DEVELOPER_DIR

if [[ -z "$SIM_ID" ]]; then
  SIM_ID="$(
    xcrun simctl list devices available |
      grep -F "$SIM_NAME" |
      sed -nE 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/p' |
      head -1
  )"
fi

if [[ -z "$SIM_ID" ]]; then
  echo "Simulator not found: $SIM_NAME" >&2
  exit 65
fi

if [[ -z "${DERIVED_DATA:-}" ]]; then
  DERIVED_DATA="$(
    find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 1 -type d -name "${SCHEME}-*" -print0 2>/dev/null |
      xargs -0 ls -td 2>/dev/null |
      head -1
  )"
fi

if [[ -z "${DERIVED_DATA:-}" || ! -d "$DERIVED_DATA" ]]; then
  echo "DerivedData not found for scheme: $SCHEME" >&2
  exit 66
fi

SPM_CACHE="${SPM_CACHE:-$DERIVED_DATA/SourcePackages}"
if [[ ! -d "$SPM_CACHE" ]]; then
  echo "SourcePackages cache not found: $SPM_CACHE" >&2
  exit 66
fi

duplicate_file="$(find "$SPM_CACHE/checkouts" -name '* 2.swift' -print -quit 2>/dev/null || true)"
if [[ -n "$duplicate_file" ]]; then
  echo "Refusing polluted SourcePackages cache; first duplicate: $duplicate_file" >&2
  echo "Use a clean Xcode DerivedData SourcePackages cache via SPM_CACHE=..." >&2
  exit 66
fi

if [[ "$ALLOW_PARALLEL_BUILDS" != "1" ]]; then
  existing_builds="$(pgrep -fl "xcodebuild .*${SCHEME}" 2>/dev/null || true)"
  if [[ -n "$existing_builds" ]]; then
    echo "Another $SCHEME xcodebuild is already running:" >&2
    echo "$existing_builds" >&2
    exit 67
  fi
fi

LOG="${LOG:-/private/tmp/pink-house-cli-build-$(date +%Y%m%d%H%M%S).log}"
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$SCHEME.app"
timeout_marker="$(mktemp /private/tmp/pink-house-build-timeout.XXXXXX)"
rm -f "$timeout_marker"

echo "REPO_ROOT=$REPO_ROOT"
echo "XCODE=$("$DEVELOPER_DIR/usr/bin/xcodebuild" -version | tr '\n' ' ')"
echo "SCHEME=$SCHEME"
echo "SIM_ID=$SIM_ID"
echo "DERIVED_DATA=$DERIVED_DATA"
echo "SPM_CACHE=$SPM_CACHE"
echo "MAX_JOBS=$MAX_JOBS"
echo "BUILD_TIMEOUT_SECONDS=$BUILD_TIMEOUT_SECONDS"
echo "LOG=$LOG"

xcrun simctl bootstatus "$SIM_ID" -b >/dev/null 2>&1 ||
  xcrun simctl boot "$SIM_ID" >/dev/null 2>&1 ||
  true

cd "$REPO_ROOT"

echo "COMMAND=xcodebuild -scheme $SCHEME -destination platform=iOS Simulator,id=$SIM_ID -derivedDataPath $DERIVED_DATA -clonedSourcePackagesDirPath $SPM_CACHE -jobs $MAX_JOBS -quiet build"

start_epoch="$(date +%s)"
perl -MPOSIX=setsid -e 'setsid() or die "setsid: $!"; exec @ARGV' \
  "$DEVELOPER_DIR/usr/bin/xcodebuild" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SPM_CACHE" \
  -jobs "$MAX_JOBS" \
  -quiet \
  build >"$LOG" 2>&1 &
build_pid=$!

(
  sleep "$BUILD_TIMEOUT_SECONDS"
  if kill -0 "$build_pid" 2>/dev/null; then
    echo "TIMEOUT_AFTER_${BUILD_TIMEOUT_SECONDS}S" >"$timeout_marker"
    echo "TIMEOUT_AFTER_${BUILD_TIMEOUT_SECONDS}S" >>"$LOG"
    kill -TERM -"$build_pid" 2>/dev/null || kill -TERM "$build_pid" 2>/dev/null || true
    sleep 10
    kill -KILL -"$build_pid" 2>/dev/null || kill -KILL "$build_pid" 2>/dev/null || true
  fi
) &
watchdog_pid=$!

wait "$build_pid"
build_status=$?
kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

if [[ -s "$timeout_marker" ]]; then
  build_status=124
fi
rm -f "$timeout_marker"

end_epoch="$(date +%s)"
echo "ELAPSED_SECONDS=$((end_epoch - start_epoch))"
echo "BUILD_EXIT=$build_status"

if [[ "$build_status" -ne 0 ]]; then
  echo "LOG_TAIL_BEGIN"
  tail -120 "$LOG" 2>/dev/null || true
  echo "LOG_TAIL_END"
  exit "$build_status"
fi

if [[ ! -d "$APP" ]]; then
  echo "Built app not found: $APP" >&2
  exit 68
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo "APP=$APP"
echo "BUNDLE_ID=$BUNDLE_ID"

xcrun simctl install "$SIM_ID" "$APP"
install_status=$?

terminate_output="$(xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>&1)"
terminate_status=$?

launch_output="$(xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" 2>&1)"
launch_status=$?

echo "$launch_output"
echo "INSTALL_EXIT=$install_status"
echo "TERMINATE_EXIT=$terminate_status"
if [[ "$terminate_status" -ne 0 ]]; then
  echo "TERMINATE_OUTPUT=$terminate_output"
fi
echo "LAUNCH_EXIT=$launch_status"

exit "$launch_status"
