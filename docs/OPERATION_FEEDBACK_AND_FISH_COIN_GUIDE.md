# 操作反馈、弹窗与鱼币联动使用指南

更新：2026-10-11。以本机 `ItemManager/` 实现为准；本指南是后续业务接入的唯一规则入口。

## 1. 固定顺序

用户确认 → 校验 → 保存业务数据和图片 → 更新相关系统 → 获取奖励到账回执 → 显示一次操作结果。

- 成功卡片只在保存成功后出现。校验失败、保存失败、用户取消，不发奖励。
- 同一操作的成功与鱼币合并显示，不再同时弹成功 Toast 和奖励气泡。
- 普通反馈使用 `OperationFeedbackCenter`；现有 `ToastManager`、`CopyToastManager` 是调用适配层，已经没有独立视图、队列和隐藏计时器。
- UI 展示实际到账数量。不能直接拿 `RewardType.rewardAmount` 拼“+50”。达到上限时保留添加成功，说明今日奖励上限，不显示虚假的加币。
- 弹窗本身不产生奖励；奖励来自明确的业务规则。复制、修改资料、保存图片、买萌宠用品、充值结果提示，默认不额外发鱼币。

## 2. 选择哪一种弹窗

| 场景 | 入口 | 行为 |
| --- | --- | --- |
| 普通成功/错误/警告/信息 | `ToastManager.shared.showSuccess/showError/showWarning/show` | 统一卡片、同一队列 |
| 复制成功 | `CopyToastManager.shared.show(text:)` | 同一队列，附带文本预览，不发奖励 |
| 成功并奖励 | `OperationFeedbackCenter.shared.succeeded(_:rewards:)` | 发奖回执与成功合成一张卡片 |
| 时光馆确认入橱 | `ShopCatalogWardrobeAddition.add/addSet` | 自动完成图片入库、业务收尾、成功和鱼币反馈 |
| 手动新建衣物保存成功 | `WardrobeOperationFeedback.added` | 每条新衣物奖励 +50，合成一次结果 |
| 累计尾款全部付清 | `WardrobeOperationFeedback.paidBalance(for:paymentID:)` | 以尾款支付流水 ID 防重，奖励 +200 |
| 首次功能体验/引导完成 | `RewardManager.triggerReward` | 获取回执并自动进入同一队列；引导结束后展示 |
| 删除确认、价格方式选择、必须处理的错误 | SwiftUI `.alert/.confirmationDialog/.sheet` | 需要用户决策时保留系统弹窗；页面已完成选择时直接执行，避免重复询问；成功后走统一反馈 |
| 魔法任务完成/待解锁卡片 | `MagicTaskCompletionManager` | 保存功能进度与交互卡片；普通反馈队列非空时暂缓显示卡片，避免叠在一起 |
| 功能解锁大卡片 | `FeatureUnlockToast/GlobalUnlockNotificationOverlay` | 保留解锁确认和导航，不承担鱼币记账 |
| 萌宠喂食、触摸飘字、主题切换动画 | 既有宠物/动画系统 | 是动作动画，不能据此判断奖励到账，也不能再重复发成功提示 |

IAP 充值等待与到账提示也走统一队列：等待 App Store 时使用信息提示，已确认到账才使用成功提示。喵币充值、StoreKit 验证、VIP 权益不通过鱼币奖励服务处理。

## 3. 时光馆接入示例

```swift
// 在 @MainActor 用户确认流程中调用。
do {
    let clothing = try await ShopCatalogWardrobeAddition.add(
        draft: draft, selection: selection,
        store: store, modelContext: modelContext)
    // 这里可以关闭 sheet 或刷新选择；不要再次 showSuccess / triggerReward。
    dismiss()
} catch {
    ToastManager.shared.showError(error.localizedDescription)
}
```

批量使用 `addSet(drafts:accessoryProductIDs:store:modelContext:)`。按最终保存的 `Clothing` 条数发奖；挂在主衣物下的 `AccessoryItem` 不额外算一条衣物。批量只显示一张成功卡片，鱼币展示所有回执的实际到账总额。

加入心愿调用同一个服务，传 `successMessage: "添加成功，已加入心愿".appLocalized`。开售提醒的时间未定档或通知权限未开启，属于提醒系统的独立信息反馈，不能撤销已成功的心愿，也不能再次发奖。

纯导入、备份恢复、测试种数据用 `ShopCatalogWardrobeInserter.insertWithImages/insertSetWithImages`。这些底层持久化接口不触发成功提示和奖励，避免恢复数据时把历史衣物重新奖励一遍。

## 4. 其他业务如何增加反馈与奖励

无奖励时：

```swift
try modelContext.save()
ToastManager.shared.showSuccess("保存成功".appLocalized)
```

已有明确奖励规则时：

```swift
try saveBusinessData()
OperationFeedbackCenter.shared.succeeded(
    "操作完成".appLocalized,
    rewards: [.init(type: rewardType, operationID: "业务名:\(recordID)")])
```

- `RewardRequest` 把奖励类型和稳定业务标识绑定。不能用每次点击新生成的 UUID，也不能用视图出现次数作标识。
- 同一回调重复执行可以再次提示，但不会再次发币。衣物新增使用 `wardrobe-add:<Clothing.id>`；付清尾款使用 `balance-paid:<WealthSavingEntry.id>`，后续另一笔支付是另一个业务事件。
- `.firstTimeFeature` 继续识别历史 `hasTriggeredFirstTime_*`，同时在钱包快照中记录首次体验标识。
- 自定义奖励必须有既有业务依据和稳定 ID；不要为“弹窗显示了”加奖励。
- 已调用 `triggerReward` 的旧入口不要再调用 `succeeded(rewards:)`。新业务优先用合并成功入口；`grant` 仅用于需要自己处理到账回执的业务，不自动显示 UI。

## 5. 鱼币记账规则

现有金额保持：新增衣物 50、付清尾款 200、搭配 ≥2 件 100/其他 20、首次功能体验 100、自定义奖励按既有引导规则。

`createOOTD` 是现有奖励类型；本次没有给所有贴纸、搭配保存或复制操作自动增加新奖励。后续需要奖励时，业务确认成功点与稳定记录 ID 必须一并接入。

每日鱼币总上限沿用 `PetStatus.dailyFishCoinLimit = 10000`。到账回执 `FishCoinRewardReceipt` 分为 `granted/limited/duplicate/unavailable/invalid`：

- 剩余额度 20，新增衣物请求 50：到账 20，卡片显示“鱼币 +20”及今日上限说明。
- 已无额度：添加仍成功，到账 0，不显示加币行。
- 同一个业务标识重放：到账 0，余额不再变化。
- 已成功但被每日上限截断的衣物/支付操作会消费标识，不能隔天重放补领；`.firstTimeFeature` 在未到账时不消费历史领取标记。
- 钱包读取/编码失败：已保存的业务仍成功，提示“奖励暂未到账”，不能显示到账数量；无自动重试队列，调用方补领必须使用同一业务 ID。
- 非正奖励金额非法，不允许借奖励入口扣币。

余额、每日计数和 `claimedOperationRewards` 在同一个 `PetStatus` 快照中保存。旧快照缺少该字段时按空集合解码，不改变既有钱包存档键。萌宠收到到账通知时同步日重置日期与领取历史；普通页面保存旧状态时合并已领取标识，避免覆盖防重记录。正式运行使用 `PetDataManager.persistOperationReward`：本地快照提交后才发布到账通知，随后沿既有钱包云同步与自动备份流程处理。该机制继承现有钱包快照同步规则，不是服务端分布式结算账本。

## 6. 与哪些系统联动

| 系统 | 责任和顺序 |
| --- | --- |
| SwiftData / ImageManager | 商品图片先变为衣橱长期引用，整组记录保存成功后才进入完成流程；失败回滚，不报成功、不发币 |
| 鱼币钱包 / PetDataManager | 基于最新内存余额计算额度，余额和防重标识同快照保存；不修改喵币、骨头币 |
| `petStatusDidUpdateExternally` | 本地快照提交后通知钱包、宠物、VIP/IAP 等已有订阅方刷新；不在视图自己改余额 |
| 魔法任务 / FeatureUnlockManager | 入橱后刷新真实衣物数量；任务达标由既有解锁规则判断，提示卡片不是任务完成凭证 |
| 心愿尾款 / NotificationManager | 入橱后刷新尾款数据通知与衣物提醒；付清后的取消/确认提醒仍由既有支付业务收尾 |
| 小组件 / SharedPersistence | 时光馆入橱后同步小组件；手动编辑和支付入口保留各自已存在的同步收尾，避免重复执行 |
| 图片云同步 | 仍由图片导入成功后的 `ClothingImageSyncService` 执行，成功提示不能代替上传回执 |
| 引导 / 开屏 / 迁移 / 前后台 | 提示队列保留未展示消息；开屏、迁移、引导或 scene 非活跃时暂停展示，恢复后继续 |
| 主题 / 原生导航 | 使用系统材质、语义背景、文字和颜色；不使用主题 Dock、固定底栏避让高度或机型判断 |

## 7. 展示与生命周期

- `MainContentView` 只安装一个 `OperationFeedbackSceneInstaller`。同一 scene 的辅助窗口覆盖 sheet，按 scene 大小和安全区布局，不使用 `UIScreen.main`、方向或机型分支。
- 辅助窗口不成为 key window；只有卡片区域参与触摸，其他位置透传到原窗口。无提示时不阻挡操作。
- 队列顺序展示；后来的复制或错误不能覆盖前一条尚未展示的成功。只按消息 UUID 取消/消费，旧计时器不能移除新消息。
- 不在页面 `.onAppear` 中订阅奖励事件并自行构造气泡，不写本地 `showToast` 状态或 `asyncAfter` 隐藏计时器。
- 普通成功/复制默认 1.5 秒，普通信息/警告 2 秒，错误 2.5 秒，成功带奖励 3 秒；VoiceOver 至少 5 秒，并播报文案、实际奖励和说明。消息字体按 Dynamic Type，卡片宽度随窗口变化。
- 提示被引导或后台暂停时，计时任务取消但消息不消费；重新出现后计时。魔法任务交互卡片暂存其原有队列，普通反馈结束后继续展示。
- 鱼币卡片保留“查看魔法任务”入口，沿 `.navigateToMagicTasks` 发送导航意图。当前打开的 sheet 仍按原业务自行关闭。

## 8. 验证和维护入口

新增入口至少核对：保存失败无成功/无奖励、真实到账、每日额度部分/零、稳定 ID 防重、批量只显示一次、sheet 关闭及页面切换不丢消息。

- `ItemManagerTests/RewardManagerTests.swift`：钱包上限、实际回执、旧快照、持久化防重、无钱包和非法奖励。
- `ItemManagerTests/OperationFeedbackTests.swift`：队列顺序、过期关闭、批量合并、钱包失败与业务成功分离，以及真实 scene 中覆盖 sheet、触摸透传和暂停保留消息。
- `ItemManagerTests/ShopCatalogWardrobeImageImportTests.swift`：长期图片引用、失败回滚。
- 执行记录和剩余验收边界：`docs/OPERATION_FEEDBACK_AND_FISH_COIN_EXEC_PLAN.md`。

后续 Agent 先读本指南，再按业务矩阵接入；更新实现时同步修改本指南、执行计划和记忆索引，不另开一套气泡组件。

析构边界：队列和 scene 协调器的析构没有 UI 清理工作，显式声明 `nonisolated deinit`；窗口隐藏/释放仍由主线程的 `dismantleUIView` 执行。本机 Xcode 27 / iOS 26.3.1 测试曾在 UIKit 释放模型时进入主线程析构回部署桥接而崩溃，定位及复验写入执行记录。Swift 对析构隔离的语义见 [官方并发迁移文档](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/commonproblems/)。

入橱选择补充（2026-10-11）：默认主衣物，小物不预选；入橱条数与奖励以确认后的实际主记录为准。运营新价格默认 CNY。详见 [默认规则](SHOP_CATALOG_ENTRY_DEFAULTS_2026-10-11.md)。

入橱确认页加入方式只保留页内单选（2026-10-11 用户截图确认），确认按钮直接保存，不再弹出相同选择。删除确认、保存失败与保存成功反馈仍遵循上表。
