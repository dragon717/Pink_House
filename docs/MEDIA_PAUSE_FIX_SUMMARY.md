# 马上来财页签切换媒体暂停修复总结

## 问题描述

在"马上来财"界面内切换顶部页签（请签/数钱/安财）时，金豆的物理模拟、震动和音效没有正确暂停。

## 根本原因分析

### 1. `onDisappear` 不可靠
- 当使用条件渲染（`if isActive { PhysicsView() } else { Color.clear }`）时，`onDisappear` 可能不会被调用
- 即使被调用，`scene?.pauseSimulation()` 的可选链如果 scene 为 nil 会失败

### 2. 引擎自动重启
- `playCollisionHaptic` 和 `playRollingTexture` 会在调用时通过 `startEngineIfNeeded()` 重新启动引擎
- 即使调用了 `stopHaptics()`，物理场景的 `update` 循环可能仍在运行

### 3. `stopHaptics()` 的保护检查
- 原来的 `stopHaptics()` 有 `guard isEngineRunning else { return }`，如果引擎状态不正确就不会停止

### 4. 状态不同步
- 只依赖 `MediaStateManager.shared.isPhysicsPaused` 不够，需要本地暂停状态作为后备

## 修复方案

### 1. HapticEngineManager 修改

```swift
// 添加本地暂停状态
@Published var isPaused: Bool = false

func stopHaptics() {
    isPaused = true  // 设置标志防止重启
    // 移除 guard isEngineRunning 检查
    // ... 停止引擎
}

func resumeHaptics() {
    isPaused = false
}

// 所有播放方法检查 isPaused
func playCollisionHaptic(...) {
    if MediaStateManager.shared.isPhysicsPaused || isPaused {
        return
    }
    // ...
}
```

### 2. GoldPhysicsView / SilverPhysicsView 修改

```swift
.onAppear {
    isViewVisible = true
    HapticEngineManager.shared.resumeHaptics()  // 恢复状态
}
.onDisappear {
    isViewVisible = false
    scene?.pauseSimulation()
    HapticEngineManager.shared.stopHaptics()     // 停止震动
    SoundManager.shared.stopAllSounds()          // 停止音效
}
```

### 3. GoldStorageView / SilverStorageView 修改

```swift
.onChange(of: isActive) { oldValue, newValue in
    if oldValue && !newValue {
        // 从激活变为非激活，停止音效和震动
        soundManager.stopAllSounds()
        hapticManager.stopHaptics()
    }
}
```

### 4. GoldScene / SilverScene 修改

```swift
func pauseSimulation() {
    self.isPaused = true
    motionManager.stopDeviceMotionUpdates()
    HapticEngineManager.shared.updateHapticParameters(intensity: 0, sharpness: 0)
    HapticEngineManager.shared.stopHaptics()     // 添加
    SoundManager.shared.stopAllSounds()          // 添加
}
```

## 修改文件列表

1. `ItemManager/Views/Wealth/HapticEngineManager.swift`
   - 添加 `isPaused` 状态
   - 修改 `stopHaptics()` 移除 `guard` 检查
   - 添加 `resumeHaptics()` 方法
   - 修改 `playCollisionHaptic` 和 `playRollingTexture` 检查 `isPaused`

2. `ItemManager/Views/Wealth/GoldPhysicsView.swift`
   - 修改 `onAppear` 调用 `resumeHaptics()`
   - 修改 `onDisappear` 直接停止音效和震动
   - 修改 `pauseSimulation()` 调用

3. `ItemManager/Views/Wealth/SilverPhysicsView.swift`
   - 同上

4. `ItemManager/Views/Wealth/WealthView.swift`
   - 在 `GoldStorageView` 和 `SilverStorageView` 中添加 `onChange` 监听

## 关键设计决策

1. **本地暂停状态**：在 `HapticEngineManager` 内部维护 `isPaused`，不依赖外部状态
2. **双重检查**：播放方法同时检查 `MediaStateManager.shared.isPhysicsPaused` 和本地 `isPaused`
3. **无保护停止**：`stopHaptics()` 无论引擎状态如何都尝试停止
4. **双重停止机制**：`onDisappear` + `onChange` 监听作为后备

## 调试日志

关键日志输出：
```
🛑 GoldPhysicsView.onDisappear: 物理模拟已暂停
⏸️ Haptic skipped (paused)
```

## 相关技能

- `.trae/skills/swiftui-media-pause/SKILL.md` - SwiftUI 媒体状态管理最佳实践
