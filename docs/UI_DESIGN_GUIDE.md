# iOS 26 液态玻璃 UI 设计规范 (Liquid Glass Design System)

## 1. 设计理念
**“Liquid Glass” (液态玻璃)** 是对 Glassmorphism 的演进，强调：
*   **流动性 (Fluidity)**：界面元素如同液态般顺滑流动，转场动画无缝衔接。
*   **通透感 (Translucency)**：多层级的高斯模糊 (Gaussian Blur)，模拟真实玻璃的光学折射。
*   **深度 (Depth)**：通过光影、模糊层级来构建 Z 轴深度，而非传统的投影。

## 2. 核心组件规范

### 2.1 材质 (Materials)
在 SwiftUI 中，我们将定义几种核心材质：

*   **GlassBackground**:
    *   `Material.ultraThin` (iOS原生) + 白色/粉色微透明覆盖层 (Opacity 0.1)。
    *   背景模糊半径：20pt。
    *   混合模式：Overlay。
*   **LiquidCard**:
    *   用于列表项或卡片。
    *   填充：线性渐变 (TopLeading 白色 0.2 -> BottomTrailing 白色 0.05)。
    *   边框：1px 描边，白色 0.3 透明度，模拟玻璃边缘高光。
    *   圆角：Continuous, 24pt。

### 2.2 色彩系统 (Color Palette)
基于 少女心愿 主题：

*   **Primary Pink**: `#FFB6C1` (浅粉红) - 用于高亮、按钮背景。
*   **Secondary Purple**: `#E6E6FA` (薰衣草紫) - 用于渐变辅助。
*   **Glass White**: `#FFFFFF` (纯白) - 不同透明度用于构建玻璃感。
*   **Text Dark**: `#333333` (深灰) - 保证阅读对比度。
*   **Text Light**: `#8E8E93` (系统灰) - 辅助信息。

### 2.3 排版 (Typography)
*   **Title**: SF Pro Rounded, Heavy, 34pt.
*   **Headline**: SF Pro Rounded, Bold, 20pt.
*   **Body**: SF Pro Text, Regular, 17pt.
*   **Caption**: SF Pro Text, Medium, 13pt (全大写，字间距加宽)。

### 2.4 交互动效
*   **按压反馈**：卡片按下时，Scale 0.98，模糊度增加，仿佛按入水中。
*   **页面切换**：Hero 动画，图片元素无缝放大过渡。

## 3. UI 原型参考描述
(基于用户提供的截图进行风格化升级)

*   **表单页**：背景不是纯白，而是带有流动光斑的浅灰背景。输入框采用“凹陷”或“全透明玻璃”效果，不再有生硬的边框。
*   **图片选择器**：选中的图片悬浮在玻璃层之上，带有细腻的投影。
*   **开关控件**：液态流体开关，开启时填充色如同液体注满。

## 4. SwiftUI 实现片段示例

```swift
struct GlassCard<Content: View>: View {
    var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
            
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            
            content
        }
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}
```
