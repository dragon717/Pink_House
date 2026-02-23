---
name: "swiftdata-icloud-delete-sync"
description: "SwiftData iCloud同步删除冲突解决方案。Invoke when implementing soft delete with iCloud sync in SwiftData, or when deleted data reappears after app restart."
---

# SwiftData iCloud 同步删除冲突解决方案

## 问题场景

在使用 SwiftData + iCloud 同步时，删除操作可能会被 iCloud 同步覆盖，导致已删除的数据在应用重启后"复活"。

### 典型症状

1. 用户删除书页/裙子/手帐等数据
2. 删除后立即查看，数据确实消失了
3. 杀掉应用重新进入
4. 被删除的数据又出现了
5. 日志显示：`isDeleted` 被重置为 `false`，但 `deletedAt` 仍有值

### 根本原因

SwiftData 的 iCloud 同步采用 "Last Writer Wins" 策略：
- 设备 A 删除数据（设置 `isDeleted = true`）
- 设备 B（或云端）的数据同步到设备 A
- 如果云端数据的 `lastModified` 更新，会覆盖本地的删除标记
- 结果：`isDeleted` 被重置为 `false`

## 解决方案：DeleteTracker 模式

### 核心思路

1. **记录删除**：删除时将 ID 记录到 `UserDefaults`
2. **应用启动时修复**：检查 `UserDefaults`，重新应用删除标记
3. **清理记录**：修复成功后清理 `UserDefaults`

### 实现步骤

#### 1. 创建 DeleteTracker

```swift
import Foundation
import SwiftData

@MainActor
final class DeleteTracker {
    static let shared = DeleteTracker()
    
    private let userDefaults = UserDefaults.standard
    private let deletedOutfitsKey = "deletedOutfits"
    
    // MARK: - 记录删除
    
    func recordDeletedOutfit(id: UUID) {
        var deletedIDs = getDeletedOutfitIDs()
        deletedIDs.append(id)
        userDefaults.set(deletedIDs.map { $0.uuidString }, forKey: deletedOutfitsKey)
        print("DeleteTracker: Recorded deleted outfit \(id)")
    }
    
    // MARK: - 获取记录的删除
    
    func getDeletedOutfitIDs() -> [UUID] {
        guard let strings = userDefaults.stringArray(forKey: deletedOutfitsKey) else { return [] }
        return strings.compactMap { UUID(uuidString: $0) }
    }
    
    // MARK: - 应用删除
    
    func applyDeletedOutfits(context: ModelContext) {
        let deletedIDs = getDeletedOutfitIDs()
        guard !deletedIDs.isEmpty else { return }
        
        let descriptor = FetchDescriptor<Outfit>()
        do {
            let allOutfits = try context.fetch(descriptor)
            var appliedCount = 0
            
            for outfit in allOutfits {
                if deletedIDs.contains(outfit.id) && !outfit.isDeleted {
                    outfit.isDeleted = true
                    outfit.deletedAt = Date()
                    outfit.lastModified = Date()
                    appliedCount += 1
                }
            }
            
            if appliedCount > 0 {
                try context.save()
                print("DeleteTracker: Applied \(appliedCount) outfit deletes")
            }
            
            // 清理已应用的删除记录
            clearDeletedOutfits()
        } catch {
            print("DeleteTracker: Failed to apply outfit deletes: \(error)")
        }
    }
    
    // MARK: - 清理记录
    
    func clearDeletedOutfits() {
        userDefaults.removeObject(forKey: deletedOutfitsKey)
    }
    
    // MARK: - 应用所有删除
    
    func applyAllDeletes(context: ModelContext) {
        applyDeletedOutfits(context: context)
        // ... 其他模型
    }
}
```

#### 2. 修改删除逻辑

在删除时，除了设置 `isDeleted`，还要记录到 `DeleteTracker`：

```swift
func deletePage(_ page: Outfit) {
    withAnimation {
        // 1. 设置删除标记
        page.isDeleted = true
        page.deletedAt = Date()
        page.lastModified = Date()
        
        // 2. 保存到数据库
        try? modelContext.save()
        
        // 3. 记录删除到 DeleteTracker（关键！）
        DeleteTracker.shared.recordDeletedOutfit(id: page.id)
        
        // 4. 刷新UI
        loadPages()
    }
}
```

#### 3. 应用启动时应用删除

在 `ItemManagerApp.swift` 中：

```swift
@main
struct ItemManagerApp: App {
    // ...
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // ... 其他初始化
                    
                    // 应用记录的删除（防止iCloud同步覆盖删除状态）
                    let context = SharedPersistence.shared.sharedModelContainer.mainContext
                    DeleteTracker.shared.applyAllDeletes(context: context)
                    
                    // ... 其他初始化
                }
        }
    }
}
```

### 需要更新的文件清单

所有执行软删除的文件都需要更新：

1. **BookDetailView.swift** - 平面书页删除
2. **WardrobeView.swift** - 衣橱裙子删除
3. **BookShelfView.swift** - 手帐删除
4. **OOTDEditorView.swift** - OOTD编辑器删除
5. **SpatialBookShelfView.swift** - 空间手帐删除
6. **OOTDSidebarView.swift** - 侧边栏删除
7. **ClothingDetailView.swift** - 裙子详情删除
8. **SpaceBookDetailView.swift** - 空间书页删除
9. **AssetPanel.swift** - 3D模型删除

### 更新模式

每个删除函数都需要添加：

```swift
// 记录删除到 DeleteTracker，防止iCloud同步覆盖
DeleteTracker.shared.recordDeleted<ModelName>(id: <model>.id)
```

## 最佳实践

### 1. 逻辑删除优于物理删除

```swift
// ✅ 推荐：逻辑删除
item.isDeleted = true
item.deletedAt = Date()

// ❌ 不推荐：物理删除
context.delete(item)
```

### 2. 始终更新 lastModified

```swift
item.isDeleted = true
item.deletedAt = Date()
item.lastModified = Date() // 关键！用于冲突解决
```

### 3. 查询时过滤已删除数据

```swift
@Query(filter: #Predicate<Outfit> { $0.isDeleted == false })
private var outfits: [Outfit]
```

### 4. 批量删除优化

```swift
// 批量设置删除标记
for item in itemsToDelete {
    item.isDeleted = true
    item.deletedAt = Date()
    item.lastModified = Date()
}

// 一次性保存
try? context.save()

// 批量记录删除
for item in itemsToDelete {
    DeleteTracker.shared.recordDeletedOutfit(id: item.id)
}
```

## 调试技巧

### 1. 添加详细日志

```swift
print("### DELETE: Setting isDeleted=true for page '\(page.note)'")
print("### DELETE: Before save - isDeleted=\(page.isDeleted)")
try? context.save()
print("### DELETE: Saved successfully")
```

### 2. 检查 DeleteTracker 记录

```swift
let deletedIDs = DeleteTracker.shared.getDeletedOutfitIDs()
print("Pending deletes: \(deletedIDs)")
```

### 3. 验证应用启动修复

```swift
func applyDeletedOutfits(context: ModelContext) {
    // ...
    print("DeleteTracker: Applied delete to outfit '\(outfit.note)'")
    // ...
}
```

## 常见陷阱

### ❌ 只在删除时设置 isDeleted

```swift
// 错误：iCloud 同步会覆盖
item.isDeleted = true
try? context.save()
```

### ✅ 使用 DeleteTracker 记录删除

```swift
// 正确：即使被覆盖，启动时也会修复
item.isDeleted = true
try? context.save()
DeleteTracker.shared.recordDeletedOutfit(id: item.id)
```

### ❌ 忘记更新 lastModified

```swift
// 错误：冲突解决可能失败
item.isDeleted = true
item.deletedAt = Date()
```

### ✅ 同时更新 lastModified

```swift
// 正确：确保冲突解决正确
item.isDeleted = true
item.deletedAt = Date()
item.lastModified = Date()
```

## 总结

SwiftData + iCloud 同步的删除冲突是一个常见问题，解决方案是：

1. **逻辑删除**：使用 `isDeleted` 标记而不是物理删除
2. **记录删除**：使用 `DeleteTracker` 将删除 ID 保存到 `UserDefaults`
3. **启动修复**：应用启动时检查并重新应用删除标记
4. **更新 lastModified**：确保冲突解决机制正确工作

这样可以确保即使 iCloud 同步覆盖了删除状态，应用启动时也会自动修复，用户不会看到已删除的数据"复活"。
