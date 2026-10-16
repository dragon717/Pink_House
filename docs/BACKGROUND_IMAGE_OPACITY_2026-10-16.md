# 图片背景不透明度修复（2026-10-16）

降低图片不透明度时，原实现会露出 `ThemeManager.backgroundColor`，默认粉色因此混入图片。现在图片背景使用中性底层：浅色模式为白色，深色模式为黑色。滑块仍直接控制图片的 alpha，不改变原图或已保存的纯色背景。

`ThemeManager.backgroundBaseColor(for:)` 统一应用背景 `LiquidBackground` 和分享卡片 `ShareCardBackground` 的底色选择。纯色模式、图片缺失兜底、主题包背景限制仍保留原有规则；高斯模糊和深色遮罩沿用原实现。

## 构建与测试：PASS

- 工作区：`/Users/sangyu/develop/Pink_House`。
- Xcode：27.0（27A266a），`/Applications/Xcode.app`；SDK：iPhoneSimulator 27.0。
- Scheme：`ItemManager`；Bundle ID：`bugod2.ItemManager`。
- 目标：`Codex DIY Outfit QA`，iPhone 17 Pro，iOS 26.3.1（23D8133）。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/BackgroundImageOpacityTests \
  -resultBundlePath /private/tmp/pink-house-background-opacity-20261016/BackgroundImageOpacityTests.xcresult
```

命令退出 0，`TEST SUCCEEDED`，3 项测试通过、0 失败：

1. 应用背景：灰色原图在粉色、绿色主题底色下，分别以 0%、53%、100% 不透明度渲染；像素保持中性灰且亮度随透明度变化。覆盖深浅色模式，以及铺满、平铺两种图片尺寸。
2. 分享卡片：同样通过实际 SwiftUI 渲染后的 RGB 像素检查，验证不混入主题色。
3. 纯色模式及图片缺失：保留用户选定的纯色底色。

测试仅使用内存图片，结束后恢复主题偏好与主题包状态。构建存在既有 actor 隔离 warning（例如 `DraftReliabilitySignpost`），模拟器启动日志有未登录 iCloud 的提示，均未阻断测试。

- 日志：`/private/tmp/pink-house-background-opacity-20261016/xcodebuild-test.log`。
- 结果：`/private/tmp/pink-house-background-opacity-20261016/BackgroundImageOpacityTests.xcresult`。

## 验证边界

本次验证为模拟器内的 SwiftUI 离屏渲染及像素断言，未进行 Computer Use 手动拖动滑块验收。未覆盖真机、iPad、其他系统版本、用户截图里的原始背景素材，以及高斯模糊开启后的视觉效果。
