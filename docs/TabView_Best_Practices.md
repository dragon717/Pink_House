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
            
            Tab("House", systemImage: "map") {
                SmallWorldTabContent()
            }
            
            Tab("我", systemImage: "face.smiling") {
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
                LegacyTabView()  // iOS 18 及以下回退
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

---

## 9. iOS 26 Tab 项位置定位（Liquid Glass 适配）

### 问题背景

iOS 26 引入 Liquid Glass 设计，TabBar 内部结构发生破坏性变更：

| 平台 | UITabBar | UITabBarButton | 替代结构 |
|------|----------|---------------|---------|
| iOS ≤ 25 | ✅ | ✅ | — |
| iOS 26 iPhone | ✅ 存在 | ❌ 移除 | `_UITabBarPlatterView` + `_UITabBarAuxiliaryView` |
| iOS 26 iPad | ❌ 不存在 | ❌ | 顶部 floating pill，需深度搜索 |

**影响**：任何依赖 `UITabBarButton` 遍历的功能（长按菜单、新手引导高亮等）在 iOS 26 上全部失效。

### iOS 26 内部视图结构

**iPhone（tab bar 在底部）：**
```
UITabBar: (0, 849, 430, 83)
├── _UITabBarPlatterView: (21, 0, 318, 62)    ← 主 tab 容器（3个非search tab）
├── _UITabBarPlatterView: (28, 7, 48, 48)     ← 内部小元素
├── _UITabBarAuxiliaryView: (347, 0, 62, 62)  ← Search tab（独立分离）
└── _UIPortalView: (0, 0, 0, 0)
```

**iPad（tab bar 在顶部 floating pill）：**
```
UITabBar 不在 view hierarchy 中
需要递归搜索 window 寻找 _UITabBarPlatterView
```

### 定位策略：分层降级

```
优先级1: UITabBarButton 遍历 (iOS ≤ 25)
    ↓ 失败
优先级2: _UITabBarPlatterView 等分 (iOS 26, UITabBar 存在)
    ↓ 失败
优先级3: 深度搜索 PlatterView (iOS 26 iPad, UITabBar 不存在)
    ↓ 失败
优先级4: SwiftUI captureGuideTarget (iOS ≤ 25)
    ↓ 失败
优先级5: 智能 Fallback (按设备/iOS版本区分)
```

### PlatterView 等分算法

```swift
// 找到主 PlatterView（宽度 > 100 的最大 PlatterView）
let platter = tabBar.subviews
    .filter { NSStringFromClass(type(of: $0)).contains("PlatterView") && $0.frame.width > 100 }
    .max { $0.frame.width < $1.frame.width }

// 按主 tab 数量等分（不含 search tab）
let mainTabCount = 3
let segmentWidth = platterGlobal.width / CGFloat(mainTabCount)
let tabFrame = CGRect(
    x: platterGlobal.minX + segmentWidth * CGFloat(tabIndex),
    y: platterGlobal.minY,
    width: segmentWidth,
    height: platterGlobal.height
)
```

### SwiftUI Tab label 捕获失效

iOS 26 的 `Tab { } label: { }` 中 label 闭包**不再作为常规 SwiftUI 视图渲染**，而是被提取为 Liquid Glass 的配置数据。因此 `GeometryReader` 的 `onAppear` 永远不会触发。

```swift
// ❌ iOS 26 上永远得不到 frame
Tab(value: 1) {
    Content()
} label: {
    Label("Title", systemImage: "icon")
        .background {
            Color.clear.captureGuideTarget(.homeHouseTab) // onAppear 不触发
        }
}
```

**应对**：Tab 项定位在 iOS 26 上完全依赖 UIKit PlatterView 路径，不依赖 SwiftUI 捕获。

### Fallback 计算要点

```swift
// ❌ 错误：假设 tab bar 居中
x: screenWidth / 2 - 34  // Liquid Glass platter 不居中，search tab 在右侧

// ✅ iPhone iOS 26：platter 偏左
let platterX = screenWidth * 0.05
let platterWidth = screenWidth * 0.74
let tabX = platterX + (platterWidth / 3) * tabIndex

// ✅ iPad iOS 26：顶部 floating pill
let pillY = safeAreaTop + 4
let pillWidth = screenWidth * 0.4  // 约占 40%
let pillX = (screenWidth - pillWidth) / 2
```

### 核心代码文件

- `TabBarItemAnchorResolver.swift` — 统一定位入口，分层降级
- `SmallWorldMenuOverlay.swift` — 长按轮盘菜单触发区域 + `buildFallbackFrame`
- `NewbieGuideCaptureAndHighlight.swift` — SwiftUI frame 捕获（iOS ≤ 25 有效）

### 调试检查清单

- [ ] iPhone iOS 26: PlatterView 等分是否对齐实际 tab 按钮？
- [ ] iPad iOS 26: 深度搜索是否找到 PlatterView？
- [ ] Tab bar 最小化/展开时位置是否跟随更新？
- [ ] 横屏/分屏模式下 fallback 计算是否正确？
- [ ] iOS ≤ 25 设备不受影响？
