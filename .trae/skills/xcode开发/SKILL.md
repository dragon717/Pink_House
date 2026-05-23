---
name: xcode开发
description: Pink_House iOS/Xcode/SwiftUI 开发与模拟器验收技能。用于修改 iOS 代码后运行 xcodebuild、Xcode Simulator、simctl 或 Computer Use 电脑控制验收，尤其要保证先对当前目标模拟器重新编译、安装并重启新进程，再判断 UI。
---

# Pink House Xcode Development

在 Pink_House 做 iOS / SwiftUI / Xcode 相关改动时使用本技能。重点不是“能看到模拟器”，而是确保看到的是刚刚修改代码编译出来的新 app。

## 必读

如果任务涉及模拟器截图、电脑控制验收、文案/视觉核对，先读：

- `docs/XCODE_SIMULATOR_COMPUTER_USE_ACCEPTANCE.md`

## 电脑控制验收铁律

Computer Use 只能证明当前 Simulator 窗口显示了什么，不能证明它来自新代码。验收必须按下面顺序：

1. 锁定用户正在看的模拟器 destination，例如 `platform=iOS Simulator,name=iPhone 17 Pro`。
2. 对同一个 destination 重新编译。
3. 安装新产物，或通过 Xcode Run 到同一个模拟器。
4. `simctl terminate` 旧进程，再 `simctl launch`。
5. 最后才用 Computer Use 读取页面和点击核验。

如果 Computer Use 看到旧文案，先假设是旧进程、旧构建、装错模拟器或页面缓存，不要先怀疑代码没改对。

## 推荐命令

仓库路径：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"
```

常规构建：

```bash
xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet build
```

iCloud 路径导致签名报 `resource fork, Finder information, or similar detritus not allowed` 时，优先把 DerivedData 放到 `/private/tmp`，并复用已有包缓存：

```bash
xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/pink-house-build-<ts> \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -quiet build
```

安装和重启：

```bash
xcrun simctl install booted /private/tmp/pink-house-build-<ts>/Build/Products/Debug-iphonesimulator/ItemManager.app
xcrun simctl terminate booted bugod2.ItemManager
xcrun simctl launch booted bugod2.ItemManager
```

文案类改动可先查产物：

```bash
rg -a -n "新文案|旧文案" /private/tmp/pink-house-build-<ts>/Build/Products/Debug-iphonesimulator/ItemManager.app
```

## 输出要求

最终回复必须写清：

- 跑过的 `xcodebuild` 命令、destination、PASS/FAIL。
- 是否安装、terminate、launch 到同一个模拟器。
- Computer Use 实际观察到的关键 UI 文案或状态。
- 未覆盖边界：未跑构建、未跑模拟器、未跑真机、或仅做静态检查。

不要把“Simulator 里有一个页面”写成完整验收通过。缺少重新编译或进程重启时，必须明确标注验收不完整。
