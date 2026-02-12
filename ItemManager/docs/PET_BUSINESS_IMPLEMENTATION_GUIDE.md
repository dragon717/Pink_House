# 萌宠业务系统实现指南与最佳实践

本文档总结了萌宠系统的核心架构设计、业务实现流程及最佳实践，旨在帮助开发者快速理解系统，并能“一次性”高效地实现新增宠物、新动作、新彩蛋等业务需求。

## 1. 架构概览

萌宠系统采用 **MVVM (Model-View-ViewModel)** 架构，结合 **有限状态机 (Finite State Machine, FSM)** 和 **面向协议编程 (Protocol-Oriented Programming)** 来管理复杂的宠物行为和状态。

*   **PetModel (`PetModel.swift`)**: 定义数据结构 (`PetStatus`) 和行为协议 (`PetBehavior`)。
*   **PetViewModel (`PetViewModel.swift`)**: 核心逻辑中枢。负责状态管理、业务逻辑触发、与 `AudioManager`/`ConfigManager` 交互。
*   **PetConcreteStates (`PetConcreteStates.swift`)**: 基于 `GameplayKit` 的状态机实现，负责管理特定状态下的视频播放逻辑和循环行为。
*   **SeamlessVideoPlayer (`SeamlessVideoPlayer.swift`)**: 底层播放器，支持无缝循环、双缓冲切换、沙盒路径自动修正。

---

## 2. 核心设计模式

### 2.1 多宠物支持：`PetBehavior` 协议
为了避免 `PetViewModel` 膨胀并支持多宠物差异化，我们将特定宠物的行为逻辑剥离到协议实现中。

```swift
protocol PetBehavior {
    var character: PetCharacter { get }
    // 打工结算逻辑
    func getWorkFinishResult(job: PetJob, status: PetStatus) -> (video: String, message: String, success: Bool)
    // 打工中断视频
    func getWorkInterruptedVideo() -> String
    // 回音彩蛋 (语音触发)
    func getEchoEgg(text: String) -> String?
    // 喂食彩蛋 (道具触发)
    func getFeedingEgg(item: PetItemDefinition) -> String?
}
```

### 2.2 状态驱动：`GKStateMachine`
所有视觉表现（视频播放）由状态机驱动。
*   **输入**：`PetViewModel.changeState(to:)`
*   **处理**：`PetConcreteStates` 中的具体 State 类（如 `InteractionState`, `WorkingState`）决定播放哪个视频、是否循环。
*   **输出**：驱动 UI 层的播放器。

---

## 3. 业务实现指南 (Cookbook)

### 3.1 如何添加新宠物 (e.g. "Maomao")

1.  **定义枚举**: 在 `PetModel.swift` 的 `PetCharacter` 中添加 `.maomao`。
2.  **实现行为**: 创建 `struct MaomaoBehavior: PetBehavior`，实现该宠物的专属逻辑（如特定彩蛋、打工表现）。
3.  **注册行为**: 在 `PetViewModel.getBehavior(for:)` 工厂方法中返回新的 Behavior。
4.  **准备资源**: 
    *   命名规范：`maomao_idle.mp4`, `maomao_eating.mp4` 等。
    *   放置位置：`ItemManager/asserts/` 或 `Bundle Resources`。

### 3.2 如何添加新动作/状态

1.  **定义状态**: 在 `PetState` 枚举中添加新状态 (e.g. `.dancing`)。
2.  **创建 State 类**: 在 `PetConcreteStates.swift` 中继承 `PetVideoState`。
    ```swift
    class DancingState: PetVideoState {
        override var videoName: String { "dancing" } // 对应 maomao_dancing.mp4
        override var logicalState: PetState { .dancing }
        override var isLooping: Bool { true }
    }
    ```
3.  **注册状态**: 在 `PetViewModel.setupStateMachine` 中将新 State 加入数组。
4.  **处理切换**: 在 `PetViewModel.changeState` 的 `switch` 中添加对应的 `enter` 逻辑。

### 3.3 如何实现打工/活动逻辑

*   **收益计算**: 
    *   不要依赖结束时的时间差估算（不准确，且容易受离线影响）。
    *   **最佳实践**: 在 `processTimePassage` (每分钟/每秒) 中实时累加收益到 `status.currentJobEarnedFishCoin`。
*   **结算展示**: 
    *   在 `PetBehavior.getWorkFinishResult` 中直接读取 `status.currentJobEarnedFishCoin` 返回给 UI。
*   **中断处理**:
    *   在 `processTimePassage` 中检查中断条件（精力<=0, 饱食<=0）。
    *   调用 `stopJob(isInterrupted: true)`，该方法会调用 `Behavior.getWorkInterruptedVideo()` 获取中断动画。

### 3.4 如何添加彩蛋

*   **语音彩蛋**:
    *   在 `Behavior.getEchoEgg(text:)` 中判断关键词。
    *   返回**绝对路径**或**文件名**。
    *   *示例*: `if text.contains("登基") { return "naicha_coronation.mp4" }`
*   **道具彩蛋**:
    *   在 `Behavior.getFeedingEgg(item:)` 中判断道具 ID 和概率。
    *   *示例*: `if item.id == "catFood" && probability < 0.05 { return "naicha_eat_rush.mp4" }`

---

## 4. 最佳实践与避坑指南

### 4.1 视频资源路径 (Crucial!)
*   **Bundle 资源**: 推荐使用文件名（不带后缀或带后缀），如 `naicha_idle`。播放器会自动在 Bundle 根目录和 `asserts` 子目录查找。
*   **绝对路径**: 
    *   **开发时**: 如果使用 macOS 绝对路径（`/Users/...`），必须确保播放器有 **Sandbox Fallback** 机制。
    *   **机制**: `SeamlessVideoPlayer` 会检测绝对路径是否可读。如果不可读（权限/沙盒问题），它会自动提取**文件名**并在 Bundle 中重新查找。
    *   **结论**: 你可以直接传入策划给的绝对路径，只要确保同名文件已打入 Bundle，代码能自动兼容。

### 4.2 状态切换与打断
*   **forceLoop**: `changeState` 支持 `forceLoop` 参数。
    *   **彩蛋视频**: 通常设置 `forceLoop: false`。播放结束后，`onAnimationFinished` 会自动切回 `idle`。
    *   **状态保持**: 如 `talking` 状态，设置 `forceLoop: true` 确保一直播放直到语音结束。
*   **优先级**: `changeState` 中传入的 `videoName` 参数优先级 **高于** State 类的默认 `videoName`。这允许灵活复用同一个 State 播放不同视频（如通用 InteractionState 播放不同的抚摸反馈）。

### 4.3 数据一致性
*   **Codable**: 所有需要持久化的状态（包括 `currentJobEarnedFishCoin`）必须遵循 `Codable` 并加入 `CodingKeys`。
*   **离线模拟**: `processTimePassage` 同时负责在线计时和离线结算。修改逻辑时务必同时考虑这两种情况。

### 4.4 调试技巧
*   **日志**: 关注 `SeamlessVideoPlayer` 的日志，查看路径查找结果（Fallback found ...）。
*   **状态监控**: 使用 `PetStatus` 中的临时字段（如 `currentJobEarnedFishCoin`）来验证逻辑是否按预期累加，而不是只看最终结果。

---

## 5. 常用代码片段

**调用播放绝对路径视频（自动回退）：**
```swift
// 即使在沙盒内，只要 Bundle 里有同名文件，这也能工作
changeState(to: .interacting, videoName: "/Users/dev/Desktop/asserts/special_video.mp4", forceLoop: false)
```

**触发一次性动画（播放完自动回 Idle）：**
```swift
// forceLoop: false 是关键
changeState(to: .interacting, videoName: "some_one_shot_animation", forceLoop: false)
```

**新增宠物配置 (PetModel.swift):**
```swift
struct MaomaoBehavior: PetBehavior {
    let character: PetCharacter = .maomao
    func getWorkFinishResult(...) -> ... { ... }
    func getWorkInterruptedVideo() -> String { "maomao_tired" }
    func getEchoEgg(...) -> String? { nil }
    func getFeedingEgg(...) -> String? { nil }
}
```
