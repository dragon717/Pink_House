---
name: "swiftui-theme-adaptation"
description: "SwiftUI 主题色适配技能。当需要为 SwiftUI 视图添加魔法配色主题支持、适配暗黑模式、统一颜色管理时调用。包含 ThemeManager 使用、颜色映射、卡片背景、边框样式等最佳实践。"
---

# SwiftUI 主题色适配最佳实践

## 核心原则

1. **背景层分离**：预览区域和设置区域应使用独立的背景层，避免遮罩冲突
2. **颜色统一管理**：通过 ThemeManager 集中管理所有主题相关颜色
3. **暗黑模式适配**：所有颜色配置必须同时支持亮色和暗色模式
4. **遮罩局部化**：灰色遮罩只应用于特定预览区域，不应影响全局

## 主题背景实现

### 正确的背景层结构

```swift
// ✅ 推荐：在 NavigationStack 内使用 ZStack 分离背景和内容
var body: some View {
    NavigationStack {
        ZStack {
            // 底层背景 - 使用主题背景
            themeBackground
            
            // 上层内容
            VStack {
                ThemePreviewSection()
                ScrollView { ... }
            }
        }
        .navigationTitle("主题配色")
    }
}

// 主题背景视图
private var themeBackground: some View {
    Group {
        switch themeManager.backgroundStyle {
        case .color:
            themeManager.backgroundColor
        case .image:
            if let image = themeManager.backgroundImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // 没有图片时回退到背景色，避免黑色区域
                themeManager.backgroundColor
            }
        }
    }
    .ignoresSafeArea() // 填充整个屏幕包括安全区域
}
```

### 避免的错误

```swift
// ❌ 错误：在 VStack 外部使用 .background() 可能导致内容区域外出现黑色
VStack { ... }
    .background(LiquidBackground()) // 包含全局模糊遮罩

// ❌ 错误：没有回退颜色导致黑色区域
case .image:
    if let image = themeManager.backgroundImage {
        Image(uiImage: image).resizable().scaledToFill()
    } else {
        Color.black // 会产生黑色区域！
    }
```

## 预览区域遮罩

### 局部遮罩实现

```swift
// ✅ 推荐：在预览区域内部使用 ZStack 实现局部遮罩
struct ThemePreviewSection: View {
    var body: some View {
        VStack {
            // 标签
            HStack { ... }
            
            // 带遮罩的预览卡片
            ZStack {
                // 灰色遮罩 - 只覆盖预览区域
                Color.black
                    .opacity(themeManager.backgroundStyle == .image ? 0.3 : 0.1)
                
                TabView { ... }
                    .tabViewStyle(.page(indexDisplayMode: .always))
            }
            .frame(height: 180)
            
            // 图例
            HStack { ... }
        }
        // 不要添加额外的背景层
    }
}
```

## 颜色映射到语义化 UI

### MagicThemePalette 使用

```swift
// 定义完整的语义化颜色系统
struct MagicThemePalette {
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accent: Color
    
    let cardBackground: Color
    let cardAccent: Color
    
    let navigationBackground: Color
    let navigationForeground: Color
    
    let segmentedBackground: Color           // ✅ 必须定义
    let segmentedSelectedBackground: Color   // ✅ 必须定义
    let segmentedSelectedForeground: Color
    
    // ... 其他颜色
}

// 在构建 palette 时，确保所有字段都有定义
enum MagicThemeDesignSystem {
    static func palette(themeManager: ThemeManager, colorScheme: ColorScheme) -> MagicThemePalette {
        let isDark = colorScheme == .dark
        let theme = themeManager.themeColorConfig.currentTheme(forDarkMode: isDark)
        let card = theme.cardColors(forDarkMode: isDark)
        let cardBackground = card.backgroundRGBA.color
        let cardAccent = card.accentRGBA.color
        
        // ✅ 定义所有需要的颜色变量
        let segmentedBackground = cardBackground.opacity(isDark ? 0.46 : 0.72)
        let segmentedSelectedBackground = cardBackground.mixed(with: .white, amount: isDark ? 0.08 : 0.18)
        
        return MagicThemePalette(
            primaryText: ...,
            segmentedBackground: segmentedBackground,           // ✅ 使用定义的变量
            segmentedSelectedBackground: segmentedSelectedBackground, // ✅ 使用定义的变量
            ...
        )
    }
}
```

## 常见问题排查

### 问题 1：出现黑色/灰色区域
**症状**：视图底部或边缘出现黑色区域
**原因**：
- 背景没有使用 `.ignoresSafeArea()`
- 图片背景为空时返回 `Color.black`
- 使用了包含全局模糊的 `LiquidBackground()`

**解决**：
1. 确保背景视图使用 `.ignoresSafeArea()`
2. 图片为空时回退到 `themeManager.backgroundColor`
3. 避免在设置页面使用 `LiquidBackground()`

### 问题 2：遮罩覆盖范围错误
**症状**：灰色遮罩超出了预览区域
**原因**：
- 遮罩放在了外层 ZStack
- 遮罩高度设置不当

**解决**：
1. 将遮罩限制在预览区域的 ZStack 内部
2. 使用固定高度 `.frame(height: 180)` 控制范围

### 问题 3：编译错误 "Cannot find X in scope"
**症状**：MagicThemePalette 初始化时报错
**原因**：缺少字段定义

**解决**：
1. 检查 `MagicThemePalette` 结构体定义的所有字段
2. 确保 `palette()` 函数中为每个字段都提供了值
3. 对于计算型字段，先定义局部变量再使用

### 问题 4：色调强度不生效（重要！）
**症状**：修改"色调强度"滑块时，卡片背景没有实时变化
**根本原因**：项目中存在**两种**色调实现方式，修改时只改了部分组件

**两种实现方式**：
1. **纯色调模式**（推荐）：`magicCardBackgroundColor.opacity(themeManager.tintOpacity)`
2. **毛玻璃+色调叠加**：`.ultraThinMaterial` + 叠加色调层

**排查步骤**：
1. **先全面检查**：使用 grep 搜索所有 `tinted`、`cardStyle`、`tintOpacity` 相关代码
2. **确定标准**：以 `ThemePreviewSection` 或 `CardBackgroundView` 为准
3. **统一修改**：确保所有相关组件使用相同的实现方式
4. **验证颜色来源**：
   - ✅ 正确：`magicCardBackgroundColor` 或 `cardColors.backgroundRGBA.color`
   - ❌ 错误：`themeManager.cardTintColor`（这是色调色，不是背景色）

**相关文件清单**：
- `CardBackgroundView.swift` - 核心组件（纯色调模式）
- `ThemePreviewSection.swift` - 预览标准（纯色调模式）
- `MeView.swift` - 魔法任务卡片（毛玻璃+色调）
- `SettingsGridItem.swift` - 设置网格项（毛玻璃+色调）
- `MagicThemeDesignSystem.swift` - 页签背景

**最佳实践**：
- 优先使用 `CardBackgroundView` 统一实现
- 必须直接绑定 `themeManager.tintOpacity`
- 修改前全面检查，避免增量修改导致不一致

## 暗黑模式适配要点

```swift
// ✅ 推荐：所有颜色都区分明暗模式
let opacity = isDark ? 0.46 : 0.72
let mixedAmount = isDark ? 0.08 : 0.18

// 使用三元表达式确保一致性
Color.black.opacity(isDark ? 0.3 : 0.1)
```

## 文件组织

当文件超过 500 行时，按功能拆分：
- `MagicColorSettingsView.swift` - 主视图
- `ThemePreviewSection.swift` - 预览组件
- `ColorSettingsComponents.swift` - 共享组件
- `MagicThemeDesignSystem.swift` - 颜色映射系统
