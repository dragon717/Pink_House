# 价格表 UI 精简 + 系列「发售阶段」时间管理（2026-09-23 需求一 / 需求二）

> 两个需求同批交付。需求一是**减法**（删冗余 UI），需求二是**加法**（系列层新增状态机与自动流转）。

---

## 需求一：清理「预约价格表」冗余 UI 及报错提示

**用户痛点原文**：「价格表图片识别功能频繁报错，且持续霸占页面，影响录入体验。」
**要求**：「只删这两处，其他保留。」

### 删除（`ShopCatalogSeriesEditSheet` 的「预约价格表」区块）

| 删除项 | 原来长什么样 |
|---|---|
| `ShopCatalogImagePickerButton(... label: "上传价格表图片（自动识别）")` | 紫色「上传价格表图片（自动识别）」按钮 |
| 红字常驻失败块 | 「上次识别失败，未写入任何内容：AI 识别不可用：未能完成操作…只识别出 1 列」+ 下方引导语 |

顺带清掉**只为这两处服务**的失效管线（不去掉就是永远不可达的死代码）：

- 识别进度行（`priceChartParsing` → 「正在识别价格表（AI 表格识别 → 本机兜底）…」）
- 失败 `alert`「解析失败，请手动录入」
- `.onChange(of: priceChartImageText)` 的识别触发
- 方法 `parsePriceChart(reference:)` / `failPriceChartParse(_:restore:)`
- `@State`：`priceChartParsing` / `priceChartParseFailure` / `showPriceChartParseAlert` / `priceChartPasteRequest`

### 保留

- **「粘贴文本录入（推荐，最准）」** 入口（`ShopCatalogChartPasteButton`，不再需要 `externalTrigger`，走组件默认值）
- 列名输入框 / 行文本 `TextEditor` / 单位输入框 / 行格式说明 / 「清除价格表」
- `priceChartImageText` 这个 `@State` 与 `makePriceChart()` 里的 `sourceImage` 写回

> ⚠️ **`priceChartImageText` 不能跟着一起删。** 它承载**既有**系列的
> `priceChart.sourceImage`：`onAppear` 从已存价格表回填、保存时原样写回。
> 删掉这个 state，用户只要「打开编辑系列 → 保存」一次，**已上传的价格表原图就被静默抹掉**。
> 需求原文只要求去掉「上传入口」，没要求丢弃已有数据。
>
> footer 说明文字保留，但删掉了其中已失效的一句「图片识别不保证百分之百准确——识别失败时会弹窗提示…」
> （功能已移除，留着就是错误说明）。

### 需要知会的一点：识别管线本身现在没有调用方

`Services/ShopCatalog/CatalogChartExtraction.swift`（多模态 → 端上 OCR → 质量门禁）
删掉价格表上传入口后**在 App 里已无任何调用点**（全仓只有它自己的定义与
`ItemManagerTests/CatalogChartExtractionTests` 的 24 个用例引用它）。

按「只删这两处，其他保留」，**本次保留该文件与测试**，未做删除。
如需一并清理，请明确指示——删除会让那 24 个用例失去被测对象。

---

## 需求二：系列「发售阶段」与预约时间管理

### 数据层

`CatalogSeries` 新增两个字段（都在 `Models/ShopCatalog/ShopCatalogModels.swift`）：

```swift
var salePhase: CatalogSeriesSalePhase? = nil   // nil = 未声明（旧数据）
var reservationEndAt: Date? = nil
```

**两个都必须是 Optional**：合成 `Decodable` 对非 Optional 字段走 `decode`，
旧覆盖层 JSON / Bundle 种子缺键会直接抛错——症状是整个系列列表打不开。
（`ShopCatalogSeriesSalePhaseTests.testLegacySeriesJSONWithoutNewKeysDecodes` 锁这条。）

新增枚举：

```swift
nonisolated enum CatalogSeriesSalePhase: String, Codable, CaseIterable, Identifiable, Sendable {
    case reservationActive   // 预约中
    case reservationEnded    // 预约已结束
    case inStock             // 现货
}
```

### 自动流转（需求 §二.3）—— 为什么是「读取时判定」

新增 `Services/ShopCatalog/ShopCatalogSeriesSalePhase.swift`（nonisolated，可单测）：

```swift
CatalogSeriesSalePhaseResolver.effectivePhase(declared:reservationEndAt:now:) -> CatalogSeriesSalePhase?
CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now:) -> CatalogSeriesSalePhase?
CatalogSeriesSalePhaseResolver.hasAutoFlowed(declared:reservationEndAt:now:) -> Bool
CatalogSeriesSalePhaseResolver.prefersFullPayment(_:) -> Bool
CatalogSeriesSalePhaseResolver.requiresReservationEndAt(_:) -> Bool
```

需求原话是「系统需增加**定时任务或触发机制**」。这里选**读取时判定**（等效的触发机制），
理由写在类型注释里，核心两条：

1. **回写会覆盖运营声明**：运营手工把阶段改回「预约中」（又开了一批），
   后台任务下一轮按旧时间又改回「预约已结束」——用户会看到「我的设置自己变回去了」。
2. 回写要动覆盖层写入口，引入落盘失败 / 并发 / 幂等三件事，为一个纯派生结果不划算。

收益是**不可能不一致**：真相来源只有一个（声明值 + 时间 + 当前时间），
不需要任何调度，也不会有「存储说预约中、展示说已结束」。

生效阶段在**系列列表的标签**上直接可见（`SeriesManageRow`），所以「自动变更」对运营是可见的：
「预约中 + 已过期」的系列，列表里显示的就是「预约已结束」。

### 表单（需求 §二.1 / §二.2）

「编辑系列 → 发售阶段」区块（`ShopCatalogSeriesEditSheet.salePhaseSection`）：

- `Picker`：**未设置（沿用销售记录）** / 预约中 / 预约已结束 / 现货。
  「未设置」是给**存量数据**准备的：不替运营猜，选了它就走改动前的档期推导，行为完全一致。
- 选「预约中」→ 显示 `DatePicker`（日期 + 时分）。选其它阶段 → **不显示**该输入框。
- 结束时间已过 → 红字提示「保存后生效状态会显示为『预约已结束』」，**但不拦保存**：
  结束时间已过本身就是合法状态（预约刚好结束），拦下来反而与 §二.3 的自动流转矛盾。
- 切到非「预约中」阶段**不清除**已录入的结束时间——那是「预约是什么时候结束的」这条事实本身，
  表单只是隐藏，不是删除。

### 前端取值（单一优先链）

`ShopCatalogProductDetailView.purchasePhase(for:)` 改为两段：

1. **系列「发售阶段」优先**：声明了（含自动流转结果）就用它 → `.reservationActive` / `.reservationEnded` / `.inStock`；
2. 未声明 → 落回既有「按销售事件档期推导」，**存量系列行为零变化，也不需要数据迁移**。

### 数据保留（需求 §二.4，用户标注的「最重要的一点」）

- 本页保存**只写** `salePhase` 与 `reservationEndAt` 两个字段，
  **一个价格字段都不碰**（预约价 / 定金 / 尾款 / 现货价）。
- 详情页「价格档案」卡片本来就不按阶段渲染，四类价格在任何阶段都照常展示
  （`priceArchiveCard` 的展示条件是「有预约记录 / 现货记录 / 价格修正」，与阶段无关）。
- 回归锁见下。

### 与需求 N 的冲突与裁定（**必读，别改回去**）

| 文档 | 说法 |
|---|---|
| 需求 N §II 场景二 | 预约期结束后提供**双分支**：【加入心愿尾款】= 定金 + 尾款；【加入衣橱】= 全款 |
| 需求二 §二 业务背景 / §二.4 | 预约结束后「需引导全款」「不能用预约价去进行定金 + 尾款的分期操作」 |

两份文档在这里直接冲突。**2026-09-23 用户裁定**：

> 「保留双分支，预约结束只改变默认 UI 引导（主推全款），但不剥夺用户记录『定金 + 尾款』的功能。
> 请按『全款为主，定金尾款为隐藏备用』的方式实现交互。」

落成实现：

- 预约已结束 → **主按钮 = 【加入衣橱】（全款，后台预约价）**，说明文案点明「不会生成尾款任务」；
- 【加入心愿尾款】（定金 + 尾款）收进 **「其他记账方式：已付过定金 / 补款期」折叠区**
  （`otherEntryOptionsDisclosure`，一次点击可达）；
- **禁止**把它改成隐藏或置灰——「官方补款期」「只交过定金」「闲鱼全款收转单」这些真实情形都需要它。

`CatalogSeriesSalePhaseResolver.prefersFullPayment` 只表达**引导**，
代码里没有任何「结束后禁止记定金尾款」的门禁，这是有意的。

---

## 验收对照

| 需求条目 | 覆盖 |
|---|---|
| §二.1 三个阶段 + 显示名 | `testPhaseOptionsAndDisplayNames` |
| §二.2 只有「预约中」需要结束时间 | `testRequiresReservationEndAtOnlyWhenActive` |
| §二.3 过期自动流转 | `testActiveAfterEndAutoFlowsToEnded`、`testBoundaryIsStrictlyAfterEnd`、`testEndedAndInStockIgnoreReservationEndAt`、`testHasAutoFlowedOnlyWhenPastActiveReservation` |
| §二.3 未声明不猜 | `testUndeclaredPhaseStaysNil` |
| §二.4 四类价格全保留 | `testAutoFlowToEndedKeepsAllPriceData`（断言声明值未被回写 + 四价原样） |
| §二.4 保存不碰价格 | `testSavingSalePhaseKeepsPriceChartOnDisk`（真落盘读 JSON 核对 `priceChart` 仍在） |
| 不剥夺记账能力（用户裁定） | `testEndedReservationStillAllowsBothEntryModes` |
| 旧数据兼容 | `testLegacySeriesJSONWithoutNewKeysDecodes` |

## 验证边界

- 主 target 编译通过（`-target ItemManager`，0 编译器诊断）
- 单测：`CatalogSeriesSalePhaseResolverTests` + `ShopCatalogSeriesSalePhaseStoreTests`
  \+ 相邻 5 个套件（价格表展示 / 深度编辑 / 价格共存 / 加购记账 / 抽取门禁）
- **未做**：模拟器 / 真机的 XCUITest 交互走查（发售阶段 Picker 的显隐联动、
  「其他记账方式」折叠区展开、列表阶段标签的视觉效果）
