---
name: "swiftui-compile-error-fix"
description: "SwiftUI 编译错误快速修复技能。当遇到 'Cannot find X in scope'、'No such module' 等编译错误时调用。包含字段缺失排查、模块导入检查、依赖分析等最佳实践。"
---

# SwiftUI 编译错误快速修复指南

## 常见错误类型及解决方案

### 错误 1：Cannot find 'X' in scope

**错误示例**：
```
Cannot find 'segmentedBackground' in scope
Cannot find 'segmentedSelectedBackground' in scope
```

**根本原因**：
在使用结构体初始化时，某些字段没有提供值。

**修复步骤**：

1. **检查结构体定义**
   ```swift
   struct MagicThemePalette {
       let segmentedBackground: Color      // ← 这个字段需要值
       let segmentedSelectedBackground: Color  // ← 这个字段需要值
       // ... 其他字段
   }
   ```

2. **在初始化前定义变量**
   ```swift
   // ❌ 错误：直接使用未定义的变量
   return MagicThemePalette(
       segmentedBackground: segmentedBackground,  // 未定义！
       ...
   )
   
   // ✅ 正确：先定义再使用
   let segmentedBackground = cardBackground.opacity(isDark ? 0.46 : 0.72)
   let segmentedSelectedBackground = cardBackground.mixed(with: .white, amount: isDark ? 0.08 : 0.18)
   
   return MagicThemePalette(
       segmentedBackground: segmentedBackground,
       segmentedSelectedBackground: segmentedSelectedBackground,
       ...
   )
   ```

3. **检查所有字段是否都有值**
   ```swift
   // 完整检查清单
   return MagicThemePalette(
       primaryText: ...,              // ✓
       secondaryText: ...,            // ✓
       tertiaryText: ...,             // ✓
       accent: ...,                   // ✓
       cardBackground: ...,           // ✓
       cardAccent: ...,               // ✓
       navigationBackground: ...,     // ✓
       navigationForeground: ...,     // ✓
       segmentedBackground: ...,      // ✓ 必须提供
       segmentedSelectedBackground: ..., // ✓ 必须提供
       segmentedSelectedForeground: ..., // ✓ 必须提供
       quickOptionFill: ...,          // ✓
       quickOptionStroke: ...,        // ✓
       quickOptionText: ...,          // ✓
       bubbleUserColors: ...,         // ✓
       bubbleUserTextColor: ...,      // ✓
       bubbleAssistantStrokeColors: ..., // ✓
       bubblePreviewBackgroundColors: ... // ✓
   )
   ```

### 错误 2：No such module 'UIKit'

**错误示例**：
```
No such module 'UIKit'
```

**可能原因**：
1. 文件类型不正确（应该是 `.swift`）
2. Xcode 缓存问题
3. 项目配置问题

**修复步骤**：

1. **检查文件扩展名**
   ```bash
   # 确保文件是 .swift 结尾
   ls -la MagicThemeDesignSystem.swift
   ```

2. **清理 Xcode 缓存**
   ```
   Product -> Clean Build Folder (Shift + Cmd + K)
   Product -> Build (Cmd + B)
   ```

3. **检查导入语句**
   ```swift
   import SwiftUI
   import UIKit  // ← 确保这一行存在且拼写正确
   
   // UIKit 用于 UIColor 操作
   extension Color {
       func mixed(with other: Color, amount: Double) -> Color {
           let lhs = UIColor(self)  // ← 需要 UIKit
           let rhs = UIColor(other)
           // ...
       }
   }
   ```

4. **如果问题持续，重启 Xcode**
   ```
   1. 关闭 Xcode
   2. 删除 DerivedData: rm -rf ~/Library/Developer/Xcode/DerivedData
   3. 重新打开 Xcode
   4. 重新编译
   ```

### 错误 3：Generic parameter 'T' could not be inferred

**错误示例**：
```
Generic parameter 'T' could not be inferred
Cannot find 'ThemeManager' in scope
```

**可能原因**：
1. 缺少必要的 import 语句
2. 文件被意外修改导致上下文丢失
3. 使用了未定义的泛型

**修复步骤**：

1. **检查文件头部**
   ```swift
   // ✅ 确保必要的导入
   import SwiftUI
   import UIKit  // 如果需要 UIColor
   
   // ✅ 检查是否有其他必要的 import
   ```

2. **检查 Environment 使用**
   ```swift
   struct ThemePreviewSection: View {
       @Environment(ThemeManager.self) private var themeManager
       // ↑ 确保 ThemeManager 已定义且可访问
   }
   ```

3. **如果是泛型问题，明确指定类型**
   ```swift
   // ❌ 可能报错
   let items = []
   
   // ✅ 明确类型
   let items: [String] = []
   ```

## 调试技巧

### 1. 使用 Xcode 的问题导航器

```
1. 打开问题导航器 (Cmd + 8)
2. 查看所有错误和警告
3. 逐个点击错误定位问题
4. 根据错误信息推断原因
```

### 2. 增量编译定位问题

```bash
# 如果一次性修改了多个文件
# 先编译一个文件，修复后再编译下一个
Cmd + B -> 修复 -> 再 Cmd + B
```

### 3. 使用注释临时禁用代码

```swift
// 如果不确定哪行代码有问题
// 可以先注释掉，逐步取消注释定位
return MagicThemePalette(
    primaryText: text.primary.color,
    // segmentedBackground: segmentedBackground,  // ← 先注释
    ...
)
```

## 预防措施

### 1. 使用代码模板

创建结构体实例时，使用模板确保所有字段都被填充：

```swift
// 模板：复制后逐项填充
return MagicThemePalette(
    primaryText: <#T##Color#>,
    secondaryText: <#T##Color#>,
    tertiaryText: <#T##Color#>,
    accent: <#T##Color#>,
    cardBackground: <#T##Color#>,
    cardAccent: <#T##Color#>,
    navigationBackground: <#T##Color#>,
    navigationForeground: <#T##Color#>,
    segmentedBackground: <#T##Color#>,
    segmentedSelectedBackground: <#T##Color#>,
    segmentedSelectedForeground: <#T##Color#>,
    quickOptionFill: <#T##Color#>,
    quickOptionStroke: <#T##Color#>,
    quickOptionText: <#T##Color#>,
    bubbleUserColors: <#T##[Color]#>,
    bubbleUserTextColor: <#T##Color#>,
    bubbleAssistantStrokeColors: <#T##[Color]#>,
    bubblePreviewBackgroundColors: <#T##[Color]#>
)
```

### 2. 代码审查清单

在提交代码前检查：

- [ ] 所有结构体字段都有值
- [ ] 所有 import 语句都正确
- [ ] 没有使用未定义的变量
- [ ] 泛型类型都已明确指定
- [ ] 编译无错误无警告

### 3. 使用自动补全

```
1. 输入结构体名称
2. 按 Cmd + Shift + A 或等待自动补全
3. Xcode 会提示需要填充的字段
4. 逐项填写
```

## 快速参考

| 错误信息 | 可能原因 | 快速修复 |
|---------|---------|---------|
| Cannot find 'X' in scope | 字段未定义 | 先定义变量再使用 |
| No such module | 导入缺失/缓存问题 | 清理缓存，检查 import |
| Generic parameter could not be inferred | 类型不明确 | 明确指定泛型类型 |
| Cannot find type | 类型未导入/未定义 | 检查 import 和依赖 |

## 相关文件

- `MagicThemeDesignSystem.swift` - 颜色映射系统
- `ThemeManager.swift` - 主题管理器
- `ThemePreset.swift` - 主题预设
