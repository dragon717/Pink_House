# 公告弹窗专项排查清单

> 更新时间：2026-04-07  
> 适用范围：当前阶段以 `modal` 弹窗链路为排查重点，不要求普通用户公告中心入口已落地。  
> 用途：当出现“看不到公告”“该弹不弹”“不该弹却弹”“点开后状态不对”“CloudKit 参数无效”等问题时，提供一套固定排查顺序。

补充说明：

1. 当前系统的整体思路、运行链路和实现约束，见 [NOTICE_CMS_RUNTIME_BEST_PRACTICES.md](/Users/muniao/Library%20/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/docs/NOTICE_CMS_RUNTIME_BEST_PRACTICES.md)

## 1. 当前阶段目标

本轮排查只聚焦以下闭环：

1. 公告能从 CloudKit 拉下来
2. 只有符合规则的公告进入 modal 候选
3. modal 在正确时机出现
4. modal 能进入详情
5. 详情能完成 `read / acknowledged`

不在本轮阻塞范围内：

1. 普通用户公告中心正式入口位置
2. 公告入口未读角标
3. banner 正式落地

---

## 2. 排查总顺序

遇到弹窗问题时，固定按这个顺序排查：

1. 先确认公告是否已成功从 CloudKit 拉取
2. 再确认公告是否进入本地候选集合
3. 再确认公告字段是否满足 modal 规则
4. 再确认触发时机是否满足 30 秒与前后台规则
5. 最后确认用户状态是否把它挡掉了

不要跳步。

---

## 3. A 段：CloudKit 拉取是否成功

### A1. 先看启动日志有没有进入公告同步

期望看到：

- `NoticePopupModifier onAppear`
- `开始同步公告`

若没有：

- 先排查主界面是否挂了公告修饰器
- 再排查 `NoticeService.setup()` 是否执行

### A2. 再看是否拉取成功

期望看到：

- `成功拉取 X 条云端公告`
- 最好还能看到具体公告标题

若看到：

- `拉取公告 失败: 参数无效`

优先怀疑：

1. `Notice` Record Type 字段缺失
2. 排序字段未配置 Sortable
3. Development / Production Schema 不一致

若看到：

- `公告排序查询失败，降级为...`
- 但后面又出现 `成功拉取 X 条云端公告`

说明：

1. 当前问题已经不是“完全拉取失败”
2. 而是某些排序字段没有配置好，系统已走降级查询
3. 后续应继续查本地合并、modal 候选和触发时机

### A3. 当前已知高风险字段

当前公告查询使用以下排序字段：

1. `isPinned`
2. `severity`
3. `displayPriority`
4. `publishAt`
5. `updatedAt`
6. `createdAt`

其中优先检查：

1. `isPinned`
2. `severity`
3. `displayPriority`
4. `publishAt`

说明：

- 查询里一旦使用未正确配置的排序字段，CloudKit 可能直接报 `参数无效`
- 若旧 Dashboard 仍停留在老版 `Notice` 字段，只配了 `id/title/content/priority/isActive/createdAt/updatedAt`，新查询就可能失败

### A4. Private DB 次要检查

若看到：

- `Did not find record type: NoticeReadStatusReset`

说明：

- 用户状态同步链路也存在 Schema 漂移
- 它不一定是“本次不弹”的主因
- 但会影响已读/重置逻辑，后续必须补齐

---

## 4. B 段：本地候选集合是否有公告

### B1. 区分“本地已有”还是“本次云同步得到”

当前“现有公告”默认来自本地 SwiftData，不等于本次已从云拉取成功。

排查时必须分清：

1. 本地旧缓存里已经有公告
2. 本次启动真的从云拿到了公告

判定原则：

- 管理页看到“现有公告”不能单独作为云同步成功证据
- 只有日志里出现“成功拉取 X 条云端公告”才算本次云同步成功

### B2. 当前已落地的来源标记

当前管理页已直接显示来源标签：

1. `本次已从云同步`
2. `本地缓存`
3. `仅本地未同步`

排查时优先利用这个标签，不要只靠肉眼看列表。

---

## 5. C 段：公告字段是否满足 modal 规则

一条公告要成为 modal 候选，至少要满足：

1. `status == published`
2. `severity == critical`
3. `channel` 包含 `modal` 或 `mixed`
4. `isSilent == false`
5. 当前运行环境命中
6. 时间窗命中
7. 版本范围命中

### C1. 状态检查

重点看：

1. 是否还是 `draft`
2. 是否是 `scheduled` 但未到生效时间
3. 是否已被归档

### C2. 渠道与等级检查

重点看：

1. `modal` 只允许 `critical`
2. `important` 即使已发布，也不该进入 modal
3. `inbox` 公告默认不会弹

### C3. 时间窗检查

重点看：

1. `publishAt`
2. `startAt`
3. `endAt`

常见误判：

1. 定时公告还没到时间
2. `endAt` 已经过期
3. 以为“已发布”就一定可见，实际时间窗没命中

### C4. 版本范围检查

重点看：

1. `minAppVersion`
2. `maxAppVersion`

若调试机版本不在范围内，公告不会进候选。

---

## 6. D 段：触发时机是否满足

### D1. 冷启动 30 秒规则

当前 modal 默认不在冷启动 30 秒内展示，但管理员验证模式除外。

所以即使公告合法：

1. 刚打开 App 不会立刻弹
2. 杀端后重启，也要等首屏稳定后再评估
3. 管理员为验证发布结果，可在同步完成后立即验证一次

补充：

1. 普通用户若命中“本次新同步到的新 `modal` 公告，且当前版本此前未展示过”，也可以跳过这 30 秒延迟
2. 若本次展示是为了承接这条新同步公告，也可同时跳过“今日全局 modal 次数上限”
3. 这两个放行只针对“新同步且当前版本未展示过”的公告，不是给所有普通用户公告统一开绿灯

### D2. 回前台规则

回前台时应按这个顺序：

1. 先同步
2. 同步完成并刷新本地公告列表
3. 再评估 modal
3. 不应回前台瞬间直接硬弹

若代码层顺序变成“先结束 syncing，再刷新本地列表”，就容易出现：

1. 云端已经拉到了
2. 但弹窗评估时拿到的仍是旧本地列表
3. 结果表现为“日志看起来成功了，但就是没弹”

### D3. 同屏互斥

若后续 banner 接入：

1. 命中 modal 时，不应同时出现 banner
2. 同一轮评估只允许一个主动提示层

### D4. 管理员验证模式

当前管理员不再“完全跳过公告弹窗”，而是走验证模式：

1. 管理员可在发布后杀端重进，快速确认公告能否弹出
2. 同一条公告版本，管理员只自动验证一次
3. 验证模式不写入普通用户已读/展示状态

若日志出现：

1. `当前管理员账号，启用公告验证模式`
2. `管理员命中可验证弹窗`
3. `以管理员验证模式显示公告弹窗`

说明管理员验证链路已命中。

---

## 7. E 段：用户状态是否把公告挡掉了

当前用户状态会直接影响 modal：

1. 当前版本已 `read`，不再弹
2. 当前版本已 `acknowledged`，不再弹
3. 当前版本已 `dismissed`，不再弹
4. 当前版本 `presentationCount >= 1`，不再弹
5. 当日已达 modal 上限，不再弹

注意：

1. 这里说的“当前版本”，不是只看公告 `id`
2. 必须结合当前版本对应的 `readTrackingKey / snapshot` 判断
3. 旧版本的 `dismissed / presentationCount` 不能默认直接拦截新版本

### E1. 重点检查项

1. `state`
2. `presentationCount`
3. `lastPresentedAt`
4. `readTrackingKey` 是否已切到当前版本
5. 当前命中的 snapshot 是否真属于当前公告版本
6. 当日是否已有其他 modal 展示

### E2. 常见误判

1. 用户以为“我没看到”，但实际上已进入 `dismissed`
2. 同公告昨天弹过并被记录，今天仍因节流规则不再弹
3. 旧已读 key 被兼容命中，导致公告直接视为已读
4. 旧版本 `dismissed / presentationCount` 误伤了新版本，表现为“云端已拉到，但就是不弹”
5. 管理员验证过一次后，误以为再次杀端也应该继续自动弹

补充：

1. 管理员验证模式不污染用户状态
2. 但会记录“本条公告版本已完成管理员验证”，用于避免每次启动重复弹

### E3. 新日志怎么直接对位

如果已经进入 `tryShowNotice`，优先看下面几条日志：

1. `公告不满足 modal 基础规则`
   - 说明问题还在公告字段本身，例如 `status / severity / channel / 时间窗 / 版本范围`
2. `公告因用户状态被拦截`
   - 说明当前版本命中了 `read / acknowledged / dismissed`
3. `公告因当前版本已展示过被拦截`
   - 说明当前版本的 `presentationCount` 或展示快照已经命中
4. `公告因今日全局弹窗次数上限被拦截`
   - 说明本次不是“新同步且允许放行”的场景，或放行参数没有走通

---

## 8. F 段：详情承接是否正常

即使公告成功弹出，还要继续检查：

1. modal 是否能进入详情页
2. 进入详情是否写入 `read`
3. 确认型公告点击“我已知晓”后是否写入 `acknowledged`

### F1. 验收最低要求

当前阶段最低必须满足：

1. 用户能从 modal 进入详情
2. 详情页进入后状态可从 `unseen` 变成 `read`
3. 确认型公告可从 `read` 变成 `acknowledged`

---

## 9. 故障类型到排查入口的映射

### 9.1 杀端重启后没看到公告

优先排查：

1. A 段 CloudKit 是否拉取成功
2. C 段是否满足 `critical + modal`
3. D 段是否仍在 30 秒窗口内
4. E 段是否已被标记为 `dismissed/read`

补充：

1. 若日志已出现“本次新同步公告，跳过冷启动延迟”，则不要再把问题先归因到 30 秒窗口
2. 这时应优先查该公告是否真的命中 `latestEligibleModalNotice()`
3. 若随后已进入 `tryShowNotice`，就直接根据 E3 的精细日志判断是“字段不合法”“用户状态拦截”“当前版本已展示”还是“全局次数上限”

### 9.2 管理页能看到公告，但用户侧不弹

优先排查：

1. B 段确认那是不是本地缓存
2. C 段确认它是不是 modal 候选
3. E 段确认用户状态是否已挡住

### 9.3 日志出现 `参数无效`

优先排查：

1. `Notice` Record Type 是否存在
2. 查询里使用的排序字段是否都已配置
3. Development Schema 是否已部署完整
4. 当前代码和 Dashboard 是否还是新旧字段混用

### 9.4 日志出现 `NoticeReadStatusReset` 不存在

优先排查：

1. Private DB 是否已创建 `NoticeReadStatusReset`
2. 相关 Schema 是否只在 Development 存在
3. 文档里的 `NoticeUserState` 与代码里的 record type 是否已统一

### 9.5 日志出现 `recordName is not marked queryable`

优先排查：

1. 是不是 `NoticeReadStatus` 私有状态同步在依赖 `recordName` 查询
2. 当前实现是否仍在使用 `database.records(matching:)` 直接查整表
3. 是否已改成 `CKQueryOperation + desiredKeys + 本地映射 state key`

---

## 10. 当前阶段执行 TODO

### P0 阻塞项

- [x] 将公告主数据查询改为“排序失败降级 + 本地排序”
- [x] 为管理页现有公告增加来源标记
- [x] 管理员验证模式改为“不污染已读状态，且同版本只验证一次”
- [x] 普通用户新同步公告支持跳过固定冷启动延迟
- [x] 普通用户新同步且当前版本未展示过的公告，可按需跳过当日全局 modal 次数上限
- [x] 已读 / dismissed / 展示次数判断改为优先绑定当前公告版本，避免旧版本状态误伤新版本
- [ ] 持续核对 `Notice` 查询排序字段与 Dashboard 索引配置
- [ ] 持续验证合法 `critical + modal` 公告可在规则命中时展示
- [ ] 持续验证 modal 到详情、详情到 `read / acknowledged` 的状态闭环

### P1 非阻塞但应尽快补齐

- [x] `NoticeReadStatus` 拉取改为 `CKQueryOperation`，避开 `recordName` 查询依赖
- [ ] 持续核对 `NoticeReadStatus` 与 `NoticeReadStatusReset` 的 Private DB Schema
- [ ] 在诊断文档中统一 `NoticeUserState` 与当前代码 record type 名称
- [ ] 为 banner 接入前预留互斥验证项

### 暂缓项

- [ ] 普通用户公告中心正式入口位置
- [ ] 公告入口角标
- [ ] “关闭提示后回到公告中心复查”的完整主流程

---

## 11. 使用方式

1. 先看日志，再按 A -> B -> C -> D -> E -> F 顺序排
2. 每次只确认一个环节是否通过
3. 不要在 CloudKit 未拉通前去怀疑 UI 动画
4. 不要在公告字段未命中前去怀疑用户状态

---

## 12. 冻结结论

1. 当前弹窗问题的第一优先级不是“弹窗样式”，而是“拉取、筛选、时机、状态”四段链路是否闭环。
2. 管理页能看到公告，不等于本次云同步成功。
3. `参数无效` 优先视为 CloudKit Schema / 索引 / 查询字段不一致问题处理。
