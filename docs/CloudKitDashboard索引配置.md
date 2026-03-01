# CloudKit Dashboard 索引配置指南

## 错误说明

```
Field 'recordName' is not marked queryable
```

这个错误表示 CloudKit 记录中的 `recordName` 字段没有被标记为可查询，导致无法执行查询操作。

## 解决步骤

### 1. 访问 CloudKit Dashboard

1. 打开 https://icloud.developer.apple.com/dashboard/
2. 使用 Apple Developer 账号登录
3. 选择容器 `iCloud.bugod2.SkirtMarket`

### 2. 配置 LolitaItem 记录类型的索引

1. 点击左侧菜单 **"Record Types"**
2. 选择 **"LolitaItem"**
3. 点击 **"Indexes"** 标签
4. 添加以下索引：

| 字段名 | 索引类型 | 说明 |
|--------|----------|------|
| recordName | Queryable | 记录唯一标识 |
| lastUpdated | Sortable | 按时间排序 |
| platformID | Queryable | 平台商品ID查询 |

### 3. 配置其他记录类型的索引

对以下记录类型重复步骤 2：

#### SkirtStockMetric
| 字段名 | 索引类型 |
|--------|----------|
| recordName | Queryable |
| timestamp | Sortable |

#### LolitaMarketIndex
| 字段名 | 索引类型 |
|--------|----------|
| recordName | Queryable |
| timestamp | Sortable |

#### MonitorTask
| 字段名 | 索引类型 |
|--------|----------|
| recordName | Queryable |
| status | Queryable |
| createdAt | Sortable |

### 4. 部署到生产环境

1. 配置完所有索引后，点击 **"Deploy"** 按钮
2. 等待部署完成（可能需要几分钟）

## 替代方案：代码中处理

如果暂时无法配置 CloudKit Dashboard，可以在代码中修改查询方式，避免查询 recordName：

```swift
// 修改前的查询（使用 recordName）
let query = CKQuery(recordType: "LolitaItem", predicate: NSPredicate(value: true))

// 修改后的查询（使用 platformID）
let predicate = NSPredicate(format: "platformID != %@", "")
let query = CKQuery(recordType: "LolitaItem", predicate: predicate)
```

## 验证配置

配置完成后，重新运行应用，检查控制台输出：

```
☁️ 开始从 CloudKit 拉取数据...
✅ 从云端拉取了 X 条记录
```

如果看到 "✅ 从云端拉取了"，说明配置成功。

## 注意事项

1. **索引生效时间** - 部署后可能需要几分钟才能生效
2. **免费额度** - CloudKit 有查询次数限制，注意监控使用量
3. **recordName** - 这是 CloudKit 内部字段，通常用于唯一标识记录
