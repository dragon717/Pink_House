# 液态玻璃与云母色调 UI 技术实现指南

## 1. 概述
本文档详细说明了 ItemManager 项目中 **“液态玻璃 (Liquid Glass)”** 和 **“亚克力云母 (Acrylic Mica)”** 两种高级 UI 材质的设计理念与技术实现。这两种风格旨在为用户提供现代、通透且具有物理质感的视觉体验，同时完美适配 iOS 的 Light/Dark 模式。

## 2. 材质定义

### 2.1 液态玻璃 (Liquid Glass)
*   **视觉特征**: 极致的通透感，仿佛一层极薄的水膜或悬浮的玻璃片。强调背景的模糊透射和边缘的高光折射。
*   **适用场景**: 需要展示丰富背景（如壁纸）的场景，追求轻量化、呼吸感的界面。
*   **核心材质**: `Material.ultraThin` (SwiftUI)
*   **关键参数**:
    *   **整体不透明度 (Transparent Opacity)**: 控制玻璃的“存在感”，范围 0% - 100%。

### 2.2 亚克力云母 (Acrylic Mica)
*   **视觉特征**: 柔和的半透明磨砂质感，带有特定的色调倾向（如淡粉色）。比玻璃更厚重，更注重氛围渲染和信息承载。
*   **适用场景**: 需要色彩氛围，或者需要更高对比度来突出内容的场景。
*   **核心材质**: `Material.regular` (SwiftUI)
*   **关键参数**:
    *   **色调浓度 (Tint Opacity)**: 控制叠加颜色的深浅，范围 10% - 80%。
    *   **色调颜色 (Tint Color)**: 自定义叠加层的颜色（默认为淡粉色 `#FFB6C1`）。

## 3. 技术架构

### 3.1 状态管理 (ThemeManager)
所有样式配置由单例 `ThemeManager` 统一管理，支持持久化存储。

```swift
enum CardStyle: String, CaseIterable, Identifiable {
    case transparent // 液态玻璃
    case tinted      // 亚克力云母
    case solid       // 经典纯色
}

class ThemeManager {
    // 独立控制参数
    var transparentOpacity: Double = 1.0 // 默认全不透明度
    var tintOpacity: Double = 0.2        // 默认 20% 浓度
    var cardTintColorHex: String = "#FFB6C1" // 默认淡粉色
}
```

### 3.2 核心组件 (CardBackgroundView)
我们将背景渲染逻辑封装为独立的 SwiftUI 视图 `CardBackgroundView`，以实现 `ClothingCard` (业务组件) 和 `GeneralSettingsView` (预览组件) 的复用。

**文件路径**: `ItemManager/Components/CardBackgroundView.swift`

## 4. 详细实现与 Dark Mode 适配

### 4.1 液态玻璃实现
使用 `ZStack` 叠加层：
1.  **模糊层**: `Rectangle().fill(.ultraThinMaterial)` (若开启模糊)。
2.  **回退层**: `Color.white`，通过透明度模拟玻璃质感（适配非模糊环境）。
    *   *Light Mode*: Opacity 0.1
    *   *Dark Mode*: Opacity 0.05 (避免在深色背景上过亮)
3.  **描边层**: `LinearGradient` 模拟边缘高光。
    *   *Light Mode*: White 0.4 -> 0.1
    *   *Dark Mode*: White 0.25 -> 0.05 (降低高光强度，防止刺眼)

```swift
case .transparent:
    ZStack {
        if themeManager.isBlurEnabled {
            Rectangle().fill(.ultraThinMaterial)
        } else {
            // Fallback: Lighten slightly in both modes
            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.1)
        }
    }
    .opacity(themeManager.transparentOpacity)
    .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.25 : 0.4),
                        .white.opacity(colorScheme == .dark ? 0.05 : 0.1)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    )
```

### 4.2 亚克力云母实现
1.  **模糊层**: `Rectangle().fill(.regularMaterial)` (使用标准材质，质感更厚)。
2.  **色调层**: `themeManager.cardTintColor` 叠加，透明度由 `tintOpacity` 控制。
3.  **描边层**: 使用同色系的渐变描边。
    *   *Light Mode*: TintColor 0.5 -> 0.1
    *   *Dark Mode*: TintColor 0.3 -> 0.05 (内敛辉光)

```swift
case .tinted:
    ZStack {
        if themeManager.isBlurEnabled {
            Rectangle().fill(.regularMaterial)
        } else {
            Color(uiColor: .systemBackground).opacity(0.5)
        }
        
        themeManager.cardTintColor
            .opacity(themeManager.tintOpacity)
    }
    .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        themeManager.cardTintColor.opacity(colorScheme == .dark ? 0.3 : 0.5),
                        themeManager.cardTintColor.opacity(colorScheme == .dark ? 0.05 : 0.1)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    )
```

## 5. 最佳实践

1.  **使用 `CardBackgroundView`**: 在任何需要应用该风格的容器上，使用 `.background { CardBackgroundView() }` 而非手动重写样式。
2.  **独立参数控制**: 不要混用透明度参数。玻璃风格调整整体透明度 (`transparentOpacity`)，云母风格调整颜色浓度 (`tintOpacity`)。
3.  **实时预览**: 在调整参数的设置页面，务必提供实时预览 (`CardBackgroundView` + 模拟背景)，因为材质效果高度依赖于背景环境。
4.  **性能优化**: 虽然 Material 效果很美，但在复杂列表（如 Grid 布局）中大量使用可能会有性能开销。目前的实现通过系统材质优化了性能，但在低端设备上应注意观察。
5.  **内容对比度**: 玻璃背景可能会降低前景文字的对比度。建议配合阴影或在文字下增加极其微弱的遮罩（如有必要），但在当前设计中，我们通过调整材质厚度和默认透明度已保证了较好的可读性。
