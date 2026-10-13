# 收纳柜接入统一主题

## 修改

收纳柜的正式配色从 `ThemeManager.getPaletteForContainer` 取得，支持魔法配色、预设和用户自定义文字/强调色，以及深浅模式。`CardBackgroundView` 的背景颜色计算抽为 `ThemeManager.cardSurfaceColor(for:)`；原卡片的绘制规则保持一致，收纳柜复用同一个来源。

删除柜内页面覆盖整屏的固定暗色色块。抽屉、柜内页面、柜子编辑与物品选择页都使用 `LiquidBackground(themeSkinWallpaperContext: .wardrobe)`，由现有组件处理纯色、用户图片、图片透明度、模糊和已启用的 ThemeSkin 壁纸。后方平面与列表背景复用 `CardBackgroundView`，遵循经典、色调、半透明和全透明设置。

图标填色、边框、分类、按钮、搜索、筛选、标题、名称和价格来自统一主题。小文字的局部底牌使用主题卡片颜色，必要时调整亮度，达到 7:1（增强对比度时 9:1）。中灰色背景本身无法提供 7:1，因此只调整这些局部阅读底牌；背景图片和外层卡片继续按主题设置绘制。`WardrobeStoragePalette.resolve` 只作没有主题环境的独立美术预览兜底，正式入口使用 `themed`。

柜体美术与暖色灯光保留，照明只作用于柜体和抠出的物品。没有新增主题开关、存档键或 ThemeSkin slot，也没有改动系统 TabView。

## 验证

Xcode 27.0（27A266a），scheme `ItemManager`，iPhone 18 Pro / iOS 27.0，UDID `FA7332BE-B29E-4879-A139-C68A24314DB1`，bundle `bugod2.ItemManager`。

- 构建、安装、启动：PASS；稳定构建入口耗时 293 秒。测试编译包含最后的格式整理。
- 主题与原暗色回归：8/8 PASS，0 失败、0 跳过。覆盖全部现有预设的深浅模式、统一卡片/文字来源、魔法配色的背景和强调色变化、中灰色主题与增强对比度，以及原有名牌价格显隐和光照渲染。
- 图片背景检查：在空的内存 SwiftData 容器中渲染完整收纳柜，使用蓝绿条纹测试图片。检查图片透过全透明卡片在深浅模式下可见，以像素采样防止固定背景色块遮挡回归。测试期间临时的主题设置恢复到原值；不插入用户库存或保存测试背景图。
- 对 `UIColor` 的 Float 颜色桥接使用 0.000001 数值容差；不以浮点转换尾差误判主题颜色不一致。

结果与真实 SwiftUI / UIKit / GPU 渲染图：`docs/design/wardrobe-storage/validation/unified-theme/`。蓝色主题选 `cinderella`，绿色主题选 `matcha`，按稳定主题 ID 取值；图片只是测试纹理，正式空柜仍没有示例物品。

构建命令：

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=600 \
LOG=/private/tmp/pink-house-storage-unified-theme-build.log \
tools/xcode/stable_cli_build_and_run.sh
```

测试命令：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 5 \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/WardrobeStorageThemeTests \
  -only-testing:ItemManagerTests/WardrobeStorageAppearanceTests \
  -resultBundlePath /private/tmp/pink-house-storage-unified-theme-final.xcresult -quiet test
```

最后按稳定主题 ID 的截图与像素复测使用 `WardrobeStorageThemeTests` 单类，4/4 PASS，0 失败、0 跳过；结果 `/private/tmp/pink-house-storage-unified-theme-ids.xcresult`。

范围与边界：没有真机或 Instruments 性能验收。构建时工作区保留其他未完成的团次/运营修改，提交仅包含本轮主题接入文件。既有并发、extension 版本号和 Xcode `exit code 0 but produced no further output` 警告不属于本轮修复。

最终从最新测试构建产物重新安装并启动同一模拟器（PID 20075）；terminate 返回 3 表示没有旧进程，install / launch PASS。Computer Use / Device Hub 确认首页原有主题设置恢复、分类抽屉与鞋柜可打开，名称、分类、空柜布局和系统 TabView 正常。截图 `validation/unified-theme/default-theme-simulator.png`；完整主题切换和图片背景覆盖由上面的内存容器渲染及像素检查验证。
