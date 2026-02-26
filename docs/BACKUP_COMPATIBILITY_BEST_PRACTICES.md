# 备份恢复兼容性最佳实践

## 问题背景

在开发 iOS 应用的数据备份与恢复功能时，经常会遇到老版本备份文件无法在新版本中恢复的问题。这是因为随着应用功能的迭代，数据模型会不断添加新字段，而老版本的备份文件缺少这些字段，导致 JSON 解码失败。

## 核心原则

### 1. 向后兼容性设计

所有 DTO (Data Transfer Object) 中的字段都应该考虑是否为可选 (`Optional`)，特别是以下类型的字段：

- **新功能相关字段**：每个新版本添加的字段
- **软删除标记**：`isDeleted`, `deletedAt` 等
- **同步时间戳**：`lastModified` 等
- **排序索引**：`sortIndex` 等
- **状态标记**：`status`, `isShared` 等

### 2. 版本标记

在 DTO 中为每个字段添加版本注释，明确该字段是在哪个版本引入的：

```swift
struct ClothingDTO: Codable {
    let id: UUID
    let name: String
    // ... 基础字段（必需）
    
    // v1.2+ 新增字段
    let isShared: Bool? 
    let sortIndex: Int?
    
    // v1.3+ 自定义小物
    let accessoryItems: [AccessoryItemDTO]?
    
    // v1.4+ 软删除支持
    let isDeleted: Bool?
    let deletedAt: Date?
    let lastModified: Date?
}
```

### 3. 默认值处理

在恢复逻辑中，为所有可选字段提供合理的默认值：

```swift
// 恢复逻辑中的默认值处理
clothing.isShared = dto.isShared ?? false
clothing.accessoriesPrice = dto.accessoriesPrice ?? 0
clothing.status = ClothingStatus(rawValue: dto.status ?? "") ?? .onShelf
clothing.sortIndex = dto.sortIndex ?? 0
clothing.isDeleted = dto.isDeleted ?? false
```

## 最佳实践清单

### DTO 设计阶段

- [ ] 所有新添加的字段都应该是可选类型 (`Type?`)
- [ ] 为每个字段添加版本注释
- [ ] 考虑字段的默认值
- [ ] 保持基础字段（如 id, name, createdAt）为必需

### 备份逻辑

- [ ] 直接从模型读取数据，不需要特殊处理
- [ ] 可选字段会自动处理为 nil 或值

### 恢复逻辑

- [ ] 使用 `??` 提供默认值
- [ ] 对于布尔值，默认 false
- [ ] 对于数值，默认 0 或合理的初始值
- [ ] 对于枚举，提供默认 case
- [ ] 对于字符串，默认空字符串或合理值

### 错误处理

```swift
do {
    manifest = try jsonDecoder.decode(BackupManifest.self, from: manifestData)
} catch let decodingError as DecodingError {
    // 详细的解码错误信息
    switch decodingError {
    case .keyNotFound(let key, let context):
        print("Missing key '\(key.stringValue)' in \(context.codingPath)")
    case .typeMismatch(let type, let context):
        print("Type mismatch for \(type) in \(context.codingPath)")
    // ... 其他错误类型
    }
}
```

## 常见陷阱

### 1. 忘记处理条件判断中的可选值

❌ 错误：
```swift
if dto.isDeleted { continue }  // isDeleted 是 Bool?
```

✅ 正确：
```swift
if dto.isDeleted ?? false { continue }
```

### 2. 直接赋值可选值给非可选属性

❌ 错误：
```swift
clothing.isDeleted = dto.isDeleted  // 类型不匹配
```

✅ 正确：
```swift
clothing.isDeleted = dto.isDeleted ?? false
```

### 3. 枚举类型的 rawValue 解包

❌ 错误：
```swift
clothing.status = ClothingStatus(rawValue: dto.status!)  // 强制解包
```

✅ 正确：
```swift
clothing.status = ClothingStatus(rawValue: dto.status ?? "") ?? .onShelf
```

## 版本升级策略

当添加新功能时：

1. **在 DTO 中添加新字段**，标记为可选
2. **更新备份逻辑**，直接读取模型值
3. **更新恢复逻辑**，提供默认值
4. **测试老版本备份**，确保能正常恢复

## 测试建议

- 保留各个版本的备份文件用于测试
- 在 CI/CD 中添加兼容性测试
- 记录每个版本的备份格式变更

## 总结

备份恢复的向后兼容性是一个需要长期维护的工作。核心原则是：**所有新字段都应该是可选的，并在恢复时提供合理的默认值**。这样可以确保老版本备份文件始终能在新版本中恢复，为用户提供无缝的升级体验。
