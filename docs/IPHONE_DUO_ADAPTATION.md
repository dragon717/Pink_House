# iPhone Duo 导航适配

2026-11-04，衣橱和心愿尾款采用同一个 `NavigationSplitView`。宽窗口显示衣物列表与详情两栏，窄窗口由系统折叠为单栏。选择衣物时切到详情列，系统返回时清除紧凑布局的选择。删除当前衣物后返回列表，通知打开衣物也经过同一入口。

主导航继续使用 `NativeTabNavigation` 的系统 `TabView`。使用 iOS 27.1 SDK 构建后，系统会在适合的 Duo 姿态把标签栏与详情工具栏放入侧边区域。衣橱工具栏的动作拆成独立项目；详情页的分享与更多使用带文字和图标的系统项目。列表列的工具栏由系统保留在自己的列内。竖条位置随姿态和窗口位置变化。[Apple 导航指南](https://developer.apple.com/videos/play/tech-talks/111462/)

衣橱、尾款和通知原本各自维护详情跳转，现在统一由 HomeView 管理。移除了原有重复布尔导航状态、空工具栏和转发函数。导航宽度取自当前容器，可见卡片范围与滚动窗口使用同一局部坐标空间。[Apple 弹性布局指南](https://developer.apple.com/videos/play/tech-talks/111461/)

## 构建

本机使用独立安装的 Xcode 27.1（27A9275）。本次代码含 27.1 的工具栏 API，开发与正式归档均需使用 Xcode 27.1 或更新版本。最低 App 系统版本仍由工程中的 iOS 17.4 配置控制，新 API 有版本判断。

```sh
export DEVELOPER_DIR="$HOME/Applications/Xcode-27.1.app/Contents/Developer"
xcodebuild -scheme ItemManager \
  -destination 'platform=iOS Simulator,id=7EAE92A5-31C5-4A41-A17C-A91F89F0B62F' \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/ItemManager-cujimhkdzvadtsdanhkygjqfdyoh" \
  -jobs 2 -quiet ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO build
```

最终构建退出码 0，产物 Info.plist 的 `DTSDKName` 为 `iphonesimulator27.1`。目标设备运行 iOS 27.1（24A94425），Bundle ID 为 `bugod2.ItemManager`。对该设备重新安装并终止旧进程后启动新 App，再通过 Device Hub 操作折叠与衣物选择。编译仍报告已有并发隔离及弃用 API 警告。[构建记录](../output/duo-adaptation/proof/final-build.log)

## 电脑操作验收

| 操作 | 实际结果 |
|---|---|
| 展开设备，选择 Nuit Marine | 左侧保留衣橱列表，右侧出现所选详情，最右显示系统竖向标签栏和分享、更多工具栏 |
| 从详情合上设备 | 保留 Nuit Marine，显示单栏详情与系统返回按钮 |
| 点击系统返回 | 回到衣橱单栏，四件示例衣物可见 |
| 在外屏选择 Herbier，再展开 | 左侧显示衣橱，右侧正确显示 Herbier |

[展开双栏](../output/duo-adaptation/proof/open-detail.png) · [合上保留详情](../output/duo-adaptation/proof/closed-detail.png) · [外屏返回](../output/duo-adaptation/proof/closed-back.png) · [再次展开保留新选择](../output/duo-adaptation/proof/reopen-selection.png)

上述适配验收覆盖专用 Duo 模拟器。真机、与另一 App 并排的系统多任务窗口及支付操作未在本轮重跑。2026-11-07 已另行补拍 iPad 和 iPhone 商品图；最新素材范围、构建验证及 Safari 上传进度见 [商店截图更新记录](APP_STORE_SCREENSHOT_REFRESH_2026-11-07.md)，线上仍有待完成的替换与排序。
