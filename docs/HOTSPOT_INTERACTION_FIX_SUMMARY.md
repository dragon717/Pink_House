# House 界面热区失效问题修复总结

## 问题描述

本文档沉淀两类容易混淆、但根因完全不同的 House 热区失效问题：

1. **图片几何尺寸错误**：热区坐标算错，表现为“点哪都不对”。
2. **上层交互层拦截**：热区本身没问题，但被全局手势层或引导顶层 window 挡住，表现为“无引导正常，有引导失效”或“首次进入才失效”。

---

## Case 1：图片几何尺寸错误

**现象**：House 界面（RococoSmallWorldView）的热区在首次加载时无法点击，但跳转到 House Tab 里的其他页面再返回后，热区恢复正常可点击。

**影响范围**：
- RococoSmallWorldView 中的热区（穿搭手帐、来财、衣橱、心愿尾款、日历、拼豆工坊）
- 仅影响 `.aspectRatio(contentMode: .fit)` 模式的图片热区

## 根本原因

当图片使用 `.aspectRatio(contentMode: .fit)` 时：
1. 图片保持宽高比，可能不会填满整个 frame
2. `GeometryReader` 获取的是 overlay 的 frame 尺寸，而非图片实际显示尺寸
3. 热区坐标计算基于错误的尺寸，导致点击位置偏移或热区完全失效

### 代码分析

**错误实现**（修复前）：
```swift
Image(imageName)
    .resizable()
    .aspectRatio(contentMode: .fit)
    .overlay(
        GeometryReader { geo in  // ❌ geo.size 是 frame 尺寸，不是图片尺寸
            HotspotButtons(using: geo.size)
        }
    )
```

**问题**：`GeometryReader` 获取的是 overlay 的 frame 尺寸，当图片使用 `.fit` 模式时，图片实际显示尺寸小于 frame 尺寸，导致热区坐标计算错误。

## 解决方案

### 核心思路

**热区坐标必须基于图片实际显示尺寸计算，而非容器 frame 尺寸。**

### 修复实现

**1. 使用 GeometryReader 包裹图片**

```swift
GeometryReader { imageGeo in
    Image(imageName)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .overlay(
            HotspotOverlay(containerSize: imageGeo.size)  // ✅ 传递图片实际尺寸
        )
}
```

**2. 热区组件支持外部传入尺寸**

```swift
struct HotspotOverlay: View {
    var geometry: GeometryProxy? = nil
    var containerSize: CGSize? = nil
    
    // 统一获取尺寸的方式
    private var size: CGSize {
        containerSize ?? geometry?.size ?? CGSize(width: 100, height: 100)
    }
    
    // 使用 size 进行热区布局
}
```

**3. 坐标计算**

```swift
// 归一化坐标 (0.0 - 1.0) 转换为实际坐标
Button(action: hotspot.action) {
    Color.black.opacity(0.001)  // 极低透明度确保可点击
        .contentShape(Rectangle())
}
.frame(
    width: hotspot.rect.width * size.width,
    height: hotspot.rect.height * size.height
)
.position(
    x: (hotspot.rect.minX + hotspot.rect.width/2) * size.width,
    y: (hotspot.rect.minY + hotspot.rect.height/2) * size.height
)
```

## 修改文件

### 1. RococoSmallWorldView.swift

**修改点**：
- `roomView` 方法：使用 `GeometryReader` 包裹图片，获取实际显示尺寸
- `roomContent` 方法：添加 `containerSize` 参数
- 新增 `roomHotspotsContent` 方法：提取热区内容，避免代码重复

**关键变更**：
```swift
// 修复前
Image(imageName)
    .resizable()
    .aspectRatio(contentMode: .fit)
    .overlay(
        roomContent(imageName: imageName, hotspots: hotspots)
    )

// 修复后
GeometryReader { imageGeo in
    Image(imageName)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .overlay(
            roomContent(imageName: imageName, hotspots: hotspots, containerSize: imageGeo.size)
        )
}
```

### 2. SmallWorldPetOverlay.swift

**修改点**：
- 添加 `containerSize` 参数支持
- 保持向后兼容（`geometry` 参数变为可选）
- 统一使用 `size` 属性获取有效尺寸

**关键变更**：
```swift
struct SmallWorldPetOverlay: View {
    var geometry: GeometryProxy? = nil
    var containerSize: CGSize? = nil
    
    private var size: CGSize {
        containerSize ?? geometry?.size ?? CGSize(width: 100, height: 100)
    }
}
```

### 3. PathShape 结构体

**修改点**：
- 添加 `size` 参数支持
- 保持向后兼容

## 最佳实践

### 1. 热区实现检查清单

- [ ] 使用 `Color.black.opacity(0.001)` 而非 `Color.clear` 确保可点击
- [ ] 添加 `.contentShape(Rectangle())` 确保点击区域正确
- [ ] 使用 `GeometryReader` 获取图片实际显示尺寸
- [ ] 将尺寸传递给热区组件，避免在 overlay 中重复获取
- [ ] 归一化坐标使用 (0.0 - 1.0) 范围
- [ ] 添加调试模式显示热区边界

### 2. 不同图片模式的处理

| 模式 | 处理方式 | 说明 |
|------|----------|------|
| `.fit` | GeometryReader 包裹图片 | 图片保持比例，可能不填满 frame |
| `.fill` | 显式计算尺寸 | 图片填满 frame，可能被裁剪 |
| 固定尺寸 | 直接使用 | 无需特殊处理 |

### 3. 调试技巧

```swift
@State private var showDebugHotspots: Bool = false

// 在 Button label 中
if showDebugHotspots {
    Rectangle()
        .fill(Color.red.opacity(0.3))
        .border(Color.red, width: 2)
} else {
    Color.black.opacity(0.001)
        .contentShape(Rectangle())
}
```

## Case 2：上层交互层拦截

### 问题现象

- 无新手引导时，House 首次进入后的「马上来财」热区可点击。
- 有新手引导时，高亮框位置正确，但点击被拦掉，用户体感为“看得到点不到”。
- 临时关闭悬浮宠物整层交互后，无引导场景恢复正常。

### 根本原因

#### 1. 全局悬浮手势层覆盖过大

`PetOverlayView` 曾把 `DragGesture(minimumDistance: 0)` 直接挂在整屏 `GeometryReader/ZStack` 根上。  
这种写法会让悬浮宠物不仅能从自己本体附近起手，也会和底层 House 热区竞争命中。

#### 2. 顶层引导窗口的命中模型被误解

`GuidePassThroughWindow` 使用的是“交互白名单”模型：

- 没有被登记到 `guideInteractiveRegions` 的区域，顶层 window 直接返回 `nil`。
- 被登记到白名单的区域，实际是**由引导层自己的 view 接住点击**。

这意味着：

- “挖空 + 高亮框”本身不会自动把点击转发给主窗口里的业务控件。
- 如果某个步骤要求用户点击高亮区域，就必须在引导层自己放一个透明按钮或透明点击层，并注册 `captureGuideInteractionRegion`。

### 已落地修复

#### 1. 收窄悬浮宠物交互区域

- 去掉整屏根容器上的手势。
- 改为只在宠物本体附近挂一个透明命中框。
- 结果：无引导场景下，House 热区不再被悬浮层拦截。

#### 2. 在引导层为 Wealth step2 补透明热点

- 在 `wealthStep2Content` 的高亮框位置额外放一个透明按钮。
- 按钮直接触发与底层一致的真实导航事件：`.navigateToSmallWorldDestination(destination: .wealth(nil))`
- 同时注册 `captureGuideInteractionRegion("feature.wealth.entry.hotspot")`
- 结果：有引导场景下，用户点击高亮框也能正常进入来财。

### 这类问题的排查顺序

1. 先确认底层热区按钮是否真的收到点击日志。
2. 再确认是否存在全局悬浮手势层抢事件。
3. 若只在引导显示时失效，优先检查：
   - 当前步骤是否只画了高亮，没有引导层透明交互区；
   - 是否误以为“挖空”就等于“底层可点击”。

### 针对 House / 引导的最佳实践补充

- 全局悬浮组件的 `TapGesture` / `DragGesture` 默认只挂在视觉本体附近，禁止挂整屏根容器。
- 运行在顶层引导 window 的点击步骤，必须明确选一种模式：
  - 只讲解：全部 `allowsHitTesting(false)`
  - 可点击：引导层自己提供透明热点，并触发真实业务动作
- 不要把“交互白名单”理解成“自动穿透到底层业务控件”。
- 当用户反馈“无引导正常，有引导失效”时，第一优先级不是调热区坐标，而是检查顶层引导 window 的交互设计。

## 经验教训

1. **GeometryReader 的位置很重要**：放在图片外层获取图片尺寸，放在 overlay 内获取容器尺寸
2. **`.fit` vs `.fill`**：`.fit` 需要特殊处理，`.fill` 可以直接使用 frame 尺寸
3. **向后兼容**：组件修改时保持向后兼容，避免影响其他调用方
4. **调试模式**：添加可视化调试功能，方便定位热区问题
5. **先分“坐标错”还是“事件被挡”**：两类问题现象相似，但修法完全不同
6. **顶层 window 的点击语义要说清楚**：白名单 != 自动穿透
7. **全局手势默认高风险**：挂在根容器上时，最容易制造“首进某页点不动”的隐性回归

## 后续建议

1. 统一项目中的热区实现方式
2. 统一项目中的“引导层透明热点”实现方式，避免每个步骤重复造按钮
3. 为 House 热区补两组回归用例：无引导、引导 step2
4. 考虑提取通用热区组件到 UI 组件库
