# House 界面热区失效问题修复总结

## 问题描述

本文档沉淀两类容易混淆、但根因完全不同的 House 热区失效问题：

1. **图片几何尺寸错误**：热区坐标算错，表现为“点哪都不对”。
2. **上层交互层拦截**：热区本身没问题，但被全局手势层或引导顶层 window 挡住，表现为“无引导正常，有引导失效”或“首次进入才失效”。
3. **小入口命中体感差**：点击日志能进来，但用户仍觉得“点很多下才进去”，本质是视觉焦点和交互矩形脱节，常见于 Pro / Pro Max 这类不同尺寸机型。

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

## Case 3：小入口在不同机型上的命中体感差

### 问题现象

- `穿搭手帐`、`梦裙日历` 这类入口在日志里已经能看到按钮点击，但用户在真机上仍觉得“很难点进去”。
- 小尺寸 Pro 调好后，Pro Max 又变差，说明不是单纯的最小尺寸不够。
- 打开调试热区时“点到调试框有反应”，也进一步说明链路后半段并没有完全断。

### 根本原因

这类问题不是“事件没到”，而是“用户想点的位置”和“真正可点的位置”不一致：

1. 原始热区通常贴合物体本体，例如镜子、台历。
2. 用户实际会被悬浮文字标签、斜向文案、视觉重心吸引。
3. 只做**以热区中心为基准的对称放大**时，在大屏上往往还是不顺手，因为标签离本体更远，视觉重心漂移更明显。
4. 如果父层还挂了缩放/拖拽手势，未放大时也可能吞掉子按钮的抬手事件，进一步放大“很难点”的体感。

### 最终收敛思路

先把问题分成三层，再决定修法：

1. **几何错位**：看热区是否整体偏移。
2. **事件被挡**：看底层按钮日志是否完全打不出来。
3. **命中体感差**：日志能打出来，但用户还是觉得难点，这时优先修“交互矩形和视觉焦点的关系”。

针对 Rococo House，最终采用的是一套可复用的基础设施，而不是继续叠临时探针：

- 把热区统一抽成 `SmallWorldHotspotSpec`。
- 用 `SmallWorldImageLayout.aspectFitFrame(...)` 统一图片实际显示区域换算。
- 用 `SmallWorldHotspotHitPolicy` 区分：
  - `exact`
  - `expanded(...)`
  - `directional(...)`
- 用 `SmallWorldHotspotLabelSpec.hitPadding` 给“悬浮标签”额外生成一个共享 action 的透明点击区。
- Guide 采集锚点继续绑定在主交互热区上，避免高亮范围和业务命中区脱节。

### 为什么“标签热区”是关键

对于镜子、台历这类小入口，用户未必会精确点在物体本体上，很多时候其实是在点标签：

- `穿搭手帐` 的文字在镜子下方偏右。
- `梦裙日历` 的文字在台历下方。

因此最终不是只“把主热区继续放大”，而是：

1. 主热区改成**朝标签方向偏置扩展**。
2. 标签本身再补一个透明点击区，并触发同一个真实业务 action。

这样在 Pro 和 Pro Max 上都更稳，因为它尊重的是用户视觉焦点，而不是假设所有机型都适合同一组对称扩展值。

### 对应代码落点

- [RococoSmallWorldView.swift](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/RococoSmallWorldView.swift)
- [SmallWorldHotspotInfrastructure.swift](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/SmallWorldHotspotInfrastructure.swift)
- [MainTabView.swift](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/MainTabView.swift)

### 针对 House 小入口的最佳实践

- 先判断是“完全没收到点击”还是“收到了点击但仍难用”，这两类不要混修。
- 对细长入口，不要只追求 `44x44`，应按视觉形态给出更贴近场景的最小命中区，例如 `56x84`。
- 对块状入口，可以优先保证 `52x52` 到 `60x68` 这类更接近日常点按习惯的尺寸。
- 若标签与本体分离明显，优先用“方向性扩展 + 标签热区”，不要只做对称扩展。
- 缩放/拖拽容器默认高风险；未放大时，父手势应优先让子热区接收事件，例如使用 `including: .subviews`。
- 日志要能区分“主热区命中”还是“标签热区命中”，否则很难判断体感问题究竟出在哪一侧。
- 一旦确认根因，不要保留大面积 touch probe 或房间级临时探针，避免后续继续干扰判断。

## 经验教训

1. **GeometryReader 的位置很重要**：放在图片外层获取图片尺寸，放在 overlay 内获取容器尺寸
2. **`.fit` vs `.fill`**：`.fit` 需要特殊处理，`.fill` 可以直接使用 frame 尺寸
3. **向后兼容**：组件修改时保持向后兼容，避免影响其他调用方
4. **调试模式**：添加可视化调试功能，方便定位热区问题
5. **先分“坐标错”还是“事件被挡”**：两类问题现象相似，但修法完全不同
6. **顶层 window 的点击语义要说清楚**：白名单 != 自动穿透
7. **全局手势默认高风险**：挂在根容器上时，最容易制造“首进某页点不动”的隐性回归
8. **再补一层“体感错位”判断**：点击日志已经打出来时，不要再怀疑主线程；优先检查视觉标签、本体热区、父手势三者是否一致
9. **基础设施比临时探针更值钱**：把热区、标签、命中策略、引导锚点收敛到统一 spec，比不断在业务页里加 if debug 更可维护

## 后续建议

1. 统一项目中的热区实现方式
2. 统一项目中的“引导层透明热点”实现方式，避免每个步骤重复造按钮
3. 为 House 热区补两组回归用例：无引导、引导 step2
4. 继续让 French Retro / 其他 House 页面复用 `SmallWorldHotspotInfrastructure`
