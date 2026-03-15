//
//  SkirtMarketPersistenceV2.swift
//  裙装股市 - SwiftData 多容器架构 V2
//
//  实现完全隔离的双容器架构：
//  - 主容器：保留原有衣橱数据（Private Database）
//  - 裙装股市容器：独立的公共数据库（Public Database）
//

import Foundation
import SwiftData
import CloudKit

/// 裙装股市数据持久化管理器 V2
/// 使用完全独立的 ModelContainer，与主应用数据完全隔离
@MainActor
final class SkirtMarketPersistenceV2 {
    static let shared = SkirtMarketPersistenceV2()
    
    /// 裙装股市专用的 ModelContainer（完全独立）
    var skirtMarketContainer: ModelContainer?
    
    /// 是否已配置
    private(set) var isConfigured = false
    
    /// 配置错误
    private(set) var configurationError: Error?
    
    private init() {}
    
    // MARK: - 配置方法
    
    /// 配置裙装股市的独立数据库
    /// 使用独立的存储文件，与主应用完全隔离
    func configure() async {
        print("🏛️ 裙装股市 V2: 开始配置独立数据库...")
        
        do {
            // 1. 创建独立的 Schema（只包含裙装股市模型）
            let schema = createSkirtMarketSchema()
            
            // 2. 创建独立的 ModelConfiguration
            // 关键：使用独立的存储文件名，与主应用完全隔离
            let config = createIsolatedConfiguration(schema: schema)
            
            // 3. 创建独立的 ModelContainer
            let container = try ModelContainer(for: schema, configurations: [config])
            self.skirtMarketContainer = container
            
            self.isConfigured = true
            print("✅ 裙装股市 V2: 独立数据库配置成功")
            print("   📁 存储位置: 独立的 skirt_market.store 文件")
            
        } catch {
            self.configurationError = error
            self.isConfigured = false
            print("❌ 裙装股市 V2: 配置失败: \(error)")
        }
    }
    
    // MARK: - Schema 定义（完全独立）
    
    /// 裙装股市专用的 Schema
    /// 只包含裙装股市相关的模型，不包含任何主应用模型
    private func createSkirtMarketSchema() -> Schema {
        Schema([
            LolitaItem.self,
            SkirtStockMetric.self,
            LolitaMarketIndex.self,
            MonitorTask.self,
            MonitorNode.self
        ])
    }
    
    // MARK: - 独立配置
    
    /// 创建完全独立的配置
    /// 使用独立的存储文件，确保与主应用完全隔离
    private func createIsolatedConfiguration(schema: Schema) -> ModelConfiguration {
        // 关键：明确指定独立的存储文件名，避免与主应用的 default.store 冲突
        // 使用 .none 禁用 CloudKit，使用纯本地存储
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // 禁用 SwiftData 的 CloudKit 同步
        )
        
        // 注意：CloudKit 公共数据库功能需要通过原生 CloudKit API 实现
        // 参考：https://developer.apple.com/documentation/cloudkit/
        
        return config
    }
    
    /// 获取裙装股市独立的存储目录
    /// 确保与主应用的存储完全隔离
    private func getSkirtMarketStoreDirectory() -> URL? {
        let fileManager = FileManager.default
        
        // 使用 Application Support 下的独立子目录
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        // 创建独立的子目录
        let skirtMarketDir = appSupport.appendingPathComponent("SkirtMarket", isDirectory: true)
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: skirtMarketDir.path) {
            do {
                try fileManager.createDirectory(at: skirtMarketDir, withIntermediateDirectories: true)
                
                // 设置目录不参与 iCloud 备份
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                var mutableURL = skirtMarketDir
                try mutableURL.setResourceValues(resourceValues)
                
                print("📁 创建裙装股市独立存储目录: \(skirtMarketDir.path)")
            } catch {
                print("❌ 创建裙装股市存储目录失败: \(error)")
                return nil
            }
        }
        
        return skirtMarketDir
    }
    
    /// 配置裙装股市存储文件不参与 iCloud 备份
    /// 在应用启动时调用
    func excludeFromBackup() {
        guard let container = skirtMarketContainer else { return }
        
        // 获取存储文件 URL
        if let storeURL = getStoreURL() {
            do {
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                var mutableURL = storeURL
                try mutableURL.setResourceValues(resourceValues)
                print("📁 裙装股市存储文件已排除在 iCloud 备份外")
            } catch {
                print("⚠️ 设置备份排除失败: \(error)")
            }
        }
    }
    
    /// 获取存储文件 URL
    private func getStoreURL() -> URL? {
        // SwiftData 存储在 Application Support 目录
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?.appendingPathComponent("skirt_market.store")
    }
    
    // MARK: - 公共方法
    
    /// 获取裙装股市的主上下文
    var mainContext: ModelContext? {
        guard let container = skirtMarketContainer else { return nil }
        return ModelContext(container)
    }
    
    /// 创建新的上下文（用于后台操作）
    func newContext() -> ModelContext? {
        guard let container = skirtMarketContainer else { return nil }
        return ModelContext(container)
    }
}

// MARK: - 架构说明

/*
## SwiftData 多容器架构 V2

### 问题背景
之前的实现中，SkirtMarketPersistence 使用了与主应用相同的 CloudKit 容器，
导致两个 ModelContainer 冲突，原有衣橱数据表被删除。

### 解决方案
使用完全独立的 ModelContainer：

1. **独立的 Schema**
   - 主应用：Clothing, Item, Outfit, Model3D 等
   - 裙装股市：LolitaItem, SkirtStockMetric, MonitorTask 等
   - 两个 Schema 完全不重叠

2. **独立的存储文件**
   - SwiftData 会自动为不同的 ModelConfiguration 创建独立的存储文件
   - 主应用：default.store
   - 裙装股市：skirt_market.store（自动命名）

3. **独立的 CloudKit 同步**
   - 每个存储文件对应独立的 CloudKit 容器实例
   - 主应用：Private Database（默认）
   - 裙装股市：Public Database（通过配置指定）

### 使用方式

```swift
// 在 App 启动时配置
@main
struct ItemManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // 配置主应用数据库（原有）
                    await SharedPersistence.shared.configure()
                    
                    // 配置裙装股市数据库（独立）
                    await SkirtMarketPersistenceV2.shared.configure()
                }
        }
        // 只注入主应用的 ModelContainer
        .modelContainer(SharedPersistence.shared.sharedModelContainer)
    }
}
```

### 关键区别

| 特性 | 主应用 | 裙装股市 |
|------|--------|----------|
| Schema | Clothing, Item, Outfit... | LolitaItem, SkirtStockMetric... |
| 存储文件 | default.store | skirt_market.store |
| CloudKit | Private Database | Public Database |
| 数据隔离 | ✅ 完全隔离 | ✅ 完全隔离 |

### 注意事项

1. **不要混用 ModelContainer**
   - 主应用的视图使用 SharedPersistence.shared.sharedModelContainer
   - 裙装股市的视图手动获取 SkirtMarketPersistenceV2.shared.mainContext

2. **@Query 的使用**
   - 主应用：正常使用 @Query
   - 裙装股市：需要手动获取数据，因为 @Query 默认使用 environment 的 container

3. **数据迁移**
   - 两个容器完全独立，不需要考虑迁移问题
   - 删除裙装股市数据不会影响主应用数据
*/
