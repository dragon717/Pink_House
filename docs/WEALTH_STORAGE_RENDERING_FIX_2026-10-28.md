# 安财动画灰屏检查与修复（2026-10-28）

## 问题与定位

用户截图：安财的黄金数量及参考价格正常，下面的动画区域是一整块灰色。

黄金、白银、虚拟币原来分别在 SwiftUI `body` 求值时调用 `createScene`，并用 `DispatchQueue.main.async` 把场景写回可选 `@State`。在首次布局、分页切换或暂停状态变化期间，State 尚未写入就可能再次创建场景；`SpriteView` 接收的场景与后续数量更新、暂停/恢复操作引用的场景可能不一致。初始 `isViewVisible == false` 又让渲染视图从暂停状态开始，仅设置 SwiftUI 的 `.background(Color.clear)` 不能直接保证底层 SKView 及其 layer 在首帧前为透明。

基线在 iOS 26.3.1 新构建上，少量金豆可显示，未稳定复现用户截图的整片灰屏。因此不把截图推断写成已复现的系统缺陷；本次修复的是代码中实际存在的场景所有权、透明宿主和生命周期问题，覆盖三种共享实现。

## 实现

- 共用 `WealthPhysicsSurface` / `WealthPhysicsHost`。场景只在 SKView 已进入窗口且具有有效尺寸后创建一次，显示、配置、暂停和恢复都操作同一个实例。
- 显式设置 SKView 的 `allowsTransparency`、`isOpaque`、背景、layer 背景及 SKScene 背景；初始暂停也不再依赖一次成功的绘制去遮住宿主默认底色。
- 回归测试确认 `presentScene` 会重置视图/场景的暂停状态。挂载之后重新同步暂停，卸载后也显式保持旧场景暂停，避免首次进入时状态失配。
- 生命周期由当前业务页、安财页、App 前后台、媒体暂停以及实际窗口挂载共同决定。离开窗口暂停，重新挂载恢复，拆卸时断开场景并停止传感器；`didMove` 不再无条件抢先启动运动传感器。
- 黄金、白银共用自定义背景的等比适配和物理边界计算；虚拟币补上尺寸变化后重建边界。
- 金属数量先验证有限值并限幅，再转整数，避免异常数据溢出中断渲染；虚拟币负数按零处理。黄金每克一豆、白银每 50 克一珠、虚拟币展示换算以及既有数量上限保持原口径。
- 未更改财富金额来源、用户钱包、充值或兑换交易。

## 验证

本机 Xcode 27.0（27A266a）。iOS 26.3.1 目标为 `Codex DIY Outfit QA`，UDID `F64FFA05-1AA0-4C8F-9920-F18A772486CB`，bundle id `bugod2.ItemManager`。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=F64FFA05-1AA0-4C8F-9920-F18A772486CB' \
  -derivedDataPath /private/tmp/pink-house-reservation-batches-ios \
  -clonedSourcePackagesDirPath /Users/sangyu/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -only-testing:ItemManagerTests/WealthPhysicsSurfaceTests \
  -only-testing:ItemManagerTests/ClothingAccessoryTests test
```

`WealthPhysicsSurfaceTests` 覆盖有效尺寸之前不创建场景、多次切换保持同一场景、初始暂停透明、恢复不重复启动、窗口拆卸/重新挂载、配置与尺寸同步、253 枚金豆与银珠、虚拟币换算及边界更新、异常金额及背景边界。`ClothingAccessoryTests` 复核财富与尾款金额计算。

结果：**TEST SUCCEEDED，31 项通过，0 失败**（安财 8 项、金额 23 项）。日志 `/private/tmp/pink-house-wealth-physics-fixed-tests.log`。首次测试捕获了 `presentScene` 重置暂停的三个断言失败，已修正并用相同测试全部复核；首次失败后的测试收尾进程无进展，终止后重新执行完整构建和测试。

测试构建结束后对同一模拟器安装并启动新进程：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install F64FFA05-1AA0-4C8F-9920-F18A772486CB /private/tmp/pink-house-reservation-batches-ios/Build/Products/Debug-iphonesimulator/ItemManager.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl terminate F64FFA05-1AA0-4C8F-9920-F18A772486CB bugod2.ItemManager
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch F64FFA05-1AA0-4C8F-9920-F18A772486CB bugod2.ItemManager -loginDays 2 -newbieGuide.hasSeenWelcome YES -AppleLanguages '(zh-Hans)'
```

安装通过；terminate 返回没有旧进程；launch 成功启动 PID 73721。登录天数是测试模拟器的启动参数，用于进入已有功能入口，不修改业务代码或真机数据。通过 Device Hub 的 Computer Use 检查：

- 数钱进入安财，黄金 3.73 克显示 3 枚金豆、白银 5.57 两显示 5 枚银珠，主题壁纸贯穿动画区域，无整片灰色遮挡。
- 虚拟页显示现有测试余额与虚拟币粒子；鱼币、骨头币兑换页可打开、关闭，钱包数字未改变。
- 喵币补充页可以打开、关闭；当前模拟器显示无法取得 App Store 商品信息，不能记作购买成功或线上商品加载通过。
- 从虚拟页切回黄金显示正常；按 Home 进入后台，再次 `simctl launch` 返回同一 PID 73721，金豆和透明背景显示正常。
- 未执行充值或兑换，不以页面打开替代交易链路验收。

## 边界

模拟器不具备真实重力传感器和 Core Haptics 触感，不能据此宣称真机摇动、扬声器音效和触感验收通过。代码未上传、未发布，用户现有安装需要升级后才能生效。
