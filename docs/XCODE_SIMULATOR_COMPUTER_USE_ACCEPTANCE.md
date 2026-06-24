# Xcode Simulator + 电脑控制验收最佳实践

> 适用范围：Pink_House iOS / SwiftUI 变更后的模拟器 UI 验收，尤其是需要用 Computer Use 读取 Simulator 画面、点击页面、核对文案或截图归档的任务。

## 1. 核心原则

电脑控制验收不是构建验证。Computer Use 只能证明“当前 Simulator 窗口正在显示什么”，不能证明这个画面来自刚刚修改的代码。

因此验收顺序必须是：

1. 明确目标模拟器。
2. 对同一个目标重新编译。
3. 安装或由 Xcode Run 到该模拟器。
4. 终止旧进程并重新启动。
5. 再用 Computer Use 看真实 UI。

如果第 5 步看到旧文案或旧布局，第一判断应是“旧进程 / 旧构建 / 装错模拟器”，不要马上判断代码没生效。

## 2. 标准流程

### 2.0 Xcode 27 beta 命令行稳定入口

如果目标是 Xcode 27 beta + `Codex iPhone 17 Pro`，优先使用稳定脚本：

```bash
tools/xcode/stable_cli_build_and_run.sh
```

这条入口会显式使用 `/Applications/Xcode-beta.app`、锁定模拟器 UDID、复用 Xcode GUI 成功构建过的干净 `DerivedData/SourcePackages`、限制 `-jobs 5`、180 秒超时终止，并完成 install / terminate / launch。详细规则见 `docs/XCODE27_BETA_CLI_BUILD_BEST_PRACTICES.md`。

注意：不要默认复用仓库里的 `build/SourcePackages`。iCloud 可能生成 `* 2.swift` 重复源码，导致 GRDB 等 SwiftPM 依赖出现重复定义。

### 2.1 锁定目标

先记录实际验收设备，避免“编译一个模拟器，看另一个模拟器”：

```bash
xcrun simctl list devices booted
```

报告里写清：

- scheme
- destination，例如 `platform=iOS Simulator,name=iPhone 17 Pro`
- iOS 版本
- bundle id

### 2.2 重新编译当前目标

优先用和用户当前 Simulator 一致的 destination：

```bash
xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet build
```

如果 iCloud 工程路径触发签名错误，例如：

```text
resource fork, Finder information, or similar detritus not allowed
```

不要把这个误判成 Swift 编译失败。可改用 `/private/tmp` 作为 DerivedData，并复用已有 SPM 缓存：

```bash
xcodebuild \
  -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /private/tmp/pink-house-build-<ts> \
  -clonedSourcePackagesDirPath build/SourcePackages \
  -quiet build
```

如果新 DerivedData 需要重新拉包而网络不可用，回退到已有 `build/SourcePackages` 缓存，或在报告中说明依赖解析边界。

### 2.3 安装并重启进程

构建通过后，不要只点 Simulator 里已经打开的 app。先安装，再终止，再启动：

```bash
xcrun simctl install booted /private/tmp/pink-house-build-<ts>/Build/Products/Debug-iphonesimulator/ItemManager.app
xcrun simctl terminate booted bugod2.ItemManager
xcrun simctl launch booted bugod2.ItemManager
```

若用户明确要求“用 Xcode 里重新编译该模拟器”，则应通过 Xcode Run 或等价的 `xcodebuild` exact destination 完成，不用旧 app 进程冒充验收。

### 2.4 证明新构建包含改动

对文案类改动，运行前可以在产物里查新旧字符串：

```bash
rg -a -n "新文案|旧文案" /private/tmp/pink-house-build-<ts>/Build/Products/Debug-iphonesimulator/ItemManager.app
```

规则：

- 产物里能查到新文案，说明代码已进入构建产物。
- Simulator 仍显示旧文案，优先排查旧进程、未重新安装、装错设备或页面缓存。
- 产物里没有新文案，说明构建不是基于当前源码。

### 2.5 用 Computer Use 验收

Computer Use 放在最后：

1. `get_app_state("Simulator")` 读取可访问性树和截图。
2. 核对页面标题、关键文案、按钮状态、当前选中态。
3. 如可访问性树和截图不一致，以截图再复核；如两者都旧，回到构建/安装链路。
4. 需要用户交互时再点击；不要用点击行为替代构建验证。

## 3. 交付报告模板

最终报告至少写清：

```text
构建：
- 命令：
- destination：
- 结果：PASS / FAIL
- 重要既有 warning：

安装与启动：
- bundle id：
- install：PASS / FAIL
- terminate + launch：PASS / FAIL

电脑控制验收：
- 工具：Computer Use / Simulator
- 观察到的关键 UI：
- 是否仍有旧文案/开发词：

边界：
- 未覆盖设备：
- 未覆盖真机能力：
- 已知非本次引入的 warning：
```

## 4. 常见反模式

- 只看已经打开的 Simulator 页面，不重新编译目标模拟器。
- `simctl install` 后不 terminate，继续看旧进程。
- 编译 iPhone 16 Pro，却在 iPhone 17 Pro 窗口验收。
- 看到旧 UI 后立刻怀疑 SwiftUI 没刷新，而不先确认产物字符串和进程状态。
- 把 Computer Use 截图当成构建通过证明。
- iCloud 路径签名失败时反复清整个 `build` 目录，导致 SPM 依赖重新拉取和权限问题；优先用 `/private/tmp` DerivedData。

## 5. 验收口径

一轮合格的电脑控制验收必须同时满足：

- 源码检查：目标文件包含预期改动。
- 构建检查：目标 destination 编译通过。
- 产物检查：app bundle 包含预期新字符串或资源。
- 运行检查：目标模拟器安装并重启新进程。
- UI 检查：Computer Use 观察到的页面与预期一致。

缺少任一环节时，最终报告必须明确写“未覆盖”，不能写成完整验收通过。
