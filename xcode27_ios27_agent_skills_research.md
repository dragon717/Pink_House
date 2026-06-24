# Xcode 27 beta、iOS 27 规范与 Apple agent skills 调研

调研时间：2026-06-24。

## 本机状态

- `/Applications/Xcode-beta.app`：Xcode 27.0 build `27A5194q`。
- 当前 `xcode-select -p` 指向 `/Library/Developer/CommandLineTools`；跑 Xcode beta 命令时用 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`。
- SDK：iOS/iPhoneSimulator 27.0，Swift 6.4。
- 已安装 simulator runtime：iOS 17.5、18.2、18.6、26.4、26.5；未发现 iOS 27 runtime。

## Apple 官方 agent skills

导出命令：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun agent skills export --output-dir /tmp/xcode27-skills-probe --replace-existing
```

导出的 7 个 skills：

- `swiftui-whats-new-27`
- `swiftui-specialist`
- `uikit-app-modernization`
- `test-modernizer`
- `device-interaction`
- `audit-xcode-security-settings`
- `c-bounds-safety`

这些是 Xcode 当前版本快照；Xcode beta 更新后重新导出，不维护仓库内副本。

## SDK 27 开发要点

- SwiftUI：SDK 27 的 `@State` 已迁移为 macro，遇到初始化、合成属性、memberwise init 报错时先查官方 skill，不靠重排赋值硬修。
- SwiftUI：新增或变化点集中在 `ContentBuilder`、reorderable containers、AsyncImage HTTP 缓存、toolbar overflow/priority/pinned/minimize、item-binding alert/dialog、非 List swipe actions、新 Document API。
- UIKit/iOS 27：iPhone Mirroring 与 iPhone app on iPad 更强调动态 resize；布局不要依赖 `UIScreen.main`、interface orientation、user interface idiom，改用 scene/window、trait collection、size class、view bounds。
- UIKit：用最新 SDK 构建时检查 `UIScene` lifecycle。

## 参考入口

- Apple: `developer.apple.com/ios/whats-new/`
- Apple: `developer.apple.com/xcode/whats-new/`
- Apple: `developer.apple.com/swiftui/whats-new/`
- Apple WWDC26: `developer.apple.com/videos/play/wwdc2026/278/`
