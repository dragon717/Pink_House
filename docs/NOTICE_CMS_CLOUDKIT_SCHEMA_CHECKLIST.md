# 公告系统 CloudKit Schema 与索引部署清单（E4）

> 更新时间：2026-04-06  
> 用途：为公告系统升级提供 CloudKit Record Type、字段、索引、环境部署与检查清单，供开发与上线前核对使用。

## 1. 目标

为 Notice CMS 提供稳定的 CloudKit 公共数据和私有状态数据结构，避免仅改本地模型但云端结构不匹配。

---

## 2. 容器范围

主容器：

- `iCloud.bugod2.ItemManager`

数据库职责：

- `Public Database`
  - 公告主数据
  - 发布相关公共信息
- `Private Database`
  - 用户公告状态
  - 用户已读/确认/忽略信息

---

## 3. Record Type 规划

### 3.1 `Notice`

用途：

- 存放公告主数据

建议字段：

- `id`
- `title`
- `summary`
- `content`
- `locale`
- `tags`
- `mediaType`
- `coverMedia`
- `builtinMediaName`
- `status`
- `channel`
- `severity`
- `displayPriority`
- `isPinned`
- `requiresAck`
- `isSilent`
- `publishAt`
- `startAt`
- `endAt`
- `archivedAt`
- `audience`
- `minAppVersion`
- `maxAppVersion`
- `actionType`
- `actionTarget`
- `actionLabel`
- `environment`
- `revision`
- `rollbackFrom`
- `createdBy`
- `updatedBy`
- `publishedBy`
- `createdAt`
- `updatedAt`
- `metadata`

### 3.2 `NoticeUserState`

用途：

- 存放用户公告状态

建议字段：

- `noticeID`
- `state`
- `readAt`
- `acknowledgedAt`
- `dismissedAt`
- `presentationCount`
- `lastPresentedAt`

### 3.3 可选 `NoticeAuditLog`

用途：

- 审计日志

建议字段：

- `noticeID`
- `fromStatus`
- `toStatus`
- `operatorID`
- `operationType`
- `operationReason`
- `revision`
- `createdAt`

---

## 4. 字段类型建议

| 字段类别 | CloudKit 类型建议 |
|---|---|
| 文本类 | `String` |
| 状态/枚举 | `String` |
| 布尔值 | `Int` 或 `String` 按现网一致性决定 |
| 时间 | `Date/Time` |
| 排序权重 | `Int` |
| 标签集合 | JSON String 或可支持的列表结构 |
| 媒体引用 | `String` 或 `Asset` |

说明：

- 若当前项目在布尔值上已大量采用 `Bool` 直存，可继续沿用项目现状。
- 标签集合若 CloudKit Schema 使用上受限，优先 JSON String。

---

## 5. Queryable / Sortable 建议

### `Notice`

优先 Queryable：

- `id`
- `status`
- `channel`
- `severity`
- `environment`
- `isPinned`
- `requiresAck`
- `publishAt`
- `startAt`
- `endAt`
- `updatedAt`

优先 Sortable：

- `publishAt`
- `updatedAt`
- `displayPriority`
- `archivedAt`

### `NoticeUserState`

优先 Queryable：

- `noticeID`
- `state`
- `readAt`
- `acknowledgedAt`
- `dismissedAt`

优先 Sortable：

- `lastPresentedAt`
- `readAt`
- `acknowledgedAt`

---

## 6. 权限建议

### Public Database

`Notice`：

- World Read：是
- World Write：否
- Authenticated Read：是
- Authenticated Write：按业务策略，不建议开放通用写
- 管理写入能力：通过应用内角色控制，不依赖 World Write

### Private Database

`NoticeUserState`：

- 用户仅读写自己的记录

---

## 7. 环境部署清单

### Development

- [ ] `Notice` 新字段已创建
- [ ] `NoticeUserState` 已创建
- [ ] Queryable/Sortable 索引已配置
- [ ] 测试数据已验证

### Production

- [ ] Schema 已从 Development 部署
- [ ] `Notice` 字段与索引已确认
- [ ] `NoticeUserState` 字段与索引已确认
- [ ] 权限设置已确认
- [ ] 正式公告已在 Production 验证

---

## 8. 部署顺序建议

1. 先在 Development 建立新字段
2. 验证本地模型与 CloudKit 映射
3. 验证用户列表、banner、modal 查询
4. 验证用户状态写入与读取
5. 将 Schema 部署到 Production
6. 在 Production 做正式验证

---

## 9. 上线前检查清单

- [ ] 新主模型字段已在 CloudKit 存在
- [ ] 用户状态模型字段已在 Private DB 存在
- [ ] 关键查询字段具备 Queryable/Sortable 能力
- [ ] Development 与 Production 都已核对
- [ ] 正式环境中已能读写新记录

---

## 10. 冻结结论

本清单冻结以下共识：

1. 只改本地模型不够，CloudKit Schema 必须同步升级。
2. Development 与 Production 必须分别核对，不可想当然。
3. 公告主数据和用户状态必须分库存放。
