# 衣物尺码表 / 价格表预览首帧修复（2026-10-15）

## 问题与修复

衣物详情中，表图路径与弹窗显示开关原来由两个独立状态控制。弹窗的内容闭包可能先读取到空路径，进入纯黑兜底；查看器随后还会独立获取图片。

- 详情页的尺码表、价格信息表，以及编辑页共用的表图选择器，统一由 `ChartImagePreview` 驱动 `.sheet(item:)`。预览路径与点击时可用的图片一起传入。
- 首次布局直接把已有图片交给 `UIImageView`，异步读取原图期间继续显示这张图。原图补全不重置当前缩放。
- 尚无图片时显示加载指示，读取失败时显示“无法加载图片”；移除空路径时的纯黑内容分支。
- 表图选择器按路径刷新缩略图并忽略已取消的旧加载；通用缩放视图忽略切换路径后才返回的旧图片。

## 验证环境与命令

- 工作区：`/Users/sangyu/develop/Pink_House`
- Xcode：`/Applications/Xcode.app`，27.0（27A266a）。
- Scheme：`ItemManager`；SDK：iPhoneSimulator 27.0。
- 目标：`Codex DIY Outfit QA`，iPhone 17 Pro，iOS 26.3.1（23D8133）。
- UDID：`F64FFA05-1AA0-4C8F-9920-F18A772486CB`。
- Bundle ID：`bugod2.ItemManager`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project ItemManager.xcodeproj -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates -jobs 3 \
  -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/ChartImageViewerTests \
  -resultBundlePath /tmp/pink-house-chart-preview-20261015/ChartImageViewerTests-window.xcresult
```

## 结果

### 构建与回归：PASS

最终命令退出 0，`TEST SUCCEEDED`。`ChartImageViewerTests` 共 3 项通过、0 失败：

1. 原文件不存在时，预览第一次窗口布局已经持有传入的图片，且图像视图尺寸大于零；不等待异步读取或下一轮 run loop。
2. 从尺码表切换至价格表时显示新图，并将缩放恢复为 1。
3. 同一路径由首帧图替换为原图时更新图像，同时保留当前 3 倍缩放。

过程记录：首轮新增测试辅助函数缺少显式 `self`，修正后完成编译；第一次运行的离屏宿主未挂载窗口，无法取得 UIKit 图像视图。补齐真实窗口及同步布局后，三项断言全部通过。上述中间失败均保留在产物目录，最终结果以 `ChartImageViewerTests-window.xcresult` 为准。

已有测试辅助类型仍有 Swift 6 Sendable 兼容性 warning（例如 `ShopCatalogOpsUploadTests.FakeWriter`），没有阻断构建。

### 安装与启动：PASS

```bash
xcrun simctl install F64FFA05-1AA0-4C8F-9920-F18A772486CB \
  /tmp/pink-house-reservation-batches-ios/Build/Products/Debug-iphonesimulator/ItemManager.app
xcrun simctl terminate F64FFA05-1AA0-4C8F-9920-F18A772486CB bugod2.ItemManager
xcrun simctl launch F64FFA05-1AA0-4C8F-9920-F18A772486CB bugod2.ItemManager -AppleLanguages '(zh-Hans)'
```

为卡片验收，在这台独立 QA 模拟器内通过既有 DEBUG 性能种子入口生成一件衣物及两张图片；退出应用、备份其本地 store 后，仅将该测试衣物的两个表图字段指向这两张图片，再重新启动。未改生产或真机数据。

### 电脑控制点验：PASS（12:27–12:31 补验）

首次电脑控制因 Mac 锁屏中断；用户明确回复“已解锁，继续点验”后，继续使用上述同目标构建、安装并启动的新进程。期间未改应用源码。

Device Hub 当前选中 `Codex DIY Outfit QA`，衣物卡片为隔离测试数据“表图预览验收”。完成以下真实交互：

1. 打开衣物卡片，点尺码表，显示 P2 测试图；双击放大成功，关闭返回详情。
2. 点价格信息表，显示另一张 P1 测试图，关闭返回详情。
3. 再次打开尺码表，显示 P2，缩放恢复为初始大小；关闭后再次打开价格表，显示 P1。
4. 最后关闭表图，详情页正常显示，两个缩略图与各自的预览图片一致。

截图：

- [尺码表打开](/tmp/pink-house-chart-preview-20261015/size-chart-open.png)
- [价格表打开](/tmp/pink-house-chart-preview-20261015/price-chart-open.png)
- [关闭后详情页](/tmp/pink-house-chart-preview-20261015/detail-after-close.png)

### 转场录像检查：PASS（本轮采集帧）

```bash
xcrun simctl io F64FFA05-1AA0-4C8F-9920-F18A772486CB \
  recordVideo --codec=h264 --force \
  /tmp/pink-house-chart-preview-20261015/chart-transitions.mov
```

录像覆盖上述四次打开及关闭。用系统 AVFoundation 解码全部 515 帧，读取成功；检出四段预览打开过程，没有整屏空黑帧。

判定范围：每 12 像素采样一次，RGB 三通道均小于 18 视为黑色；同时满足“全屏黑色占比 > 85%”及“中央区域黑色占比 > 98%”才计为整屏空黑帧。实际最大全屏黑色占比为 47.04%，符合图片查看器的黑色留边，整屏空黑帧计数为 0。此结果仅覆盖录像实际采集到的帧，与前述首帧 UIKit 回归测试共同作为验证证据。

产物目录：`/tmp/pink-house-chart-preview-20261015/`，包含 `chart-transitions.mov`、`video-frame-metrics.csv`、`video-analysis.json` 及临时分析脚本 `analyze-video.swift`。

## 边界

模拟器与首帧回归测试不能覆盖真机系统转场、实际 iCloud 下载、相册保存权限。该修复尚未替换已发布版本。
