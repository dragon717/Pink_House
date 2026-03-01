# GRDB + CloudKit 影子模型架构实现总结

## 架构概述

采用业界成熟的"影子模型"架构，完全独立于 SwiftData：

```
┌─────────────────────────────────────────────────────────────┐
│                    裙子股市架构 V3                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────────┐      ┌─────────────────────────────┐ │
│  │  GRDB 本地存储    │◄────►│   CloudKit 公共数据库        │ │
│  │  skirt_market.db │      │   iCloud.bugod2.SkirtMarket │ │
│  │  完全独立 SQLite │      │   所有用户共享               │ │
│  └──────────────────┘      └─────────────────────────────┘ │
│           ▲                                               │
│           │                                               │
│  ┌────────┴────────┐                                      │
│  │   SyncEngine    │  ← 异步同步引擎                      │
│  └─────────────────┘                                      │
│                                                             │
│  ┌──────────────────┐                                     │
│  │ SwiftUI 视图层   │  ← GRDBLolitaItemObserver           │
│  │ (响应式更新)      │    替代 @Query                      │
│  └──────────────────┘                                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 核心组件

### 1. GRDBManager
- **文件**: [GRDBManager.swift](file:///Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Services/SkirtMarket/GRDBSkirtMarket/GRDBManager.swift)
- **职责**: 管理独立的 SQLite 数据库
- **特点**:
  - 使用 `DatabasePool` 支持并发访问
  - 存储在 `Application Support/SkirtMarketGRDB/` 目录
  - 不参与 iCloud 备份
  - 完全独立于 SwiftData

### 2. GRDBLolitaItem
- **文件**: [GRDBLolitaItem.swift](file:///Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Services/SkirtMarket/GRDBSkirtMarket/Models/GRDBLolitaItem.swift)
- **职责**: 数据模型 + 查询方法 + SwiftUI 观察器
- **特点**:
  - 使用 `Codable` + `FetchableRecord` + `PersistableRecord`
  - 内置 `GRDBLolitaItemObserver` 替代 `@Query`
  - 支持软删除和同步状态跟踪

### 3. SyncEngine
- **文件**: [SyncEngine.swift](file:///Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Services/SkirtMarket/GRDBSkirtMarket/SyncEngine.swift)
- **职责**: 协调本地 GRDB 和云端 CloudKit
- **特点**:
  - 定时同步（每5分钟）
  - 双向同步（上传 + 拉取）
  - 冲突检测和处理
  - 异步队列保证顺序

### 4. GRDBDressStockMarketView
- **文件**: [GRDBDressStockMarketView.swift](file:///Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Services/SkirtMarket/GRDBSkirtMarket/Views/GRDBDressStockMarketView.swift)
- **职责**: SwiftUI 界面示例
- **特点**:
  - 使用 `GRDBLolitaItemObserver` 实现响应式
  - 手动同步按钮
  - 同步状态显示

## 数据库 Schema

### lolita_items 表
```sql
CREATE TABLE lolita_items (
    id TEXT PRIMARY KEY,
    cloud_kit_record_id TEXT,
    platform_id TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL,
    raw_title TEXT NOT NULL,
    cleaned_name TEXT,
    brand TEXT,
    current_price REAL NOT NULL,
    currency TEXT NOT NULL DEFAULT 'CNY',
    status TEXT NOT NULL DEFAULT 'unknown',
    is_deleted BOOLEAN NOT NULL DEFAULT 0,
    last_updated DATETIME NOT NULL,
    first_seen_at DATETIME NOT NULL,
    sync_status TEXT NOT NULL DEFAULT 'pending',
    modified_at DATETIME NOT NULL
);
```

### 其他表
- `skirt_metrics`: 股票指标
- `market_indices`: 市场指数
- `monitor_tasks`: 监控任务
- `monitor_nodes`: 监控节点
- `sync_outbox`: 同步队列

## 使用方式

### 1. 初始化（在 App 启动时）
```swift
// 初始化 GRDB
try await GRDBManager.shared.initialize()

// 配置同步引擎
await SyncEngine.shared.configure()

// 从云端拉取数据
await SyncEngine.shared.pullFromCloud()
```

### 2. 在 SwiftUI 中使用
```swift
struct MyView: View {
    @StateObject private var observer = GRDBLolitaItemObserver()
    
    var body: some View {
        List(observer.items) { item in
            Text(item.rawTitle)
        }
        .onAppear {
            observer.startObservingActive()
        }
        .onDisappear {
            observer.stopObserving()
        }
    }
}
```

### 3. 添加数据
```swift
let item = GRDBLolitaItem(
    platform: "xianyu",
    platformID: "123456",
    rawTitle: "AP 小白云",
    currentPrice: 2500.0
)

try await GRDBManager.shared.writer?.write { db in
    try item.insert(db)
}
```

### 4. 手动同步
```swift
await SyncEngine.shared.syncToCloud()   // 上传到云端
await SyncEngine.shared.pullFromCloud() // 从云端拉取
```

## 优势

### ✅ 完全隔离
- 使用独立的 SQLite 文件
- 不依赖 SwiftData 或 Core Data
- 不会影响主应用的数据库

### ✅ 高性能
- GRDB 比 SwiftData 更快
- 支持复杂的 SQL 查询
- 数据库连接池优化并发

### ✅ 响应式
- `GRDBLolitaItemObserver` 替代 `@Query`
- 自动监听数据库变化
- SwiftUI 自动更新

### ✅ 可靠的同步
- 异步 SyncEngine
- 支持离线操作
- 自动重试机制
- 冲突检测

### ✅ 类型安全
- 编译时 SQL 检查
- Codable 支持
- 强类型模型

## 待办事项

### 需要添加的依赖
在 `Package.swift` 或 Xcode 中添加：
```swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
]
```

### 需要完成的模型
- [ ] GRDBSkirtStockMetric
- [ ] GRDBLolitaMarketIndex
- [ ] GRDBMonitorTask
- [ ] GRDBMonitorNode

### 需要完成的视图
- [ ] 市场指数视图
- [ ] 节点监控视图
- [ ] 商品详情视图

### 需要优化的功能
- [ ] 冲突解决策略
- [ ] 增量同步优化
- [ ] 后台同步支持
- [ ] 数据压缩/加密

## 注意事项

1. **GRDB 依赖**: 需要先添加 GRDB 库到项目
2. **线程安全**: 所有数据库操作都在正确的队列执行
3. **错误处理**: 需要完善错误处理和用户提示
4. **测试**: 需要充分测试同步逻辑

## 与 SwiftData 方案对比

| 特性 | SwiftData 方案 | GRDB 方案 |
|------|---------------|-----------|
| 数据隔离 | ❌ 有风险 | ✅ 完全隔离 |
| 性能 | 中等 | 高 |
| 复杂度 | 低 | 中等 |
| 灵活性 | 低 | 高 |
| 同步控制 | 有限 | 完全控制 |
| 学习成本 | 低 | 中等 |

## 结论

GRDB + CloudKit 影子模型架构是目前最稳健的方案，它：
- 完全避免了与主应用数据库的冲突
- 提供了更好的性能和灵活性
- 实现了可靠的云端同步

建议采用此方案重构裙子股市功能。
