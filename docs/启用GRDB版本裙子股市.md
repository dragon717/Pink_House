# 启用 GRDB 版本裙子股市

## 已完成的更改

### 1. 启用 GRDB 初始化
在 [ItemManagerApp.swift](file:///Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/ItemManagerApp.swift#L153-L159) 中：
```swift
// 0.7 裙子股市功能 - 使用 GRDB 版本（完全独立于 SwiftData）
do {
    try await GRDBManager.shared.initialize()
    await SyncEngine.shared.configure()
    print("✅ 裙子股市功能已启用（GRDB 版本）")
} catch {
    print("❌ 裙子股市初始化失败: \(error)")
}
```

### 2. 更新视图入口
在 [MainTabView.swift](file:///Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/MainTabView.swift#L743-L744) 中：
```swift
// 使用 GRDB 版本的裙子股市（完全独立于 SwiftData）
GRDBDressStockMarketView()
```

## 架构对比

### 旧架构（已禁用）
```
SwiftData ModelContainer (冲突！)
    ↓
与主应用共享 Core Data 存储
    ↓
表结构冲突导致数据丢失
```

### 新架构（GRDB）
```
GRDB SQLite (完全独立)
    ↓
独立的 skirt_market.sqlite 文件
    ↓
SyncEngine ←→ CloudKit 公共数据库
    ↓
不影响主应用任何数据
```

## 优势

✅ **完全隔离** - 独立的 SQLite 数据库，不影响主应用
✅ **高性能** - GRDB 比 SwiftData 更快
✅ **可靠同步** - 异步 SyncEngine，支持离线操作
✅ **类型安全** - 编译时 SQL 检查

## 测试步骤

1. **Clean Build** - Cmd+Shift+K
2. **运行应用** - 检查控制台输出：
   - 应该看到 "✅ 裙子股市功能已启用（GRDB 版本）"
   - 应该看到 "📦 GRDBManager: 数据库初始化成功"
3. **进入裙子股市** - 检查是否能正常显示界面
4. **添加测试数据** - 测试添加商品功能
5. **检查同步** - 测试 CloudKit 同步

## 回滚方案

如果出现问题，可以回滚到禁用状态：

```swift
// 在 ItemManagerApp.swift 中注释掉 GRDB 初始化
// try await GRDBManager.shared.initialize()
// await SyncEngine.shared.configure()
print("⚠️ 裙子股市功能已禁用")
```

## 注意事项

1. **首次启动** - 会创建新的 SQLite 数据库文件
2. **iCloud 同步** - 需要登录 iCloud 才能同步到云端
3. **数据隔离** - 裙子股市数据完全独立于衣橱数据
4. **备份恢复** - 裙子股市数据不参与 iCloud 文件备份

## 文件位置

- **本地数据库**: `Application Support/SkirtMarketGRDB/skirt_market.sqlite`
- **CloudKit 容器**: `iCloud.bugod2.SkirtMarket`
- **不参与备份**: 已设置 `isExcludedFromBackup = true`
