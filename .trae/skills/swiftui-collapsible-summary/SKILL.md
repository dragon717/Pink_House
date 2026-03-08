---
name: "swiftui-collapsible-summary"
description: "SwiftUI折叠面板带摘要显示模式。Invoke when implementing expandable/collapsible UI with summary view when collapsed, especially for data dashboards and statistical views."
---

# SwiftUI 折叠面板 + 摘要显示技能

## 使用场景

当需要实现以下功能时调用此技能：
- 可展开/折叠的内容区域
- 折叠时显示数据摘要（而非完全隐藏）
- 统计面板、数据看板、筛选器等

## 核心模式

### 1. 基础结构

```swift
struct CollapsibleView: View {
    @State private var expanded: Bool = true
    
    // 计算摘要数据
    private var summaryStats: (value1: Int, value2: Decimal, hasData: Bool) {
        // 计算逻辑...
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // 标题按钮 - 点击切换展开状态
            Button {
                withAnimation {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text("标题(点我展开/折叠)")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
            }
            
            // 条件渲染
            if expanded {
                // 展开状态：显示完整内容
                FullContentView()
            } else {
                // 折叠状态：显示摘要
                SummaryCard(stats: summaryStats)
            }
        }
    }
}
```

### 2. 摘要卡片组件

```swift
struct SummaryCard: View {
    let stats: (value1: Int, value2: Decimal, hasData: Bool)
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "icon.name")
                    .foregroundStyle(.accent)
                Text("摘要标题")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if stats.hasData {
                    Text("关键指标")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
            }
            
            if stats.hasData {
                HStack(spacing: 0) {
                    StatItem(title: "指标1", value: "\(stats.value1)")
                    Divider().frame(height: 30)
                    StatItem(title: "指标2", value: "¥\(stats.value2)")
                }
            } else {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(CardBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
```

### 3. 最近数据计算模式（单日期字段）

```swift
// 找到最近的数据点（如最近月份）
private var recentStats: (month: Int, count: Int, amount: Decimal, hasData: Bool) {
    let calendar = Calendar.current
    let now = Date()
    
    // 1. 过滤有效数据并排序
    let sortedData = items
        .filter { $0.date != nil }
        .sorted { $0.date! < $1.date! }
    
    // 2. 找到最近的数据点
    // 优先找当前日期之后的数据，如果没有则取最后一个
    guard let nearest = sortedData.first(where: { $0.date! >= now }) ?? sortedData.last,
          let date = nearest.date else {
        return (0, 0, 0, false)
    }
    
    // 3. 统计该时间点的所有数据
    let month = calendar.component(.month, from: date)
    let monthItems = items.filter { 
        calendar.component(.month, from: $0.date!) == month 
    }
    
    let count = monthItems.reduce(0) { $0 + $1.quantity }
    let amount = monthItems.reduce(0) { $0 + $1.value }
    
    return (month, count, amount, true)
}
```

### 4. 最近数据计算模式（双日期字段：开始时间 + 结束时间）

```swift
// 适用于有开始时间和结束时间的场景（如尾款开始时间 + 尾款结束时间）
private var recentStats: (month: Int, count: Int, amount: Decimal, hasData: Bool) {
    let calendar = Calendar.current
    let now = Date()
    
    // 1. 获取所有有日期（开始或结束）的数据
    let validItems = items.filter { 
        $0.startDate != nil || $0.endDate != nil 
    }
    
    guard !validItems.isEmpty else {
        return (0, 0, 0, false)
    }
    
    // 2. 按开始时间排序（如果开始时间不存在则使用结束时间）
    let sortedItems = validItems.sorted { i1, i2 in
        let d1 = i1.startDate ?? i1.endDate!
        let d2 = i2.startDate ?? i2.endDate!
        return d1 < d2
    }
    
    // 3. 找到最近的数据点：优先找当前日期之后的，如果没有则取最后一个
    guard let nearest = sortedItems.first(where: { item in
        // 检查开始时间或结束时间是否有在当前日期之后的
        if let start = item.startDate, start >= now {
            return true
        }
        if let end = item.endDate, end >= now {
            return true
        }
        return false
    }) ?? sortedItems.last else {
        return (0, 0, 0, false)
    }
    
    // 4. 确定最近月份：优先使用开始时间，否则使用结束时间
    let nearestDate = nearest.startDate ?? nearest.endDate!
    let nearestMonth = calendar.component(.month, from: nearestDate)
    
    // 5. 统计该月份的所有数据（只要开始时间或结束时间在该月份都算）
    let monthItems = items.filter { item in
        if let start = item.startDate,
           calendar.component(.month, from: start) == nearestMonth {
            return true
        }
        if let end = item.endDate,
           calendar.component(.month, from: end) == nearestMonth {
            return true
        }
        return false
    }
    
    let count = monthItems.reduce(0) { $0 + $1.quantity }
    let amount = monthItems.reduce(0) { $0 + $1.value }
    
    return (nearestMonth, count, amount, true)
}
```

## 关键要点

| 要点 | 说明 |
|------|------|
| **withAnimation** | 切换状态时添加动画，提升体验 |
| **计算属性** | 将统计逻辑封装为计算属性，保持 body 简洁 |
| **空状态处理** | 使用 `hasData` 标志处理无数据情况 |
| **组件复用** | 摘要卡片可设计为通用组件，多处复用 |
| **类型安全** | 使用命名元组提高代码可读性 |

## 常见变体

### 变体1：按时间最近
```swift
// 找到当前时间之后最近的日期
let nearest = items.first(where: { $0.date >= now }) ?? items.last
```

### 变体2：按数值最大
```swift
// 找到数值最大的项
let maxItem = items.max(by: { $0.value < $1.value })
```

### 变体3：按优先级
```swift
// 找到优先级最高的未完成任务
let urgent = items
    .filter { !$0.isCompleted }
    .max(by: { $0.priority < $1.priority })
```

## 示例：完整实现

参见 `DepositPlanView.swift` 中的：
- `MonthSelectorView` - 按月份折叠面板
- ` ` - 按系列折叠面板
- `RecentMonthCard` - 摘要卡片组件
