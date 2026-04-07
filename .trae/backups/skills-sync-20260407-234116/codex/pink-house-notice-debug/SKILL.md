---
name: pink-house-notice-debug
description: Pink_House 公告系统排查技能。用于定位 Notice 在 CloudKit 拉取失败、本地缓存与云端不一致、弹窗不出现、删除后回流、管理员验证弹窗异常等问题，并统一按固定顺序排查日志、模型、同步链路和状态链路。
---

# Pink House Notice Debug

在 Pink_House 里处理公告系统问题时使用这个技能，尤其是下面这些场景：

1. 杀端重进后没有公告
2. 日志显示拉到了云端公告，但没有弹窗
3. 删除公告后又回来了
4. 管理页能看到公告，但不确定是不是本次云同步回来的
5. CloudKit 报 `参数无效`
6. 普通用户拉到了新公告，但因为冷启动节流没有及时看到

## 先读什么

1. 先读 [../../docs/NOTICE_CMS_RUNTIME_BEST_PRACTICES.md](../../docs/NOTICE_CMS_RUNTIME_BEST_PRACTICES.md)
2. 再读 [../../docs/NOTICE_CMS_MODAL_DEBUG_CHECKLIST.md](../../docs/NOTICE_CMS_MODAL_DEBUG_CHECKLIST.md)

## 优先看的代码

1. `ItemManager/Models/Notice.swift`
2. `ItemManager/Services/NoticeCloudKitService.swift`
3. `ItemManager/Services/NoticeService.swift`
4. `ItemManager/Services/NoticeReadStatusService.swift`
5. `ItemManager/Views/Notice/NoticePopupView.swift`
6. `ItemManager/Views/Notice/NoticeAdminView.swift`

## 固定排查顺序

任何公告问题都按这个顺序查，不要跳步：

1. 先查云端拉取是否成功
2. 再查本地缓存是否已更新
3. 再查公告字段是否满足候选规则
4. 再查同步结束后是否重新评估弹窗
5. 最后才查已读、dismiss、展示次数

## 关键判断原则

### 1. 不要把“管理页能看到公告”当成云同步成功

管理页读的是本地 SwiftData。

真正的云同步成功证据是：

1. 日志出现 `成功拉取 X 条云端公告`
2. 管理页来源标签显示 `本次已从云同步`

### 2. 管理员和普通用户是两套弹窗语义

普通用户：

1. 受已读和展示次数影响
2. 默认受 30 秒节流影响
3. 会写入用户状态
4. 若本次刚从云端同步到了新的 modal 公告，且此前未展示过，可跳过冷启动延迟

管理员：

1. 走验证模式
2. 只为确认“发布成功后确实能弹”
3. 同一公告版本只自动验证一次
4. 不写 `read / acknowledged / dismissed / presentationCount`

### 3. 删除问题优先按“软删除回流”思路排查

不要先怀疑 UI。

优先看：

1. 本地记录是不是已 `archived`
2. 云端停用有没有成功
3. 云端记录是否已不存在
4. 本地是否在下次同步时被旧云端版本覆盖

### 4. `参数无效` 先怀疑 CloudKit 索引，不先怀疑业务规则

尤其先查：

1. 排序字段是否可排序
2. 查询字段是否可查询
3. Development / Production Schema 是否一致

补充：

1. `Notice` 主数据和 `NoticeReadStatus` 私有状态都不要依赖 `recordName` 可查询
2. 更稳的做法是 `CKQueryOperation + desiredKeys + 本地排序/本地映射`

## 推荐日志搜索词

优先搜索：

1. `开始同步公告`
2. `成功拉取`
3. `公告同步完成`
4. `service.notices changed`
5. `普通用户命中新同步公告，跳过冷启动延迟`
6. `管理员命中可验证弹窗`
7. `公告弹窗已显示`
8. `停用公告失败`
9. `保留本地删除状态`

## 处理约束

1. 先基于日志和现有实现定位，再改代码
2. 不要一上来就重构公告系统
3. 不要把管理员验证模式重新并回普通用户已读逻辑
4. 不要移除来源标签
5. 在这个仓库里，默认不要跑 Xcode 编译；由用户自己编译并反馈报错

## 改完后至少确认的结果

1. 能区分“没拉到云端”和“拉到了但没弹”
2. 管理页能看出公告来源
3. 管理员能验证弹窗，但不会污染已读状态
4. 普通用户新同步公告不会继续被固定 30 秒延迟吞掉
5. 删除后的云端公告不会轻易从旧缓存回流
