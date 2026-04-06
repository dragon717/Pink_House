# 公告系统查询与排序策略（B3）

> 更新时间：2026-04-06  
> 对应任务：`NOTICE_CMS_DEV_TASKS.md` 中 B3  
> 用途：定义公告系统在用户侧和管理侧的查询、筛选与排序规则，作为本地缓存、SwiftData、CloudKit Schema 索引设计的共同依据。

## 1. 目标

解决当前“靠单一 `priority` 排序”的问题，建立可解释的多维查询与排序体系。

核心目标：

- 用户侧能稳定看到当前应看的公告
- 管理侧能快速区分不同生命周期状态
- 查询规则与字段设计、索引设计保持一致

---

## 2. 查询场景分类

### 用户侧

- 公告中心列表
- 首页 banner 候选
- modal 候选
- 公告详情读取

### 管理侧

- 草稿列表
- 定时列表
- 已发布列表
- 已归档列表
- 审计与回滚列表

---

## 3. 用户侧基础筛选条件

用户侧候选公告必须满足：

1. `status == published`
2. `environment == 当前运行环境`
3. `startAt == nil` 或 `startAt <= now`
4. `endAt == nil` 或 `endAt > now`
5. 版本命中：
   - `minAppVersion == nil` 或 当前版本 >= `minAppVersion`
   - `maxAppVersion == nil` 或 当前版本 <= `maxAppVersion`
6. 受众命中

---

## 4. 用户侧列表排序

公告中心建议排序：

1. `isPinned desc`
2. `severity desc`
3. `displayPriority desc`
4. `publishAt desc`
5. `updatedAt desc`

说明：

- `severity` 决定“重要程度”
- `displayPriority` 决定“同级排序”
- `publishAt` 决定“新旧顺序”

---

## 5. banner 候选查询规则

候选必须满足：

1. 满足用户侧基础筛选条件
2. `channel` 包含 `banner` 或为 `mixed`
3. `severity == important` 或 `severity == critical`
4. 用户状态不为 `acknowledged`
5. 不与 `modal` 同时触发

排序建议：

1. `severity desc`
2. `displayPriority desc`
3. `publishAt desc`

数量限制：

- 单次前台恢复最多展示 1 条

---

## 6. modal 候选查询规则

候选必须满足：

1. 满足用户侧基础筛选条件
2. `channel` 包含 `modal` 或为 `mixed`
3. `severity == critical`
4. 用户状态为 `unseen`
5. `presentationCount < modalMaxPresentationCount`
6. 当前未超过每日 modal 上限
7. 不处于冷启动禁止窗口

排序建议：

1. `displayPriority desc`
2. `publishAt desc`

数量限制：

- 单次评估只取 1 条

---

## 7. 公告详情查询规则

详情页读取原则：

- 优先按稳定 ID 查找
- 允许查看已归档公告历史详情的后台版本
- 用户侧默认只允许查看当前仍可见或历史缓存中仍合法的公告

---

## 8. 管理侧筛选规则

### 草稿列表

- `status == draft`
- 排序：
  1. `updatedAt desc`
  2. `createdAt desc`

### 定时列表

- `status == scheduled`
- 排序：
  1. `publishAt asc`
  2. `updatedAt desc`

### 已发布列表

- `status == published`
- 排序：
  1. `isPinned desc`
  2. `publishAt desc`
  3. `updatedAt desc`

### 已归档列表

- `status == archived`
- 排序：
  1. `archivedAt desc`
  2. `updatedAt desc`

---

## 9. 受众与版本过滤顺序

建议过滤顺序：

1. `environment`
2. `status`
3. 时间窗
4. 版本范围
5. 受众
6. 渠道
7. 用户状态

原因：

- 先过滤粗粒度条件，可减少后续逻辑成本

---

## 10. 索引建议

推荐为以下字段建立 Queryable/Sortable 能力：

- `status`
- `environment`
- `severity`
- `displayPriority`
- `isPinned`
- `publishAt`
- `startAt`
- `endAt`
- `updatedAt`
- `archivedAt`
- `minAppVersion`
- `maxAppVersion`

如受 CloudKit 限制，可优先保证：

1. `status`
2. `environment`
3. `publishAt`
4. `updatedAt`
5. `severity`

---

## 11. 禁止做法

以下做法禁止继续使用：

1. 只按 `priority` 单字段排序
2. 只看“最新一条”决定是否弹窗
3. 不做时间窗过滤直接拿所有已发布公告
4. 不区分用户侧和管理侧查询目标

---

## 12. 验收标准

- 用户侧能稳定拿到正确的当前可见公告
- `banner/modal` 候选规则清晰可测
- 管理侧能按生命周期快速分组查看公告
- 排序不再依赖单字段承载多重语义

---

## 13. 冻结结论

本规范冻结以下共识：

1. 用户侧、管理侧必须使用不同查询视角。
2. `severity` 与 `displayPriority` 拆分后，排序与提醒逻辑分开。
3. `modal` 候选必须是严格受限的单条结果，而不是“最新一条”。
