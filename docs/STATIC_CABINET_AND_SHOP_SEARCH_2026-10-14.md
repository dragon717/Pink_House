# 固定柜体、物品换层与店铺搜索（2026-10-14）

## 当前行为

按照用户后续截图要求，收纳柜的柜冠、底座、侧柱、背板、横向层板和灯条全部固定，只有柜内物品、名称价格牌、状态标记与物品自身投影上下滑动。前一版仍将完整层板放进滚动区，本次将其拆成家具与物品两部分：固定背景只渲染空柜层架，原生滚动区仅渲染 `WardrobeStorageShelfContents`，不再叠加第二份活动柜体或展示垫。

可见中段按房间高度放入整数个完整格子，每格高度均分中段；物品行使用相同高度。因此原生吸附停稳和滚动到末尾时，物品仍对齐固定层板，不因末尾残余高度而错层。柜冠与底座继续保持原始比例，新增物品只追加逻辑物品行，每行两件，至少四行。全部分类及自定义柜子共用布局；空柜没有示例物品。

店铺名下方增加全宽「搜索系列或商品」输入框，查询当前年份下的系列名、商品名、款式名和商品类型。搜索忽略大小写、全半角及字母重音，支持空格分词；已归档商品和其他店铺数据不会命中。输入新关键词时清除原系列选择，避免只在上一系列内搜索。清除后恢复当前年份的全部系列，查询不修改目录或入橱记录。结果仍为匹配系列卡，点击进入原有选购页。

年份选项不超过三个时，左侧改成紧凑年份选择器，与系列栏并排，下方系列卡使用全宽，消除单一年份造成的长空白列。年份较多时，保留 68 pt 窄侧栏，补上年份标题、每个年份的系列数及主题色选中标记；侧栏底板按实际选项数收短。背景、卡片和文字仍使用统一主题配色及已启用壁纸，系统 TabView 保持原样。

用户随后圈出的系列名称 / 商品数量小底框已移除，整张主题卡片保留。天空音乐会、天鹅入梦的卡面素材在夜间仍为浅色，文字使用现有自适应调色板按实际卡面亮度生成，避免套用深色页面的浅色文字后无法阅读；默认卡面继续遵循统一配色。

实际页面复核又发现旧店家列表对白色卡面用了浅色文字、浅色系统下深蓝主题背景的店铺标题 / 结果数量用了黑色文字。本次将店家卡与系列卡的卡面配色合并为 `ShopCatalogAppearance.cardPalette`，页面裸文字另按页面背景取色，并为导航栏指定与实际背景一致的明暗模式。输入框提示文字显式使用相邻表面的次要文字色。皮肤已启用时，页面文字按皮肤壁纸的日夜模式处理，不改变素材、皮肤 slot 或持久化 key。

衣橱首页右侧原先只有透明手势区，本次增加带柜门图标、左向箭头与「收纳柜 / 左滑打开」文字的固定拉手。点击与左滑调用同一 `openStorageDrawer`，拉手和原边缘手势都可打开；垂直滚动不触发，编辑 / 搜索 / 抽屉打开时隐藏，VoiceOver 支持直接点击。拉手颜色复用收纳柜的统一主题及对比度处理，不改变首页列表布局或底部系统导航。

## 定向测试命令

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=826F5E71-D2BC-4E76-A8C5-4251C526A5D4' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -jobs 2 -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:ItemManagerTests/ShopCatalogAlbumTests \
  -only-testing:ItemManagerTests/ShopCatalogAlbumAppearanceTests \
  -only-testing:ItemManagerTests/WardrobeStorageCabinetFrameTests \
  -only-testing:ItemManagerTests/WardrobeStorageThemeTests \
  -resultBundlePath /private/tmp/pink-house-static-cabinet-search-verified-20261014.xcresult \
  -quiet test
```

验证范围：年份和系列选择、查询字段与数据隔离、搜索清空、真实 SwiftUI 的紧凑年份 / 多年份侧栏 / 深色查询结果与空结果；整数格布局及逻辑行增长；鞋柜日间、包包柜夜间 2 / 24 件物品，末行完整可达、滑动中途、上下两端强拉回弹；共享主题与背景回归。固定格子中间的无物品窄带逐像素比较，覆盖所有横向层板与灯条，而非只检查两侧立柱；物品区域必须确实改变。

首轮测试在模拟器安装 app 阶段停滞，尚未进入用例；已取消该轮（退出 75），仅对同一测试模拟器执行 shutdown / boot，bootstatus 12 秒完成，未清除设备数据。同一设备重跑与单独安装仍停滞；重启模拟器控制服务后保留原设备数据，额外创建了 `Codex Static Cabinet QA`（79741285-FF46-4B0E-A3AB-BAA1D415E5CF），该设备首次启动仍停在系统数据初始化。最终切换至已安装的 iPhone 17 Pro / iOS 26.3.1（826F5E71-D2BC-4E76-A8C5-4251C526A5D4）进行实际用例。

测试使用隔离目录及内存物品、临时窗口，查询与截图不插入用户收藏；测试主题设置恢复。实际页面检查另按正式模拟器流程重新 build / install / terminate / launch。

## 模拟器构建命令

```bash
XCODE_APP=/Applications/Xcode.app \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
SIM_ID=826F5E71-D2BC-4E76-A8C5-4251C526A5D4 \
MAX_JOBS=2 BUILD_TIMEOUT_SECONDS=600 \
DERIVED_DATA=/Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
LOG=/private/tmp/pink-house-static-cabinet-search-ui-readable-final-build-20261014.log \
tools/xcode/stable_cli_build_and_run.sh
```

目标为 Xcode 27.0 / 27A266a，ItemManager，iPhone 17 Pro / iOS 26.3.1，bundle `bugod2.ItemManager`。本次只提交柜体与店铺浏览修改、对应测试及验收记录；不纳入工作区既有预约批次、运营端和模型修改。

边界：未覆盖真机帧率、iPad / 横屏 / 大字号实际页面和完整购买入橱回归。既有 MainActor / Sendable、扩展与主 app 的版本号不一致及资源去重脚本提示不属于本次修改。

## 不依赖模拟器的验证

在补充系列文字和首页拉手前，已额外执行通用 Simulator 编译（Xcode 27.0，arm64，退出 0）：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 2 \
  ONLY_ACTIVE_ARCH=YES ARCHS=arm64 -quiet build
```

还直接编译生产 `ShopCatalogAlbumSelection`、共享 Catalog 模型、生产布局计算及分类层高元数据，复用既有测试中四组选择 / 搜索、两组布局用例及其断言，在 macOS 命令行执行：**6 组、177 条同源断言通过，退出 0**。备用执行器去除 UI 测试宿主和 XCTest 注入，仅用 Swift precondition 执行原断言；没有复制或改写被测搜索 / 布局算法。该结果不覆盖 SwiftUI 绘制、触摸滑动或系统键盘。机器摘要在 `docs/design/wardrobe-storage/validation/static-furniture/host-assertion-summary.json`，包含来源 SHA-256。

## 旧系统兼容问题

iOS 26.3.1 首轮 13 项测试中，9 项通过；店铺画面及三项主题测试均在临时主题对象释放时 SIGABRT，日志为指针释放错误。崩溃栈依次为 `ThemeManager.__deallocating_deinit`、`swift_task_deinitOnExecutorMainActorBackDeploy`、`swift::TaskLocal::StopLookupScope::~StopLookupScope()`。柜体实际 GPU 渲染与层板 / 灯条静止断言已通过，店铺四种画面也完成截图，但没有把崩溃用例计为通过。

主题对象没有 actor 收尾业务，按仓库 `ShopCatalogStore`、`OperationFeedbackCenter` 的既有做法补上 `nonisolated deinit {}`，避免调用该旧系统回部署析构路径；没有改主题设置、持久化 key 或皮肤 slot。随后重跑完整定向测试。

**完整重跑：13 项通过、0 失败、退出 0**。已归档 `simulator-test-summary.json` 和 8 张固定柜体 GPU 截图，PNG 压缩前后逐字节核对像素相同；滑动中途、首尾及强拉回弹均未改变横向层板 / 灯条与两端像素。此轮在最后移除系列文字底框、添加首页拉手之前执行；柜体、搜索算法与兼容修复此后未变，最后的卡片显示另行定向复验。

## 首页交互验收

Xcode 27.0 对 iPhone 17 Pro / iOS 26.3.1 重新构建成功（退出 0），安装成功，终止步骤报告无旧进程，随后启动新进程成功。Device Hub 显示同一设备，Computer Use 观察到右侧柜门图标、「收纳柜」「左滑打开」和 `storage.open.handle` 的辅助功能入口；坐标单击打开抽屉，关闭后从拉手向左拖动再次打开，抽屉显示衣柜、鞋柜、包包柜、配饰柜和添加柜子。相关页面截图为 `home-storage-handle.png`、`home-storage-drawer.png`。后续店铺文字修正不改首页入口源代码。

定向显示测试使用隔离目录，再覆盖紧凑年份、多年份、深色查询 / 空结果、两套主题各自浅色 / 深色及浅色系统配深色背景。所有标题和数量直接绘制在整体卡面，截图中的缺失封面占位仅来自测试目录，不向用户衣橱插入示例物品。

最终显示复验为上述定向命令只保留 `-only-testing:ItemManagerTests/ShopCatalogAlbumAppearanceTests`，结果包改为 `/private/tmp/pink-house-album-readable-final-20261014.xcresult`：**1 个显示用例通过、9 种页面完成 GPU 截图、0 失败、退出 0**。机器摘要及当前源文件 SHA-256 为 `album-final-test-summary.json`；此前 13 项中的其他搜索 / 柜体 / 主题源代码均保持不变。

最后文字修正后再次执行上方正式 build / install / terminate / launch 命令：构建 31 秒、退出 0，安装 0，终止报告无旧进程（3），启动 0，新 PID 12411。Computer Use 在同一 iPhone 17 Pro 观察到店家卡的深色文字、店铺深色背景上的浅色标题与数量，以及没有文字小底框的真实系列卡。输入「天鹅」后显示「找到 1 个系列」和「天鹅之歌 / 36 件商品」，点击系统搜索键收起键盘，清除后恢复「共 6 个系列」。真实页面截图为 `shop-list-readable.png`、`shop-album-plain-text.png`、`shop-album-search-live.png`。

本次显示复验曾有一轮测试编译因测试夹具将 slot 数组直接传给 Set 参数而退出 65，修正夹具类型后重跑通过；未修改生产 slot。Computer Use 设置查询字段时返回 AX cannotComplete，但随后截图与辅助功能树已确认查询文字和结果改变，验收以实际界面为准。
