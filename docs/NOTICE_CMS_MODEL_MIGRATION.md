# 公告主模型迁移设计（B1）

> 更新时间：2026-04-06  
> 对应任务：`NOTICE_CMS_DEV_TASKS.md` 中 B1  
> 用途：定义旧 `Notice` 模型向新公告内容系统主模型的迁移策略，作为数据层改造和 CloudKit 字段升级的实现依据。

## 1. 目标

将现有“单条公告 + 简单排序 + 是否活跃”的模型，迁移为“支持生命周期、渠道、严重等级、时间窗、动作和审计”的主模型。

迁移目标：

- 兼容旧公告数据
- 保留旧记录的可见性和历史
- 为新系统补齐生命周期和渠道语义
- 避免旧 `priority` 继续承载错误语义

---

## 2. 现有旧模型概况

当前旧模型主要字段包括：

- `id`
- `title`
- `content`
- `mediaURL`
- `cloudKitMediaURL`
- `builtinMediaName`
- `mediaType`
- `createdAt`
- `updatedAt`
- `isActive`
- `priority`
- `version`
- `recordName`
- `creatorID`
- `metadata`

核心问题：

1. 无 `status`
2. 无 `channel`
3. 无 `severity`
4. 无 `publishAt/startAt/endAt`
5. 无 `requiresAck`
6. 无明确审计链路

---

## 3. 新模型最小目标结构

迁移后的主模型至少要能表达：

- 公告内容
- 生命周期
- 展示渠道
- 提醒强度
- 时间窗
- 动作跳转
- 发布环境
- 版本与审计信息

参考冻结字段见：
[NOTICE_CMS_FIELD_SPEC.md](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_FIELD_SPEC.md)

---

## 4. 迁移总原则

1. 旧公告默认进入新系统，不做数据丢弃。
2. 缺失的新字段采用可解释默认值。
3. 迁移后先保证“可展示、可读取”，再逐步增强“可运营”。
4. 所有旧公告先保守降级，不强行推断高风险语义。
5. 旧 `priority` 只迁移为排序权重，不直接映射为 `severity`。

---

## 5. 字段迁移映射

| 旧字段 | 新字段 | 迁移规则 | 备注 |
|---|---|---|---|
| `id` | `id` | 直接保留 | 主键不变 |
| `recordName` | `recordName` | 直接保留 | CloudKit 关联保持稳定 |
| `title` | `title` | 直接保留 | 无需转换 |
| `content` | `content` | 直接保留 | 无需转换 |
| `mediaURL` | `coverMedia` | 若存在则迁移 | 与内置图统一到展示媒体语义 |
| `builtinMediaName` | `builtinMediaName` | 直接保留 | 便于兼容旧内置图 |
| `mediaType` | `mediaType` | 直接保留 | `none / image / video` |
| `priority` | `displayPriority` | 直接保留为排序值 | 不再映射 `severity` |
| `isActive` | `status` | `true -> published`, `false -> archived` | 最保守映射 |
| `version` | `revision` | 直接迁移 | 版本延续 |
| `creatorID` | `createdBy` | 若存在则迁移 | 仅做初始值，不代表新审计完整 |
| `createdAt` | `createdAt` | 直接保留 | 历史时间延续 |
| `updatedAt` | `updatedAt` | 直接保留 | 历史时间延续 |
| `metadata` | `metadata` | 直接保留 | 便于后续扩展 |

---

## 6. 新字段默认补齐策略

| 新字段 | 默认值 | 补齐理由 |
|---|---|---|
| `summary` | `nil` | 旧数据无摘要，不强制生成 |
| `locale` | `zh-CN` 或 `nil` | 视现网主要语言而定，优先保守 |
| `tags` | 空 | 旧数据无标签 |
| `status` | 来自 `isActive` | 生命周期基础映射 |
| `channel` | `inbox` | 旧公告默认只进入公告中心 |
| `severity` | `info` | 不臆测高风险级别 |
| `isPinned` | `false` | 旧公告不默认置顶 |
| `requiresAck` | `false` | 旧公告不默认要求确认 |
| `isSilent` | `true` | 旧公告迁移后不默认强提示 |
| `publishAt` | `createdAt` | 若已发布则给出基础发布时间 |
| `startAt` | `createdAt` | 保证时间窗可解释 |
| `endAt` | `nil` | 后续由过期治理补全 |
| `archivedAt` | `updatedAt` 或 `nil` | 仅对归档态旧公告可补 |
| `audience` | `all` | 旧公告无分群逻辑 |
| `minAppVersion` | `nil` | 旧公告默认全量可见 |
| `maxAppVersion` | `nil` | 旧公告默认全量可见 |
| `actionType` | `none` | 旧公告默认无动作 |
| `actionTarget` | `nil` | 与 `actionType` 一致 |
| `actionLabel` | `nil` | 与 `actionType` 一致 |
| `environment` | 迁移发生所在环境 | 必须明确入模 |
| `publishedBy` | `nil` | 旧记录无法可靠补齐 |
| `updatedBy` | `nil` | 旧记录无法可靠补齐 |
| `rollbackFrom` | `nil` | 旧记录无回滚语义 |

---

## 7. 旧公告迁移分层

### 7.1 第一层：可读迁移

目标：

- 所有旧公告都能在新系统中读取
- 旧公告能进入公告中心
- 不因为缺少新字段而丢失

做法：

- 保守补默认值
- 所有旧公告默认只走 `inbox`
- 不自动触发 `banner / modal`

### 7.2 第二层：可管迁移

目标：

- 管理端能看到旧公告
- 可对旧公告做归档、复制、新版重发

做法：

- 为旧公告补生命周期字段
- 允许复制为新草稿
- 不建议直接把旧公告强行改造成高复杂运营对象

### 7.3 第三层：可运营增强

目标：

- 仅对仍有价值的旧公告补摘要、标签、动作等增强字段

做法：

- 人工补录或后续运营整理

---

## 8. 迁移边界规则

### 允许自动迁移的

- 基础内容字段
- 时间字段
- 活跃状态到生命周期状态
- 排序字段到显示优先级

### 不允许自动推断的

- 高优先级到 `critical`
- 需要确认到 `requiresAck = true`
- 旧媒体一定适合新 banner / modal 样式
- 旧公告一定要继续提示给用户

---

## 9. 迁移后行为规则

迁移后的旧公告默认遵循：

1. 在公告中心可见
2. 不默认进入 `banner`
3. 不默认进入 `modal`
4. 不默认要求确认
5. 已归档旧公告不回流到线上

---

## 10. 推荐迁移实施顺序

1. 扩展本地主模型
2. 完成旧字段到新字段的本地映射
3. 完成 CloudKit 主记录字段扩展
4. 验证旧数据在新 UI 中可见
5. 再开启新发布流程

---

## 11. 验收标准

- 旧公告在迁移后仍能展示
- 旧 `priority` 不再驱动强提醒
- 旧公告不会因为迁移突然变成弹窗公告
- 旧公告可被归档、复制和复用

---

## 12. 冻结结论

本迁移方案冻结以下共识：

1. 旧公告先保守迁移为“可读内容”，不是“强运营内容”。
2. `isActive` 只映射生命周期，不映射触达强度。
3. 旧 `priority` 只留排序语义，不再留提醒语义。
