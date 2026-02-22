# SwiftUI 配置统一管理最佳实践

> 本文档总结了在 Pink House 项目中使用的配置统一管理思路，以小世界轮盘菜单为典型案例。

## 背景

在小世界长按菜单的实现中，我们需要：
- 内层一级菜单：3个分类（常用、乐玩、大世界）
- 外层二级菜单：动态数量的功能项
- 角度范围可调整，方便调试视觉效果

**问题：** 角度值、数量、间距等参数散落在代码各处，修改时需要多处调整，容易遗漏。

**解决方案：** 使用统一的配置枚举 `WheelConfig` 集中管理所有参数。

## 核心思路

### 1. 配置集中化

```swift
// MARK: - 轮盘配置（统一管理角度范围）
enum WheelConfig {
    // 基础角度范围（以正上方为0°，顺时针为正）
    static let startAngle: Double = -45   // 左边界
    static let endAngle: Double = 45      // 右边界
    
    // 计算属性（自动推导）
    static var totalAngle: Double { endAngle - startAngle }
    
    // 一级菜单配置
    static let innerMenuCount = 3
    static var innerMenuStep: Double { 
        totalAngle / Double(innerMenuCount - 1) 
    }
    
    // 二级菜单配置
    static let outerMenuPadding: Double = 5
    static var outerMenuTotalAngle: Double { 
        totalAngle - outerMenuPadding * 2 
    }
}
```

### 2. 使用配置替代硬编码

**修改前（硬编码）：**
```swift
// 内层轮盘
ForEach(0..<3) { index in
    let angle = -45 + Double(index) * 45  // 魔法数字
    // ...
}

// 外层轮盘
let totalAngle = 80.0
let itemStartAngle = -45 + 5
let step = items.count > 1 ? 80.0 / Double(items.count - 1) : 0
```

**修改后（使用配置）：**
```swift
// 内层轮盘
ForEach(0..<WheelConfig.innerMenuCount) { index in
    let angle = WheelConfig.startAngle + Double(index) * WheelConfig.innerMenuStep
    // ...
}

// 外层轮盘
let itemStartAngle = WheelConfig.startAngle + WheelConfig.outerMenuPadding
let step = items.count > 1 ? WheelConfig.outerMenuTotalAngle / Double(items.count - 1) : 0
```

### 3. 调试效率提升

**场景：调整角度范围从 90° 改为 180°**

**传统方式：**
1. 搜索所有 `-45` 和 `45`
2. 逐个修改为 `-90` 和 `90`
3. 检查是否有遗漏

**统一管理方式：**
```swift
// 只需修改一处
static let startAngle: Double = -90
static let endAngle: Double = 90
// 所有计算属性自动更新
```

## 命名规范

| 类型 | 命名示例 | 说明 |
|------|----------|------|
| 基础边界值 | `startAngle`, `endAngle` | 描述范围边界 |
| 计算属性 | `totalAngle`, `innerMenuStep` | 使用 `var` + 计算逻辑 |
| 数量/计数 | `innerMenuCount` | 明确层级和含义 |
| 间距/边距 | `outerMenuPadding` | 描述用途和位置 |
| 半径尺寸 | `innerRadius`, `outerRadius` | 明确层级 |

## 项目实战：小世界轮盘菜单

### 文件结构

```
SmallWorldMenuOverlay.swift
├── WheelConfig (配置枚举)
├── WheelMenuCategory (数据模型)
├── WheelMenuItem (数据模型)
├── SmallWorldMenuOverlay (主视图)
├── InnerWheelView (内层轮盘)
├── OuterWheelView (外层轮盘)
├── WheelBackground (背景)
├── CategoryBubble (分类按钮)
└── ItemBubble (功能项按钮)
```

### 配置使用示例

```swift
// MARK: - 内层固定轮盘
struct InnerWheelView: View {
    let categories: [WheelMenuCategory]
    @Binding var selectedIndex: Int
    let radius: CGFloat
    let isLowMemoryDevice: Bool
    let monicaPink: Color

    var body: some View {
        ZStack {
            // 背景使用配置的角度范围
            WheelBackground(
                radius: radius + 35,
                startAngle: WheelConfig.startAngle,
                endAngle: WheelConfig.endAngle,
                monicaPink: monicaPink
            )

            // 三个分类使用配置的步长计算位置
            ForEach(0..<WheelConfig.innerMenuCount) { index in
                let angle = WheelConfig.startAngle + Double(index) * WheelConfig.innerMenuStep
                let radians = angle * .pi / 180
                let x = radius * cos(radians)
                let y = radius * sin(radians)

                CategoryBubble(...)
                    .offset(x: x, y: y)
            }
        }
    }
}

// MARK: - 外层二级菜单
struct OuterWheelView: View {
    let categories: [WheelMenuCategory]
    let selectedIndex: Int
    let rotation: Double
    let radius: CGFloat
    let isLowMemoryDevice: Bool
    let monicaPink: Color
    let onItemSelected: (WheelMenuItem) -> Void

    var body: some View {
        ZStack {
            let items = categories[selectedIndex].items
            
            // 使用配置的边距和总角度
            let itemStartAngle = WheelConfig.startAngle + WheelConfig.outerMenuPadding
            let step = items.count > 1 
                ? WheelConfig.outerMenuTotalAngle / Double(items.count - 1) 
                : 0
            
            ForEach(items.indices, id: \.self) { itemIndex in
                let angle = itemStartAngle + Double(itemIndex) * step
                let radians = angle * .pi / 180
                let x = radius * cos(radians)
                let y = radius * sin(radians)

                ItemBubble(...)
                    .offset(x: x, y: y)
            }
        }
    }
}
```

## 进阶技巧

### 1. 环境特定配置

```swift
enum WheelConfig {
    #if DEBUG
    static let animationDuration: Double = 0.1  // 调试时加快动画
    #else
    static let animationDuration: Double = 0.3  // 发布时使用正常速度
    #endif
}
```

### 2. 设备适配

```swift
enum WheelConfig {
    static var innerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 100 : 85
    }
    
    static var outerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 220 : 190
    }
}
```

### 3. 动态调整

```swift
// 根据功能项数量动态调整分布
static func calculateStep(itemCount: Int) -> Double {
    guard itemCount > 1 else { return 0 }
    return outerMenuTotalAngle / Double(itemCount - 1)
}
```

## 总结

### 统一管理配置的优势

1. **DRY 原则** - Don't Repeat Yourself
   - 避免魔法数字重复出现
   - 减少出错概率

2. **单一职责**
   - 配置集中管理
   - 逻辑代码专注于业务

3. **可维护性**
   - 修改一处，全局生效
   - 版本控制更清晰

4. **可读性**
   - `WheelConfig.startAngle` 比 `-45` 更易理解
   - 新成员快速上手

### 何时使用

- ✅ 同一个数值在多处使用
- ✅ 需要频繁调整的参数
- ✅ 有明确业务含义的数值
- ✅ 层级/分类相关的配置

- ❌ 只使用一次的简单数值
- ❌ 纯局部逻辑的临时变量

### 记住

> 当你发现同一个数字在代码中出现 2 次以上时，
> 就该考虑使用统一的配置管理了。

## 参考

- 技能文件：`.trae/skills/swiftui-config-management/SKILL.md`
- 实战代码：`ItemManager/Views/SmallWorldMenuOverlay.swift`
