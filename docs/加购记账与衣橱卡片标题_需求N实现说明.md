# 加购记账逻辑与衣橱卡片标题优化（需求 N）实现说明

> 2026-09-23 · 对应需求文档《加购记账逻辑与衣橱卡片标题优化》
> 涉及模块：店家上新（ShopCatalog）加购链路 + 衣橱卡片（ClothingCard）+ 衣橱编辑（ClothingEditView）

---

## 一、核心原则的落点

> 需求原文：「所有金额（定金、尾款、预约价）必须由系统自动读取后台数据，绝对不能让用户手动输入。」

| 金额 | 唯一来源 | 备注 |
|---|---|---|
| 预约价 | `CatalogPriceArchive.currentReservationPrice`（修正优先，否则回退最近预约销售记录） | 全款入橱金额 |
| 已付定金 | `CatalogPriceArchive.currentDeposit` | 只读展示 |
| 待付尾款 | `预约价 − 已付定金` | 系统算 |

**改动前**：`ShopCatalogReservationSheet`（旧名「我已经预约」）里有一个「已付定金」`TextField`，
用户手填 → 直接违反核心原则，也导致「尾款」金额依赖手填值。

**改动后**：该 sheet 改为「金额（自动读取，无需填写）」只读区块，**全页不存在任何金额输入框**。
口径由 `option` 决定：

- `.depositPaid` → 定金取 `currentDeposit`，**尾款读后台录入的 `currentBalance`**（缺失才回退「预约价 − 定金」），可设尾款时间 → 衣橱「已付定」
- `.fullPaid` → 金额取预约价，尾款恒 0，不提供尾款时间 → 衣橱「已全款」

---

## 二、加购记账状态机（需求 §II）

新增纯逻辑模块 `ItemManager/Services/ShopCatalog/ShopCatalogWardrobeEntryPolicy.swift`：

```swift
nonisolated enum ShopCatalogWardrobeEntryOption { case wishlist, depositPaid, fullPaid }
ShopCatalogWardrobeEntryPolicy.options(phase:hasReservationPrice:hasStockPrice:) -> [Option]
ShopCatalogWardrobeEntryPolicy.buttonTitle(for:phase:) -> String
```

| 场景 | 分支 | 草稿口径（`PriceMode`） | 衣橱状态 | 心愿尾款任务 |
|---|---|---|---|---|
| 预约期内 | 付定金加购 | `.reservation(depositPaid: 后台定金)` | 已付定 | ✅ 生成待补任务（**尾款读后台录入的「尾款」**） |
| 预约期内 | 全款加购 | `.fullReservation` | 已全款 | ❌ 绝不生成 |
| 预约期结束 | 分支 A【加入心愿尾款】 | `.reservation(depositPaid: 后台定金)` | 已付定 | ✅ 生成待补任务（尾款口径同上） |
| 预约期结束 | 分支 B【加入衣橱】 | `.fullReservation` | 已全款 | ❌ 绝不生成 |
| 现货在售 | 加入少女衣橱 | `.stock` | 已拥有（已付清） | ❌ |

### 新增的 `PriceMode.fullReservation`

```swift
case .fullReservation:
    guard let event = archive.reservation else { return nil }
    depositAmount = event.price      // 全款记为「已付定金」
    balanceAmount = 0                // 尾款 0
    totalAmount   = event.price
    isDepositPlan = true
```

这样落到 `Clothing` 上就是 `isDepositPlan == true && deposit > 0 && balance == 0`
→ `isFullPaymentReservation == true` → 卡片标签「全款」，
且 `pendingFinalPaymentAmount == 0` → 心愿尾款里不会出现待补任务。

> 「已付定」= `isFinalPaymentPlan`（`isDepositPlan && !isFullPaymentReservation`），
> 「全款」= `isFullPaymentReservation`。两者互斥，口径沿用既有 `Clothing` computed，不新增状态源。

### 详情页按钮矩阵

| 阶段 | 按钮 |
|---|---|
| 预约中 | 加入心愿 / **付定金加购** / **全款加购** |
| 预约未开始 | 加入心愿（= 开售提醒） |
| 现货在售 | 加入少女衣橱 |
| 预约已结束 | 预约已结束标签 + **【加入衣橱】全款（主按钮）** / 【加入心愿尾款】收进「其他记账方式」折叠区（无预约价但有现货 → 原「加入少女衣橱」） |
| 无窗口无价格 | 加入少女衣橱 |

「已在心愿尾款中 / 已在少女衣橱中」的存量提示改用 `isFinalPaymentPlan` 判断
（旧口径用 `isDepositPlan`，会把全款入橱误报成「已在心愿尾款中」）。

---

## 三、衣橱卡片标题（需求 §III）

新增 `ItemManager/Services/ShopCatalog/ShopCatalogWardrobeTitle.swift`：

```swift
ShopCatalogWardrobeTitle.recordName(seriesName:designName:color:) -> String
ShopCatalogWardrobeTitle.resolvedColor(explicit:specColors:productName:) -> String?
```

组合顺序 `[系列名] [款式名] [颜色]`，四档降级：

| 条件 | 结果 |
|---|---|
| 系列 + 款式 + 颜色 | `天鹅之歌 段段方领JSK 生成色` |
| 无系列名 | `段段方领JSK 生成色` |
| 无颜色（纯配饰） | `天鹅之歌 珍珠发箍` |
| 都无 | `珍珠发箍` |

**两个补充口径（需求未写但必要）**：

1. **防重复**：款式名已含系列名时（种子数据形如 `雪国来信 JSK` 属于「雪国来信」系列）
   不重复前置，否则卡片出现「雪国来信 雪国来信 JSK 夜空蓝」。
2. **颜色兜底**：用户没点颜色时取后台规格色第一个（`store.colors(forProduct:)`），
   再退到商品名颜色词。保证记录名**总能带颜色**，同名不同色可区分 ——
   符合「系统自动读取后台数据，不让用户动脑」。

### 与商品标题的分工（不要合并）

- `ShopCatalogTitlePresentation` = **商品标题**（详情页 / 点菜页 / 商品管理）：
  标题 = 款式名，颜色只出「· N 色」标注。
- `ShopCatalogWardrobeTitle` = **写入衣橱的记录名**：三段式，必须带颜色。

记录一旦脱离列表就没有其它颜色线索，用户要靠名字找回是哪一条 ——
这是 `ShopCatalogTitlePresentation` 头部注释里既有的「有意保留的例外」，
需求 N 把它固定为三段式。

套装合并名同步改为以主衣物**记录名**开头（原来用原始 `product.name`，会丢掉系列口径）。

---

## 四、状态标签（需求 §III.3）

`ShopCatalogWardrobeStatusTag`（nonisolated 纯逻辑，唯一口径）：

| 标签 | 条件 | 色 |
|---|---|---|
| `已售出` | `reservationKind == .sold` | 红 |
| `全款` | `isFullPaymentReservation` | 主题强调色 |
| `已付定` | `isDepositPlan && !isFullPaymentReservation` | 主题强调色 |
| `转单` | `isResaleTransfer`（与付款标签**互相独立**，可并存） | 蓝灰 |

口径唯一来源 `ShopCatalogWardrobeStatusTag.chips(...)`，由 `WardrobeCellSnapshot.statusTags`
透出：衣橱列表卡在图片右上角横排渲染全部标签；网格卡只渲染主标签（避免与 3D / 库存角标重叠）。

`转单` 是新增的持久化字段：

- `Clothing.isResaleTransfer: Bool = false`（轻量迁移，默认 false）
- `ClothingEditDraft.isResaleTransfer: Bool?`（**Optional** —— 非 Optional 会让已落盘的旧草稿 JSON 解码失败）
- `ClothingDTO.isResaleTransfer: Bool?`（旧备份无键 → 恢复为 false）
- 编辑页入口：购买信息区「转单」开关（闲鱼收单等）

> 「已拥有」的普通记录**不挂付款标签** —— 若把「全款」也给 `owned`，全部存量衣橱会被刷上标签，
> 视觉噪音过大。全款口径只覆盖「预约价全款入橱」这条显式路径。

---

## 五、改动文件清单

**新增**

- `ItemManager/Services/ShopCatalog/ShopCatalogWardrobeEntryPolicy.swift`
- `ItemManager/Services/ShopCatalog/ShopCatalogWardrobeTitle.swift`
- `ItemManagerTests/ShopCatalogWardrobeEntryTests.swift`

**修改**

- `ShopCatalogWardrobeInserter.swift`：`PriceMode.fullReservation`；记录名改走 `ShopCatalogWardrobeTitle`；
  全款的价格留痕文案；套装合并名改用主记录名；`with(...)` 透传 `isResaleTransfer`；
  **待补尾款改读后台录入的 `currentBalance`**（§八）
- `ShopCatalogWardrobeEntryPolicy.swift`：状态机之外新增 `ShopCatalogWardrobeAmount`（尾款唯一算法，§八）
- `ShopCatalogProductDetailView.swift`：按钮矩阵（预约中 / 预约已结束双分支）；
  `ShopCatalogReservationSheet` 改为 `option` 驱动的只读金额确认页（待付尾款走 `ShopCatalogWardrobeAmount`）；
  存量提示判断口径修正
- `ClothingCard.swift`：快照 `isResaleTransfer` + `statusTags`；列表卡标签横排；网格卡主标签
- `Clothing.swift`：`isResaleTransfer` 字段 + init 参数
- `ClothingEditView.swift` / `ClothingEditSections.swift`：草稿字段、编辑模型、读写映射、转单开关
- `TimeHallWardrobeInsertion.swift`：一键入库透传 `isResaleTransfer`
- `BackupModels.swift` / `BackupService.swift`：备份/恢复带 `isResaleTransfer`
- `ShopCatalogTitlePresentation.swift`：更新「记录名例外」的注释口径

---

## 六、验收对照（需求 §IV）

| 验收项 | 覆盖用例 |
|---|---|
| 预约结束后选【加入心愿尾款】→ 衣橱「已付定」，尾款金额正确且无需手填 | `testEndedReservationDepositBranchKeepsFinalPaymentTask` |
| 预约结束后选【加入衣橱】→ 衣橱「已全款」，金额 = 预约价，心愿尾款无该商品记录 | `testEndedReservationFullBranchHasNoFinalPaymentTask` |
| 两分支金额一致、差别只在尾款任务 | `testDepositBranchAndFullBranchDifferOnlyInFinalPaymentTask` |
| 标题 = `[系列名] [款式名] [颜色]` | `testWardrobeRecordNameComposesSeriesDesignColor` |
| 同名不同色清晰区分 | `testSameDesignDifferentColorsAreDistinguishable` |
| 纯配饰降级 `[系列名] [款式名]` | `testColorlessProductDegradesToSeriesAndDesign` + 四档降级用例 |
| 状态标签 全款 / 已付定 / 转单 | `testStatusChipsForPaymentStates`、`testResaleTransferChipStandsAloneAndCombines` |
| 转单落库 | `testResaleTransferPersistsThroughInsert` |

## 七、验证边界

- 主 target 编译（`-target ItemManager`）通过
- `ItemManagerTests/ShopCatalogWardrobeEntryTests` 用例全绿（见当日工作日志的回执）
- 未做的：真机 / 模拟器上的 XCUITest 交互走查（按钮矩阵与 sheet 的端到端点击）

---

## 八、尾款口径修正（同日复验发现）

### 问题

需求 §II 原文要求「尾款金额自动读取后台录入的**『尾款』**数据」，但首版实现是**现算**的：

```swift
balanceAmount = event.price - depositAmount   // 预约价 − 已付定金
```

而后台 `CatalogSaleEvent` 本来就带独立的 `balance`（尾款）字段
（价格表录入的四列之一：定金 / 尾款 / 预约价 / 现货价），
`CatalogPriceArchive.currentBalance` 也已把它暴露出来 —— 等于把录入的尾款丢了不用。

**后果**：后台三价自洽时（定金 + 尾款 = 预约价）两者数值相同、看不出问题；
一旦不自洽（模型注释明确「允许缺省字段，**不做强约束**」，价格表由人工/OCR 录入，
完全可能出现预约价 ≠ 定金 + 尾款），待补尾款就会与后台录入值差一截，
直接违反验收标准「心愿尾款里出现**金额完全正确**的待办任务」。

### 修法：抽出唯一算法，两处共用

新增 `ShopCatalogWardrobeAmount`（`ShopCatalogWardrobeEntryPolicy.swift`，nonisolated 可单测）：

```swift
static func pendingBalance(backendBalance:reservationPrice:depositPaid:) -> Decimal
// 后台录入的尾款 → 后台没录 → 退回「预约价 − 已付定金」；负数归零

static func isBackendPriceInconsistent(deposit:balance:reservationPrice:) -> Bool
// 定金 + 尾款 ≠ 预约价（缺字段不判定，避免旧数据误报）
```

两处消费点**必须**共用它：

| 位置 | 作用 |
|---|---|
| `ShopCatalogWardrobeDraftBuilder.makeDraft`（`.reservation`） | 决定心愿尾款任务写多少钱 |
| `ShopCatalogReservationSheet.pendingBalance` | 决定弹窗上「待付尾款」显示多少钱 |

分开算就会「弹窗显示 302、落库写 300」。**入橱总额仍取后台预约价**（需求 §II 分支 B 口径），不变。

### 不自洽时不静默

后台三价对不上时，衣橱记录备注里如实留两句：

- `后台三价不自洽：定金 ¥128 + 尾款 ¥300 ≠ 预约价 ¥430；待补尾款按「录入的尾款」记账`
- 价格口径行改为 `定金 ¥128 + 尾款 ¥300（预约价 ¥430，以后台录入为准）` ——
  不写「A + B = C」这种算不平的等式，也不许偷偷改数。

### 回归锁

`ShopCatalogWardrobeEntryTests` 新增 3 例（套件 24 例 0 失败）：

- `testPendingBalancePrefersBackendBalanceOverDerived`：后台 300 优先于推导值 302；缺失回退；负数归零
- `testBackendPriceInconsistencyDetection`：自洽 / 不自洽 / 缺字段三态
- `testInconsistentBackendPricesAreRecordedVerbatim`：端到端 —— 注入不自洽后台数据（`ShopCatalogStore(catalog:)`），
  断言 `draft.balance == 300`、`priceTotal == 430`、备注含「不自洽」与「以后台录入为准」、
  `clothing.pendingFinalPaymentAmount == 300`

现有种子数据自洽（428 = 128 + 300），故本修正对存量数据**行为中性**
（`ShopCatalogPhase456Tests` 的 `balance == 300` 断言不变）。
