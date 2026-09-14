# 时光馆图一重构 + 品牌页商品功能 — 分步推进方案

> 目标分两步，**先做完第一步再进第二步**。
> 第一步：严格对照参考图一逐项重做「时光馆」页面，彻底替换现有实现。
> 第二步：品牌页商品功能 —— 每件商品可直接加入衣橱 + 淘宝式商品分类与详情页（含尺码表、价格表）。
>
> 本文只列**改动内容与顺序**，不含时间估算。所有文件路径以本机工作区
> `/Users/sangyu/develop/Pink_House` 为准。

---

## 0. 开口前必须先落实的一件事

**参考图一不在工作区。**

图一是上一轮以微信图片形式直接发进对话的，没有落到磁盘（`temp/`、`output/`、
`asserts/` 都没有留档）。本轮「严格对照逐项重做」的**间距 / 字号 / 色值 / 栏宽**
必须对着原图量，不能凭记忆。

我手上保留的上一轮分析记录（可先用来搭结构，但不足以定"严格"）：

| 元素 | 已知参数 |
|---|---|
| 左侧年份栏 | 宽 86pt；选中＝橙色字 + 3pt 橙竖条 + 白底 |
| 顶部系列 chips | 文案格式「月.日 + 系列名」；选中＝浅橙底 + 橙字 |
| 商品卡片 | 左方图 + 右标题/价格；价格＝「小 ¥ + 大数字」两段字号 |
| 系列行（图二范式） | 方图 + 绿「新」角标 + 价格区间（橙红） + 尺码 + 浅橙「查看」 |

**请贴一次图一**。在拿到原图前，第一步的 1-1 ~ 1-3 可以推进（结构层），
1-4（视觉细节对齐）和 1-6（验收）做不了。

---

## 第一步 · 时光馆逐项重做（图一范式）

### 1-1 现状盘点：要替换掉的东西先点名

`ItemManager/Views/TimeHall/TimeHallView.swift`，**3148 行单文件**，当前是「四分支路由 + 三套页面骨架」：

```
TimeHallView.body (line 438)
└─ Group
   ├─ activeMerchant == .pinkHouse        → pinkHouseHall
   ├─ activeMerchant == .midsummerTale    → MidsummerBrandView      ← 上一轮新加
   ├─ 其他 curated 品牌                    → curatedBrandHall(_:)
   └─ activeMerchant == nil               → merchantSelection
```

三套骨架并存，就是「旧方案」：

| 旧组件 | 行数区段 | 作用 |
|---|---|---|
| `header` / `expandedArchiveHeader` | ~600–2100 | 粉房子馆的头部 + 折叠头 |
| `archiveScrollView` | — | 粉房子馆滚动体 |
| `curatedBrandHeader` / `curatedExpandedArchiveHeader` / `curatedArchiveScrollView` | ~500–600 起 | 其他品牌馆的**平行第二套** |
| `merchantSelection` | — | 品牌选择页 |
| `TimeHallMode`（编年史/图鉴手册/珍选/搭配） | line 4–21 | 四模式切换维度 |
| `LiquidBackground` + `GlassCard` | — | 液态玻璃底 + 玻璃卡 |
| `collapsedModeMenu` / `treasureButtonCompact` | — | 折叠态菜单 / 收藏按钮 |
| `TimeHallMagazinePageCard` / `TimeHallCatalogItemCard` / `TimeHallCommerceItemCard` | 2105 / 2495 / 2554 | 三套卡片 |

外部挂载点只有一个：

```
ItemManager/Views/MainTabView.swift:418    TimeHallView()
```

> 这意味着**对外接口可以保持不变**（还是 `TimeHallView()`），重构不会波及 Tab 层。

### 1-2 建分支保退路

```bash
git switch -c feat/timehall-fig1-rebuild
```

现有回归护栏（改完必须仍然全绿）：

- `ItemManagerTests/TimeHallCatalogValidationTests.swift`
- `ItemManagerTests/TimeHallPublicationProtocolTests.swift`

### 1-3 拆文件：新建图一新范式

**不再往 3148 行文件里加东西。** 新建目录
`ItemManager/Views/TimeHall/Rebuild/`：

| 新文件 | 职责 |
|---|---|
| `TimeHallHomeView.swift` | 图一首页骨架（年份栏 + 筛选 chips + 商品流） |
| `TimeHallYearRail.swift` | 通用左侧年份栏 |
| `TimeHallFilterChips.swift` | 顶部筛选 chips 行 |
| `TimeHallProductCard.swift` | 图一商品卡片（左方图 + 右标题/价格） |
| `TimeHallProductGrid.swift` | 商品流容器（分组 / 网格） |
| `TimeHallBrandSelector.swift` | 品牌入口（图一风：卡片或横滑） |
| `TimeHallTheme.swift` | **从图一取色/取字号**的令牌层 |
| `TimeHallHomeAdapter.swift` | 把 `TimeHallCatalogStore` 适配成「年份 → 系列 → 商品」 |

`TimeHallTheme.swift` 是「严格对照」的落点：色值、字号、圆角、间距**全部集中在这里**，
原图量出来一个数就改一个常量，不在视图里散落硬编码。

`TimeHallHomeAdapter.swift` 是纯逻辑层（不 import SwiftUI），把现有
`TimeHallItemDTO` / `TimeHallCommerceItemDTO` / `TimeHallCoordinateDTO` 归一化成
图一需要的三级结构，**可单测**。

### 1-4 逐项对照清单（图一 → 新实现）

拿到原图后逐条填这张表，每条对应一次改动 + 一张快照：

| # | 图一元素 | 现状 | 新实现落到 | 状态 |
|---|---|---|---|---|
| A-1 | 页面背景色/材质 | `LiquidBackground` 液态玻璃 | `TimeHallTheme.pageBackground` | 待量 |
| A-2 | 左年份栏：宽度 | 无（现为顶部模式 Tab） | `TimeHallYearRail.width` | 86pt（待复核） |
| A-3 | 左年份栏：选中态 | 无 | 橙字 + 3pt 竖条 + 白底 | 待量色值 |
| A-4 | 左年份栏：未选中态 | 无 | 灰字，副标题不染橙 | 上一轮已踩过这个坑 |
| A-5 | 顶部 chips 行 | 无（现为 `TimeHallMode` Tab） | `TimeHallFilterChips` | 待量 |
| A-6 | chips 文案格式 | 无 | 「月.日 + 系列名」 | 待确认 |
| A-7 | 商品卡片：图片区 | 现有卡片是**上图下文**竖式 | `TimeHallProductCard` 改左图右文 | 结构变更 |
| A-8 | 商品卡片：价格 | 单行 `¥N` 或划线价 | 「小 ¥ + 大数字」两段字号 | 待量字号 |
| A-9 | 商品卡片：角标 | 无 | 待原图确认是否有「新」/「HOT」 | 待确认 |
| A-10 | 分组标题 | `TimeHallMagazinePageCard` | 待原图确认 | 待确认 |
| A-11 | 滚动/吸附行为 | `onScrollGeometryChange` 折叠头 | 待原图确认 | 待确认 |
| A-12 | 底部安全区/留白 | — | 按原图量 | 待量 |

### 1-5 替换与清理

- `TimeHallView.body` 的 `Group` 四分支 → **单一路由**（`TimeHallHomeView`）
- 删除旧骨架：`pinkHouseHall`、`curatedBrandHall(_:)`、`curatedBrandHeader(_:)`、
  `expandedArchiveHeader`、`curatedExpandedArchiveHeader`、`archiveScrollView`、
  `curatedArchiveScrollView`、`collapsedModeMenu`
- `MainTabView.swift:418` **不动**
- 保留（第二步还要用）：`TimeHallItemDetailView`、`TimeHallCommerceItemDetailView`、
  `TimeHallCoordinateDetailView`、`TimeHallStoryDetailView`、`TimeHallWardrobeDraftBuilder`

**三个需要你拍板的设计问题**（见文末确认清单 Q2 / Q3）：

1. `TimeHallMode` 四模式（编年史/图鉴手册/珍选/搭配）——图一里没有这个维度。删除？还是降级成 chips 的一个筛选轴？
2. `MidsummerBrandView`（上一轮的仲夏物语品牌页）——并入新范式？还是保留为独立页？
3. `LiquidBackground` 液态玻璃底——图一是什么底？保留还是换成图一的底？

### 1-6 验收

1. `xcodebuild` 主 target + test target 编译通过
2. `TimeHallCatalogValidationTests` / `TimeHallPublicationProtocolTests` 不回归
3. `TimeHallHomeAdapter` 新增单测（三级结构归一化、空数据不白屏）
4. **区块快照逐张对比图一** —— 注意上一轮踩过的坑：
   - `ImageRenderer` 渲染 `ScrollView`/`Form`/`List` 只出空框架 → 年份栏、chips、商品卡片必须**抽成独立非滚动组件**才能快照
   - 带 `.task` / `.onAppear` 写状态的页面丢进 `ImageRenderer` 会 `Fatal error` 崩测试进程
   - `UIImage.size` 是**点**不是像素
5. 模拟器实机走查（iPhone 18 Pro）

---

## 第二步 · 品牌页商品功能

### 2-0 现状：已有什么、缺什么

**已经具备（不用重做）：**

| 能力 | 位置 | 说明 |
|---|---|---|
| 颜色/尺码**数据** | `TimeHallCommerceItemDTO.colors` / `.sizes` | 真实数据，抽查某商品 4 色 / 尺码 `0,1,2` |
| 加入衣橱按钮组件 | `TimeHallAddToWardrobeButton`（line 2303） | 已存在 |
| 商品 → 衣橱映射 | `TimeHallWardrobeDraftBuilder.makeDraft(for: TimeHallCommerceItemDTO…)` | **已把 colors/sizes 拼进 `ClothingEditDraft`** |
| 衣橱创建入口 | `TabNavigationManager.presentWardrobeCreation(with:)`（line 79） | 已存在 |

**真实缺口（这才是要做的）：**

| # | 缺口 | 证据 |
|---|---|---|
| G1 | **商品卡片上没有加入衣橱入口** | `addToWardrobe` 只在两个**详情页**（line 2412 / 2678），卡片 `TimeHallCommerceItemCard` 上没有 |
| G2 | **详情页不是淘宝式分类** | `detailFacts` 只渲染两行**纯文本**：`颜色：A、B、C` / `尺寸：S、M、L`，无选中态、无点选、无价格联动 |
| G3 | **没有尺码表** | `TimeHallCommerceItemDTO` 只有 `sizes: [String]`（就是 `S/M/L` 标签），**没有**肩宽/胸围/腰围/衣长等实测字段 |
| G4 | **没有价格表** | 只有 `regularPriceJPY` / `salePriceJPY` 两个标量，**没有**按尺码/颜色区分的价格矩阵 |
| G5 | **货币写死日元** | `TimeHallWardrobeDraftBuilder.draft(...)` 里 `originalPriceCurrencyCode: ClothingPriceCurrency.jpy.rawValue` 硬编码，`originalPrice: 0` |
| G6 | **加入衣橱＝跳编辑页** | `presentWardrobeCreation` 打开衣橱创建流程，不是一键直插 —— 与"快捷"可能不符 |
| G7 | **馆藏路径丢分类** | `makeDraft(for: TimeHallItemDTO)` 传 `colors: ""` / `sizes: ""`，且 `TimeHallItemDTO` **根本没有**这两个字段 |

### 2-1 数据层扩字段（G3 / G4 / G5 的前提）—— ✅ 已实施

**已落地**（详见第三节）：

| 改动 | 位置 |
|---|---|
| 新增 `TimeHallPriceTier` / `TimeHallSizeChart` / `TimeHallSizeRow` | `ItemManager/Models/TimeHall/TimeHallModels.swift` |
| `TimeHallCommerceItemDTO` 追加 `priceTiers` / `sizeChart`（可选） | 同上 |
| 尺码表解析器 + `resolvedSizeChart` | `ItemManager/Services/TimeHall/TimeHallSizeChartParser.swift` |
| 11 个用例 | `ItemManagerTests/TimeHallSizeChartParserTests.swift` |

**硬约束（已验证）：**

- 新字段全部可选 → Swift 合成解码对可选属性走 `decodeIfPresent`，
  历史 `catalog*.json` 无这两个键时解码为 `nil`，**不需要**自定义 `init(from:)`
  （项目里 `TimeHallCommerceItemDTO` **没有任何构造点**，只从 JSON 解码，这一点已确认）
- 不改既有字段名（`TimeHallPackCache` 缓存与 Bundle 解码都依赖）
- 小于 3 项测量值不产出尺码表 —— 否则会把描述正文里的「ウエスト」误判成尺码表
  （Wunderwelt 的描述里这个词到处都是）

**数据从哪来：见第三节（已核实，不是「只能人工录入」）。**

**仍需补的两块 UI（不阻塞数据层）：**

1. **人工录入入口**：给创作者一个填表入口，写入 `TimeHallSizeChart` 时
   置 `isManuallyEntered: true`。落点与形态取决于「人工录入入口放在哪」
   —— 建议复用仲夏物语的投稿页范式（`MidsummerContributeView`），
   但归属到时光馆下需要你先定页面归属
2. **价格表数据**：`priceTiers` 目前**无历史数据**（现有 JSON 只有 `regularPriceJPY` /
   `salePriceJPY` 单档）。要么走人工录入，要么界面上回退成单档展示

### 2-2 商品卡片改造（G1）

改 `TimeHallCommerceItemCard`（line 2554）：

| 改动 | 具体内容 |
|---|---|
| 加加入衣橱入口 | 卡片右下角一个「+ 衣橱」小按钮 / 或长按 contextMenu，**不遮挡**收藏心形 |
| 显示分类摘要 | 颜色数 + 尺码范围 chips（如「4 色 · S–L」），数据来自 `colors` / `sizes` |
| 价格呈现 | 对齐图一「小 ¥ + 大数字」 |
| 点击行为 | 主体仍进详情页；「+ 衣橱」走 quick-add（Q4） |

### 2-3 商品详情页改造成淘宝式（G2 / G3 / G4）

改 `TimeHallCommerceItemDetailView`（line 2621），自上而下分区：

| 区 | 内容 | 现状 |
|---|---|---|
| ① 图集 | 横向翻页大图 | 已有 `TabView` |
| ② 标题区 | 中文名 + 原名 + 品牌 + 品番 | 已有 |
| ③ 价格区 | 现价（大）+ 原价划线 + 定金/尾款 | 已有 `commercePrice`，需扩「定金/尾款」 |
| ④ **颜色选择行** | 可点选，选中态边框/勾选；色块（若可映射 hex） | **缺**，替换 `detailFacts` 里的纯文本 |
| ⑤ **尺码选择行** | 可点选，选中态；无货置灰；「尺码 ▸」可跳尺码表 | **缺** |
| ⑥ **加入衣橱** | 主按钮，带当前选中的颜色/尺码 | 已有按钮，**需接选中态** |
| ⑦ 商品介绍 | 正文 | 已有 |
| ⑧ **尺码表** | 表格：表头 + 行；单位 cm/inch 切换 | **缺** |
| ⑨ **价格表** | 规格 × 价格/定金/尾款 表格 | **缺** |
| ⑩ 溯源 | 查看官方商品页 / 图录原图 | 已有 |

④⑤ 的选中态用 `@State private var selectedColor: String?` / `selectedSize: String?`
（**不进 DTO**，纯 UI 态）。

### 2-4 加入衣橱的两种模式（G6 / G7）

**Q4 需要你选：**

- **模式 A · 一键直插**：`modelContext.insert(Clothing(...))` + 图片落盘 + toast，
  不跳页。最快，但绕过衣橱的编辑确认。
- **模式 B · 跳编辑页**（现状）：`presentWardrobeCreation(with: draft)`，
  带预填数据进衣橱创建流程。安全，但多一步。
- **推荐：卡片＝A（快捷），详情页＝B（可确认）**。两个入口两种语义，符合你说的"快捷加入"。

**映射修正（无论选哪个都要做）：**

- 选中的颜色/尺码写入 `ClothingEditDraft.colors` / `.sizes`（现在 commerce 路径是
  全部拼接，应改成写入选中的那一个）
- 价格按 `priceTiers` 命中规格取价；货币读 `currency`，**去掉 `jpy` 硬编码**
- `makeDraft(for: TimeHallItemDTO)` 的 `colors: ""` / `sizes: ""`（G7）：
  要么给 `TimeHallItemDTO` 补字段，要么明确"馆藏路径无分类"是预期行为

### 2-5 验收

**单测**（新建 `ItemManagerTests/TimeHallCommerceTests.swift`）：

- 旧 `catalog*.json`（无 `priceTiers` / `sizeChart`）**解码不炸**
- 若无 `priceTiers`，回退到 `regularPriceJPY` / `salePriceJPY` 单档
- 尺码表 rows/columns 列数不匹配时的容错
- 选中色/尺码 → draft 映射正确
- 货币映射：JPY / CNY 各自落到正确的 `ClothingPriceCurrency`

**快照**（沿用第一步建立的区块快照方法）：

| 文件 | 核对 |
|---|---|
| `10-card-with-quickadd.png` | 卡片上的加入衣橱入口 + 分类摘要 |
| `11-color-selector.png` | 颜色行选中/未选中 |
| `12-size-selector.png` | 尺码行选中/无货 |
| `13-size-chart.png` | 尺码表（含空态） |
| `14-price-table.png` | 价格表（含空态） |

**模拟器**：卡片「+ 衣橱」→ 衣橱列表出现该件（颜色/尺码/价格正确）。

---

## 三、尺码表数据来源（已核实，非推测）

这是第二步最容易被低估的一环。核实结论：**数据大部分已经在本地了，只是从未被解析。**

品牌官网商品页的尺寸文本，历史上是**随 `description` / `descriptionZH` 一起采集入库**的，
格式高度规整：

```
着丈：約98cm
バスト：約88～140cm
ウエスト：約68～138cm
肩幅：約34cm
袖丈：約62cm
```

实测覆盖率（2026-09-14 统计 `ItemManager/Resources/TimeHall/*.json`）：

| 目录 | 商品数 | 可解析尺码表（≥3 项） | 比例 |
|---|---|---|---|
| `catalog-baby-stars-shine-bright.json` | 861 | **283** | **33%** |
| `catalog-wunderwelt-fleur.json` | 3116 | 2 | 0% |
| `catalog-angelic-pretty.json` | 267 | 0 | 0% |
| `catalog-juliette-et-justine.json` | 221 | 0 | 0% |
| `catalog.json` | 308 | 0 | 0% |
| **合计** | **4773** | **285** | **6%** |

**三类来源，按成本排序：**

1. **零成本可落地（285 件 / 6%）**：Baby 官网把尺寸写成文字，已被采集。
   写一个解析器即可结构化，不需要新增抓取。Baby 品牌覆盖率达 **33%**。
2. **需补采集规则（少量）**：Juliette et Justine 的尺码表是 HTML 表格，
   被「拍平」成了文本行（能看到 `バストトップ /cm Bust /cm 胸围 /cm` 这样的表头行）。
   表头可识别，数值行需要逐条核对，暂不自动处理。
3. **抓不到的（绝大多数）**：Angelic Pretty、Wunderwelt（二手）的尺码表在**图片**里，
   公开渠道拿不到结构化数据 —— **这正是人工录入入口存在的理由**。

### 已落地的实现

| 文件 | 内容 |
|---|---|
| `ItemManager/Models/TimeHall/TimeHallModels.swift` | 新增 `TimeHallPriceTier`（价格表一档，含 定金/尾款/币种）、`TimeHallSizeChart`、`TimeHallSizeRow`；给 `TimeHallCommerceItemDTO` 加 `priceTiers` / `sizeChart` 两个**可选**字段 |
| `ItemManager/Services/TimeHall/TimeHallSizeChartParser.swift` | 解析器：日文优先、中文补齐、同列冲突以日文为准、重复出现取首次、少于 3 项返回 nil（避免把文案里的「ウエスト」误判成尺码表）；另提供 `resolvedSizeChart`（**已存结构化数据 > 文本解析**） |
| `ItemManagerTests/TimeHallSizeChartParserTests.swift` | **11 个用例**，全部通过：解析规则、行值对齐、解码兼容、覆盖率下限回归 |

**人工录入入口的约定**：写入 `TimeHallSizeChart` 时置 `isManuallyEntered: true`，
以便界面与统计区分「公开文本解析」与「创作者录入」两种来源。

**加字段的安全性**：`TimeHallCommerceItemDTO` 全项目**没有任何构造点**，只从 JSON 解码；
新增字段为可选，Swift 合成的解码对可选属性走 `decodeIfPresent`，
所以历史 JSON（无这两个键）解码为 `nil`，不会 `keyNotFound`。已用真实 JSON 断言。

---

## 四、已锁定的决策

| # | 决策 |
|---|---|
| Q2 | **珍选 / 搭配从主页四模式中移除**，但**保留为独立页面**，暂不删除 |
| Q5 | 尺码表来源见第三节；**预留人工录入入口**（`isManuallyEntered: true`） |
| Q6 | **接受数据层加字段** —— 已实施（见第三节） |

### Q2 的实现方式（有个坑要说清楚）

`ItemManagerTests/TimeHallCatalogValidationTests.swift` 里有一条：

```swift
func testTimeHallUsesSharedFourTabMapping() {
  XCTAssertEqual(TimeHallMode.allCases.map(\.rawValue),
    ["chronicle", "styleSpray", "story", "coordinate"])
  ...
}
```

**直接从 `TimeHallMode` 删掉 `.story` / `.coordinate` 会让这条既有测试挂。**
（我查过：`TimeHallMode` 实际只在 `TimeHallView.swift` 内部使用，
测试名里的 "Shared" 是起大了，但它仍然是一道护栏。）

所以「移除」的正确做法是**改选择器而不是改枚举**：

1. 保留 `TimeHallMode` 四个 case 与两处 `switch`（`curatedBrandContent` / `archiveScrollViewBody`）不动
2. 新增 `TimeHallMode.primaryPickerModes: [TimeHallMode] = [.chronicle, .styleSpray]`
3. `modePicker`（1486）与 `collapsedModeMenu`（1486 附近）改为遍历 `primaryPickerModes`，主页只出现两个模式
4. 珍选 / 搭配 各自的 `storyContent`、`coordinateContent`、`curatedStories`、`curatedCoordinates` **整体搬进独立页面**，从别处入口进入
5. 既有测试保持全绿

> ⚠️ 注意别混淆：`TimeHallPublicationModels.swift:130` 里也有 `.coordinate` / `.story`，
> 那是**发布分片的类型枚举**，与 `TimeHallMode` 是两个东西，不要一起改。

---

## 五、确认结果（2026-09-14 已全部回答）

| # | 问题 | 结论 |
|---|---|---|
| Q1 | 重新贴参考图一 | ✅ 已提供（`微信图片_20260914032045_2326_72.jpg`，关注店铺列表范式） |
| Q2 | 珍选 / 搭配怎么处理 | ✅ 移除，但**暂时保留为独立页面**（改选择器而不改枚举，避免既有测试挂） |
| Q3 | `MidsummerBrandView` 并入还是独立 | ⏳ 维持独立页（本轮未被要求重写，未改动） |
| Q4 | 加入衣橱的形态 | ✅ **两种都做、都保留，不预设默认**——已实现 |
| Q5 | 尺码表数据来源 | ✅ 285 件可零成本从既有文本解析，另预留人工录入入口 |
| Q6 | 是否接受数据层加字段 | ✅ 接受（`priceTiers` / `sizeChart` 已落地） |
| Q7 | 「两者都先保留」指什么 | ✅ 经澄清 = **加入衣橱的两种形态**（不是新旧页面并存） |

> **Q7 的澄清很关键**：既然「两者」指的是衣橱形态而不是新旧页面，
> 第一步的主页就是**硬替换**，不需要额外做「版本切换入口」，
> 1-5 的清理范围不作废。

---

## 六、执行顺序总览

```
第一步
  1-1 盘点旧方案        ← ✅ 已完成
  1-2 建分支保退路      ← ✅ 已完成（旧轮播保留、主页改指向新实现）
  1-3 拆文件搭新骨架    ← ✅ 已完成（新建 Rebuild/ 四个文件）
  1-4 逐项对照图一      ← ✅ 已完成（对照表见交付说明）
  1-5 替换 + 清理旧骨架  ← 🟡 主页已替换；旧轮播代码仍留在文件里待删
  1-6 验收             ← ✅ build + 86 项回归 + 25 项新测 + 5 张快照

第二步
  2-1 数据层扩字段      ← ✅ 已完成
  2-2 卡片加加入衣橱入口 ← ✅ 已完成
  2-3 详情页淘宝式改造   ← ⏳ 未做（G2/G3/G4 的 UI 部分）
  2-4 映射修正 + 快捷加入 ← ✅ 两种形态都已完成
  2-5 单测 + 快照 + 模拟器走通 ← 🟡 单测与快照已通；模拟器手动走查待做
```

**验收基线**：主 target 与 test target 编译通过；
`TimeHallCatalogValidationTests`、`TimeHallPublicationProtocolTests` 不回归；
新增用例全绿；快照逐张人工核对。

---

## 七、进度更新（2026-09-14 11:35）

### 已完成

**时光馆主页（图一范式）** —— 硬替换旧的左右滑动轮播：

- 新增 `TimeHallBrandListHome`：标题 + 搜索框 + 筛选条（全部／有上新／国牌／日牌）+ `ScrollView` 列表
- 新增 `TimeHallBrandListRow`：方形缩略图（含左下绿「新」角标）+ 品牌名 + 绿字主指标 + 竖线 + 灰字时间 + 橙色「进店」+ 灰色「⋯」
- `TimeHallView.body` 的主页分支由 `merchantSelection` 改为 `brandListHome`；
  `TimeHallMerchant` 由 `private` 提升为 internal 供新文件复用
- 旧轮播实现仍留在 `TimeHallView.swift`，仅不再作为主页渲染（回退成本为零）

**衣橱两种形态（并行保留，无默认偏向）**：

- 形态 A「一键入库」：`TimeHallWardrobeQuickInserter`，不打开编辑页直接落 `Clothing`
- 形态 B「加入并编辑」：复用既有 `presentWardrobeCreation(with:)`
- 两者共用同一套字段映射（`TimeHallWardrobeDraftBuilder`），入库内容不会走偏

### 过程中被快照抓出来的三个真问题（均已修）

| 问题 | 表现 | 修法 |
|---|---|---|
| 时间文案病句 | 仲夏物语显示「**今天前加入**」 | 「今天／昨天」不接「前」；补回归用例 |
| 「⋯」渲染成禁止符号 | `Menu` 在 `ImageRenderer` 下无法栅格化 | 改为 `Button` + `confirmationDialog`，快照可核对 |
| 缩略图圆角偏大 | 14pt 比图一略圆 | 调为 12pt |

### 关键结论：关于「N 件新品」的诚实口径

现有 catalog 只有 `listingStatus`（`in_stock` / `sold_out`）和单一批次的 `observedAt`，
**推不出「新品」**。因此：

- 只有**仲夏物语**填了 `newItemCount`，口径可核验（2026 年 3 个系列 8 件单品）
- 其余品牌主指标退化为**真实在售件数**（`N件在售`），且**不出现**绿「新」角标
- `newItemCount > 0` 必须有来源说明，由单测强制（`testNewItemCountMustCarryVerifiableSource`）
- 图一本身也不是每行都有「N件新品」，所以这个降级不违背参考图

### 下一步（尚未做）

- 2-3 商品详情页改造成淘宝式（颜色行 / 尺码行 / 尺码表 / 价格表的可点选 UI）
- 1-5 清理：确认无引用后删除旧的 `merchantSelection` 系列函数
- 模拟器手动走查（搜索、筛选、进店、一键入库、跳编辑页）

---

_生成时间：2026-09-14（第七节同日 11:35 追加）_
