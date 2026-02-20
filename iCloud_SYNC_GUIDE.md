# iCloud 同步实现指南

## 概述

本项目已实现完整的 iCloud 同步功能，包括自动同步、数据迁移和去重机制。

## 核心组件

### 1. SwiftDataMigrationManager

**文件**: `ItemManager/Services/SwiftDataMigrationManager.swift`

负责：
- 创建支持 iCloud 的 ModelContainer
- 执行本地数据到 iCloud 的迁移
- **数据去重**：通过 ID 检查避免重复数据

**去重逻辑示例**:
```swift
for item in items {
    let id = item.id
    let fetchDescriptor = FetchDescriptor<Clothing>(predicate: #Predicate { $0.id == id })
    let existing = try? cloudContext.fetch(fetchDescriptor).first
    
    if existing == nil {  // 去重检查
        let newItem = createClothingCopy(from: item)
        cloudContext.insert(newItem)
    }
}
```

### 2. iCloudSyncManager

**文件**: `ItemManager/Services/iCloudSyncManager.swift`

负责：
- 同步状态监控
- 冲突解决（"最后写入者胜出"策略）
- 提供 `SyncableModel` 协议支持

**冲突解决**:
```swift
func resolveConflict<T: PersistentModel>(
    local: T,
    remote: T,
    localTimestamp: Date,
    remoteTimestamp: Date
) -> T {
    if localTimestamp > remoteTimestamp {
        return local  // 保留本地数据
    } else {
        return remote  // 采用远程数据
    }
}
```

### 3. iCloudSyncStatusView

**文件**: `ItemManager/Views/Components/iCloudSyncStatusView.swift`

提供：
- 同步状态可视化
- 手动同步触发
- 迁移进度显示

## CloudKit 自动同步配置

### ModelContainer 配置

在 `SwiftDataMigrationManager.createCloudModelContainer()` 中：

```swift
let cloudConfig = ModelConfiguration(
    schema: schema,
    isStoredInMemoryOnly: false,
    cloudKitDatabase: .automatic  // 自动使用 CloudKit
)
```

### 模型要求

所有支持 iCloud 同步的模型必须：

1. **有默认值的属性**:
```swift
@Model
final class Clothing {
    var id: UUID = UUID()
    var name: String = ""  // 必须有默认值
    var lastModified: Date = Date()  // iCloud 同步时间戳
}
```

2. **可选的关系**:
```swift
@Relationship(deleteRule: .nullify)
var tags: [Tag]? = []  // 必须是 Optional
```

3. **移除 unique 约束**:
```swift
// 不要这样写
@Attribute(.unique) var id: UUID  // ❌

// 应该这样写
var id: UUID = UUID()  // ✅
```

## 数据去重机制

### 1. 迁移时去重

当从本地数据库迁移到 iCloud 时：

```
本地数据 → 检查云端是否存在相同ID → 不存在则插入
```

**实现位置**: `SwiftDataMigrationManager` 的各个 `migrateXXX` 方法

### 2. 运行时去重

SwiftData + CloudKit 自动处理：
- 同一记录的多设备编辑会产生冲突
- 使用 `lastModified` 时间戳决定保留哪个版本
- 冲突解决后自动同步到所有设备

### 3. 多设备场景

**场景**: 用户在 iPhone 和 iPad 上同时创建相同的数据

**解决方案**:
1. 每个数据有唯一的 `id` (UUID)
2. 使用 `lastModified` 时间戳判断最新版本
3. 冲突时采用 "最后写入者胜出" 策略
4. 数组合并使用 `mergeArrays` 方法

## 使用指南

### 1. 启用 iCloud 同步

在应用设置中开启 iCloud 同步开关：

```swift
SwiftDataMigrationManager.shared.isCloudSyncEnabled = true
```

### 2. 初始化同步

应用启动时自动初始化：

```swift
let container = try SwiftDataMigrationManager.shared.createModelContainer()
iCloudSyncManager.shared.setup(with: container)
```

### 3. 显示同步状态

在 UI 中添加同步状态指示器：

```swift
iCloudSyncStatusView()
```

### 4. 监听同步事件

```swift
NotificationCenter.default.addObserver(
    forName: iCloudSyncManager.syncStatusChanged,
    object: nil,
    queue: .main
) { notification in
    // 更新 UI
}
```

## 故障排除

### 1. 同步不工作

检查清单：
- [ ] iCloud 账户是否登录
- [ ] 网络连接是否正常
- [ ] `Capabilities` 中是否启用 CloudKit
- [ ] Container ID 是否正确配置

### 2. 数据重复

可能原因：
- 迁移过程中断
- 多设备同时创建相同数据

解决方案：
- 重新执行迁移：`iCloudSyncManager.shared.performMigration()`
- 手动删除重复数据

### 3. 冲突解决

默认使用 "最后写入者胜出" 策略。如需自定义：

```swift
extension Clothing: SyncableModel {
    func merge(with other: Clothing) {
        // 自定义合并逻辑
        if other.lastModified > self.lastModified {
            self.name = other.name
            self.price = other.price
            // ... 其他字段
        }
    }
}
```

## 最佳实践

1. **始终使用 UUID**: 确保每条记录有唯一标识
2. **添加 lastModified**: 支持冲突解决
3. **避免大量数据一次性同步**: 分批处理
4. **提供用户反馈**: 显示同步状态和进度
5. **处理离线场景**: 保存到本地，恢复网络后自动同步

## 文件清单

- `ItemManager/Services/SwiftDataMigrationManager.swift` - 迁移管理器
- `ItemManager/Services/iCloudSyncManager.swift` - 同步管理器
- `ItemManager/Views/Components/iCloudSyncStatusView.swift` - 状态视图

## 模型修改清单

已添加 `lastModified` 字段的模型：
- ✅ Clothing
- ✅ CutoutItem
- ✅ BookGroup
- ✅ Outfit
- ✅ SpaceBookGroup
- ✅ SpaceOutfit
- ✅ Tag
- ✅ Brand
- ✅ SceneObjectData
- ✅ Model3D

已移除 `@Attribute(.unique)` 的模型：
- ✅ 所有模型

已将关系改为 Optional 的模型：
- ✅ 所有模型
