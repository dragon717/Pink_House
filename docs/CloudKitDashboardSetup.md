# CloudKit Dashboard 配置指南

## 问题说明

你看到的错误 "Invalid container to get datastore" 是因为新容器 `iCloud.bugod2.SkirtMarket` 还没有被 CloudKit 服务器识别。这通常发生在：

1. 容器刚添加到 entitlements，还没有被任何设备访问过
2. 需要先在真实设备或模拟器上运行应用，触发 CloudKit 初始化

## 解决方案

### 方法一：通过应用自动初始化（推荐）

1. **在 Xcode 中运行应用**（使用真实设备或模拟器）
2. **确保 iCloud 已登录**
3. 应用启动时会自动调用 `CloudKitSetup.shared.initializeContainer()`
4. 这会创建所有必要的记录类型

### 方法二：手动在 CloudKit Dashboard 配置

如果自动初始化失败，可以手动配置：

#### 步骤 1：访问 CloudKit Dashboard

1. 打开 https://icloud.developer.apple.com/dashboard/
2. 使用你的 Apple Developer 账号登录
3. 在左侧选择你的 App
4. 确认能看到 `iCloud.bugod2.SkirtMarket` 容器

#### 步骤 2：创建记录类型

点击 "Record Types" → "+" 创建以下类型：

**1. LolitaItem**
```
Fields:
- platformID: String (Required)
- platform: String (Required)
- rawTitle: String (Required)
- cleanedName: String (Optional)
- brand: String (Optional)
- currentPrice: Double (Required)
- currency: String (Required)
- status: String (Required)
- isDeleted: Int (Required)  // 0 = false, 1 = true
- lastUpdated: Date/Time (Required)
```

**2. SkirtStockMetric**
```
Fields:
- skirtName: String (Required)
- platformID: String (Required)
- currentPrice: Double (Required)
- priceChange: Double (Required)
- changePercent: Double (Required)
- volume24h: Int (Required)
- trend: String (Required)
- timestamp: Date/Time (Required)
```

**3. LolitaMarketIndex**
```
Fields:
- indexValue: Double (Required)
- changePercent: Double (Required)
- totalVolume: Int (Required)
- activeItems: Int (Required)
- timestamp: Date/Time (Required)
```

**4. MonitorTask**
```
Fields:
- platformID: String (Required)
- platform: String (Required)
- taskType: String (Required)
- status: String (Required)
- priority: Int (Required)
- createdAt: Date/Time (Required)
- updatedAt: Date/Time (Required)
- claimedBy: String (Optional)
- claimedAt: Date/Time (Optional)
- result: String (Optional)
```

**5. MonitorNode**
```
Fields:
- nodeID: String (Required)
- deviceName: String (Required)
- isActive: Int (Required)
- lastSeen: Date/Time (Required)
- completedTasks: Int (Required)
- reliabilityScore: Double (Required)
```

#### 步骤 3：配置权限（Security Roles）

点击 "Security Roles"：

1. **选择 `_world` 角色**（所有用户）
2. **设置权限**：
   - LolitaItem: Read (✅), Write (❌)
   - SkirtStockMetric: Read (✅), Write (❌)
   - LolitaMarketIndex: Read (✅), Write (❌)
   - MonitorTask: Read (✅), Write (❌)
   - MonitorNode: Read (✅), Write (❌)

3. **选择 `_icloud` 角色**（已登录 iCloud 的用户）
4. **设置权限**：
   - LolitaItem: Read (✅), Write (✅)
   - SkirtStockMetric: Read (✅), Write (✅)
   - LolitaMarketIndex: Read (✅), Write (✅)
   - MonitorTask: Read (✅), Write (✅)
   - MonitorNode: Read (✅), Write (✅)

#### 步骤 4：创建索引

点击 "Indexes"，为每个记录类型创建以下索引：

**LolitaItem:**
- platformID: Queryable
- lastUpdated: Sortable
- isDeleted: Queryable

**SkirtStockMetric:**
- skirtName: Queryable
- timestamp: Sortable

**LolitaMarketIndex:**
- timestamp: Sortable

**MonitorTask:**
- status: Queryable
- createdAt: Sortable

## 验证配置

配置完成后，在 CloudKit Dashboard 的 "Data" 标签页中：

1. 应该能看到所有记录类型
2. 尝试手动创建一条 LolitaItem 记录
3. 确认没有权限错误

## 故障排除

### 错误："Invalid container to get datastore"

**原因**：容器还没有被 CloudKit 服务器完全初始化

**解决**：
1. 确保 entitlements 文件已正确配置
2. 在 Xcode 中 Clean Build Folder (Cmd+Shift+K)
3. 重新运行应用
4. 等待几分钟让 CloudKit 服务器同步

### 错误："Permission denied"

**原因**：Security Roles 权限配置不正确

**解决**：
1. 检查 `_world` 和 `_icloud` 角色的权限设置
2. 确保至少给 `_icloud` 角色 Write 权限
3. 保存更改后等待几分钟生效

### 错误："Record type not found"

**原因**：记录类型还没有创建

**解决**：
1. 确认在 Record Types 中已创建所有需要的类型
2. 检查字段名称拼写是否正确
3. 重新运行应用触发自动创建

## 参考

- [CloudKit Documentation](https://developer.apple.com/documentation/cloudkit/)
- [CloudKit Dashboard Guide](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/EnablingCloudKit/EnablingCloudKit.html)
