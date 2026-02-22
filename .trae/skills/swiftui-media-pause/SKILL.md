---
name: "swiftui-media-pause"
description: "SwiftUI media state management best practices. Invoke when implementing audio/haptics/physics pause functionality in SwiftUI, especially with SpriteKit and nested TabView."
---

# SwiftUI 媒体状态管理最佳实践

## 问题场景

在 SwiftUI 中使用 SpriteKit 物理模拟、Core Haptics 震动和音频时，当视图切换或消失时需要正确暂停这些媒体。常见场景：

- TabView 切换子页面（如"马上来财"界面的请签/数钱/安财切换）
- 视图被条件渲染替换（`if isActive { PhysicsView() } else { Color.clear }`）
- 应用进入后台

## 核心问题

1. **`onDisappear` 不可靠**：SwiftUI 的 `onDisappear` 在视图被条件渲染替换时可能不会被调用
2. **引擎自动重启**：调用 `stopHaptics()` 后，物理模拟的 `update` 循环可能仍在运行，会重新启动引擎
3. **状态不同步**：多个管理器（`MediaStateManager`、`HapticEngineManager`）之间的暂停状态需要同步

## 最佳实践

### 1. 双重保护机制

在震动管理器中添加本地暂停状态，不依赖外部状态：

```swift
@MainActor
final class HapticEngineManager: ObservableObject {
    @Published var isPaused: Bool = false
    
    func stopHaptics() {
        isPaused = true  // 设置标志防止重启
        // ... 停止引擎
    }
    
    func resumeHaptics() {
        isPaused = false
    }
    
    func playHaptic() {
        // 检查本地暂停状态
        if isPaused || MediaStateManager.shared.isPhysicsPaused {
            return
        }
        // ... 播放震动
    }
}
```

### 2. 在播放方法中检查暂停状态

所有播放方法都应该检查暂停状态：

```swift
func playCollisionHaptic(intensity: Float) {
    // 双重检查：本地暂停 + 全局暂停
    if MediaStateManager.shared.isPhysicsPaused || isPaused {
        return
    }
    // ...
}

func playRollingTexture(intensity: Float) {
    if MediaStateManager.shared.isPhysicsPaused || isPaused {
        // 停止滚动音效和震动
        soundManager.updateRollingSound(intensity: 0)
        try? rollingPlayer?.stop(atTime: 0)
        rollingPlayer = nil
        return
    }
    // ...
}
```

### 3. 视图生命周期管理

在物理视图中正确管理生命周期：

```swift
struct PhysicsView: View {
    @State private var scene: PhysicsScene?
    
    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: createScene(size: proxy.size))
                // 不要在这里使用 onAppear/onDisappear
        }
        .onAppear {
            // 恢复震动状态
            HapticEngineManager.shared.resumeHaptics()
        }
        .onDisappear {
            // 停止物理模拟
            scene?.pauseSimulation()
            // 停止音效和震动
            HapticEngineManager.shared.stopHaptics()
            SoundManager.shared.stopAllSounds()
        }
    }
}
```

### 4. 父视图状态监听

在父视图中监听状态变化，作为后备机制：

```swift
struct ParentView: View {
    let isActive: Bool
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    @ObservedObject private var soundManager = SoundManager.shared
    
    var body: some View {
        VStack {
            if isActive {
                PhysicsView()
            } else {
                Color.clear
            }
        }
        .onChange(of: isActive) { oldValue, newValue in
            if oldValue && !newValue {
                // 从激活变为非激活，停止音效和震动
                soundManager.stopAllSounds()
                hapticManager.stopHaptics()
            }
        }
    }
}
```

### 5. 物理场景暂停

在 SpriteKit 场景中正确暂停：

```swift
class PhysicsScene: SKScene {
    func pauseSimulation() {
        self.isPaused = true
        motionManager.stopDeviceMotionUpdates()
        
        // 停止所有外部媒体
        HapticEngineManager.shared.stopHaptics()
        SoundManager.shared.stopAllSounds()
    }
    
    func resumeSimulation() {
        self.isPaused = false
        startMotionUpdates()
    }
    
    override func update(_ currentTime: TimeInterval) {
        guard !isPaused else { return }
        // ... 更新逻辑
    }
}
```

### 6. 移除不必要的保护检查

`stopHaptics()` 不应该有提前返回的保护：

```swift
// ❌ 不要这样
func stopHaptics() {
    guard isEngineRunning else { return }  // 这会阻止停止
    // ...
}

// ✅ 应该这样
func stopHaptics() {
    isPaused = true  // 先设置标志
    // 无论引擎状态如何都尝试停止
    try? continuousPlayer?.stop(atTime: 0)
    try? rollingPlayer?.stop(atTime: 0)
    engine?.stop { _ in
        self.isEngineRunning = false
    }
}
```

## 关键要点

1. **本地暂停状态**：在管理器内部维护暂停状态，不依赖外部状态
2. **播放前检查**：所有播放方法都要检查暂停状态
3. **双重停止机制**：`onDisappear` + `onChange` 监听
4. **场景暂停**：SpriteKit 场景的 `isPaused` 和外部媒体同步
5. **无保护停止**：`stop` 方法不要有提前返回，确保总是执行

## 常见陷阱

- ❌ 只在 `SpriteView` 上使用 `onDisappear`（应该在整个视图上使用）
- ❌ 依赖 `scene?.pauseSimulation()` 的可选链（如果 scene 为 nil 会失败）
- ❌ `stopHaptics()` 中有 `guard isEngineRunning` 检查
- ❌ 只依赖 `MediaStateManager.shared.isPhysicsPaused`（需要本地状态作为后备）

## 调试技巧

添加日志追踪状态变化：

```swift
.onDisappear {
    print("🛑 View disappeared")
    HapticEngineManager.shared.stopHaptics()
    SoundManager.shared.stopAllSounds()
}

func playHaptic() {
    if isPaused {
        print("⏸️ Haptic skipped (paused)")
        return
    }
    // ...
}
```
