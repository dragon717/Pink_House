#!/usr/bin/env bash
# Build the native Mac app for local use. Does not upload or install it.
set -euo pipefail

export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$REPO_ROOT/build/mac-release}"
mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"

BUILD_ARGS=(
  build -project "$REPO_ROOT/ItemManager.xcodeproj" -scheme PinkHouseOps
  -configuration Release -destination "platform=macOS,arch=$(uname -m)"
  -derivedDataPath "$OUTPUT_ROOT/DerivedData" -jobs "${MAX_JOBS:-2}"
  ONLY_ACTIVE_ARCH=YES
)
if [[ -n "${SPM_CACHE:-}" ]]; then
  BUILD_ARGS+=(
    -clonedSourcePackagesDirPath "$SPM_CACHE"
    -disableAutomaticPackageResolution -skipPackageUpdates
  )
fi

if ! xcodebuild "${BUILD_ARGS[@]}" >"$OUTPUT_ROOT/build.log" 2>&1; then
  tail -80 "$OUTPUT_ROOT/build.log" >&2
  exit 1
fi

BUILT_APP="$OUTPUT_ROOT/DerivedData/Build/Products/Release/PinkHouseOps.app"
codesign --verify --deep --strict "$BUILT_APP"
STAGING="$(mktemp -d "$OUTPUT_ROOT/.package.XXXXXX")"
APP_NAME="少女心愿运营.app"
ditto "$BUILT_APP" "$STAGING/$APP_NAME"
codesign --verify --deep --strict "$STAGING/$APP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$STAGING/$APP_NAME" "$STAGING/少女心愿运营.zip"

# Keep earlier local packages recoverable instead of merging signed bundles.
if [[ -e "$OUTPUT_ROOT/$APP_NAME" || -e "$OUTPUT_ROOT/少女心愿运营.zip" ]]; then
  PREVIOUS="$(mktemp -d "$OUTPUT_ROOT/.previous.XXXXXX")"
  for name in "$APP_NAME" "少女心愿运营.zip"; do
    if [[ -e "$OUTPUT_ROOT/$name" ]]; then
      mv "$OUTPUT_ROOT/$name" "$PREVIOUS/$name"
    fi
  done
fi
mv "$STAGING/$APP_NAME" "$OUTPUT_ROOT/$APP_NAME"
mv "$STAGING/少女心愿运营.zip" "$OUTPUT_ROOT/少女心愿运营.zip"
rmdir "$STAGING"

printf 'App: %s\nZip: %s\nBuild log: %s\n' \
  "$OUTPUT_ROOT/$APP_NAME" "$OUTPUT_ROOT/少女心愿运营.zip" "$OUTPUT_ROOT/build.log"
