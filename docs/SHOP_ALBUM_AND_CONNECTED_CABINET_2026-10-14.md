# 店铺时光册与收纳柜连续性（2026-10-14）

后续用户进一步要求横向层板和灯条也固定、仅物品滑动，并优化年份空列及增加店铺内搜索。当前实现与最新验收见 [固定柜体与店铺搜索](STATIC_CABINET_AND_SHOP_SEARCH_2026-10-14.md)；本记录保留前一轮结果。

## 最终行为

时光馆首屏由「店家上新」更名为「店铺时光册」。店铺页左侧独立滚动的年份栏包含全部年份、由新到旧的实际年份，以及有数据时的未标年份。顶部横向栏改为全部与所选年份下的系列名称；选年份会清除原系列选择并将系列栏回到开头。系列按稳定 ID 筛选，同名系列不会串选。目录刷新时，已消失的年份或系列自动回到可用选择。

在售与已结束的系列均可按年份翻阅；已归档系列和其他店铺的系列仍由原数据层排除。下方保留系列卡，点击进入原有系列选购页；商品、颜色、套装、确认入橱、价格与鱼币流程沿用既有入口。没有新增生产示例数据。页面背景继续使用时光馆的主题壁纸，筛选控件和文字底板复用主题容器配色；选中态用主题色边框与加粗的可读文字。

柜冠和底座仍固定，仅中间层架上下滚动、随物品数量自动增加。原布局正常滚动时连贯，但两端原生弹性回弹会将层架拉开、露出主题背景；本次在滚动视口后增加完整固定空柜背板，在前方固定左右雕花侧柱。回弹露出的是柜内空间，两端与侧柱始终连成一体。滚动层不再淡出，避免背板透过层板形成叠影。背板不参与点击和辅助功能，层板仍使用原生滚动及吸附。

全部分类和自定义柜子复用上述修复。继续使用既有透明 PNG、深色打光、程序化缺图兜底、价格隐私设置和系统 TabView；空柜保持空白。布局尺寸与每层两件、至少四层的增长规则没有改变。

## 定向测试

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=FA7332BE-B29E-4879-A139-C68A24314DB1' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -jobs 5 -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/ShopCatalogAlbumTests \
  -only-testing:ItemManagerTests/ShopCatalogAlbumAppearanceTests \
  -only-testing:ItemManagerTests/WardrobeStorageCabinetFrameTests \
  -only-testing:ItemManagerTests/WardrobeStorageThemeTests \
  -resultBundlePath /private/tmp/pink-house-album-connected-cabinet-pass-20261014.xcresult \
  -quiet test
```

覆盖：年份与系列选择、同名 ID 隔离、刷新后的失效选择、历史销售系列可见性；真实 SwiftUI 深浅主题下的年份栏及系列筛选页面；各类层高与增长边界；鞋柜日间和包包柜夜间 2 / 24 件物品、末层完整可达、固定雕花与柜脚；预设主题配色、壁纸透出与文字可读性。

最终结果：**12/12 PASS，0 失败 / 0 跳过，xcodebuild 返回 0**。测试执行 196.8 秒，整次构建与测试约 217 秒。机器摘要及九张像素不变的压缩渲染图保存在 `docs/design/wardrobe-storage/validation/connected-cabinet/`；`screenshots.json` 记录来源测试及像素哈希。

断层回归测试实际将原生 UIScrollView 拉到顶部 -72 pt、底部最大偏移 +72 pt，确认偏移确实到达。固定侧柱像素差不超过 3 个 RGBA 色阶（GPU 合成存在舍入），并扫描柜内区域，确认没有露出特意设置的青色房间背景。截图中的收藏名称、价格和无图片图标仅存在于内存测试窗口，不写入用户衣橱。前一轮复测中，截图前的异步等待让原生吸附先把强拉位置复位，11/12 通过；已将夹具改为同步布局、立即截图，并在截图前后均断言偏移仍在强拉位置，生产滚动行为没有为测试修改。

## 构建与实际页面

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=FA7332BE-B29E-4879-A139-C68A24314DB1 \
MAX_JOBS=5 BUILD_TIMEOUT_SECONDS=600 \
LOG=/private/tmp/pink-house-album-connected-cabinet-release-ui-build-20261014.log \
tools/xcode/stable_cli_build_and_run.sh
```

验证设备为 iPhone 18 Pro / iOS 27.0，Xcode 27.0 / 27A266a，bundle `bugod2.ItemManager`。实际页面验收按正式模拟器流程在测试后重新 build / install / terminate / launch，随后使用 Device Hub Computer Use 读取新进程。

最终构建 23 秒，build / install / launch 均返回 0；terminate 返回 3（测试结束后没有旧进程），随后成功启动 PID 61875。实际读取到「店铺时光册」标题、夜鸢店铺左侧全部年份 / 2026 与顶部真实系列名；点击 2026 后选择「天鹅之歌」，下方只显示对应 36 件商品的系列卡，点击可进入原有点菜式选购页。只打开后关闭，没有勾选或确认入橱。

实际鞋柜为 0 双，完整柜冠、连续侧柱、层架、底座和柜脚在系统底栏上方显示，没有示例物品。实际截图为同目录下 `album-shop-simulator.png`、`album-selected-series-simulator.png`、`shoes-empty-simulator.png`。本次原生页面核对没有执行拖动；强拉回弹与多物品末层以测试窗口实际 UIScrollView 偏移和 GPU 截图为证据。

边界：测试夹具支持深浅主题、多物品与强拉回弹，未证明真机帧率、所有图片抠图质量或完整入橱业务回归；没有覆盖 iPad、横屏和大字号实际页面。既有 MainActor / Sendable、扩展与主 app 的 CFBundleVersion 不一致及资源去重脚本提示仍在。本次提交只包含浏览布局、柜体连接修复及其测试、记录；工作区既有预约批次和运营修改不纳入提交。
