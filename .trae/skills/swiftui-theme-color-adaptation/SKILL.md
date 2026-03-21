---
name: "swiftui-theme-color-adaptation"
description: "SwiftUI 主题颜色适配最佳实践。Invoke when implementing theme-aware UI components, adapting colors for magic/custom color schemes, or fixing theme color display issues."
---

# SwiftUI 主题颜色适配最佳实践

## 概述

本技能总结了在魔法配色/客制化配色系统中正确适配主题颜色的方法和最佳实践，避免常见陷阱。

## 核心概念

### 1. 配置层次

系统有两套独立的配置：

```swift
// 配色模式 - 控制整体配色方案
enum ColorSchemeMode {
    case magic   // 魔法配色：基于背景色自动生成
    case custom  // 客制化配色：用户选择主题预设
}

// 萌宠对话皮肤 - 控制对话气泡的视觉风格
enum PetChatSkinTheme {
    case classic  // 经典皮肤：纯色（默认值）
    case magic    // 魔法皮肤：渐变 + 边框
}
```

**重要**：不要假设用户会修改默认值！始终处理默认配置的情况。

### 2. 颜色来源优先级

```swift
// ✅ 正确：使用 ThemeManager 提供的颜色
themeManager.cardBackgroundColor    // 卡片背景色
themeManager.cardTintColor          // 卡片强调色
themeManager.primaryTextColor       // 主文字色
themeManager.accentTextColor        // 强调色

// ❌ 错误：使用硬编码或系统颜色
Color(.systemBackground)
.primary
.pink
```

## 最佳实践

### 1. 统一颜色来源原则

**原则**：同一组件在不同地方应使用相同的颜色来源。

**示例**：

```swift
// ✅ 正确：主题预览页和 PetChatView 使用相同的颜色
// ThemePreviewSection.swift
.background(themeManager.cardBackgroundColor)

// PetChatView.swift
.background(themeManager.cardBackgroundColor)

// ❌ 错误：使用不同的颜色来源
// ThemePreviewSection.swift
.background(themeManager.cardBackgroundColor)

// PetChatView.swift
.background(Color(.systemBackground))  // 会导致暗黑模式下显示黑色
```

### 2. 经典皮肤适配主题配色

**原则**：经典皮肤也应适配主题配色，只是视觉效果不同。

**实现**：

```swift
@ViewBuilder
private func bubbleBackground(isUser: Bool) -> some View {
    if skinTheme == .classic {
        // 经典皮肤：使用纯色，但也要适配主题
        RoundedRectangle(cornerRadius: 16)
            .fill(themeManager.cardBackgroundColor)  // ✅ 使用主题卡片背景色
            .shadow(color: .black.opacity(0.05), radius: 4)
    } else {
        // 魔法皮肤：使用渐变 + 边框
        RoundedRectangle(cornerRadius: 16)
            .fill(
                LinearGradient(
                    colors: [bubbleStart, bubbleEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: assistantStrokeColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}
```

### 3. 对比验证法

**方法**：当组件在某处工作正常但在另一处不正常时，对比实现差异。

**步骤**：

1. **找到对照组**
   ```swift
   // 主题预览页 - 工作正常
   .background(themeManager.cardBackgroundColor)
   ```

2. **找到问题实现**
   ```swift
   // PetChatView - 显示黑色
   .background(Color(.systemBackground))  // ❌ 问题所在
   ```

3. **对比差异并修复**
   ```swift
   // 修改为与主题预览页一致
   .background(themeManager.cardBackgroundColor)  // ✅ 修复
   ```

### 4. 颜色来源追溯

**方法**：当颜色显示不正确时，追溯完整链路。

**示例链路**：

```
PetChatView.bubbleBackground()
  ↓
themeManager.cardBackgroundColor
  ↓
ThemeManager.cardBackgroundColor (getter)
  ↓
colorSchemeMode 判断
  ├─ .magic → generateMagicCardBackground()
  │            ↓
  │         基于 backgroundColor 智能生成
  │
  └─ .custom → themeColorConfig.currentTheme()
               ↓
            使用主题预设的卡片背景色
```

**验证步骤**：
1. 检查 getter 实现
2. 确认在不同配色模式下的返回值
3. 验证返回值是否符合预期

### 5. 默认值检查清单

在实现主题适配时，始终检查：

- [ ] 这个配置项的默认值是什么？
- [ ] 默认值在暗黑模式下会有什么问题？
- [ ] 是否需要特殊处理默认值的情况？
- [ ] 颜色来源是否统一使用 ThemeManager？

## 常见陷阱

### 陷阱 1：使用系统颜色

```swift
// ❌ 错误
.fill(Color(.systemBackground))  // 暗黑模式下是黑色

// ✅ 正确
.fill(themeManager.cardBackgroundColor)  // 始终是主题卡片背景色
```

### 陷阱 2：硬编码颜色

```swift
// ❌ 错误
.fill(.pink)  // 不会随主题变化

// ✅ 正确
.fill(themeManager.cardTintColor)  // 跟随主题强调色
```

### 陷阱 3：忽略默认配置

```swift
// ❌ 错误：假设用户会使用魔法皮肤
if skinTheme == .magic {
    // 只在魔法皮肤下适配
}

// ✅ 正确：处理所有情况，包括默认的经典皮肤
if skinTheme == .classic {
    // 经典皮肤也要适配主题
    .fill(themeManager.cardBackgroundColor)
} else {
    // 魔法皮肤使用渐变
}
```

### 陷阱 4：被表面现象迷惑

**现象**：气泡背景显示黑色

**错误假设**：
- ScrollView 背景覆盖
- 有额外的黑色遮罩
- 某个 overlay 导致的

**正确分析**：
- 检查气泡本身的背景色设置
- 追溯颜色来源
- 发现是 `Color(.systemBackground)` 在暗黑模式下就是黑色

## 调试技巧

### 1. 添加临时颜色标识

```swift
// 临时添加边框，确认视图范围
.background(themeManager.cardBackgroundColor)
.border(.red, width: 2)  // 临时调试用
```

### 2. 打印颜色值

```swift
let bgColor = themeManager.cardBackgroundColor
print("背景色：\(bgColor)")  // 确认颜色值
```

### 3. 对比不同配置下的值

```swift
// 在魔法配色模式下
print("魔法配色：\(themeManager.cardBackgroundColor)")

// 切换到客制化配色模式
print("客制化配色：\(themeManager.cardBackgroundColor)")
```

## 实施检查清单

在提交主题适配代码前，检查：

- [ ] 所有颜色都来自 ThemeManager
- [ ] 没有使用硬编码颜色或系统颜色
- [ ] 经典皮肤和魔法皮肤都适配了主题
- [ ] 魔法配色和客制化配色都正确工作
- [ ] 暗黑模式下的显示效果正确
- [ ] 与主题预览页的实现一致
- [ ] 检查了配置项的默认值
- [ ] 追溯了颜色的完整计算链路

## 相关资源

- 问题解决总结文档：`.trae/docs/萌宠气泡主题配色适配问题解决总结.md`
- ThemeManager 实现：`ItemManager/Services/ThemeManager.swift`
- 主题预览组件：`ItemManager/Views/Settings/ThemePreviewSection.swift`
- 萌宠对话视图：`ItemManager/Views/PetChat/PetChatView.swift`

## 总结

主题颜色适配的关键：

1. **统一颜色来源**：始终使用 ThemeManager 提供的颜色
2. **处理默认配置**：不要假设用户会修改默认值
3. **对比验证**：找到工作正常的实现作为对照
4. **追溯链路**：从使用点到源头完整追踪
5. **系统性排查**：不要过早下结论，逐一排除可能性

遵循这些原则可以避免 90% 的主题适配问题。
