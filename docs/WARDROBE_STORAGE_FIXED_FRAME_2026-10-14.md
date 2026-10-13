# 收纳柜固定柜顶与柜底（2026-10-14）

## 最终行为

柜体分成三段：固定柜冠、独立滚动的中间层架、固定底座。库存增加只追加中间层架，每层两条收藏；柜顶、蝴蝶结、抽屉与柜脚的位置和原始比例不随库存数量或滚动改变。全部分类和自定义柜子共用该布局。

`WardrobeStorageRoomView` 将现有 GeometryReader 的可用高度传入柜体。`WardrobeStorageCabinetLayout` 根据房间宽高计算三段尺寸，仅层板置于 LazyVStack / ScrollView。中段严格裁切，保留原有系统吸附、顶部初始锚点和减少动态效果设置。至少四层；较高、较窄的页面补充空层直至覆盖整个中段，不产生侧柱中断或柜底上方的空白断层。

空间较小、横向尺寸较宽时，柜体等比缩小，为两端和至少一格完整展示空间留出位置。上下留白沿用柜体自身的 12 / 18 pt，不增加固定底栏避让；页面高度仍由系统安全区和原生 TabView 决定。底座素材缺失时提供程序化兜底。

没有生成或修改位图素材；继续使用统一主题配色、主题背景、暗黑模式照明与价格隐私设置。空柜不加入示例物件，不修改收藏、分类、照片、数量、存档或时光馆入橱流程。

## 构建

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=600 \
LOG=/private/tmp/pink-house-storage-fixed-frame-build-20261014.log \
tools/xcode/stable_cli_build_and_run.sh
```

Xcode 27.0 / 27A266a，scheme ItemManager，iPhone 18 Pro / iOS 27.0，bundle `bugod2.ItemManager`。构建 71 秒，build / install / launch 返回 0；terminate 返回 3（没有旧进程），随后成功启动新进程。

## 定向验证

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -jobs 5 -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/WardrobeStorageCabinetFrameTests \
  -resultBundlePath /private/tmp/pink-house-storage-fixed-frame-layout-20261014.xcresult \
  -quiet test
```

布局验证覆盖所有层高：跨过填充层容量时只增一层，奇数物品不遗漏；较高视口没有断层；紧凑视口保留柜冠、底座的原始比例及一层完整展示空间。真实 SwiftUI GPU 渲染在独立测试窗口中分别对比鞋柜日间、包包柜夜间的 2 件 / 24 件物品，以及滚动到末层前后的固定柜顶雕花区、柜底雕花和柜脚像素；中段应发生变化，滚动位置确认最后一层可完整到达。测试夹具只在内存和临时窗口中存在，不写入 SwiftData 或用户收藏。

同源代码的统一主题验证命令另加 `-only-testing:ItemManagerTests/WardrobeStorageThemeTests`，结果位于 `/private/tmp/pink-house-storage-fixed-frame-pass-20261014.xcresult`；该组 4/4 通过，覆盖预设配色、背景图透出、卡片风格和可读性。后续仅修正布局测试夹具，没有改动生产代码或主题实现。

首两次测试编译因新夹具缺少 Combine 导入、尝试写入只读的系统 Reduce Motion 环境值而中止；已修正夹具。前两次运行均 6/7 通过，唯一失败为透明轮廓外的投影会随中段物品滚动变化。像素检查确认变化集中在柜冠 / 底座邻近滚动区的投影（雕花与柜脚保持不变），断言改为比较固定雕花和柜脚区域、排除相邻投影，仍核对中段滚动末端。

最终 `WardrobeStorageCabinetFrameTests`：**3/3 PASS，0 失败 / 0 跳过**。机器摘要 `docs/design/wardrobe-storage/validation/fixed-frame/layout-test-summary.json`；六张最终 GPU 渲染图同目录，命名为 `shoes-light-*` 与 `bags-dark-*`，已读取像素预览，末层可见收藏 23 / 24 及价格，柜冠和柜脚完整。

## 实际页面核对

测试结束后再次对同一目标运行上述构建脚本（`LOG=/private/tmp/pink-house-storage-fixed-frame-ui-build-20261014.log`），19 秒，build / install / launch 均返回 0；terminate 返回 3（测试结束后无旧进程），启动 PID 42302。随后通过 Device Hub Computer Use 从首页「更多 → 我的收纳柜」进入鞋柜并切换包包柜。

- 两种层高下，顶部雕花 / 蝴蝶结与控件分开，抽屉 / 柜脚在初始位置即完整可见。
- 底部没有被系统 TabView 遮挡，没有恢复自绘底栏。
- 页面实际库存为零，层架保持空白；添加柜子入口和分类切换仍可用。
- 实际截图：`shoes-empty-initial-simulator.png`、`bags-empty-initial-simulator.png`，均在 `validation/fixed-frame/`。

边界：实际页面核对仅覆盖 iPhone 18 Pro / iOS 27.0 的空柜初始布局与分类切换；Device Hub 多次拖动返回 AXError.cannotComplete，未将拖动尝试计为 UI 滚动验收。多物品与滚动末端通过原生 SwiftUI GPU 测试窗口和 UIScrollView 的实际偏移验证。夜间照明在该测试窗口验证；模拟器系统外观试切 dark 后，当前 app 实际画面仍为日间，因此不计作夜间真实页面验收；系统外观已恢复原来的 light。紧凑 / 较高空间只做布局计算验证，未覆盖实际 iPad、横屏、大字号、真机帧率或完整数据回归。

既有 MainActor / Sendable、扩展 CFBundleVersion 3 与主 app 1 不一致、资源去重脚本警告仍在；本轮没有修改这些无关项。`git diff --check` 通过。
