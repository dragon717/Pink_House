# SwiftUI 导航栏自定义最佳实践

## 概述

本文档总结了在 SwiftUI 中自定义导航栏的最佳实践，特别是基于"马上来财"页面的实现经验。

## 核心实现模式

### 1. 基础结构

```swift
NavigationStack {
    ZStack {
        // 背景
        LiquidBackground()
            .ignoresSafeArea()
        
        // 内容
        VStack(spacing: 0) {
            // 主内容区域
            TabView(selection: $selectedTab) {
                ViewA().tag(Tab.a)
                ViewB().tag(Tab.b)
                ViewC().tag(Tab.c)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        leadingToolbarContent
        centerToolbarContent
        trailingToolbarContent
    }
}
```

### 2. Toolbar Placement 详解

| Placement | 用途 | 注意事项 |
|-----------|------|----------|
| `.topBarLeading` | 左上角按钮 | iOS 16+ 推荐使用 |
| `.navigationBarLeading` | 左上角按钮 | iOS 15 兼容 |
| `.principal` | 导航栏中央 | 用于标题或页签选择器 |
| `.topBarTrailing` | 右上角按钮 | iOS 16+ 推荐使用 |
| `.navigationBarTrailing` | 右上角按钮 | iOS 15 兼容 |
| `.keyboard` | 键盘工具栏 | 自定义键盘完成按钮 |

### 3. 三栏布局最佳实践

```swift
@ToolbarContentBuilder
private var leadingToolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
        Menu {
            Text("标题")
                .font(.headline)
            Text("副标题")
                .font(.caption)
        } label: {
            Text("🐎")
                .font(.caption)  // 统一字体大小
        }
    }
}

@ToolbarContentBuilder
private var centerToolbarContent: some ToolbarContent {
    ToolbarItem(placement: .principal) {
        Picker("功能", selection: $selectedTab) {
            ForEach(Tab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 180)  // 适当宽度确保居中
    }
}

@ToolbarContentBuilder
private var trailingToolbarContent: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
        HStack(spacing: 12) {
            Button { } label: {
                Image(systemName: "icon")
                    .font(.caption)  // 统一字体大小
            }
        }
    }
}
```

## 关键经验总结

### 1. 尺寸控制

**❌ 避免使用 `scaleEffect`**
```swift
// 不推荐 - 在 Toolbar 中可能不生效
Text("🐎")
    .font(.body)
    .scaleEffect(0.85)
```

**✅ 使用字体大小控制**
```swift
// 推荐 - 在 Toolbar 中稳定生效
Text("🐎")
    .font(.caption)  // 或 .footnote, .subheadline
```

### 2. 居中对齐

**问题**: `.principal` placement 的页签选择器可能不居中

**解决方案**:
- 使用适当的 `frame(width:)` 限制宽度
- 避免使用 `scaleEffect` 影响布局
- 确保三个位置的元素尺寸协调

```swift
ToolbarItem(placement: .principal) {
    Picker("功能", selection: $selectedTab) {
        // ...
    }
    .pickerStyle(.segmented)
    .frame(width: 180)  // 适当宽度
}
```

### 3. 元素尺寸统一

```swift
// 统一使用 .caption 大小
Text("🐎").font(.caption)                    // 左侧
// SegmentedPicker 保持默认大小            // 中央
Image(systemName: "icon").font(.caption)    // 右侧
```

### 4. 条件显示

```swift
@ToolbarContentBuilder
private var trailingToolbarContent: some ToolbarContent {
    // 条件显示 - 只在特定页签显示
    if selectedTab == .specificTab {
        ToolbarItem(placement: .topBarTrailing) {
            // 按钮内容
        }
    }
    
    // 键盘完成按钮
    ToolbarItem(placement: .keyboard) {
        Button("完成") {
            // 收起键盘
        }
    }
}
```

## 完整示例代码

```swift
import SwiftUI

struct CustomNavigationView: View {
    @State private var selectedTab: MainTab = .first
    
    enum MainTab: String, CaseIterable, Identifiable {
        case first = "第一"
        case second = "第二"
        case third = "第三"
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color.clear.ignoresSafeArea()
                
                // 内容
                TabView(selection: $selectedTab) {
                    FirstView().tag(MainTab.first)
                    SecondView().tag(MainTab.second)
                    ThirdView().tag(MainTab.third)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左侧
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Text("菜单标题").font(.headline)
                        Text("菜单描述").font(.caption)
                    } label: {
                        Text("🐎").font(.caption)
                    }
                }
                
                // 中央
                ToolbarItem(placement: .principal) {
                    Picker("功能", selection: $selectedTab) {
                        ForEach(MainTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                
                // 右侧
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button { } label: {
                            Image(systemName: "gear")
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }
}
```

## 常见陷阱

### 1. scaleEffect 在 Toolbar 中不生效
- **原因**: Toolbar 使用特殊的渲染机制
- **解决**: 使用字体大小控制（`.font(.caption)`）

### 2. principal 元素不居中
- **原因**: 元素宽度过大或使用了 scaleEffect
- **解决**: 限制 frame 宽度，移除 scaleEffect

### 3. 左右元素显示不全
- **原因**: principal 元素占用过多空间
- **解决**: 减小 principal 元素宽度，确保三栏平衡

## 参考实现

本项目中的参考实现:
- **马上来财页面**: `ItemManager/Views/Wealth/WealthView.swift`
- **梦裙日历页面**: `ItemManager/Views/Calendar/DreamDressCalendarView.swift`

## 版本兼容性

| iOS 版本 | Placement 推荐 |
|----------|---------------|
| iOS 16+ | `.topBarLeading`, `.topBarTrailing` |
| iOS 15 | `.navigationBarLeading`, `.navigationBarTrailing` |
| 通用 | `.principal`, `.keyboard` |

---

*文档创建日期: 2026-02-17*
*基于马上来财页面导航栏重构经验总结*
