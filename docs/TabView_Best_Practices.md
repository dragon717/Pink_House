# iOS 18+ SwiftUI TabView 最佳实践

## 核心原则：拥抱原生 API

### ❌ 避免的做法
- 手动操作底层 `UITabBar`（会导致崩溃）
- 使用 ZStack 叠加自定义按钮
- 通过 Mirror 反射修改私有属性
- 强制解包可选值

### ✅ 推荐的做法
- 使用 SwiftUI 原生修饰符
- 利用版本条件编译处理兼容性
- 使用 `Tab(role:)` 实现特殊功能
- 让系统处理滚动交互

---

## 1. 基础结构（iOS 18+）

```swift
@available(iOS 18.0, *)
struct ModernTabView: View {
    var body: some View {
        TabView {
            Tab("首页", systemImage: "house") {
                HomeView()
            }
            
            Tab("设置", systemImage: "gear") {
                SettingsView()
            }
            
            // 独立搜索按钮（最右侧）
            Tab(role: .search) {
                SearchView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
```

### 关键特性
- **悬浮胶囊样式**：`.tabViewStyle(.sidebarAdaptable)` 自动启用 Liquid Glass 效果
- **独立搜索按钮**：`Tab(role: .search)` 在右侧显示圆形搜索按钮
- **无需手动布局**：系统处理所有间距和动画

---

## 2. 版本兼容性处理

### 扩展方法模式

```swift
extension View {
    /// iOS 26+ 搜索工具栏行为
    @ViewBuilder
    func applySearchToolbarBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.searchToolbarBehavior(.automatic)
        } else {
            self
        }
    }
    
    /// iOS 26+ TabBar 滚动最小化
    @ViewBuilder
    func applyTabBarMinimizeBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
```

### 使用方式

```swift
TabView {
    // ... Tabs
}
.tabViewStyle(.sidebarAdaptable)
.applyTabBarMinimizeBehavior()  // 自动处理版本差异
.applySearchToolbarBehavior()
```

---

## 3. 搜索功能实现

### 基础搜索（iOS 18+）

```swift
TabView {
    // ... 其他 Tabs
    
    Tab(role: .search) {
        SearchContainerView()
    }
}
.searchable(
    text: $searchText,
    placement: .toolbar,
    prompt: "搜索..."
)
```

### 搜索容器视图

```swift
@available(iOS 18.0, *)
struct SearchContainerView: View {
    @Binding var searchText: String
    @Environment(\.modelContext) private var modelContext
    @Query var items: [Item]
    
    var filteredItems: [Item] {
        if searchText.isEmpty { return [] }
        return items.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) 
        }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredItems) { item in
                Text(item.name)
            }
            .navigationTitle("搜索")
        }
    }
}
```

---

## 4. 滚动交互（iOS 26+）

### 原生自动处理

```swift
TabView {
    // ... Tabs
}
.tabBarMinimizeBehavior(.onScrollDown)  // iOS 26+
```

**行为**：
- 向下滑动 → TabBar 自动最小化
- 向上滑动 → TabBar 自动展开
- 无需任何手动监听代码

### ⚠️ 重要提醒

| API | 最低版本 | 说明 |
|-----|---------|------|
| `.tabViewStyle(.sidebarAdaptable)` | iOS 18 | 悬浮胶囊样式 |
| `Tab(role: .search)` | iOS 18 | 独立搜索按钮 |
| `.tabBarMinimizeBehavior()` | iOS 26 | 滚动最小化 |
| `.searchToolbarBehavior()` | iOS 26 | 搜索工具栏行为 |

---

## 5. 视觉样式配置

### TabBar 背景

```swift
TabView {
    // ... Tabs
}
.toolbarBackground(.visible, for: .tabBar)
.toolbarBackground(.ultraThinMaterial, for: .tabBar)  // Liquid Glass 效果
```

### 导航栏隐藏（沉浸式体验）

```swift
NavigationStack {
    ContentView()
        .toolbarBackground(.hidden, for: .navigationBar)
}
```

---

## 6. 完整示例代码

```swift
import SwiftUI
import SwiftData

// MARK: - 版本兼容扩展
extension View {
    @ViewBuilder
    func applyTabBarMinimizeBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func applySearchToolbarBehavior() -> some View {
        if #available(iOS 26.0, *) {
            self.searchToolbarBehavior(.automatic)
        } else {
            self
        }
    }
}

// MARK: - iOS 18+ 现代 TabView
@available(iOS 18.0, *)
struct ModernTabView: View {
    @State private var searchText = ""
    
    var body: some View {
        TabView {
            Tab("衣橱", systemImage: "cabinet.fill") {
                WardrobeTabContent()
            }
            
            Tab("小世界", systemImage: "map") {
                SmallWorldTabContent()
            }
            
            Tab("我的", systemImage: "face.smiling") {
                MeTabContent()
            }
            
            Tab(role: .search) {
                SearchContainerView(searchText: $searchText)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .applyTabBarMinimizeBehavior()  // iOS 26+
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "搜索..."
        )
        .applySearchToolbarBehavior()  // iOS 26+
    }
}

// MARK: - 主入口
struct MainTabView: View {
    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                ModernTabView()
            } else {
                LegacyTabView()  // iOS 17 及以下回退
            }
        }
    }
}
```

---

## 7. 常见问题与解决方案

### Q: 为什么 TabBar 没有悬浮效果？
**A**: 确保使用 `.tabViewStyle(.sidebarAdaptable)` 且在 iOS 18+ 环境运行。

### Q: 搜索按钮没有显示在最右侧？
**A**: 使用 `Tab(role: .search)` 而不是普通 Tab。

### Q: 滚动时 TabBar 没有自动收缩？
**A**: `.tabBarMinimizeBehavior()` 需要 iOS 26+，低版本会自动忽略。

### Q: 如何避免 "Unexpectedly found nil" 崩溃？
**A**: 
- 不要操作底层 UITabBar
- 使用 SwiftUI 原生修饰符
- 避免强制解包可选值

---

## 8. 调试技巧

### 检查当前 iOS 版本

```swift
if #available(iOS 26.0, *) {
    print("支持 tabBarMinimizeBehavior")
} else if #available(iOS 18.0, *) {
    print("仅支持 sidebarAdaptable")
} else {
    print("使用传统 TabView")
}
```

### 预览不同版本

```swift
#Preview("iOS 18+") {
    if #available(iOS 18.0, *) {
        ModernTabView()
    } else {
        Text("需要 iOS 18+")
    }
}
```

---

## 总结

1. **始终优先使用原生 API**
2. **使用版本条件编译处理兼容性**
3. **避免手动操作底层 UIKit 组件**
4. **让系统处理滚动和动画**
5. **测试时关注最低支持版本**

遵循这些实践，可以构建出稳定、兼容且符合 Apple 设计规范的 TabView 界面。
