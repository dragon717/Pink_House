# 公告系统字段表（A1）

> 更新时间：2026-04-06  
> 对应任务：`NOTICE_CMS_DEV_TASKS.md` 中 A1  
> 用途：冻结公告系统主模型与用户状态模型字段，作为数据层、前端、CloudKit Schema 的统一依据。

## 1. 设计原则

1. 内容字段与展示字段分离。
2. 生命周期字段与审计字段分离。
3. 用户状态单独建模，不混入公告主记录。
4. 旧字段优先兼容映射，不直接复用旧语义。
5. 所有字段都必须能说明“为什么存在”。

---

## 2. 公告主模型字段

| 字段名 | 类型 | 必填 | 默认值 | 查询/排序 | 说明 | 旧字段映射 |
|---|---|---|---|---|---|---|
| `id` | `UUID/String` | 是 | 新建时生成 | Query | 公告唯一标识 | 旧 `id` |
| `recordName` | `String?` | 否 | `nil` | Query | CloudKit Record ID | 旧 `recordName` |
| `title` | `String` | 是 | `""` | Query | 公告标题 | 旧 `title` |
| `summary` | `String?` | 否 | `nil` | 否 | 列表摘要文案 | 新增 |
| `content` | `String` | 是 | `""` | 否 | 公告正文 | 旧 `content` |
| `locale` | `String?` | 否 | `nil` | Query | 语言/地区标识，如 `zh-CN` | 新增 |
| `tags` | `[String]?` 或 JSON | 否 | 空 | Query | 活动标签、主题标签 | 新增 |
| `mediaType` | `Enum` | 是 | `none` | Query | `none / image / video` | 旧 `mediaType` |
| `coverMedia` | `String?` | 否 | `nil` | 否 | 列表或详情媒体资源 | 旧 `mediaURL` / `builtinMediaName` |
| `builtinMediaName` | `String?` | 否 | `nil` | 否 | 内置素材资源名 | 旧 `builtinMediaName` |
| `status` | `Enum` | 是 | `draft` | Query | `draft / scheduled / published / archived` | 由旧 `isActive` 映射 |
| `channel` | `Enum/Set` | 是 | `inbox` | Query | `inbox / banner / modal / mixed` | 新增 |
| `severity` | `Enum` | 是 | `info` | Query + Sort | `info / important / critical` | 从旧 `priority` 迁移但不等价 |
| `displayPriority` | `Int` | 否 | `0` | Sort | 同级公告的排序权重 | 旧 `priority` |
| `isPinned` | `Bool` | 否 | `false` | Query + Sort | 是否置顶 | 新增 |
| `requiresAck` | `Bool` | 是 | `false` | Query | 是否要求显式确认 | 新增 |
| `isSilent` | `Bool` | 是 | `false` | Query | 是否只进公告中心，不触发前台提示 | 新增 |
| `publishAt` | `Date?` | 否 | `nil` | Query + Sort | 实际发布时间或定时发布时间 | 新增 |
| `startAt` | `Date?` | 否 | `nil` | Query | 生效开始时间 | 新增 |
| `endAt` | `Date?` | 否 | `nil` | Query | 生效结束时间 | 新增 |
| `archivedAt` | `Date?` | 否 | `nil` | Query | 归档时间 | 新增 |
| `audience` | `String/JSON` | 否 | `all` | Query | 目标受众定义 | 新增 |
| `minAppVersion` | `String?` | 否 | `nil` | Query | 最低可见版本 | 新增 |
| `maxAppVersion` | `String?` | 否 | `nil` | Query | 最高可见版本 | 新增 |
| `actionType` | `Enum?` | 否 | `nil` | Query | `none / deeplink / tab / page / externalURL` | 新增 |
| `actionTarget` | `String?` | 否 | `nil` | 否 | 动作目标 | 新增 |
| `actionLabel` | `String?` | 否 | `nil` | 否 | 动作按钮文案 | 新增 |
| `environment` | `Enum` | 是 | 当前环境 | Query | `development / production` | 新增 |
| `revision` | `Int` | 是 | `1` | Sort | 公告版本号 | 旧 `version` |
| `rollbackFrom` | `String?` | 否 | `nil` | Query | 从哪个版本回滚 | 新增 |
| `createdBy` | `String?` | 否 | `nil` | Query | 创建者标识 | 旧 `creatorID` 部分兼容 |
| `updatedBy` | `String?` | 否 | `nil` | Query | 最后编辑者标识 | 新增 |
| `publishedBy` | `String?` | 否 | `nil` | Query | 发布者标识 | 新增 |
| `createdAt` | `Date` | 是 | `now` | Sort | 创建时间 | 旧 `createdAt` |
| `updatedAt` | `Date` | 是 | `now` | Sort | 更新时间 | 旧 `updatedAt` |
| `metadata` | `String/JSON?` | 否 | `nil` | 否 | 扩展字段 | 旧 `metadata` |

---

## 3. 字段取值约束

### 3.1 `status`

- `draft`
- `scheduled`
- `published`
- `archived`

### 3.2 `channel`

- `inbox`
- `banner`
- `modal`
- `mixed`

说明：
- 单渠道场景优先使用单值。
- 多渠道场景可以使用 `mixed`，并在 `metadata` 或后续结构字段中记录实际渠道集合。

### 3.3 `severity`

- `info`
- `important`
- `critical`

说明：
- `severity` 决定“提醒强度建议”
- `displayPriority` 决定“排序权重”
- 二者不得混用

### 3.4 `actionType`

- `none`
- `deeplink`
- `tab`
- `page`
- `externalURL`

---

## 4. 字段默认策略

### 新建草稿默认值

| 字段 | 默认值 |
|---|---|
| `status` | `draft` |
| `channel` | `inbox` |
| `severity` | `info` |
| `displayPriority` | `0` |
| `isPinned` | `false` |
| `requiresAck` | `false` |
| `isSilent` | `false` |
| `audience` | `all` |
| `revision` | `1` |

### 发布态补齐规则

- 若 `publishAt == nil`，发布时写入当前时间。
- 若 `startAt == nil`，默认取 `publishAt`。
- 若 `actionType != none` 且 `actionTarget == nil`，禁止发布。
- 若 `status == scheduled` 且 `publishAt == nil` 且 `startAt == nil`，禁止保存为定时态。

---

## 5. 用户状态模型字段

| 字段名 | 类型 | 必填 | 默认值 | 查询/排序 | 说明 | 旧字段映射 |
|---|---|---|---|---|---|---|
| `noticeID` | `String` | 是 | 无 | Query | 关联公告 ID | 旧 `noticeID` / `recordName` / `readTrackingKey` |
| `state` | `Enum` | 是 | `unseen` | Query | `unseen / read / acknowledged / dismissed` | 旧“已展示/已读” |
| `readAt` | `Date?` | 否 | `nil` | Sort | 首次已读时间 | 旧已读时间 |
| `acknowledgedAt` | `Date?` | 否 | `nil` | Sort | 显式确认时间 | 新增 |
| `dismissedAt` | `Date?` | 否 | `nil` | Sort | 用户关闭或忽略时间 | 新增 |
| `presentationCount` | `Int` | 是 | `0` | Sort | 被前台提示过的次数 | 新增 |
| `lastPresentedAt` | `Date?` | 否 | `nil` | Sort | 最近一次前台提示时间 | 新增 |

---

## 6. 用户状态取值规则

### `state`

- `unseen`
  - 用户尚未在公告中心或提示渠道中看到公告
- `read`
  - 用户看过公告，但不代表完成确认
- `acknowledged`
  - 用户显式确认过公告
- `dismissed`
  - 用户关闭过提示，但不一定阅读详情

说明：
- `requiresAck == true` 的公告，`read` 不等于完成态。
- `dismissed` 不应覆盖 `acknowledged`。

---

## 7. 查询与排序建议

### 用户侧列表排序

建议排序优先级：

1. `isPinned desc`
2. `severity desc`
3. `publishAt desc`
4. `updatedAt desc`

### 管理侧列表排序

建议排序优先级：

1. `status`
2. `updatedAt desc`
3. `publishAt desc`

---

## 8. 旧字段迁移建议

| 旧字段 | 新字段 | 迁移规则 |
|---|---|---|
| `id` | `id` | 直接复用 |
| `title` | `title` | 直接复用 |
| `content` | `content` | 直接复用 |
| `mediaURL` | `coverMedia` | 迁移到统一媒体字段 |
| `builtinMediaName` | `builtinMediaName` | 直接复用 |
| `mediaType` | `mediaType` | 直接复用 |
| `priority` | `displayPriority` | 直接迁移，不再直接映射 `severity` |
| `isActive` | `status` | `true -> published`，`false -> archived` |
| `version` | `revision` | 直接迁移 |
| `creatorID` | `createdBy` | 可作为初始兼容值 |
| `createdAt` | `createdAt` | 直接复用 |
| `updatedAt` | `updatedAt` | 直接复用 |
| `recordName` | `recordName` | 直接复用 |

---

## 9. 冻结结论

本字段表冻结以下关键共识：

1. `severity` 与 `displayPriority` 必须拆开。
2. `status` 必须显式表达生命周期。
3. 用户状态必须从公告主记录中解耦。
4. `Development` 与 `Production` 必须入模，而不是只靠日志区分。
5. 旧模型能迁移，但不能继续沿用旧语义驱动新系统。
