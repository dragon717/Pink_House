---
name: "swiftui-theme-adaptation"
description: "SwiftUI主题色适配技能。当需要为SwiftUI视图添加魔法配色主题支持、适配暗黑模式、统一颜色管理时调用。包含ThemeManager使用、颜色映射、卡片背景、边框样式等最佳实践。"
---

# SwiftUI 主题色适配技能

## 概述

本技能用于将 SwiftUI 视图适配到魔法配色主题系统，确保界面在不同主题色下保持一致性和美观性。

## 何时调用

- 为新页面/组件添加主题色支持
- 修改现有视图的颜色适配
- 统一项目中的颜色管理
- 添加暗黑模式支持
- 创建可复用的主题化组件

## 核心概念

### 1. ThemeManager 颜色体系

```swift
@Environment(ThemeManager.self) private var themeManager
```

| 属性 | 用途 | 适用场景 |
|------|------|----------|
| `primaryTextColor` | 主要文字 | 标题、重要内容 |
| `secondaryTextColor` | 次要文字 | 描述、提示信息 |
| `tertiaryTextColor` | 辅助文字 | 禁用状态、次要按钮 |
| `accentTextColor` | 强调色 | 图标、按钮、选中状态、进度条 |
| `cardBackgroundColor` | 卡片背景 | 容器、列表项、统计卡片 |

### 2. 暗黑模式适配

```swift
@Environment(\.colorScheme) private var colorScheme

// 根据模式调整透明度
.background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.6 : 0.8))
```

### 3. 标准卡片样式

```swift
.background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.6 : 0.8))
.cornerRadius(16)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
)
```

## 适配步骤

### 步骤 1: 注入 ThemeManager

```swift
struct MyView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme  // 如需暗黑模式适配
    // ...
}
```

### 步骤 2: 替换硬编码颜色

**Before:**
```swift
Text("标题")
    .foregroundColor(.primary)

.background(Color.gray.opacity(0.1))
```

**After:**
```swift
Text("标题")
    .foregroundStyle(themeManager.primaryTextColor)

.background(themeManager.cardBackgroundColor.opacity(0.5))
```

### 步骤 3: 适配容器背景

**列表项示例:**
```swift
HStack {
    // 内容
}
.padding(.vertical, 12)
.padding(.horizontal, 16)
.background(
    RoundedRectangle(cornerRadius: 16)
        .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.6 : 0.8))
)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
)
```

**统计卡片示例:**
```swift
VStack {
    // 内容
}
.padding()
.background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.5 : 0.8))
.cornerRadius(16)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
)
```

### 步骤 4: 适配子组件

对于可复用组件，注入 ThemeManager:

```swift
struct MyComponent: View {
    @Environment(ThemeManager.self) private var themeManager
    // ...
}
```

## 颜色映射规范

### 文字颜色

| 元素 | 颜色 |
|------|------|
| 标题/主要文字 | `themeManager.primaryTextColor` |
| 描述/副标题 | `themeManager.secondaryTextColor` |
| 禁用/提示 | `themeManager.tertiaryTextColor` |
| 强调/选中 | `themeManager.accentTextColor` |

### 图标颜色

| 状态 | 颜色 |
|------|------|
| 正常图标 | `themeManager.accentTextColor` |
| 次要图标 | `themeManager.secondaryTextColor` |
| 禁用图标 | `themeManager.tertiaryTextColor` |

### 按钮颜色

| 类型 | 颜色 |
|------|------|
| 主要按钮背景 | `themeManager.accentTextColor` |
| 次要按钮 | `themeManager.secondaryTextColor` |
| 危险/删除 | `themeManager.tertiaryTextColor` |

### 进度条/图表

| 元素 | 颜色 |
|------|------|
| 进度条填充 | `themeManager.accentTextColor` |
| 进度条背景 | `themeManager.secondaryTextColor.opacity(0.2)` |
| 图表线条 | `themeManager.accentTextColor` |
| 图表填充 | `themeManager.accentTextColor.opacity(0.3)` |

## 常见场景

### 场景 1: List 中的卡片项

```swift
List {
    ForEach(items) { item in
        ItemRow(item: item)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.6 : 0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.vertical, 4)
            )
    }
}
.scrollContentBackground(.hidden)
```

### 场景 2: 统计卡片

```swift
VStack(alignment: .leading, spacing: 16) {
    Label("统计标题", systemImage: "chart")
        .font(.headline)
        .foregroundStyle(themeManager.accentTextColor)
    
    // 内容
}
.padding()
.background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.5 : 0.8))
.cornerRadius(16)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
)
```

### 场景 3: 子组件（StatBox、ItemRow 等）

```swift
struct StatBox: View {
    let title: String
    let value: String
    let color: Color
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack {
            Text(title)
                .foregroundStyle(themeManager.secondaryTextColor)
            Text(value)
                .foregroundStyle(color)  // 传入的颜色
        }
        .padding()
        .background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.accentTextColor.opacity(0.1), lineWidth: 1)
        )
    }
}
```

## 注意事项

1. **始终注入 ThemeManager**: 不要在视图间传递颜色，统一通过环境注入
2. **保持透明度一致**: 暗黑模式下使用 0.6，亮色模式下使用 0.8
3. **添加边框**: 卡片建议添加 `accentTextColor.opacity(0.15)` 的细边框
4. **圆角统一**: 大卡片使用 16，小盒子使用 12
5. **隐藏默认背景**: List 使用 `.scrollContentBackground(.hidden)`

## 检查清单

- [ ] 注入 `@Environment(ThemeManager.self)`
- [ ] 注入 `@Environment(\.colorScheme)`（如需暗黑模式适配）
- [ ] 替换所有 `.foregroundColor(.primary)` → `.foregroundStyle(themeManager.primaryTextColor)`
- [ ] 替换所有 `.foregroundColor(.secondary)` → `.foregroundStyle(themeManager.secondaryTextColor)`
- [ ] 替换所有 `.foregroundColor(.gray)` → `.foregroundStyle(themeManager.tertiaryTextColor)`
- [ ] 替换所有强调色 → `themeManager.accentTextColor`
- [ ] 替换所有背景色 → `themeManager.cardBackgroundColor`
- [ ] 添加圆角和边框
- [ ] 检查暗黑模式下的显示效果
