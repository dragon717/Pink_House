# SwiftData 软删除与数据恢复最佳实践复盘

## 问题背景
在开发 `ItemManager` 的云端备份与恢复功能时，遇到了一个“顽固复活”的 Bug：
用户将物品放入回收站（软删除），执行云端备份（此时备份包含了该物品）。随后从云端恢复数据时，该物品被错误地识别为“新物品”并被重新创建，导致其从回收站“复活”回到衣橱列表，且状态变为未删除。

## 根本原因分析

### 1. SwiftData 查询机制陷阱
SwiftData 的 `FetchDescriptor` 在默认情况下，可能会对查询结果进行隐式过滤。
- **现象**：使用 `context.fetch(FetchDescriptor<Clothing>())` 进行批量查询时，未能返回那些 `isDeleted=true` 的对象。
- **推测原因**：虽然我们自定义了 `isDeleted` 属性用于软删除，但 SwiftData 内部可能有对数据状态的缓存或快照机制，导致在特定上下文中（尤其是涉及到 `ModelActor` 或后台上下文时），未提交的更改或已标记删除的对象被排除在结果集之外。

### 2. 属性遮蔽 (Property Shadowing) 风险
SwiftData 的 `PersistentModel` 协议本身可能包含系统级的 `isDeleted` 属性（用于标记物理删除）。
- **风险**：我们在 `Clothing` 模型中自定义了 `var isDeleted: Bool`。在某些运行时情况下，访问 `item.isDeleted` 可能产生了歧义，或者 SwiftData 的内部优化导致访问到了系统底层的物理删除状态（通常为 false），而非我们业务逻辑的软删除状态。

### 3. 数据一致性检查不足
原有的恢复逻辑仅依赖于批量查询构建的内存 Map (`clothingMap`)。一旦批量查询遗漏了某个对象，恢复逻辑就会误判该对象不存在，进而执行 `context.insert` 创建新对象。

## 解决方案与最佳实践

### 1. 显式开启 Pending Changes
在进行关键的数据同步或恢复操作时，必须显式告知 SwiftData 包含所有待处理的更改。

```swift
var descriptor = FetchDescriptor<Clothing>()
descriptor.includePendingChanges = true // 关键：确保内存中的脏数据也能被查到
let allItems = try context.fetch(descriptor)
```

### 2. 双重检查机制 (Double-Check Pattern)
不要盲目信任一次批量查询的结果。在决定“创建新对象”之前，应进行一次精确的二次查找。

```swift
if let existing = clothingMap[dto.id] {
    // 命中缓存
} else {
    // 兜底：精确查找
    var specificDesc = FetchDescriptor<Clothing>(predicate: #Predicate { $0.id == dto.id })
    specificDesc.includePendingChanges = true
    if let found = try? context.fetch(specificDesc).first {
        // 找回了被遗漏的对象
    } else {
        // 确认为新对象，安全创建
    }
}
```

### 3. 多重状态判断 (Robust State Checking)
为了规避属性遮蔽风险，使用多个属性组合判断状态。对于软删除，`deletedAt` 是一个更可靠的辅助标记。

```swift
// 不仅检查 isDeleted，还检查 deletedAt
// 只要满足其一，即视为软删除
let isSoftDeleted = item.isDeleted || item.deletedAt != nil
```

### 4. 强制状态同步 (Force State Synchronization)
在恢复逻辑中，**本地状态拥有最高优先级**。
如果本地对象处于软删除状态，无论备份数据如何，恢复后必须强制其保持删除状态。

```swift
if isLocalDeleted {
    clothingBack.isDeleted = true
    if clothingBack.deletedAt == nil { clothingBack.deletedAt = Date() }
}
```

## 总结
在处理本地优先（Local-First）的数据同步架构时，**“信任本地状态”**是核心原则。对于 SwiftData 这类现代持久化框架，开发者需要对其查询行为（Query Behavior）和上下文隔离（Context Isolation）保持警惕，通过显式配置（如 `includePendingChanges`）和防御性编程（如双重检查）来确保数据的一致性。
