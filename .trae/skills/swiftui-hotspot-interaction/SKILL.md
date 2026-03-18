---
name: "swiftui-hotspot-interaction"
description: "SwiftUI 图片热区交互实现指南。Invoke when implementing clickable hotspots on images with aspect ratio constraints, or when hotspot click areas are misaligned/not working."
---

# SwiftUI 热区交互技能

## 概述

本技能用于在 SwiftUI 中实现图片热区交互，解决因图片缩放模式（`.fit`/`.fill`）导致的热区坐标计算错误问题。

## 何时调用

- 实现图片上的可点击热区
- 热区点击位置偏移或无法点击
- 图片使用 `.aspectRatio(contentMode: .fit)` 模式
- 需要处理不同屏幕尺寸下的热区适配

## 核心问题

### 问题描述

当图片使用 `.aspectRatio(contentMode: .fit)` 时：
- 图片保持宽高比，可能不会填满整个 frame
- `GeometryReader` 获取的是容器尺寸，而非图片实际显示尺寸
- 热区坐标计算错误，导致点击位置偏移

### 错误示例

```swift
// ❌ 错误：GeometryReader 获取的是 overlay 尺寸，不是图片实际尺寸
Image("background")
    .resizable()
    .aspectRatio(contentMode: .fit)
    .overlay(
        GeometryReader { geo in  // geo.size 是 frame 尺寸，不是图片尺寸
            HotspotButton(position: geo.size)
        }
    )
```

## 解决方案

### 方案一：GeometryReader 包裹图片（推荐）

适用于图片使用 `.fit` 模式的场景。

```swift
struct ImageWithHotspots: View {
    let hotspots: [HotspotData]
    
    var body: some View {
        GeometryReader { imageGeo in
            Image("background")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay(
                    HotspotOverlay(
                        hotspots: hotspots,
                        containerSize: imageGeo.size  // 传递图片实际尺寸
                    )
                )
        }
    }
}

struct HotspotOverlay: View {
    let hotspots: [HotspotData]
    let containerSize: CGSize
    
    var body: some View {
        ForEach(hotspots) { hotspot in
            Button(action: hotspot.action) {
                Color.black.opacity(0.001)  // 极低透明度确保可点击
                    .contentShape(Rectangle())
            }
            .frame(
                width: hotspot.rect.width * containerSize.width,
                height: hotspot.rect.height * containerSize.height
            )
            .position(
                x: (hotspot.rect.minX + hotspot.rect.width/2) * containerSize.width,
                y: (hotspot.rect.minY + hotspot.rect.height/2) * containerSize.height
            )
        }
    }
}
```

### 方案二：显式计算尺寸

适用于已知图片原始尺寸的场景。

```swift
struct ImageWithHotspots: View {
    @State private var imageSize = CGSize(width: 1919, height: 1079)
    
    var body: some View {
        GeometryReader { geometry in
            // 计算图片实际显示尺寸
            let displayWidth = geometry.size.height * (imageSize.width / imageSize.height)
            let displayHeight = geometry.size.height
            
            Image("background")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .overlay(
                    HotspotContent(
                        size: CGSize(width: displayWidth, height: displayHeight)
                    )
                )
        }
    }
}
```

### 方案三：兼容两种尺寸获取方式

适用于组件需要支持多种调用方式。

```swift
struct HotspotOverlay: View {
    var geometry: GeometryProxy? = nil
    var containerSize: CGSize? = nil
    
    // 统一获取尺寸
    private var size: CGSize {
        containerSize ?? geometry?.size ?? CGSize(width: 100, height: 100)
    }
    
    var body: some View {
        // 使用 size 进行布局
        Button(action: {}) {
            Color.clear.contentShape(Rectangle())
        }
        .frame(width: size.width * 0.1, height: size.height * 0.1)
    }
}
```

## 热区数据定义

```swift
struct HotspotData: Identifiable {
    let id = UUID()
    let name: String
    let rect: CGRect  // 归一化坐标 (0.0 - 1.0)
    let action: () -> Void
    var label: String? = nil
    var labelPosition: CGPoint? = nil
}

// 使用示例
let hotspots = [
    HotspotData(
        name: "按钮1",
        rect: CGRect(x: 0.35, y: 0.53, width: 0.08, height: 0.19),
        action: { print("点击按钮1") },
        label: "点击这里",
        labelPosition: CGPoint(x: 0.41, y: 0.725)
    )
]
```

## 调试技巧

### 1. 显示热区边界

```swift
@State private var showDebugHotspots: Bool = false

Button(action: hotspot.action) {
    if showDebugHotspots {
        Rectangle()
            .fill(Color.red.opacity(0.3))
            .border(Color.red, width: 2)
    } else {
        Color.black.opacity(0.001)
            .contentShape(Rectangle())
    }
}
```

### 2. 添加点击日志

```swift
Button(action: {
    print("[Hotspot] 点击: \(hotspot.name), 坐标: (\(hotspot.rect.minX), \(hotspot.rect.minY))")
    hotspot.action()
}) {
    // ...
}
```

## 常见陷阱

| 陷阱 | 问题 | 解决方案 |
|------|------|----------|
| 使用 `Color.clear` | 可能无法接收点击事件 | 使用 `Color.black.opacity(0.001)` |
| 忘记 `.contentShape(Rectangle())` | 点击区域可能不正确 | 显式设置 contentShape |
| `GeometryReader` 嵌套过深 | 获取到错误的尺寸 | 直接在图片外层使用 GeometryReader |
| 归一化坐标计算错误 | 热区位置偏移 | 确保 rect 是 (x, y, width, height) 格式 |

## 检查清单

- [ ] 热区使用 `Color.black.opacity(0.001)` 而非 `Color.clear`
- [ ] 添加 `.contentShape(Rectangle())` 确保点击区域
- [ ] 使用 `GeometryReader` 获取图片实际显示尺寸
- [ ] 将尺寸传递给热区组件，避免重复获取
- [ ] 归一化坐标使用 (0.0 - 1.0) 范围
- [ ] 添加调试模式显示热区边界
- [ ] 测试不同屏幕尺寸和方向

## 相关技能

- `swiftui-theme-adaptation` - 主题色适配
- `swiftui-config-management` - 配置管理
