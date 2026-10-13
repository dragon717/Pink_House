# 收纳柜暗黑模式与分层照明

## 本轮实现

系统深浅模式决定收纳柜外观，不修改用户保存的主题色。抽屉、分类栏、标题、搜索、筛选、列表卡片、名称/价格牌、自定义柜子图标均使用收纳模块的语义配色。夜间背景为灰黑紫，主文字为柔白，次要文字为灰粉；强调色从现有主题取得，必要时调整亮度以保证可读性。背景与文字按层设计，不进行全屏颜色反转。

`WardrobeStoragePalette` 的背景均为不透明颜色，避免自定义壁纸改变小字号的对比度。主文字、次要文字、价格/选中强调文字在所有模块背景上至少达到 7:1；系统「增强对比度」下目标为 9:1。名牌不经过灯光 shader。原生导航栏、表单和系统 TabView 保留系统深浅模式行为。

柜体继续复用原有透明 PNG。`WardrobeStorageLighting.metal` 通过 SwiftUI `colorEffect` 实时调光：每层背板、左右侧壁、水平层面使用不同的粗略法线与空间位置，计算上沿固定灯条的方向和距离衰减；前侧立柱与雕花边沿单独保留更亮的环境光。灯条和暖色光晕限定在柜体凹槽内，层面接缝保留遮蔽。顶冠完整位于滚动视口之外，柜体投影落在后方的 UI 平面上。

成功抠出的物品在立体柜中接受轻微上亮下暗的暖光，并增加边缘亮光与接触阴影。列表保留中性照片显示。未成功抠出的原始照片不增加轮廓亮光，以免整个矩形照片发光。所有照明均为展示效果，不写入原始照片、抠图文件、`Clothing.imagePaths` 或业务模型。包包、配饰和自定义柜子共用照明组件。

灯光静态，无持续计时器或循环动画；图片处理沿用后台串行抠图与有界缓存，柜内层架使用 LazyVStack。日间直接绕过光照 shader。缺少柜体图片时仍使用程序绘制兜底。空柜子没有示例物品。

## 技术边界

这是 2.5D 光照：柜内平面有解析法线，物品使用位置照明和透明轮廓效果。现有 PNG 的雕花起伏与照片中的真实材质无法凭单张颜色图精确恢复；没有声明已实现物理准确的浮雕法线、材质反射或镜面倒影。后续需要更精细的雕花受光时，可追加对齐的法线/粗糙度贴图。

SwiftUI shader 自 iOS 17 起可用，本工程最低版本为 iOS 17.4。shader 只施加于 SwiftUI 图片/绘制层，不包含文字、ProgressView 或 UIKit 承载控件。

## 验证

`WardrobeStorageAppearanceTests` 检查浅色/暗色/增强对比度，以及黑、白、粉、绿、灰、黄主题强调色在所有文本背景上的对比度，并检查非法颜色值。视觉测试临时创建自己的图片文件，在 UIWindow 中渲染真实层架组件，覆盖白鞋、黑鞋、包、配饰、空层架与价格显隐；不插入 SwiftData 或用户自定义柜子设置，结束时清理自己的临时原图。

提交范围从 Git index 导出到 `/private/tmp/pink-house-storage-staged-20261013/` 后独立构建和测试，避免未提交的团次/运营改动成为隐含依赖。构建、测试与实际模拟器验收结果如下。

## 官方依据

- [Apple Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)：可读性与自适应颜色。
- [SwiftUI colorEffect](https://developer.apple.com/documentation/swiftui/view/coloreffect(_:isenabled:))：运行时颜色 shader。
- [WCAG 对比度](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html)：普通文字至少 4.5:1；本模块小文字采用更高目标。

### 2026-10-13 验收记录

环境：Xcode 27.0（27A266a），scheme `ItemManager`，iPhone 18 Pro / iOS 27.0，UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`，bundle `bugod2.ItemManager`。

1. 提交内容独立回归：PASS，73/73，0 失败、0 跳过。测试类为 `WardrobeStorageAppearanceTests`、`WardrobeStorageCutoutTests`、`WardrobeStorageInventoryTests`、`WardrobeStorageSettingsTests`、`ShopCatalogWardrobeImageImportTests`、`ShopCatalogWardrobeEntryTests`。结果：`/private/tmp/pink-house-storage-night-staged-3.xcresult`，机器摘要 `docs/design/wardrobe-storage/validation/dark-mode-test-summary.json`。
2. 补齐自定义香水圆台的夜间照明后，相关回归 PASS，12/12：Appearance + Settings；结果 `/private/tmp/pink-house-storage-night-final.xcresult`，摘要 `dark-mode-final-test-summary.json`。
3. 视觉检查发现默认搜索占位文字偏淡，改为显式语义次要文字颜色，并同步柜子名称提示、物品搜索提示。最终重新构建 PASS，218 秒；install PASS，launch PASS（PID 5149）。terminate 返回 3，明确为「没有旧进程可终止」，随后已启动新进程。
4. Computer Use / Device Hub：观察了暗色抽屉、完整鞋柜、系统实时切回浅色、包包柜滚动、暗色列表搜索与筛选、自定义柜子表单。柜顶保持完整，包包柜滚动可显示柜脚，灯条跟随层架，名称/价格牌的灯光与文字分层正确。正常库存为空，没有示例物品；表单验收只打开后取消，没有创建用户柜子。最终恢复模拟器原来的浅色设置。

测试命令（`TEST_CLASS` 依次使用上面六个类；本轮实际命令同时传入六个 `-only-testing`）：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /private/tmp/pink-house-storage-staged-20261013/ItemManager.xcodeproj \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 5 \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/WardrobeStorageAppearanceTests \
  -only-testing:ItemManagerTests/WardrobeStorageCutoutTests \
  -only-testing:ItemManagerTests/WardrobeStorageInventoryTests \
  -only-testing:ItemManagerTests/WardrobeStorageSettingsTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeImageImportTests \
  -only-testing:ItemManagerTests/ShopCatalogWardrobeEntryTests \
  -resultBundlePath /private/tmp/pink-house-storage-night-staged-3.xcresult -quiet test
```

最后构建、安装与重启使用仓库稳定入口，指向提交快照中的同一脚本：

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=600 \
LOG=/private/tmp/pink-house-storage-night-acceptance-build.log \
/private/tmp/pink-house-storage-staged-20261013/tools/xcode/stable_cli_build_and_run.sh
```

截图位于 `docs/design/wardrobe-storage/validation/`：

- `dark-mode-drawer.png`、`dark-mode-shoe-room.png`、`light-mode-shoe-room.png`
- `dark-mode-bag-room-scrolled.png`、`dark-mode-list.png`、`dark-mode-cabinet-editor.png`
- `dark-shelves-price-visible.png` / `dark-shelves-price-hidden.png`、对应的 `light-*`：真实 SwiftUI/GPU 组件渲染，用测试内存对象检查白鞋、黑鞋、包、配饰与价格隐私；不作为正式柜内示例。

构建环境修复：首次发现缺少 Metal Toolchain，已通过官方 `xcodebuild -downloadComponent MetalToolchain` 安装 27A266a。后续全量构建超过默认 180 秒，因此本次最终验收时限调整为 600 秒。提交快照读取与工作区相同的、未被 Git 跟踪的 Package.resolved（generative-ai-swift revision `44a40daf54bcb8db2695f4af618107e72c472b36`）并复用本地依赖缓存；不改依赖版本。

验证边界：没有真机、iOS 17.4 运行时或 Instruments 帧率/能耗验收；不宣称已经测得真机性能。既有 MainActor / Sendable 警告、extension 与 parent 的 CFBundleVersion 不一致、资源去重脚本每次运行提示及 Xcode `exit code 0 but produced no further output` 诊断仍存在，本轮不修改这些无关代码。Device Hub 偶发 AXError，已重新读取并以实际截图确认结果。

后续用户要求统一主题配色与背景：本页的独立深色背景描述已由 [收纳柜接入统一主题](WARDROBE_STORAGE_UNIFIED_THEME_2026-10-13.md) 取代，柜体灯光继续沿用。
