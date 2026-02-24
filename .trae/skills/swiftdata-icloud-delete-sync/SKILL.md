---
name: "swiftdata-icloud-delete-sync"
description: "SwiftData iCloud同步删除冲突解决方案。Invoke when implementing soft delete with iCloud sync in SwiftData, or when deleted data reappears after app restart."
---

# SwiftData + iCloud 同步删除冲突解决方案

## 问题场景

在使用 SwiftData + iCloud 同步时，删除操作可能会被 iCloud 同步覆盖，导致已删除的数据在应用重启后"复活"。

### 典型症状

1. 用户删除数据（书页/裙子/手帐/拼豆作品等）
2. 删除后立即查看，数据确实消失了
3. 杀掉应用重新进入
4. 被删除的数据又出现了
5. 回收站里没有这些数据

### 根本原因

SwiftData 的 iCloud 同步采用 "Last Writer Wins" 策略：
- 设备 A 删除数据（设置 `isDeleted = true`）
- iCloud 同步将设备 B（或云端）的数据同步到设备 A
- 如果云端数据的 `lastModified` 更新，会覆盖本地的删除标记
- 结果：`isDeleted` 被重置为 `false`，数据"复活"

**关键问题**：iCloud 同步是异步的，可能在应用启动后才完成，导致删除状态被覆盖。

---

## 解决方案：基于时间戳的 DeleteTracker 模式

### 核心思想

1. **记录删除时间戳**：删除时将 ID 和**删除时间**记录到 iCloud Key-Value Store
2. **在 ModelContainer 创建后立即应用删除**：确保在 iCloud 同步之前就已经设置好删除状态
3. **冲突时比较时间戳**：比较删除时间和数据最后修改时间
4. **24小时保留期**：删除记录保留24小时，防止同步延迟导致的问题

### 执行顺序（关键！）

```
✅ 正确顺序：
1. 创建 ModelContainer
2. 立即应用删除（DeleteTracker）← 在 iCloud 同步之前！
3. iCloud 同步开始
4. iCloud 同步完成
5. UI 加载

❌ 错误顺序：
1. 创建 ModelContainer
2. iCloud 同步开始
3. iCloud 同步完成（覆盖删除状态）
4. UI 加载
5. 应用删除（太晚！lastModified 已被更新）
```

---

## 实现步骤

### 1. 模型要求

确保模型包含以下字段：

```swift
@Model
final class MyModel {
    var id: UUID = UUID()
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    var lastModified: Date = Date()  // 关键！用于冲突解决
    
    // ... 其他字段
}
```

### 2. 创建 DeleteTracker（强制删除策略）

```swift
import Foundation
import SwiftData

@MainActor
final class DeleteTracker {
    static let shared = DeleteTracker()
    
    private let iCloudStore = NSUbiquitousKeyValueStore.default
    private let userDefaults = UserDefaults.standard
    private let deletedItemsKey = "deletedMyModels_v2"  // v2: 存储 [UUID: TimeInterval]
    
    // MARK: - 记录删除
    
    func recordDeletedItem(id: UUID) {
        let deleteTime = Date()
        var records = getDeletedRecords()
        records[id.uuidString] = deleteTime.timeIntervalSince1970
        saveRecords(records)
        print("DeleteTracker: Recorded delete at \(deleteTime)")
    }
    
    // MARK: - 应用删除（强制删除策略）
    
    func applyDeletedItems(context: ModelContext) {
        let deletedRecords = getDeletedDates()
        guard !deletedRecords.isEmpty else { return }
        
        let descriptor = FetchDescriptor<MyModel>()
        do {
            let allItems = try context.fetch(descriptor)
            var appliedCount = 0
            
            for item in allItems {
                if let deleteTime = deletedRecords[item.id] {
                    // 强制删除策略：只要在删除记录中，就强制删除
                    // 避免 iCloud 同步覆盖导致的删除失效
                    if !item.isDeleted {
                        item.isDeleted = true
                        item.deletedAt = deleteTime
                        item.lastModified = Date()
                        appliedCount += 1
                        print("DeleteTracker: ✓ Force deleted '\(item.name)'")
                    }
                }
            }
            
            if appliedCount > 0 {
                do {
                    try context.save()
                    print("DeleteTracker: ✓ Saved \(appliedCount) deletes to database")
                    
                    // 立即再次保存，防止 iCloud 同步覆盖
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        try? context.save()
                        print("DeleteTracker: ✓ Re-saved \(appliedCount) deletes (anti-race)")
                    }
                } catch {
                    print("DeleteTracker: ✗ Failed to save deletes: \(error)")
                }
            }
        } catch {
            print("Failed to apply deletes: \(error)")
        }
    }
    
    // MARK: - 辅助方法
    
    private func getDeletedRecords() -> [String: Double] {
        if let cloudDict = iCloudStore.dictionary(forKey: deletedItemsKey) as? [String: Double] {
            return cloudDict
        }
        return userDefaults.dictionary(forKey: deletedItemsKey) as? [String: Double] ?? [:]
    }
    
    private func getDeletedDates() -> [UUID: Date] {
        let records = getDeletedRecords()
        var result: [UUID: Date] = [:]
        for (idString, timestamp) in records {
            if let uuid = UUID(uuidString: idString) {
                result[uuid] = Date(timeIntervalSince1970: timestamp)
            }
        }
        return result
    }
    
    private func saveRecords(_ records: [String: Double]) {
        userDefaults.set(records, forKey: deletedItemsKey)
        iCloudStore.set(records, forKey: deletedItemsKey)
        iCloudStore.synchronize()
    }
}
```

### 3. 在 SharedPersistence 中延迟应用删除（关键！）

由于 iCloud 同步是异步的，我们需要等待同步完成后再应用删除：

```swift
// SharedPersistence.swift
private init() {
    do {
        // 创建 ModelContainer
        self.sharedModelContainer = try SwiftDataMigrationManager.shared.createModelContainer()
        
        // ⚠️ 关键：延迟应用删除，确保 iCloud 同步完成
        let context = self.sharedModelContainer.mainContext
        DeleteTracker.shared.pendingContext = context
        
        // 延迟5秒首次应用删除，确保 iCloud 同步完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            print("DeleteTracker: 首次应用删除...")
            DeleteTracker.shared.applyAllDeletes(context: context)
        }
        
        // 10秒后再次应用删除（处理同步延迟较大的情况）
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            print("DeleteTracker: 第二次应用删除...")
            DeleteTracker.shared.applyAllDeletes(context: context)
        }
        
    } catch {
        // ... 错误处理
    }
}
```

### 4. 修改删除逻辑

```swift
func deleteItem(_ item: MyModel) {
    withAnimation {
        // 1. 设置删除标记
        item.isDeleted = true
        item.deletedAt = Date()
        item.lastModified = Date()  // 关键！
        
        // 2. 保存到数据库
        try? modelContext.save()
        
        // 3. 记录删除到 DeleteTracker（关键！）
        DeleteTracker.shared.recordDeletedItem(id: item.id)
    }
}
```

### 5. 24小时保留期（防止同步延迟）

```swift
/// 清理已处理的删除记录（保留24小时）
private func clearProcessedRecords(ids: [UUID], key: String, typeName: String) {
    var records = getDeletedRecords(for: key)
    let now = Date().timeIntervalSince1970
    let retentionPeriod: Double = 24 * 60 * 60  // 24小时
    
    for id in ids {
        if let timestamp = records[id.uuidString] {
            // 只清理超过24小时的记录
            if now - timestamp > retentionPeriod {
                records.removeValue(forKey: id.uuidString)
            }
        }
    }
    
    saveDeletedRecords(records: records, key: key)
}
```

### 6. 恢复操作（关键！）

从回收站恢复时，**必须**清除 DeleteTracker 中的删除记录：

```swift
func restoreItem(_ item: MyModel) {
    withAnimation {
        // 1. 恢复删除标记
        item.isDeleted = false
        item.deletedAt = nil
        item.lastModified = Date()
        
        // 2. 从 DeleteTracker 中移除删除记录（关键！）
        DeleteTracker.shared.removeDeletedItem(id: item.id)
    }
}
```

### 7. 手动同步按钮（用户体验优化）

为用户提供手动触发删除同步的选项：

```swift
// 在工具栏菜单中添加
Menu {
    // ... 其他选项
    
    Divider()
    
    Button {
        // 手动触发删除同步
        DeleteTracker.shared.applyAllDeletes(context: modelContext)
    } label: {
        Label("同步删除状态", systemImage: "arrow.triangle.2.circlepath")
    }
} label: {
    Image(systemName: "plus")
}
```

---

## 最佳实践

### ✅ 应该做的

1. **在 ModelContainer 创建后立即应用删除**
   ```swift
   // SharedPersistence.init() 中
   self.sharedModelContainer = try ...
   DeleteTracker.shared.applyAllDeletes(context: context)  // 立即！
   ```

2. **始终更新 `lastModified`**
   ```swift
   item.isDeleted = true
   item.deletedAt = Date()
   item.lastModified = Date()  // 关键！
   ```

3. **使用 iCloud Key-Value Store 同步删除记录**
   - 确保删除记录在设备间同步
   - 即使应用重装也能恢复删除状态

4. **24小时保留期**
   - 防止 iCloud 同步延迟导致的问题
   - 不要立即清除删除记录

5. **恢复时清理 DeleteTracker**
   - 防止恢复的数据被再次删除

6. **查询时过滤已删除数据**
   ```swift
   @Query(filter: #Predicate<MyModel> { $0.isDeleted == false })
   private var items: [MyModel]
   ```

### ❌ 不应该做的

1. **在 UI 加载后再应用删除**
   ```swift
   // ❌ 错误：太晚了，iCloud 同步可能已经覆盖删除状态
   .onAppear {
       DeleteTracker.shared.applyAllDeletes(context: context)
   }
   
   // ✅ 正确：在 SharedPersistence.init() 中立即应用
   ```

2. **只记录 ID，不记录时间戳**
   - 无法处理冲突情况
   - 可能导致误删或数据复活

3. **物理删除而不是软删除**
   ```swift
   // ❌ 错误
   context.delete(item)
   
   // ✅ 正确
   item.isDeleted = true
   ```

4. **恢复时不清理 DeleteTracker**
   - 下次启动时数据会被再次删除

---

## 调试技巧

### 添加详细日志

```swift
// 查看时间戳比较
print("DeleteTracker: [\(item.name)] deleteTime:\(deleteTime), lastModified:\(item.lastModified), diff:\(timeDiff)s")

// 查看决策结果
print("DeleteTracker: ✓ Applied delete to '\(item.name)' (deleted after last modify)")
print("DeleteTracker: ✗ Keeping '\(item.name)' (modified after delete)")

// 查看记录匹配
print("DeleteTracker: Checking \(deletedRecords.count) deleted \(typeName)(s), IDs: \(ids)")
```

### 检查删除记录

```swift
let records = DeleteTracker.shared.getDeletedRecords()
print("Pending deletes: \(records)")
```

### 验证执行顺序

查看日志中的时间戳：
```
// ✅ 正确顺序
DeleteTracker: Applying all tracked deletes...
DeleteTracker: Applied delete to 'xxx'
🔄 创建 ModelContainer，iCloud 同步: 启用
☁️ iCloud 同步通知收到

// ❌ 错误顺序
🔄 创建 ModelContainer，iCloud 同步: 启用
☁️ iCloud 同步通知收到
DeleteTracker: Applying all tracked deletes...
DeleteTracker: ✗ Keeping 'xxx' (modified after delete)
```

---

## 完整示例代码

参见项目中的文件：
- `DeleteTracker.swift` - 完整的删除追踪器实现
- `SharedPersistence.swift` - 在 ModelContainer 创建后立即应用删除
- `PerlerBeadPatternListView.swift` - 删除逻辑示例

---

## 关于 NSPersistentCloudKitContainer

**不需要切换！** SwiftData 的 `cloudKitDatabase: .automatic` 底层就是 `NSPersistentCloudKitContainer`。SwiftData 是 Core Data + CloudKit 的封装层。

### 切换成本

如果直接迁移到 `NSPersistentCloudKitContainer`：

| 方面 | 工作量 |
|------|--------|
| 模型重写 | 所有 `@Model` → `NSManagedObject` 子类 |
| 查询重写 | 所有 `@Query` → `NSFetchRequest` |
| 数据绑定 | 自动 → 手动 KVO |
| 预计时间 | **1-2 周重构** |

### 更好的选择

继续使用 SwiftData + DeleteTracker，优化策略：
1. **多次延迟执行**：5秒和10秒各执行一次
2. **手动同步按钮**：让用户可以主动触发
3. **强制删除策略**：忽略时间戳，只要在删除记录中就删除

## 总结

SwiftData + iCloud 同步的删除冲突是一个常见问题，解决方案的关键是**多次尝试 + 强制策略**：

1. **记录删除时间戳**：使用 `[UUID: Date]` 字典存储到 iCloud Key-Value Store
2. **多次延迟应用删除**：5秒和10秒各执行一次，处理不同网络延迟
3. **强制删除策略**：只要在删除记录中，就强制设置 `isDeleted = true`
4. **24小时保留期**：删除记录保留24小时，防止同步延迟
5. **手动同步按钮**：给用户主动触发的选项
6. **恢复时清理 DeleteTracker**：防止恢复的数据被再次删除

**核心原则**：由于 iCloud 同步是异步且不可控的，我们采用"多次尝试 + 强制策略"来确保删除状态最终被正确应用。
