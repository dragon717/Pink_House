# SpriteKit 物理容器最佳实践

## 概述

本文档总结了在 SwiftUI 中使用 SpriteKit 实现物理效果容器的最佳实践，参考金豆银珠和虚拟币物理容器的实现经验。

## 核心架构

### 1. 环境变量控制

使用环境变量统一管理物理模拟的生命周期：

```swift
@Environment(\.isSimulationActive) var isSimulationActive
@Environment(\.isWealthStorageActive) var isWealthStorageActive
@Environment(\.scenePhase) var scenePhase
```

**最佳实践：**
- `isSimulationActive`：控制是否允许物理模拟（如 Tab 切换时暂停）
- `isWealthStorageActive`：控制财富存储页面是否激活
- `scenePhase`：监听应用前后台状态
- 使用 `MediaStateManager` 统一管理媒体状态

### 2. 暂停状态计算

```swift
private var shouldPause: Bool {
    !isViewVisible || 
    scenePhase != .active || 
    !isSimulationActive || 
    !isWealthStorageActive || 
    mediaStateManager.isPhysicsPaused
}
```

**关键点：**
- 综合所有条件决定是否暂停
- 任一条件不满足都应暂停物理模拟
- 暂停时停止震动和音效

### 3. 场景生命周期管理

**懒加载模式：**

```swift
@State private var scene: VirtualCoinScene?

private func createScene(size: CGSize) -> SKScene {
    if let existingScene = scene {
        if existingScene.size != size {
            existingScene.size = size
        }
        return existingScene
    }
    
    let newScene = VirtualCoinScene(size: size)
    // 异步赋值避免状态修改警告
    DispatchQueue.main.async {
        if self.scene == nil {
            self.scene = newScene
        }
    }
    return newScene
}
```

**避免的问题：**
- 不要在视图更新时直接修改 `@State`
- 使用异步赋值避免 "Modifying state during view update" 警告
- 复用现有场景而不是重复创建

## 物理场景实现

### 1. 碰撞检测优化

**性能优化策略：**

```swift
// 仅让约 10% 的物体作为"触觉传感器"报告碰撞
let isSensor = Int.random(in: 1...10) == 1
body.contactTestBitMask = isSensor ? (PhysicsCategory.coin | PhysicsCategory.wall) : 0
```

**原因：**
- 避免大量物体互相碰撞产生过多回调
- 保持碰撞检测的准确性同时减少性能开销

### 2. 震动反馈聚合

**帧级聚合策略：**

```swift
private var frameMaxImpulse: CGFloat = 0.0
private var frameContactPoint: CGPoint = .zero
private var frameCollisionCount: Int = 0
private var isWallCollisionFrame: Bool = false

func didBegin(_ contact: SKPhysicsContact) {
    let impulse = contact.collisionImpulse
    if impulse > 0.0001 {
        if impulse > frameMaxImpulse {
            frameMaxImpulse = impulse
            frameContactPoint = contact.contactPoint
        }
        frameCollisionCount += 1
        
        // 检测撞墙
        if (contact.bodyA.categoryBitMask == PhysicsCategory.wall) ||
           (contact.bodyB.categoryBitMask == PhysicsCategory.wall) {
            isWallCollisionFrame = true
        }
    }
}
```

**在 update 中处理：**

```swift
override func update(_ currentTime: TimeInterval) {
    // 处理聚合的碰撞数据
    if frameCollisionCount > 0 {
        triggerAggregatedHaptic(currentTime: currentTime)
    }
    
    // 持续震动调制
    let currentEnergy = min(CGFloat(frameCollisionCount) * 0.1 + frameMaxImpulse * 0.5, 1.0)
    if currentEnergy > 0.05 {
        HapticEngineManager.shared.playRollingTexture(intensity: Float(currentEnergy))
    }
    
    // 重置帧数据
    frameMaxImpulse = 0.0
    frameCollisionCount = 0
    isWallCollisionFrame = false
}
```

### 3. 批量处理物体

**避免一次性创建大量物体：**

```swift
private let coinsPerFrameAdd: Int = 20
private let coinsPerFrameRemove: Int = 30

private func processCoinQueues() {
    // 分批添加/移除，避免卡顿
    if currentCount < targetCount {
        let countToAdd = min(coinsPerFrameAdd, targetCount - currentCount)
        // 添加 countToAdd 个物体
    } else if currentCount > targetCount {
        let countToRemove = min(coinsPerFrameRemove, currentCount - targetCount)
        // 移除 countToRemove 个物体
    }
}
```

## 3D 纹理生成

### 1. 径向渐变模拟球体

```swift
let colors = [
    UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 1.0).cgColor, // 高光中心
    UIColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0).cgColor, // 固有色
    UIColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1.0).cgColor,  // 暗部
    UIColor(red: 0.7, green: 0.5, blue: 0.05, alpha: 1.0).cgColor   // 边缘
] as CFArray

let locations: [CGFloat] = [0.0, 0.4, 0.7, 1.0]

if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
    cgContext.drawRadialGradient(
        gradient,
        startCenter: gradientCenter,
        startRadius: 0,
        endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
        endRadius: radius,
        options: .drawsBeforeStartLocation
    )
}
```

### 2. 高光效果

```swift
cgContext.saveGState()
cgContext.setBlendMode(.screen)
let highlightColors = [
    UIColor(white: 1.0, alpha: 0.8).cgColor,
    UIColor(white: 1.0, alpha: 0.0).cgColor
] as CFArray
// 绘制高光渐变...
cgContext.restoreGState()
```

### 3. 纹理缓存

```swift
class TextureGenerator {
    static let shared = TextureGenerator()
    private var cachedTexture: SKTexture?
    
    func getTexture() -> SKTexture {
        if let cached = cachedTexture {
            return cached
        }
        // 生成纹理并缓存
        let texture = SKTexture(image: image)
        self.cachedTexture = texture
        return texture
    }
}
```

## 震动和音效

### 1. 区分碰撞类型

```swift
private func triggerAggregatedHaptic(currentTime: TimeInterval) {
    let normalizedIntensity: Float
    let sharpness: Float
    let impactType: SoundManager.ImpactType
    
    if isWallCollisionFrame {
        // 撞墙：强烈震动
        normalizedIntensity = Float(min(frameMaxImpulse * 10.0, 1.0))
        sharpness = 0.9
        impactType = .hard
    } else {
        // 物体互撞：中等震动
        let baseIntensity = Float(min(frameMaxImpulse * 15.0, 1.0))
        normalizedIntensity = baseIntensity * 0.6
        sharpness = 0.4
        impactType = .soft
    }
    
    HapticEngineManager.shared.playCollisionHaptic(
        intensity: normalizedIntensity,
        sharpness: sharpness,
        position: CGPoint(x: normalizedX, y: normalizedY),
        type: impactType
    )
}
```

### 2. 频率限制

```swift
private let hapticMinInterval: TimeInterval = 0.08

guard currentTime - lastHapticTime > hapticMinInterval else { return }
lastHapticTime = currentTime
```

## 常见问题和解决方案

### 1. "Modifying state during view update"

**原因：** 在视图更新过程中直接修改 `@State`

**解决：** 使用异步赋值

```swift
DispatchQueue.main.async {
    if self.scene == nil {
        self.scene = newScene
    }
}
```

### 2. 物理容器不显示

**检查点：**
- 确保 `SpriteView` 有明确的 frame
- 检查 `isPaused` 状态
- 确认场景正确初始化
- 验证 `allowsTransparency` 选项

### 3. 性能问题

**优化策略：**
- 限制最大物体数量（如 100-500）
- 分批处理物体添加/移除
- 仅部分物体报告碰撞
- 使用纹理而非实时绘制

## 文件组织建议

```
ItemManager/
├── Views/
│   └── Wealth/
│       ├── VirtualCurrencyView.swift      # 主视图
│       ├── VirtualCoinTextureGenerator.swift  # 纹理生成（可选拆分）
│       └── VirtualCoinScene.swift         # 物理场景（可选拆分）
├── Managers/
│   ├── HapticEngineManager.swift          # 震动管理
│   ├── SoundManager.swift                 # 音效管理
│   └── MediaStateManager.swift            # 媒体状态
└── docs/
    └── SPRITEKIT_PHYSICS_BEST_PRACTICES.md  # 本文档
```

## 参考实现

- **GoldPhysicsView.swift** - 金豆物理容器
- **SilverPhysicsView.swift** - 银珠物理容器
- **VirtualCurrencyView.swift** - 虚拟币物理容器

## 总结

成功的 SpriteKit 物理容器实现需要：

1. **完善的生命周期管理** - 环境变量 + 懒加载
2. **性能优化** - 批量处理 + 碰撞检测优化
3. **丰富的反馈** - 震动 + 音效 + 3D 纹理
4. **稳定的状态管理** - 避免视图更新时修改状态
5. **合理的资源限制** - 控制物体数量上限
