---
name: "swiftui-config-management"
description: "SwiftUI configuration centralization best practices. Invoke when implementing UI layouts with configurable parameters, angle ranges, spacing, or any magic numbers that need unified management."
---

# SwiftUI 配置统一管理最佳实践

## 核心理念

**将分散的魔法数字（Magic Numbers）集中到统一的配置枚举中**，实现：
1. 一处修改，全局生效
2. 代码可读性提升
3. 调试和迭代效率提高
4. 避免硬编码带来的维护困难

## 适用场景

- 轮盘/扇形菜单的角度范围
- 网格布局的行列数、间距
- 动画时长、缓动曲线
- 颜色、字体、圆角等视觉参数
- 任何在多个地方重复使用的数值

## 最佳实践规范

### 1. 创建配置枚举

```swift
// MARK: - 统一配置管理
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

**❌ 避免：**
```swift
// 硬编码，难以维护
ForEach(0..<3) { index in
    let angle = -45 + Double(index) * 45
}
```

**✅ 推荐：**
```swift
// 使用配置，清晰易改
ForEach(0..<WheelConfig.innerMenuCount) { index in
    let angle = WheelConfig.startAngle + Double(index) * WheelConfig.innerMenuStep
}
```

### 3. 命名规范

| 类型 | 命名示例 | 说明 |
|------|----------|------|
| 基础值 | `startAngle`, `endAngle` | 描述边界 |
| 计算属性 | `totalAngle`, `innerMenuStep` | 使用 var + 计算 |
| 数量 | `innerMenuCount` | 明确层级和含义 |
| 间距/边距 | `outerMenuPadding` | 描述用途 |

### 4. 注释规范

```swift
enum WheelConfig {
    // 角度范围（以正上方为0°，顺时针为正）
    static let startAngle: Double = -45  // 左边界：左上45度
    static let endAngle: Double = 45     // 右边界：右上45度
    
    // 一级菜单：3个分类均匀分布
    static let innerMenuCount = 3
    
    // 二级菜单：留有边距，避免贴边
    static let outerMenuPadding: Double = 5
}
```

## 实战案例：轮盘菜单

### 需求
实现一个两层轮盘菜单：
- 内层：3个分类按钮
- 外层：动态数量的功能项
- 角度范围可调整

### 实现

```swift
// MARK: - 轮盘配置（统一管理）
enum WheelConfig {
    // 角度范围
    static let startAngle: Double = -45
    static let endAngle: Double = 45
    static var totalAngle: Double { endAngle - startAngle }
    
    // 内层一级菜单
    static let innerMenuCount = 3
    static var innerMenuStep: Double { totalAngle / Double(innerMenuCount - 1) }
    
    // 外层二级菜单
    static let outerMenuPadding: Double = 5
    static var outerMenuTotalAngle: Double { totalAngle - outerMenuPadding * 2 }
}

// MARK: - 内层轮盘
struct InnerWheelView: View {
    let radius: CGFloat
    
    var body: some View {
        ForEach(0..<WheelConfig.innerMenuCount) { index in
            let angle = WheelConfig.startAngle + Double(index) * WheelConfig.innerMenuStep
            // 使用 angle 计算位置...
        }
    }
}

// MARK: - 外层轮盘
struct OuterWheelView: View {
    let items: [MenuItem]
    let radius: CGFloat
    
    var body: some View {
        let itemStartAngle = WheelConfig.startAngle + WheelConfig.outerMenuPadding
        let step = items.count > 1 
            ? WheelConfig.outerMenuTotalAngle / Double(items.count - 1) 
            : 0
        
        ForEach(items.indices, id: \.self) { index in
            let angle = itemStartAngle + Double(index) * step
            // 使用 angle 计算位置...
        }
    }
}
```

### 调试技巧

**修改角度范围，只需改一处：**
```swift
// 从 90° 改为 180°
static let startAngle: Double = -90
static let endAngle: Double = 90
```

所有使用 `WheelConfig` 的地方会自动更新。

## 进阶技巧

### 1. 环境特定配置

```swift
enum WheelConfig {
    #if DEBUG
    static let animationDuration: Double = 0.1  // 调试时加快
    #else
    static let animationDuration: Double = 0.3
    #endif
}
```

### 2. 设备适配

```swift
enum WheelConfig {
    static var innerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 100 : 85
    }
}
```

### 3. 与 SwiftUI 预览结合

```swift
#Preview("Wide Angle") {
    // 临时修改配置查看效果
    let _ = { WheelConfig.startAngle = -90 }()
    WheelMenuView()
}
```

## 总结

**统一管理配置的核心价值：**
1. **DRY 原则** - Don't Repeat Yourself
2. **单一职责** - 配置集中，逻辑分散
3. **可维护性** - 修改一处，全局生效
4. **可读性** - 命名清晰的配置比魔法数字更易懂

**记住：** 当你发现同一个数字在代码中出现 2 次以上时，就该考虑统一管理了。
