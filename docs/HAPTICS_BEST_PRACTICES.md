# iOS 触觉反馈 (Haptics) 最佳实践与开发指南

本文档总结了在 `Pink_House` 项目中实施触觉反馈系统的经验教训，特别是关于 **Core Haptics** 与 **UIKit (UIFeedbackGenerator)** 的混合使用、性能优化及架构设计。

## 1. 核心架构设计

### 1.1 统一管理原则 (The Singleton Manager)
永远不要在 `View` 内部直接实例化 `UIImpactFeedbackGenerator` 或管理 `CHHapticEngine`。
**错误的做法 (Anti-Pattern):**
```swift
struct MyView: View {
    // ❌ 错误：View 是值类型，重建时会导致 Generator 状态丢失或频繁创建
    private let generator = UIImpactFeedbackGenerator(style: .medium) 
    
    var body: some View {
        Button("Tap") {
            generator.impactOccurred() // 可能不生效或有延迟
        }
    }
}
```

**正确的做法 (Best Practice):**
使用单例 `HapticEngineManager` 统一管理所有震动请求。
```swift
struct MyView: View {
    // ✅ 正确：引用单例
    @ObservedObject private var hapticManager = HapticEngineManager.shared
    
    var body: some View {
        Button("Tap") {
            // 通过管理器调用，内部处理引擎状态、Fallback 逻辑和参数调优
            hapticManager.playUIFeedback(intensity: 0.5, sharpness: 0.5)
        }
    }
}
```

### 1.2 双层降级策略 (Graceful Degradation)
iOS 设备对震动的支持分为两类，必须同时兼容：
1.  **Core Haptics (iPhone 8 及更新机型)**: 支持精细控制强度 (`Intensity`)、锐度 (`Sharpness`)、瞬态 (`Transient`) 和持续 (`Continuous`) 震动。
2.  **UIKit Haptics (旧机型/简单场景)**: 仅支持预设的 `Light`, `Medium`, `Heavy`, `Rigid`, `Soft` 几种风格。

`HapticEngineManager` 必须封装这种差异：
- 优先尝试启动 Core Haptics 引擎。
- 如果硬件不支持或引擎启动失败，自动降级调用 `UIImpactFeedbackGenerator`。

## 2. 常见坑与解决方案

### 2.1 震动不生效 (The "Silent Haptic" Issue)
**现象**: 调用了震动代码，但手机毫无反应。
**原因**:
1.  `UIImpactFeedbackGenerator` 未调用 `prepare()` 就立即触发，导致唤醒延迟错过时机。
2.  `CHHapticEngine` 处于停止状态（如后台切回后未重启）。
3.  **强度过低**: Core Haptics 的线性 `Intensity` 在低值（如 0.1）时几乎无法感知。

**解决方案**:
- **非线性强度映射**: 在 `HapticEngineManager` 中对输入的强度做 `pow(intensity, 0.5)` 处理，提升低强度区间的感知度。
- **强制 Prepare**: 在 UIKit 降级路径中，务必先调用 `generator.prepare()`。
- **生命周期监听**: 监听 `UIApplication.willEnterForegroundNotification` 自动重启引擎。

### 2.2 性能卡顿 (Performance Stutter)
**现象**: 在拖拽 (`DragGesture`) 过程中触发震动导致 UI 掉帧。
**原因**:
- 在 `onChanged` 高频回调中频繁创建对象或进行重计算。
- 震动引擎与主线程 UI 渲染争抢资源。

**解决方案**:
- **按需触发**: 不要每一帧都震动，设置时间阈值或距离阈值。
- **预加载**: 在 `onChanged` 的**第一次**调用（`!isDragging` 时）进行引擎准备。
- **轻量化**: 使用 `HapticEngineManager.playUIFeedback` 这种封装好的轻量方法，避免手动创建 `CHHapticPattern`。

## 3. API 使用规范

### 3.1 `HapticEngineManager.playUIFeedback`
用于所有标准 UI 交互（按钮、拖拽、吸附）。

```swift
/// - Parameters:
///   - intensity: 0.0 - 1.0 (推荐：轻微 0.3, 标准 0.5, 强烈 0.8)
///   - sharpness: 0.0 - 1.0 (推荐：柔和 0.3, 清脆 0.7)
///   - fallbackStyle: 降级时的 UIKit 风格
func playUIFeedback(intensity: Float, sharpness: Float, fallbackStyle: UIImpactFeedbackGenerator.FeedbackStyle)
```

**典型参数配置**:
| 场景 | Intensity | Sharpness | Fallback | 感觉描述 |
| :--- | :--- | :--- | :--- | :--- |
| **拖拽开始** | 0.6 | 0.7 | `.medium` | 紧致、有力，类似“拿起”物体 |
| **吸附/放下** | 0.3 | 0.3 | `.light` | 轻盈、柔和，类似“软着陆” |
| **普通点击** | 0.5 | 0.5 | `.medium` | 标准确认感 |
| **错误/警告** | 0.8 | 0.8 | `.rigid` | 尖锐、急促 |

### 3.2 物理模拟 (Physics Haptics)
用于游戏化场景（如金豆碰撞、物体滚动）。
- 使用 `playCollisionHaptic`：支持空间音效定位（虽然手机只有左右震感，但结合参数调整可模拟位置）。
- 使用 `playRollingTexture`：**仅限** Core Haptics，用于持续的滑动/滚动反馈。**注意**：必须在 `onEnded` 时显式停止，否则会一直震动。

## 4. 调试技巧

1.  **强制测试模式**: 在 `HapticEngineManager` 中保留 `playTestHaptic()` 方法，用于在 `onAppear` 时强制触发一次满强度的震动，确认引擎是否存活。
2.  **日志监控**: 在 `engine.stoppedHandler` 中打印日志，监控引擎是否因系统原因（如来电、后台）被意外终止。
3.  **静音开关**: 注意 iOS 系统设置中的“静音模式下不震动”或“系统触感反馈”开关可能会影响测试结果。

## 5. 待办事项 / 未来优化
- [ ] 细化空间震感：利用 `CHHapticDynamicParameter` 更精确地控制左右声道的震动平衡。
- [ ] 自定义波形库：将常用的震动模式（如“心跳”、“波浪”）序列化为 AHAP 文件存储，减少代码硬编码。
