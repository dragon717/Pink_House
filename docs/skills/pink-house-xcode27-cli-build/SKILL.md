---
name: pink-house-xcode27-cli-build
description: Pink_House Xcode 27 beta 命令行稳定构建与模拟器启动技能。用于用户要求用命令行跑 Xcode beta 编译、Codex iPhone 17 Pro/iOS 26.5 模拟器启动、限制 3 分钟超时、限制最多 5 个编译线程、排查 “exit code 0 but produced no further output” 或 iCloud SourcePackages 污染时。
---

# Pink House Xcode 27 CLI Build

在 Pink_House 中用 Xcode 27 beta 命令行构建、安装并启动模拟器时使用本技能。默认不要重新发明命令，优先使用仓库脚本。

## 先读

1. `docs/XCODE27_BETA_CLI_BUILD_BEST_PRACTICES.md`
2. `docs/XCODE_SIMULATOR_COMPUTER_USE_ACCEPTANCE.md`（需要 UI / 截图 / 文案验收时）
3. `tools/xcode/stable_cli_build_and_run.sh`

## 默认流程

从仓库根目录运行：

```bash
tools/xcode/stable_cli_build_and_run.sh
```

脚本默认：

- 使用 `/Applications/Xcode-beta.app`。
- 锁定 `Codex iPhone 17 Pro`，优先解析为 UDID。
- 复用 Xcode GUI 成功构建过的 `~/Library/Developer/Xcode/DerivedData/ItemManager-*/SourcePackages`。
- 拒绝含 `* 2.swift` 的污染 SPM checkout。
- `xcodebuild` 使用 `-jobs 5`。
- 180 秒 watchdog；超时返回 124 并终止进程组。
- 构建后安装到同一模拟器，并 `terminate` + `launch`。

## 不要踩的坑

- 默认 `xcrun` 找不到 `simctl` 时，显式设置 `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`，不要改全局 `xcode-select`。
- 不要用名称模糊的 destination；优先使用 `platform=iOS Simulator,id=<UDID>`。
- 不要默认复制仓库里的 `build/SourcePackages`；iCloud 可能生成 `* 2.swift`，导致 GRDB 等包重复定义。
- 不要并发启动第二条 `xcodebuild`。如已有构建，先查目标、运行时长和是否超过 180 秒。
- 不要把 `terminate` 的 “found nothing to terminate” 当失败；后续 `launch` 为 0 即可。

## 诊断判断

`exit code 0 but produced no further output` 在 Xcode 27 beta 中可能与成功构建同时出现。按这个顺序判断：

1. `BUILD_EXIT` 是否为 0。
2. 日志是否有 `BUILD FAILED` / `BUILD INTERRUPTED`。
3. app bundle 是否存在。
4. `INSTALL_EXIT` 和 `LAUNCH_EXIT` 是否为 0。

最终构建、安装、启动都为 0 时，这条诊断按 beta 噪音记录，不按失败处理。

## 输出要求

最终回复写清：

- 使用的脚本或完整 `xcodebuild` 命令。
- Xcode 版本、destination / UDID。
- `MAX_JOBS`、`BUILD_TIMEOUT_SECONDS`。
- build / install / terminate / launch 的结果。
- 是否有 `exit code 0 but produced no further output`，以及既有 warning 摘要。
- 是否存在残留编译进程。
- 未覆盖边界：UI 点击、截图、真机、完整 clean build 等。
