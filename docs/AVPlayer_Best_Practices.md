# iOS AVPlayer 无缝循环播放与状态管理最佳实践

## 1. 背景与问题

在开发 `SeamlessVideoPlayer`（支持无缝切换和循环播放的组件）时，我们遇到了以下严重稳定性问题：

1.  **崩溃与黑屏**：
    *   错误码：`CoreMediaError -12860` (SampleTimingInfoInvalid) 和 `-12785`。
    *   现象：快速点击交互（Start -> Stop Touching）或从循环切换到单次播放时，视频黑屏或导致应用崩溃。
2.  **系统错误日志**：
    *   错误码：`FigApplicationStateMonitor err=-19431`。
    *   现象：应用在后台或锁屏状态下，尝试调用播放控制导致系统报错。
3.  **状态竞争 (Race Condition)**：
    *   现象：快速连续操作导致视频状态错乱（如本该停止循环的视频继续循环，或本该播放的视频未加载）。

## 2. 根本原因分析 (Root Cause Analysis)

### 2.1 AVPlayerLooper 的局限性
`AVPlayerLooper` 是 Apple 官方提供的循环播放解决方案，但它在以下场景表现脆弱：
*   **动态队列修改**：当 `AVPlayerLooper` 正在工作（预加载副本）时，调用 `disableLooping()` 或尝试从 `AVQueuePlayer` 中 `remove()` item，极易破坏 CoreMedia 底层的解码管道，导致 -12860 错误。
*   **并发操作**：在主线程频繁创建和销毁 Looper，容易引发内部状态竞争。

### 2.2 Player 复用的副作用
为了性能，我们最初尝试复用两个 `AVQueuePlayer` (A/B) 实例。然而：
*   **状态残留**：旧的 Observer、Item 状态或 Looper 关联很难彻底清理干净。
*   **污染**：上一次播放的错误状态可能会带入下一次播放。

### 2.3 生命周期管理缺失
*   **后台播放**：iOS 限制了应用在后台的视频播放能力（除非申请了特定权限）。简单的 Watchdog 机制在后台强制调用 `play()` 会触发系统保护机制报错。

## 3. 最终解决方案

我们采用了一套**"降维打击"**的重构方案，牺牲微小的内存分配性能，换取绝对的稳定性。

### 3.1 弃用 AVPlayerLooper，改用手动 Seek
这是解决崩溃问题的核心。我们不再依赖 `AVPlayerLooper` 的队列机制，而是手动控制循环。

**旧代码 (易崩溃):**
```swift
// 创建 Looper
looper = AVPlayerLooper(player: player, templateItem: item)
// 停止 Looper (危险操作)
looper.disableLooping() 
```

**新代码 (稳定):**
```swift
// 监听播放结束
NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
    if self.isLooping {
        // 手动循环：Seek 到头并重播
        player.seek(to: .zero)
        player.play()
    } else {
        // 结束播放
        self.onFinished?()
    }
}
```
**优势**：完全避免了操作 `AVQueuePlayer` 的队列，消除了 CoreMedia 崩溃的根源。

### 3.2 弃用复用，每次新建 Player
每次切换视频时，都创建一个全新的 `AVQueuePlayer` 实例。

```swift
// 关键重构：每次创建新的 Player，避免复用导致的状态污染
let nextPlayer = AVQueuePlayer()
nextLayer.player = nextPlayer
```
**优势**：确保每次播放都是"白纸一张"，无任何历史包袱。

### 3.3 引入 Loading ID 防抖
为了解决快速点击导致的 Race Condition，引入了 UUID 校验机制。

```swift
let loadingID = UUID()
self.currentLoadingID = loadingID

// 在异步回调中检查 ID
if self.currentLoadingID == loadingID {
    performSwitch()
}
```

### 3.4 智能生命周期管理
监听应用前后台状态，自动暂停/恢复 Watchdog。

```swift
private func handleAppBackground() {
    isAppActive = false
    activePlayer?.pause() // 避免后台播放报错
}

private func checkPlaybackStatus() {
    guard isAppActive else { return } // 阻断后台检查
    // ...
}
```

## 4. 最佳实践总结

在 iOS Swift 开发复杂的视频播放业务时，建议遵循以下原则：

1.  **慎用 AVPlayerLooper**：除非是简单的、长期的背景视频。对于频繁交互、短视频切换场景，**监听通知 + `seek(to: .zero)`** 是更健壮的选择。
2.  **不可变性优先 (Immutability)**：在处理 Player 这种重状态对象时，**新建优于复用**。现代 iOS 设备的性能足以支撑轻量级 Player 的频繁创建。
3.  **逻辑截断优于物理清理**：
    *   当需要停止播放时，不要试图去清理 `AVQueuePlayer` 的队列（`removeAllItems`），这很危险。
    *   **做法**：直接销毁 Player，或者通过逻辑 Flag 忽略后续回调。
4.  **尊重生命周期**：始终处理 `UIApplication` 的后台通知，不要在后台尝试操作 UI 或 Video Player。
5.  **防御性编程**：
    *   使用 `UUID` 标记异步任务，防止回调错乱。
    *   在 `deinit` 中务必清理 Observer。
    *   在操作 Layer/Player 分离时，显式设为 `nil` 帮助 ARC 释放。

## 5. 代码参考
*   核心实现：[SeamlessVideoPlayer.swift](ItemManager/Views/Pet/SeamlessVideoPlayer.swift)
