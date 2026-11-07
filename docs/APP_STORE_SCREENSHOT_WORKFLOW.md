# App Store 商品图工作流

## 4.4 商店图

本版从模拟器运行的 App 采集衣橱、心愿尾款、衣橱统计。四件衣物的商品照片是本次生成的展示素材。两件已付定金，两件已购买。衣物、余额和统计由 App 正常读取并计算。默认空衣橱另存验收图。

| 设备 | 成图像素（宽 × 高） | 苹果外框 |
|---|---|---|
| iPhone 12 | 1170 × 2532 | White |
| iPhone 17 Pro | 1206 × 2622 | Silver |
| iPhone 17 Pro Max | 1320 × 2868 | Silver |
| iPad Pro 13 英寸 M5 | 2064 × 2752 | Silver |
| iPhone Duo 外屏 | 1398 × 2034 | Star White，Outer Closed |
| iPhone Duo 内屏 | 2853 × 2007（本版横图），2007 × 2853（竖版模板） | Star White，Inner Open，按方向选用 |

Apple 要求每个提交的尺寸提供 1–10 张 JPEG 或 PNG，成图不能有透明通道。衣橱、尾款和统计按这个顺序展示。尺寸指整张商店图，包含背景、文案和设备框。苹果列出的必备组为灵动岛中屏 iPhone，以及支持 iPad 的 App 的 13 英寸 iPad。规格表另列大屏要求，未提供灵动岛大屏时须提供 Face ID 大屏。本版使用 17 Pro Max 覆盖大屏，另为 iPhone 12 单独制作。在 4.4 版本的「App 预览和截屏」中选择「iPhone Duo」即可上传。两种原生分辨率使用同一栏位，每种语言合计最多 10 张。使用 iOS 27.1 及之后 SDK 的应用自 2027 年 4 月起须提供。使用者已同意苹果营销素材使用条款。[截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) · [苹果产品外框](https://developer.apple.com/design/resources/#product-bezels) · [Duo 适配](https://developer.apple.com/iphone-duo/prepare/)

### 复现 Duo 采集环境

本机使用独立安装的 Xcode 27.1 运行 iPhone Duo 模拟器。先在苹果组件目录确认运行时的名称和构建号。27.1 同时有候选版和正式版，指定正式构建号可以明确选择。首次安装时使用下列命令。[苹果组件目录](https://devimages-cdn.apple.com/downloads/xcode/simulators/index2.dvtdownloadableindex)

```sh
DEVELOPER_DIR="$HOME/Applications/Xcode-27.1.app/Contents/Developer" \
  xcodebuild -downloadPlatform iOS -buildVersion 24A94425 -architectureVariant arm64
```

在 Device Hub 选择专用 Duo，分别展开和合上。用 `xcrun simctl io "$DEVICE_ID" enumerate` 核对当前两块内置屏的名称、分辨率和方向，导出实际显示 App 的那一块。放大检查照片、文字和导航后再合成。后台的「设备预览 → 产品页面」可以复核商品页顺序。[Apple Duo 模拟器演示](https://developer.apple.com/videos/play/tech-talks/111461/)

4.4 的 Duo 图依次展示外屏衣橱、展开后的衣橱列表与所选衣物详情、外屏衣物详情。展开图来自实际 `NavigationSplitView`，保留系统竖向导航。iPad 衣橱和尾款截图先选择示例衣物，让详情列显示实际内容；统计页展示衣橱与统计双栏。上一轮的每日配色附图保留为历史输入，不再放入本轮上传目录。

```bash
root=output/app-store-4.4
uv run --with pillow python tools/app_store/render_gallery.py "$root" duo-outer --scenes wardrobe detail
uv run --with pillow python tools/app_store/render_gallery.py "$root" duo-inner-landscape --scenes wardrobe
```

### 采集和合成

1. 新建名称以 `Pink House Store ` 开头的专用模拟器。编译、安装当前代码。首次采集空状态后再导入示例数据。首次录制须处理定位权限并关闭首次日签。本轮只展示离线衣橱，专用模拟器可用 `xcrun simctl privacy "$DEVICE_ID" revoke location bugod2.ItemManager` 预设不允许定位，避免系统弹窗遮住截图；此设置不代表定位功能验收。冷启动图片可能晚于页面按钮出现，固定等待时间不能替代逐张视觉检查。
2. 使用本次发布目录 `output/app-store-4.4`。示例数据库及四张图片保存在 `demo/`。重新生成数据库时，先在独立模拟器的 App 文档中建立 `StoreScreenshotExport/`，运行 `StoreScreenshotFixtureTests/testExportWardrobeFixture`，退出进程后用 SQLite backup 导出完整快照。仅在专用空模拟器放置该数据库至 App Group 的 `Library/Application Support/default.store`。图片放入 App 文档的 `Images/`。
3. 在同一设备执行以下测试。采集前核对同一设备的时钟、电量和屏幕方向。导出后按附件名称将原图放入 `raw/<语言>/<设备>/wardrobe.png`、`payments.png`、`stats.png`。逐张确认服装照片、目标页、文案和转场均正常。
4. `frames/` 存放与表格设备对应的苹果原始透明 PNG。合成器自动定位开孔，检查设备分辨率，输出不含透明通道的 sRGB PNG。三个页面的简中、繁中和英文案在 `tools/app_store/render_gallery.py`。Duo 原生画面齐备后按同样步骤合成。

```bash
export DEVELOPER_DIR="$HOME/Applications/Xcode-27.1.app/Contents/Developer"
xcodebuild -scheme ItemManager -destination "platform=iOS Simulator,id=$DEVICE_ID" -jobs 2 build
xcodebuild -scheme ItemManager -destination "platform=iOS Simulator,id=$DEVICE_ID" -jobs 2 \
  -parallel-testing-enabled NO -only-testing:ItemManagerUITests/StoreScreenshotUITests/testCaptureCurrentFeatures \
  -resultBundlePath "$RESULT_BUNDLE" test
xcrun xcresulttool export attachments --path "$RESULT_BUNDLE" --output-path "$ATTACHMENTS"
uv run --with pillow python tools/app_store/import_test_screenshots.py output/app-store-4.4 "$DEVICE_MODEL" "$ATTACHMENTS"
uv run --with pillow python tools/app_store/render_gallery.py output/app-store-4.4 iphone12 iphone17pro iphone17promax ipad13
uv run --with pillow python tools/app_store/package_gallery.py output/app-store-4.4
uv run --with pillow python tools/app_store/verify_gallery.py output/app-store-4.4/少女心愿-4.4-商店截图.zip
```

用 `stage_uploads.py <发布目录> <本轮独立上传目录> --revision 271` 生成带版本后缀的文件与 SHA-256 清单。Duo 两种屏幕自动归入同一个 `duo/` 文件夹。将每个语言、设备文件夹中的三个 PNG 按文件序号上传。登录 App Store Connect，选择「少女心愿」的可编辑 iOS 版本和对应语言，打开「在媒体管理器中查看所有尺寸」，切换 iPhone 或 iPad 及表内对应槽位。保存后重新打开该语言，复核三张缩略图、顺序和设备槽位。预览拼图用于选图；`templates/` 存放透明开孔的 Duo 工作模板；`proof/` 存放验收证据。[苹果上传指南](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)

## 旧商品图作业
> 状态：2026-05-25 梳理。本文只记录 `temp/商品图/` 的工具和生成作业归属，不要求本轮移动或删除目录。

## 当前目录性质

- `temp/商品图/appshot/` 是外部 `appshot-cli` 工具 checkout，包含 `.git`、`node_modules`、CI、skill、frames、fonts 等工具资产。它不是 Pink_House app runtime 依赖，也不应作为 app 构建、启动或 Swift 代码读取路径。
- `temp/商品图/appshot-job/` 是 Pink_House 商品图生成作业，主要放输入/输出目录配置、截图 captions、富文案 overlay 配置等发布物料生产上下文。它也不是 app runtime 依赖。
- 衣橱性能压测样例不再以 `temp/商品图/` 为默认输入。压测图片建议放到 `tools/perf-samples/wardrobe-images/`，或由执行者通过 `--image-dir <absolute-path>` 显式传入。

## 后续迁移建议

| 当前路径 | 建议迁移位置 | 说明 |
|---|---|---|
| `temp/商品图/appshot/` | `tools/appshot/` 或全局安装 `appshot-cli` | 如果需要固定工具版本，可迁入 `tools/appshot/` 并在 README 记录安装和运行命令；如果只需要通用 CLI，优先记录全局安装方式，避免把 `node_modules` 长期留在仓库临时目录。 |
| `temp/商品图/appshot-job/` | `tools/appshot-job/` 或发布素材文档 | 如果作业配置需要可重复执行，迁到 `tools/appshot-job/`；如果只保留成品截图、尺寸、文案和验收记录，迁入发布素材文档即可。 |
| 最终商品截图 | 正式发布素材目录 | 保留可提交 App Store 的最终成品和必要源配置，避免只在 `temp/` 中保存唯一副本。 |

## 删除 temp 前检查

1. 确认 Swift / Xcode runtime 没有读取 `temp/商品图/`。
2. 确认性能压测命令改用 `tools/perf-samples/wardrobe-images/` 或显式 `--image-dir`。
3. 确认商品图工具的安装方式、作业配置和最终成品截图已有正式位置。
4. 确认 `appshot/` 内的外部 `.git`、`node_modules` 不再作为 `temp/` 保留理由。
