# 萌宠音频与交互系统开发指南 (Audio Development Guide)

本文档总结了 `Pink_House` 项目中音频模块 (`AudioManager`) 和视频交互模块 (`SeamlessPlayer`) 的核心架构、常见陷阱解决方案以及最佳实践。旨在为后续维护和开发提供技术参考。

## 1. 核心架构概述

项目采用 **AVAudioEngine** 作为核心音频处理引擎，结合 **AVAudioSession** 管理系统音频路由。主要功能包括：
- **实时监听 (VAD)**：基于能量 (RMS) 和 CoreML (`SoundAnalysis`) 的人声检测。
- **回声变声 (Echo)**：录制人声 -> 变调 (`AVAudioUnitTimePitch`) -> EQ 处理 -> 播放。
- **无缝视频 (SeamlessPlayer)**：基于 `AVQueuePlayer` 的双缓冲视频切换系统。

## 2. 核心问题与解决方案 (Troubleshooting)

在开发过程中，我们解决了一系列涉及 Core Audio 底层机制的复杂问题，以下是关键案例总结。

### 2.1 音频引擎崩溃 (Error -10868) 与噪音
**现象**：
- 播放录音时崩溃，报错 `error -10868 (kAudioUnitErr_FormatNotSupported)`。
- 或者不崩溃但播放出刺耳噪音/变调。

**原因**：
`AVAudioSession` 在 `PlayAndRecord` (录音) 和 `Playback` (播放) 模式切换时，硬件采样率可能会改变（如 48kHz -> 44.1kHz）。`AVAudioEngine` 的 `inputNode` 和连接节点如果未及时刷新格式，会导致采样率不匹配。

**解决方案**：
1.  **强制重置引擎**：在 `setupAudioSession` 改变 Category 后，必须调用 `engine.reset()`，强制 Engine 与硬件重新握手。
2.  **正确的格式获取**：录音时使用 `inputNode.outputFormat(forBus: 0)` 获取 Tap 格式，而非 `inputFormat`。
3.  **动态重连**：播放前调用 `engine.disconnectNodeOutput` 断开旧连接，使用当前音频文件的实际格式 (`file.processingFormat`) 重新连接节点链。

### 2.2 音频路由死循环 (Infinite Loop)
**现象**：
控制台疯狂刷屏 `Route changed`，CPU 占用飙升，应用卡死。

**原因**：
代码中强制设置 `builtInMic` -> 触发系统 `routeChange` 通知 -> 通知回调中再次调用 `setupAudioSession` -> 再次触发通知 -> 死循环。

**解决方案**：
1.  **忽略无关通知**：在 `handleRouteChange` 中明确忽略 `.categoryChange` 类型的通知。
2.  **防御性设置**：在 `setupAudioSession` 中，先检查 `session.category` 和 `session.preferredInput` 是否已经是目标值，如果是则跳过设置。

### 2.3 录音“吞字”现象
**现象**：
用户说话的第一个字（如“你好”的“你”）经常录不进去。

**原因**：
VAD (语音活动检测) 需要一定时间（几十到几百毫秒）来确认声音超过阈值。当状态切换为 `recording` 时，声音的开头部分已经流失。

**解决方案**：**环形缓冲区 (Ring Buffer)**
- 维护一个 `preRecordBuffer` 数组，始终缓存最近 20 个音频缓冲（约 500ms）。
- 当检测到说话开始录音时，先将缓冲区内的历史数据写入文件，再写入实时数据。

### 2.4 播放过早结束 (Truncated Playback)
**现象**：
复述还没说完，状态就切回了“倾听”，导致尾音被切断。

**原因**：
`AVAudioPlayerNode.scheduleFile` 的 `completionHandler` 触发时机不可靠，通常早于声音实际通过扬声器播放完毕的时间（受缓冲区大小和效果器延迟影响）。

**解决方案**：
- 放弃 `completionHandler` 用于状态流转。
- **精确计算时长**：`duration = file.length / sampleRate`。
- **手动定时**：使用 `DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3)` 控制结束，增加 0.3s 缓冲确保完整性。

## 3. 性能优化最佳实践

### 3.1 音频线程与主线程交互
Core Audio 的 Tap Block (`installTap`) 是在实时音频线程上回调的，极其敏感。
- **DON'T**: 在 Tap Block 中无条件 `DispatchQueue.main.async`。这会导致每秒 50-100 次的主线程调度，造成 UI 严重卡顿。
- **DO**: 引入 `_isListening`, `_isRecording` 等**本地原子标志位**（非 `@Published`），在 Tap Block 中先检查标志位，只有状态真正需要变更时才派发到主线程。

### 3.2 避免高频 I/O
- **问题**：`PetInteractionManager` 在获取 `currentPetId` 时，每次都从 `UserDefaults` 读取并解码 JSON。
- **优化**：改为直接从内存中的 `PetDataManager.shared.status` 读取。`UserDefaults` 仅用于持久化存储，不应作为实时数据源。

### 3.3 视频播放器 (SeamlessPlayer)
- **路径查找优化**：视频文件名查找涉及 Bundle 遍历，开销较大。在 `update` 方法中，先检查 `videoName` 是否变化，若未变则直接跳过查找。
- **多路径回退**：查找视频时应支持多种策略（Bundle Root, `asserts` 子目录, 无后缀匹配），并提供合理的 Fallback（如回退到 `idle` 状态），防止因缺少文件导致黑屏。

## 4. 代码规范 (Code Guidelines)

1.  **Swift Concurrency**：
    *   `AudioManager` 标记为 `@MainActor`，确保 UI 状态更新安全。
    *   音频回调 (`Tap Block`) 处于非隔离上下文，访问属性需注意线程安全（使用专门的内部变量如 `_isRecording`）。

2.  **错误处理**：
    *   所有 Audio API (`AVAudioSession`, `AVAudioFile` 等) 的 `try-catch` 必须有明确的错误日志。
    *   关键路径（如播放失败）必须有恢复机制（`restartListening`），防止 App 陷入死状态。

3.  **日志管理**：
    *   避免在音频回调或高频 UI 刷新 (`update`) 中打印日志。
    *   关键状态变化（Start/Stop Listening, Route Change）应保留日志以便排查。

## 5. 维护清单 (Maintenance Checklist)

- [ ] **新增音效**：需确保采样率兼容，建议统一使用 44.1kHz 或 48kHz 的 WAV/CAF 格式。
- [ ] **新增视频**：放入 `ItemManager/asserts` 目录，命名规范为 `petId_action.mp4` (e.g., `naicha_eating.mp4`)。
- [ ] **iOS 版本适配**：关注 `AVAudioSession` 在新 iOS 版本中的行为变化，特别是隐私权限和后台处理策略。
