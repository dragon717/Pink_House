#!/bin/bash
# 运营上传 / 公共库字段配置 —— 本轮改动的回归测试入口。
# 用法：bash scripts/run_ops_upload_tests.sh
#       LOG=/tmp/other.log bash scripts/run_ops_upload_tests.sh   # 换日志路径
# 注意：xcodebuild 输出写进 $LOG，脚本自身只往 stdout 打结论；
#       要另存一份请在调用后再拷贝 $LOG，别直接重定向脚本 stdout。
set -u
cd /Users/sangyu/develop/Pink_House

UDID=FA7332BE-B29E-4879-A139-C68A24314DB1
LOG="${LOG:-/tmp/xcb_upload_test.log}"

COMMON=(
  -IDEPackageSupportDisableManifestSandbox=YES
  -skipPackagePluginValidation
  -skipMacroValidation
  ENABLE_USER_SCRIPT_SANDBOXING=NO
  "OTHER_SWIFT_FLAGS=\$(inherited) -Xfrontend -disable-sandbox"
)

CLASSES=(
  ShopCatalogAssetMediaKeyTests
  ShopCatalogGzipTests
  ShopCatalogOpsMediaStagingTests
  ShopCatalogUploadJobTests
  ShopCatalogOpsPublishScopeTests
  ShopCatalogOpsPublisherTests
  ShopCatalogMediaRetryTests
)
ARGS=()
for c in "${CLASSES[@]}"; do
  ARGS+=("-only-testing:ItemManagerTests/$c")
done

xcrun simctl boot "$UDID" 2>/dev/null || true

xcodebuild -scheme ItemManager \
  -destination "platform=iOS Simulator,id=$UDID" \
  SYMROOT="$PWD/build/symUpload" \
  OBJROOT="$PWD/build/objUpload" \
  "${ARGS[@]}" "${COMMON[@]}" \
  test > "$LOG" 2>&1
echo "退出码=$?"
grep -E "\*\* TEST (SUCCEEDED|FAILED) \*\*" "$LOG"
grep -E "Executed [0-9]+ tests" "$LOG" | tail -1
echo "--- 实际执行的类 ---"
grep -oE "Test Case '-\[ItemManagerTests\.[A-Za-z0-9]+ " "$LOG" | sort -u
