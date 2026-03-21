---
name: "swiftui-newbie-guide"
description: "SwiftUI新手引导系统实现指南。包含状态管理、动画引导、遮罩高亮、视频播放等。Invoke when implementing onboarding/guidance flow with animations and highlights in SwiftUI."
---

# SwiftUI 新手引导系统实现指南

## 核心架构

### 1. 状态管理（State Management）

```swift
// 引导步骤枚举
enum GuideStep: String, CaseIterable, Identifiable {
    case none = "none"
    case welcome = "welcome"
    case step1 = "step1"
    case complete = "complete"
    
    var id: String { rawValue }
}

// 引导状态（需持久化）
struct GuideState: Codable {
    var isCompleted: Bool = false
    var currentStep: String = GuideStep.none.rawValue
    var completedSteps: [String] = []
    var skippedAt: Date? = nil
}

// 单例管理器
final class GuideManager: ObservableObject {
    static let shared = GuideManager()
    
    @Published var state: GuideState = GuideState()
    @Published var currentStep: GuideStep = .none
    @Published var isShowingGuide: Bool = false
    
    // 配置
    private let stateKey = "guide.state"
}
```

**最佳实践：**
- 使用 `Codable` 实现状态持久化
- 使用 `@Published` 实现响应式更新
- 单例模式确保全局状态一致
- 每个步骤独立配置文案、目标位置、动画类型

### 2. 遮罩与高亮（Mask & Highlight）

#### 2.1 圆形挖空遮罩
```swift
// 带挖空的半透明背景
GeometryReader { geometry in
    ZStack {
        // 半透明背景
        Color.black
            .opacity(0.5)
            .ignoresSafeArea()
        
        // 挖空区域
        Circle()
            .frame(width: 80, height: 80)
            .position(highlightCenter)
            .blendMode(.destinationOut)
    }
    .compositingGroup()
}
```

#### 2.2 脉冲高亮效果
```swift
struct HighlightPulseView: View {
    let center: CGPoint
    let radius: CGFloat
    
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8
    
    var body: some View {
        ZStack {
            // 外圈脉冲
            Circle()
                .stroke(Color.white.opacity(pulseOpacity), lineWidth: 2)
                .frame(width: radius * 2 * pulseScale, height: radius * 2 * pulseScale)
            
            // 内圈边框
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .shadow(color: .white.opacity(0.5), radius: 10)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulseScale = 1.5
                pulseOpacity = 0.0
            }
        }
    }
}
```

**最佳实践：**
- 使用 `blendMode(.destinationOut)` 实现真正的挖空
- 使用 `compositingGroup()` 确保混合模式生效
- 脉冲动画使用 `repeatForever` 持续吸引注意力
- 高亮圈和动画元素位置分离，独立可调

### 3. 点击穿透处理

```swift
// 允许点击穿透到下层视图
.allowsHitTesting(false)

// 仅特定区域可点击
.overlay(
    ClickableArea()
        .contentShape(Circle())
        .onTapGesture { /* 处理点击 */ }
)
```

**最佳实践：**
- 遮罩层使用 `.allowsHitTesting(false)` 允许穿透
- 气泡等需要交互的组件保持可点击
- 挖空区域自然穿透，无需额外处理

### 4. 视频动画引导

```swift
struct GuideVideoPlayer: View {
    let videoName: String
    let isLooping: Bool
    let isFlipped: Bool  // 支持镜像翻转
    
    var body: some View {
        PetVideoPlayer(
            videoName: videoName,
            isLooping: isLooping,
            isMuted: true
        )
        .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
    }
}
```

**最佳实践：**
- 使用透明视频（MOV with alpha channel）
- 支持镜像翻转实现左右跑动效果
- 非循环视频停在最后一帧：设置 `isLooping: false`
- 视频元素设置 `.allowsHitTesting(false)` 不阻挡点击

### 5. 动画路径规划

```swift
// 起点和终点分离配置
var startPosition: CGPoint {
    CGPoint(x: screenWidth / 2, y: screenHeight - 130)
}

var endPosition: CGPoint {
    CGPoint(x: screenWidth * 0.88, y: screenHeight * 0.10)
}

// 执行动画
withAnimation(.linear(duration: 5.0)) {
    position = endPosition
}
```

**最佳实践：**
- 起点、终点、高亮位置三者独立配置
- 使用 `withAnimation` 实现平滑过渡
- 动画时长与视频时长相匹配
- 动画开始前隐藏原视图，营造"跑走"效果

## 扩展接口设计

### 1. 步骤配置协议

```swift
protocol GuideStepConfigurable {
    var title: String { get }
    var description: String { get }
    var targetPosition: CGPoint? { get }
    var highlightPosition: CGPoint? { get }
    var animationType: GuideAnimationType { get }
    var duration: TimeInterval { get }
}

enum GuideAnimationType {
    case none
    case running(videoName: String)
    case pointing(videoName: String)
    case custom(AnyView)
}
```

### 2. 事件回调接口

```swift
protocol GuideEventDelegate {
    func guideDidStart()
    func guideDidComplete()
    func guideDidSkip(at step: GuideStep)
    func guideDidEnterStep(_ step: GuideStep)
}
```

### 3. 可扩展的遮罩样式

```swift
enum HighlightStyle {
    case circle(radius: CGFloat)
    case rect(cornerRadius: CGFloat)
    case roundedRect(size: CGSize, cornerRadius: CGFloat)
    case custom(Path)
}
```

## 需要拓展编写的地方

### 1. 多步骤引导支持
- 当前实现：欢迎 → 跑步 → 指向 → 完成
- 扩展：支持任意数量的步骤配置
- 扩展：支持步骤间的条件跳转

### 2. 更多动画类型
- 淡入淡出
- 缩放强调
- 路径动画（贝塞尔曲线）
- 组合动画序列

### 3. 高亮样式扩展
- 矩形高亮
- 圆角矩形高亮
- 自定义形状高亮
- 多区域同时高亮

### 4. 交互方式扩展
- 手势引导（滑动、长按）
- 多指操作引导
- 拖拽引导

### 5. 数据追踪
- 引导完成率统计
- 步骤停留时长
- 跳过率分析
- A/B 测试支持

## 文件组织建议

```
ItemManager/
├── Services/
│   ├── NewbieGuide/
│   │   ├── GuideManager.swift          # 核心管理器
│   │   ├── GuideState.swift            # 状态定义
│   │   ├── GuideStep.swift             # 步骤枚举
│   │   └── GuideConfiguration.swift    # 配置协议
│   └── VideoResourceManager.swift      # 视频资源管理
├── Views/
│   ├── Guide/
│   │   ├── GuideOverlayView.swift      # 遮罩容器
│   │   ├── GuideBubbleView.swift       # 气泡视图
│   │   ├── GuideHighlightView.swift    # 高亮视图
│   │   └── GuideVideoPlayer.swift      # 视频播放器
│   └── Pet/
│       └── PetVideoPlayer.swift        # 复用现有播放器
└── Utilities/
    └── View+Guide.swift                # View扩展
```

## 使用示例

```swift
// 在 App 启动时
.guideOverlay(isActive: $showGuide) {
    WelcomeGuideStep()
    RunningGuideStep(video: "cat_run", duration: 5)
    PointingGuideStep(video: "cat_point", target: .createButton)
}

// 在特定页面
.guideHighlight(for: .filterButton, style: .circle(radius: 30))
.guideBubble("点击这里筛选你的裙子")
```

## 调试技巧

1. **重置引导状态**：在设置中添加"重置新手引导"选项
2. **快速跳过**：开发模式下双击遮罩跳过
3. **位置调试**：使用 `DebugOverlay` 显示坐标网格
4. **动画慢放**：设置 `animationSpeed: 0.5` 慢速查看

## 性能优化

1. 视频预加载：在引导开始前预加载视频资源
2. 懒加载遮罩：仅在需要时创建遮罩视图
3. 及时清理：引导完成后释放视频内存
4. 避免重绘：使用 `drawingGroup()` 优化复杂遮罩
