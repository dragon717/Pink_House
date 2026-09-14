# 仲夏物语 · 规格选择（仿淘宝「加入购物车」）

> 对应需求：商品详情页的「一键入库」原先是一点即落库，无法选颜色 / 尺码等规格。
> 现改为参照淘宝商品详情页「加入购物车」的交互：**先选规格，再入库**。

## 一、与淘宝的三点刻意差异（产品决策，不要照抄淘宝）

| | 淘宝「加入购物车」 | 本功能「一键入库」 |
|---|---|---|
| 可见性 | 需要登录，部分商品限购 | **所有使用者都可见可点**，不要求登录、无权限闸门 |
| 数量 | 受库存 / 限购数约束 | **不限数量**（默认 1，可加到任意大，没有上限档） |
| 库存 | 加购会锁定 / 扣减库存 | **不校验、不扣减任何库存**；品牌库存不受影响 |

推论（写代码时容易顺手写错的点）：

- `MidsummerSKU` **没有** `stock` 字段——没有库存数据，也就不该有「缺货」这种灰态
- 数量步进器**不写** `quantity < max` 之类的判断
- 选项变灰**只可能**来自「组合不成立」，不来自「卖完了」

## 二、交互形态

规格面板是一个**覆盖在详情页上的底部抽屉**，不是新的 push 页、也不是嵌套 sheet——
与淘宝一致：加购不离开详情页，抽屉升起、选完即收。

界面里明确写出「不限入库数量 · 不影响品牌库存」，
让使用者一眼看出这不是电商的下单/加购动作。

### 入口行为矩阵

| 入口 | 行为 | 为什么 |
|---|---|---|
| 详情页「一键入库」 | 弹规格抽屉 → 选规格 / 数量 → 「加入衣橱」直接落库 | 本需求的主体 |
| 详情页「加入并编辑」 | 弹**同一个**抽屉 → 「下一步：确认并编辑」跳衣橱编辑页并预填刚选的规格 | 否则编辑页里会出现「我明明选了粉色，怎么没有」 |
| 列表卡片上的 ⊕ | 不弹面板，走**默认规格**直接入库；吐司写明实际规格 | 那个入口的价值就是「快」；但绝不能静默替使用者决定，所以吐司必须带出规格 |
| 系列详情页行内的 ⊕ | 同上 | 保持一致 |

### 选中 / 取消选中（可切换，且允许全不选）

**规则：点已选项 = 取消选中。** 款式、颜色分类、尺码三组走**同一条**规则，
并且允许一组都不选 —— 不存在「必选组」。

| 当前状态 | 点击 | 结果 |
|---|---|---|
| 未选中 | 点它 | 选中 |
| 已选中 | 再点它 | **取消选中**，该组回到未选 |
| 任一状态 | 点同组另一项 | 换成另一项（不是取消） |

实现要点：

- 走 `MidsummerSpecResolver.toggling(groupID:optionID:in:of:)`，
  **不要**在视图里直接改 `selection`。`toggling` 内部显式 `removeValue`，
  而 `selecting` 是恒定赋值——用错就不会有取消语义。
- 取消后同样过一遍 `normalized`：少一组约束只会让组合更宽松，
  所以**其它组已选不会被牵连清掉**。点掉尺码不会把刚挑好的配色一起弄丢。
- **确认按钮不再禁用**。既然允许不选，禁用就等于把这条规则作废——
  取消选择之后反而卡在面板里出不去。缺的规格由 `wardrobeMapping`
  回退到单品自带的配色 / 尺码，落库结果依然成立。
  底部提示也从「请先选择 X」改成陈述句「未选 X，将按商品默认信息入库」。
- 可发现性：面板里写一行「点击选中；再次点击已选项即可取消，也可以一组都不选。」
  （`spec-toggle-hint`）。以前点已选项只是「重选同一个值」，看上去像没反应。

### 规格缺省

单品没有规格组时，抽屉**照样打开**，并明确写一句
「该单品暂无规格可选，将按单品信息直接加入衣橱。」

不选择「规格缺省就直接跳过抽屉」的原因：使用者无从判断自己是不是漏选了什么。
统一路径 + 一句如实说明，比「有时候弹、有时候不弹」可预期得多。

## 三、数据模型

```swift
MidsummerSpecGroup   // 规格组：id / name / role? / options
MidsummerSpecOption  // 组内选项：id / name / image?
MidsummerSKU         // 一条具体组合：id / options[groupID: optionID] / image? / price?
```

挂在单品上（两个字段都可选，旧 JSON 不加字段也能解码）：

```json
{
  "id": "midsummer-2026-sakura-lamb-sk",
  "specGroups": [
    { "id": "color", "name": "颜色分类", "role": "color",
      "options": [
        { "id": "sk-pink",  "name": "Sk粉色", "image": null },
        { "id": "sk-white", "name": "Sk白色", "image": null }
      ] },
    { "id": "size", "name": "尺码", "role": "size",
      "options": [ { "id": "s", "name": "S", "image": null }, … ] }
  ],
  "skus": null
}
```

- `role` 决定该组的选中值落到衣橱的哪个字段：`color` → 配色、`size` → 尺码、
  `variant`（款式）/ `other` → 只进备注，其中 `variant` 还会拼进**入库名称**。
  缺省时按名字关键词推断（「尺码 / 尺寸 / 码 / size」「款式 / 版型 / 款型」
  「颜色 / 配色 / 色 / color」）。
- `skus` 为 `null` / 空表示**不做组合约束**：任意搭配都合法。
  这是「只有规格组、还没整理出组合表」的常见中间状态，不该因此把界面卡住。

### 归集商品：一个电商链接 = 一个商品

「樱花小羊」这类商品在淘宝上是**一个链接**，点进去在颜色分类里选 9 个款式
（印花SK / 段段JSK / 无腰OP / 内搭 / 开衫 / 围裙 / 罩裙 / 小物）。
这种商品不要拆成多条单品，而是用**三组规格**装进同一个单品：

```
款式（role: variant） × 颜色分类（role: color） × 尺码（role: size）
```

SKU 表把三者交叉起来，每一条带该款的价格——于是「选了内搭就只有奶白色可选」
这类联动、以及逐款定价都由同一张表驱动，不需要额外代码。
详见 `MIDSUMMER_TALE_PRICE_AND_CONSOLIDATION.md`。

### 图片回退链

`image` 字段既支持 `Assets.xcassets` 里的名字，也支持 `http(s)` 图链。
展示时按优先级取：

1. **命中 SKU 的组合图** —— 用于「内搭奶白色 S1粉色」这类跨组专属图
2. 已选选项里第一个带图的 —— 通常就是颜色分类那张（「Sk粉色」显示 Sk粉色 的图）
3. 单品封面 `item.coverImage`
4. 都没有 → 界面渲染**明确的「无图」占位**（浅灰底 + 相片图标）

第 4 条用「无图」占位而**不是**品牌水印渐变，是因为水印渐变会让使用者分不清
「这个规格有专属图」和「这个规格还没图」。

## 四、解析器：四类必须覆盖的边界

全部逻辑在 `MidsummerSpecResolver`（`nonisolated`、无副作用、可脱离 UI 单测）。

| 情况 | 行为 |
|---|---|
| 1. **规格缺省** | `hasSpecs == false`、`isComplete == true`；不卡流程；文案「该单品暂无规格可选」 |
| 2. **有规格组、无 SKU 表** | 所有选项恒可用（无约束）；`isAvailable` 直接返回 `true` |
| 3. **多规格联动** | 某选项与「其它组当前选择」无法组成任何合法组合 → 灰化禁用，并给出一行说明 |
| 4. **选中状态变化** | 改 A 组后，B 组失效的旧选择**自动清掉**，不留假选中；提示变成「已选 Sk粉色 · 请选择 尺码」 |

联动的判定细节（`isAvailable`）：某条 SKU **没有提及**某个组时，该组**不参与**这条 SKU 的约束。
否则「只标注了颜色的 SKU」会把整个尺码组判死——这一点被单测逮到过。

### 为什么把逻辑抽成纯函数

这四种状态迁移都不该靠点界面来验证。抽成无副作用的纯函数后，
19 个单测能在 0.2 秒内跑完全部分支（含「改配色后尺码被清掉」这类时序问题）。

## 五、规格数据从哪来

目前有两个来源，优先级同其他仲夏物语数据：

| 来源 | 现状 |
|---|---|
| Bundle 种子 `midsummer-series.json` | **已有**：樱花小羊 5 件单品带 `specGroups`（颜色分类 + 尺码），其余单品无规格（正好覆盖「规格缺省」路径） |
| CloudKit 创作者上传 | **尚未接入**：`MidsummerCloudService` 与投稿表单仍按「无规格」处理，见「待办」 |

### 规格图怎么填

**结论：本轮未能从淘宝抓到规格图。** 实测记录：

1. 短链 `https://e.tb.cn/h.8JmuwHMKIB4LK8H` 可解析出真实商品地址（item id `1032370386538`）
2. `https://item.taobao.com/item.htm?id=…` 返回纯 JS 壳，图片走 `mtop` 接口
3. `mtop.taobao.pcdetail.data.get` 返回 `RGV587_ERROR::SM`（风控），h5 令牌签名流程也拿到 `x5secdata` 挑战 → **需要登录**
4. 真实浏览器（Chromium）打开该商品页 → **302 到 `login.taobao.com`**，未登录会话完全拿不到商品内容

因此当前种子里的 `image` 全是 `null`，界面显示「无图」占位。
后续补图的三种方式（任选）：

- **创作者上传**：接上 CloudKit CKAsset（需先补投稿表单的规格字段，见待办）
- **填图链**：把 `image` 换成 `http(s)` URL（`MidsummerCoverView` 已支持 `AsyncImage`）
- **本地素材**：把图放进 `Assets.xcassets`，`image` 填 asset 名

> ⚠️ 版权提醒：不要把淘宝商品图直接打包进 App。仲夏物语是国牌，
> 我们没有被授权再分发其官方图（同 `MidsummerTheme.swift` 顶部注释的口径）。

## 六、怎么验

### 单测（24 例，覆盖上面四类边界 + 图片回退 + 价格 + 角色推断 + 数量 + 切换选中）

```bash
cd /Users/sangyu/develop/Pink_House
xcodebuild test -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:ItemManagerTests/MidsummerSpecResolverTests \
  -IDEPackageSupportDisableManifestSandbox=YES \
  -skipPackagePluginValidation -skipMacroValidation \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'
```

### 快照（版式人工核对）

`MidsummerSpecPanelSnapshotTests` 只渲染 `MidsummerSpecGroupsSection`（**不含 ScrollView**，
否则 `ImageRenderer` 只能截到空框），PNG 落在
`NSTemporaryDirectory()/midsummer_spec_snapshots/`。
四个场景：带缩略图并选中 / 无图占位 / 联动灰化 / 规格缺省提示。

### 交互验收（XCUITest）

```bash
xcodebuild test -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -resultBundlePath /tmp/ph_spec.xcresult \
  -only-testing:ItemManagerUITests/MidsummerSpecSelectionUITests \
  -IDEPackageSupportDisableManifestSandbox=YES \
  -skipPackagePluginValidation -skipMacroValidation \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'
```

| 用例 | 断言什么 |
|---|---|
| `testSelectSpecsThenInsert` | 详情页点「一键入库」弹出规格面板；默认已预选一套组合；改选 Sk白色 / L 后确认按钮标题跟着变；点两次加号数量为 3；确认后反馈里带齐「Sk白色 / L ×3」；面板收起 |
| `testItemWithoutSpecsStillInserts` | 无规格单品点「一键入库」弹出面板并显示「暂无规格可选」，不出现别的单品的规格选项，确认后可直接入库 |
| `testCardQuickInsertReportsChosenSpecs` | 卡片 ⊕ 仍是快速入库，但吐司必须带出实际使用的规格 |

### 访问性标识契约（改产品代码时同步改测试）

`spec-option-<groupID>-<optionID>` / `spec-quantity-plus` /
`spec-quantity-minus` / `spec-quantity-value` / `spec-confirm` / `spec-close` /
`spec-drawer-backdrop` / `spec-empty-hint` / `spec-linkage-hint-<groupID>` /
`midsummer-detail-quick-insert` / `midsummer-detail-open-editor`

> ⚠️ 「面板是否打开」请用叶子元素（`spec-confirm` / `spec-option-*`）判定，
> **不要**给整个面板挂容器级 identifier：实测容器标识会覆盖直接子元素自己的 identifier，
> 导致确认按钮的 `spec-confirm` 变成容器标识、测试找不到它。
> 同理，`spec-empty-hint` 这类挂在 `HStack` 上的标识要按「静态文案」兜一下
> （`staticTexts.matching(label CONTAINS …)`）。

## 七、待办（本轮未做，已与使用者确认或属后续）

- **投稿表单的规格字段**：创作者目前无法在 App 内录入规格组 / SKU / 规格图
- **CloudKit 规格读写**：`MidsummerCloudService` 需要能序列化 `specGroups` / `skus`
- **日牌商品详情页沿用同一面板**：`TimeHallCommerceItemDetailView` 目前仍是直接落库；
  组件（`MidsummerSpecDrawer` / `MidsummerSpecPanel`）已做成可复用，接过去只需提供
  `specGroups` / `skus` 数据源
- **「内搭奶白色 S1粉色」这类跨组组合图**：机制已支持（`MidsummerSKU.image` 优先级最高），
  等真实组合表填进来即可生效
