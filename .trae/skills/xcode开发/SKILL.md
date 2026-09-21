---
name: "xcode开发"
description: "Pink_House iOS 工程的 Xcode 构建与验收技能。当要用 xcodebuild 编译 ItemManager、跑 build-for-testing / test、做模拟器 UI 验收、写或调试 XCUITest、或用 ImageRenderer 做 SwiftUI 快照核对时使用。也用于这些具体症状：SwiftPM manifest 报 sandbox_apply: Operation not permitted；SwiftData 的 Model()/Relationship() 报 external macro implementation type could not be found 或 swift-plugin-server produced malformed response；日志里没有任何 error: 却出现 Command PhaseScriptExecution failed；ObservableObject / @Environment(\\.modelContext) 报 does not conform / missing import；模拟器里看到的文案是旧的、或疑似跑到了旧构建产物。"
---

本技能记录 Pink_House 工程在本机（`/Users/sangyu/develop/Pink_House`）**实测验证过**的构建与验收口径。
当它与 `AGENTS.md`、其他 skill、或你记忆里的 Xcode 用法冲突时，**以本技能为准，但仍要先跑一次环境自检确认**（见下）。

## TRIGGER / DO NOT TRIGGER

TRIGGER 当：需要编译/测试 iOS 工程；要在模拟器上验证 UI；要写或排错 XCUITest / 快照测试；xcodebuild 报了看不懂的错。
DO NOT TRIGGER 当：只改 Markdown 文档、只做纯代码阅读或评审、只跑不落盘的纯逻辑单测（用 `-only-testing` 直接跑即可）、或任务与 iOS 构建无关。

## 三条铁律

1. **先测环境，再下命令。** Xcode 路径、模拟器名、DerivedData 位置都会随机器和 Xcode 版本变。
   任何写死路径的命令在运行前，先执行 `scripts/detect_environment.sh` 取真实值。
   本技能里所有 `/Applications/...`、`iPhone xx Pro` 都只是**当时的快照**，不是常量。

2. **验收 = 重新编译 + 装到同一台模拟器 + 杀掉旧进程再启动。**
   「模拟器里有一个页面」不等于「这个页面来自新代码」。缺少任一步骤，必须在结论里标注**验收不完整**。

3. **先分清是环境问题还是代码问题。**
   判据只有一条：**报错的文件是否在你本次 `git status` 里**。不在 → 环境问题，不要改代码。

## 环境自检（每个会话开工第一步）

```bash
.trae/skills/xcode开发/scripts/detect_environment.sh
```

## References

- `references/environment-facts.md`: 用任何写死路径或 destination 之前读。本机 Xcode / 模拟器 / bundle id / pbxproj 特性 / 默认 MainActor 隔离 / `MemberImportVisibility` 的实测事实，以及 AGENTS.md 里**已失效**的三条说法。
- `references/build-commands.md`: 要跑 xcodebuild 时读。三条可用命令（编译主 target / build-for-testing / test）、三个必须一起给的沙箱开关、以及怎么 grep 才不误报。
- `references/sandbox-pitfalls.md`: **编译报了看不懂的错时先读**。三个沙箱坑的识别与绕过，尤其「日志无 `error:` 却失败」的判读口径。
- `references/device-verification.md`: 要在模拟器上看效果时读。安装 / terminate / launch 顺序、Computer Use 的适用边界、XCUITest 是唯一可靠的真交互路径、以及「假绿」检测。
- `references/uitest-pitfalls.md`: 写或改 XCUITest 前读。定位元素、点击命中、懒渲染、断言分支的高频坑。
- `references/snapshot-testing.md`: 用 `ImageRenderer` 导出 PNG 做版式核对前读。五个会让快照失真或直接崩测试进程的坑。

## Scripts

- `scripts/detect_environment.sh` — 输出本机 Xcode 路径/版本、可用模拟器、bundle id、产物路径，供命令拼装。
- `scripts/build.sh` — 封装好三个沙箱开关的构建入口（`app` / `testing` / `test` 三种模式）。
- `scripts/verify_fresh_build.sh` — 校验产物 mtime 晚于本轮构建起点，防「旧产物假绿」。

## 输出要求

结论里必须写清：跑过的命令与 destination、PASS/FAIL、是否完成安装与进程重启、实际观察到的 UI 状态，
以及未覆盖的边界（未跑构建 / 未装模拟器 / 未跑真机 / 仅静态检查）。
