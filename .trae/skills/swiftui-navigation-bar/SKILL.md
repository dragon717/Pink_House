---
name: "swiftui-navigation-bar"
description: "SwiftUI navigation bar height control and layout optimization. Invoke when using .principal placement causes extra spacing, or when navigation bar height needs adjustment."
---

# SwiftUI 导航栏高度控制技能

## 问题场景

当使用 `.principal` placement 在导航栏中间放置自定义视图时，导航栏会默认采用 **large title 模式**，导致导航栏高度增加，从而在导航栏和内容之间产生额外的空白区域。

## 典型症状

- 使用 `.principal` 放置标签切换器或自定义标题
- 导航栏下方出现大块空白
- 经典样式（使用 `.topBarLeading`）正常，时尚样式（使用 `.principal`）出现空白

## 解决方案

### 方法 1：使用 Inline 模式（推荐）

```swift
.toolbar {
    ToolbarItem(placement: .principal) {
        CustomTabSwitcher()
    }
}
.navigationBarTitleDisplayMode(.inline)  // 强制紧凑模式
```

### 方法 2：调整自定义视图高度

```swift
ToolbarItem(placement: .principal) {
    CustomTabSwitcher()
        .frame(height: 36)  // 固定高度
}
```

### 方法 3：使用 TopBarLeading 替代

```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        CustomTabSwitcher()
    }
}
```

> ⚠️ 注意：此方法会改变布局，标签切换器会靠左对齐而非居中

## 导航栏模式对比

| 模式 | 配置 | 高度 | 适用场景 |
|------|------|------|----------|
| Large Title | 默认（使用 `.principal`） | 较大（约 96pt） | 需要突出标题的页面 |
| Inline | `.navigationBarTitleDisplayMode(.inline)` | 紧凑（约 44pt） | 自定义导航栏内容 |

## 最佳实践

### 1. 时尚样式布局

```swift
struct HomeView: View {
    var body: some View {
        NavigationStack {
            // 内容
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // 左侧按钮
            }
            
            ToolbarItem(placement: .principal) {
                // 中间标签切换器
                FashionTabSwitcher()
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                // 右侧按钮
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)  // 关键：避免额外空白
    }
}
```

### 2. 经典样式布局

```swift
.toolbar {
    ToolbarItem(placement: .topBarLeading) {
        // 标签切换器在左侧
        TabSwitcher()
    }
    
    ToolbarItem(placement: .topBarTrailing) {
        // 操作按钮在右侧
        ActionButtons()
    }
}
// 不需要 .navigationBarTitleDisplayMode，因为不使用 .principal
```

## 检查清单

- [ ] 使用 `.principal` placement 时，添加 `.navigationBarTitleDisplayMode(.inline)`
- [ ] 自定义视图有固定高度，避免导航栏高度不确定
- [ ] 对比经典样式和时尚样式，确保布局一致
- [ ] 测试不同 iOS 版本的显示效果

## 常见错误

### 错误 1：忘记添加 inline 模式

```swift
// ❌ 错误：使用 .principal 但没有设置 inline 模式
.toolbar {
    ToolbarItem(placement: .principal) {
        CustomView()
    }
}
// 结果：导航栏高度过大，出现空白
```

### 错误 2：在子视图中设置

```swift
// ❌ 错误：在子视图中设置，可能被父视图覆盖
struct ChildView: View {
    var body: some View {
        Content()
            .navigationBarTitleDisplayMode(.inline)  // 可能不生效
    }
}

// ✅ 正确：在 NavigationStack 层级设置
struct ParentView: View {
    var body: some View {
        NavigationStack {
            ChildView()
                .navigationBarTitleDisplayMode(.inline)  // 生效
        }
    }
}
```

## 相关技能

- `swiftui-theme-adaptation` - SwiftUI 主题色适配
- `swiftui-config-management` - SwiftUI 配置统一管理
