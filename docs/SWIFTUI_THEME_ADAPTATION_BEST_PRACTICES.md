# SwiftUI 主题色适配最佳实践

## 项目背景

本项目使用魔法配色主题系统，通过 `ThemeManager` 统一管理颜色，支持动态主题切换和暗黑模式适配。

## 核心架构

### ThemeManager 颜色体系

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

## 适配模式

### 模式一：视图级别适配

适用于页面级别的视图，直接在主视图中注入 ThemeManager。

```swift
struct MyView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            LiquidBackground()
                .ignoresSafeArea()
            
            ScrollView {
                VStack {
                    // 内容
                }
            }
        }
    }
}
```

### 模式二：组件级别适配

适用于可复用组件，每个组件独立注入 ThemeManager。

```swift
struct StatBox: View {
    let title: String
    let value: String
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack {
            Text(title)
                .foregroundStyle(themeManager.secondaryTextColor)
            Text(value)
                .foregroundStyle(themeManager.accentTextColor)
        }
        .padding()
        .background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.5))
        .cornerRadius(12)
    }
}
```

### 模式三：List 行级别适配

适用于 List 中的列表项，使用 `.listRowBackground()` 设置背景。

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

## 标准卡片样式

### 大卡片（统计卡片、设置卡片）

```swift
.padding()
.background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.5 : 0.8))
.cornerRadius(16)
.overlay(
    RoundedRectangle(cornerRadius: 16)
        .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
)
.shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
```

### 列表项卡片

```swift
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

### 小盒子（StatBox、数据展示）

```swift
.padding()
.background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.3 : 0.5))
.cornerRadius(12)
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(themeManager.accentTextColor.opacity(0.1), lineWidth: 1)
)
```

## 颜色映射表

### 文字颜色映射

| 原颜色 | 主题颜色 |
|--------|----------|
| `.primary` | `themeManager.primaryTextColor` |
| `.secondary` | `themeManager.secondaryTextColor` |
| `.gray` | `themeManager.tertiaryTextColor` |
| 强调色（如 `.pink`, `.brown`） | `themeManager.accentTextColor` |

### 背景颜色映射

| 原颜色 | 主题颜色 |
|--------|----------|
| `Color(uiColor: .secondarySystemGroupedBackground)` | `themeManager.cardBackgroundColor` |
| `Color(uiColor: .tertiarySystemGroupedBackground)` | `themeManager.cardBackgroundColor.opacity(0.5)` |
| `.ultraThinMaterial` | `themeManager.cardBackgroundColor.opacity(0.5)` |

### 图标颜色映射

| 状态 | 颜色 |
|------|------|
| 主要图标 | `themeManager.accentTextColor` |
| 次要图标 | `themeManager.secondaryTextColor` |
| 禁用图标 | `themeManager.tertiaryTextColor` |

## 暗黑模式适配

### 透明度规范

- **暗黑模式**: 使用 `opacity(0.6)` 或 `opacity(0.5)`
- **亮色模式**: 使用 `opacity(0.8)` 或 `opacity(0.5)`

### 代码示例

```swift
@Environment(\.colorScheme) private var colorScheme

.background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.6 : 0.8))
```

## 实际案例

### 案例 1: 魔法任务页面

```swift
struct MagicTaskRow: View {
    let feature: FeatureItem
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)
                
                Image(systemName: feature.icon)
                    .foregroundColor(iconColor)
            }
            
            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.displayName)
                    .foregroundColor(themeManager.primaryTextColor)
                
                Text(condition.description)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            // 状态
            statusView
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
    }
}
```

### 案例 2: 统计卡片

```swift
struct OverviewStatsCard: View {
    let clothings: [Clothing]
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("总览统计", systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundStyle(themeManager.accentTextColor)
            
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatBox(title: "总裙子数", value: "\(totalCount)", unit: "件")
                    StatBox(title: "总裙子价值", value: "¥\(formatPrice(dressValue))", unit: "")
                }
            }
        }
        .padding()
        .background(themeManager.cardBackgroundColor.opacity(colorScheme == .dark ? 0.5 : 0.8))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(themeManager.accentTextColor.opacity(0.15), lineWidth: 1)
        )
    }
}
```

### 案例 3: 常用菜单设置

```swift
struct FavoriteMenuSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        List {
            Section {
                ForEach(selectedAndUnlockedItems) { item in
                    SelectedItemRow(item: item, isEditing: isEditing)
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
            } header: {
                Text("已选中的常用功能")
                    .foregroundColor(themeManager.secondaryTextColor)
            }
        }
        .scrollContentBackground(.hidden)
    }
}
```

## 检查清单

在提交代码前，请确认以下事项：

- [ ] 所有视图已注入 `@Environment(ThemeManager.self)`
- [ ] 所有文字颜色使用 `themeManager.xxxTextColor`
- [ ] 所有背景使用 `themeManager.cardBackgroundColor`
- [ ] 所有强调色使用 `themeManager.accentTextColor`
- [ ] 已添加暗黑模式适配（`@Environment(\.colorScheme)`）
- [ ] 卡片已添加圆角（16 或 12）
- [ ] 卡片已添加边框（`accentTextColor.opacity(0.15)`）
- [ ] List 使用 `.scrollContentBackground(.hidden)`
- [ ] 编译通过，无警告

## 常见问题

### Q1: 为什么使用 `.foregroundStyle()` 而不是 `.foregroundColor()`？

A: `.foregroundStyle()` 是 SwiftUI 的现代 API，支持更丰富的样式定义，与 `ShapeStyle` 协议兼容更好。

### Q2: 如何处理传入的颜色参数？

A: 对于需要自定义颜色的组件（如 StatBox），保留 `color` 参数用于数值显示，但背景和文字仍使用 themeManager。

```swift
struct StatBox: View {
    let title: String
    let value: String
    let color: Color  // 用于数值颜色
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        VStack {
            Text(title)
                .foregroundStyle(themeManager.secondaryTextColor)  // 固定
            Text(value)
                .foregroundStyle(color)  // 传入的
        }
        .background(themeManager.cardBackgroundColor)  // 固定
    }
}
```

### Q3: 如何处理图表颜色？

A: 图表线条和填充使用 `themeManager.accentTextColor`，保持与主题一致。

```swift
Chart(data) { item in
    LineMark(
        x: .value("X", item.x),
        y: .value("Y", item.y)
    )
    .foregroundStyle(themeManager.accentTextColor)
}
```

## 相关文件

- `ItemManager/Services/ThemeManager.swift` - 主题管理器
- `.trae/skills/swiftui-theme-adaptation/SKILL.md` - 技能文档

## 更新记录

- 2025-03-09: 初始版本，总结魔法配色主题适配经验
