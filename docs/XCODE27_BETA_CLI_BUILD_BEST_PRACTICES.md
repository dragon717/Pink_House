# Xcode 27 Beta CLI Build Best Practices

> 适用范围：Pink_House 在 Xcode 27 beta 下用命令行构建、安装并启动到 `Codex iPhone 17 Pro` 模拟器。当前稳定入口是 `tools/xcode/stable_cli_build_and_run.sh`。

## 结论

稳定流程不是“清空一切重新编译”，而是复用 Xcode GUI 已验证过的干净 DerivedData / SourcePackages，并用命令行加上明确护栏：

- 显式使用 `/Applications/Xcode-beta.app`，不要依赖系统默认 `xcode-select`。
- destination 用模拟器 UDID，避免编到同名或旧系统设备。
- 不使用 iCloud 仓库里的 `build/SourcePackages` 作为默认 SPM 缓存。
- 构建并发限制为 `-jobs 5`。
- 构建总时限限制为 180 秒；超时立即终止并报告 `TIMEOUT`，不让后台编译失控。
- 构建成功后必须安装到同一台模拟器，并 `terminate` + `launch` 新进程。

## 标准入口

从仓库根目录运行：

```bash
tools/xcode/stable_cli_build_and_run.sh
```

默认值：

```text
XCODE_APP=/Applications/Xcode-beta.app
SCHEME=ItemManager
SIM_NAME=Codex iPhone 17 Pro
MAX_JOBS=5
BUILD_TIMEOUT_SECONDS=180
ALLOW_PARALLEL_BUILDS=0
```

可按需覆盖：

```bash
SIM_ID=<udid> BUILD_TIMEOUT_SECONDS=180 MAX_JOBS=5 tools/xcode/stable_cli_build_and_run.sh
```

## 为什么不用仓库 build/SourcePackages

iCloud 同步可能在 SPM checkout 里生成 `* 2.swift` 文件。GRDB 这类包一旦出现重复 Swift 源文件，Xcode 27 beta 会把同名类型看成重复定义，例如：

```text
DatabaseValue is ambiguous for type lookup in this context
where clause cannot be applied to a non-generic top-level declaration
```

这不是业务源码错误，而是污染缓存导致同一包源码被编译两份。稳定脚本会检查 `SourcePackages/checkouts`，一旦发现 `* 2.swift` 就拒绝继续构建。

优先使用 Xcode GUI 成功构建后留下的：

```text
~/Library/Developer/Xcode/DerivedData/ItemManager-*/SourcePackages
```

## 诊断口径

Xcode 27 beta 日志里可能出现：

```text
error: the following command failed with exit code 0 but produced no further output
```

这条诊断可以和 `BUILD_EXIT=0` 同时出现。判断构建是否通过时，以以下顺序为准：

1. `xcodebuild` 进程退出码。
2. 是否出现 `** BUILD FAILED **` / `** BUILD INTERRUPTED **`。
3. 是否产出 `Build/Products/Debug-iphonesimulator/ItemManager.app`。
4. `simctl install` 和 `simctl launch` 是否成功。

如果最终 `BUILD_EXIT=0`，且 install / launch 也为 0，这条 `exit code 0` 诊断按 Xcode beta 噪音记录，不按失败处理。

## 当前已知 warning

这些 warning 不是本流程的阻塞条件，但需要在后续修复窗口跟进：

- Swift 6 语言模式下会升级为 error 的 actor isolation / Sendable / async 警告。
- `NSLock.lock/unlock` 在 async context 中不可用的 Swift 6 预警。
- imported type retroactive conformance 警告，例如 `CLLocationCoordinate2D: Codable`、`UIImage: Identifiable`。
- `The CFBundleVersion of an app extension ('3') must match that of its containing parent app ('1').`
- `Remove Duplicate Resources` run script 未启用 Based on dependency analysis。

## 稳定性守则

- 构建前先查是否已有 `xcodebuild` / `swift-frontend` / `clang`，不要叠加多轮编译。
- 已有构建超过 180 秒，先停掉再重跑。
- 需要“干净构建”时优先用 Xcode GUI clean build 预热 DerivedData；命令行全新 DerivedData 在 180 秒窗口内可能超时，不能把这个误写成源码失败。
- 如果必须导出临时源码快照，不要复制污染的 `build/SourcePackages`。
- `terminate` 返回 “found nothing to terminate” 时可记为非阻塞；关键是随后的 `launch` 返回 0。
- 构建通过不等于 UI 验收通过。视觉 / 文案 / 点击验收仍按 `docs/XCODE_SIMULATOR_COMPUTER_USE_ACCEPTANCE.md` 继续做。

## 交付模板

```text
构建：
- 入口：tools/xcode/stable_cli_build_and_run.sh
- Xcode：
- destination：
- 并发：
- 超时：
- 结果：
- 日志：

安装与启动：
- app：
- bundle id：
- install：
- terminate：
- launch：

诊断：
- exit code 0 but produced no further output：
- 既有 warning：
- 是否有残留编译进程：

边界：
- 未做 UI 点击 / 截图 / 真机验收时必须说明。
```
