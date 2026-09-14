# 加入衣橱入口失联 + 创作者上传入口 · 排查与修复

> 交付时间：2026-09-14
> 触发反馈：「一键入库 / 加入并编辑看不到入口」「点购物袋加号后是空白」「缺少创作者上传入口」
> 关联文档：[TIME_HALL_BRAND_LIST_AND_WARDROBE_INSERTION.md](./TIME_HALL_BRAND_LIST_AND_WARDROBE_INSERTION.md)、[MIDSUMMER_TALE_CLOUDKIT_SETUP.md](./MIDSUMMER_TALE_CLOUDKIT_SETUP.md)

---

## 一、排查结论

反馈里的三件事，其实是**三个独立成因**，不是同一个 bug。

### 1. 「一键入库 / 加入并编辑」看不到

三处入口，各自不同的问题：

| 位置 | 实际状况 | 成因 |
|---|---|---|
| Pink House（`pinkHouseHall`） | 商品卡是 `TimeHallCatalogItemCard`，**从未接入库入口** | 功能缺口，不是显示问题 |
| 其余 4 个日牌（`curatedBrandHall`） | `TimeHallCommerceItemCard` **有**按钮，但视觉上等于隐形 | 图标是「白色 + `.ultraThinMaterial`」，浅色模式下压在浅色商品图上对比度趋近 0 |
| 仲夏物语 | 独立品牌页，**整页没有接入衣橱** | 功能缺口 |

还有一条连带的：详情页里的「加入并编辑」要**先能打开详情页**才看得到，而
`TimeHallCommerceItemCard` / `TimeHallCatalogItemCard` 当时是
「外层 `Button` 里再嵌两个 `Button`」——SwiftUI 里嵌套 `Button` 是未定义行为，
内层会吃掉点击，整卡点击变得不可靠，**表现就是点了卡片没反应，详情页根本打不开**。

截图证据（修复前）：`04-仲夏物语品牌页` 顶栏只有返回键，商品行右侧只有一个橙色袋子图标。

### 2. 点「购物袋加号」呈现空白

那个橙色 `bag.badge.plus` **不是按钮，只是一个装饰性 `Image`**
（`MidsummerBrandView.swift` 商品卡片最右）。点击穿透到整行，触发 `onTap` 打开
`MidsummerItemDetailSheet`——而那个弹窗当时只有商品信息 + 「查看原文出处」+「完成」，
**没有任何加入衣橱的操作**。使用者预期它是「加购」，看到的就是一个什么都不能做的空壳页。

另有一处隐患：弹窗内容是 `if let series = detailSeries { ... }`，
条件不满足时会呈现一个**真正的空白 sheet**。正常路径下 `detailSeries` 与 `detailItem`
同时赋值不会错位，但这属于「出错即白屏」的写法，本轮一并加了兜底。

### 3. 「缺少创作者上传入口」

入口**已经存在**（`MidsummerTopBar` 的「上传上新」按钮 + 完整的 `MidsummerContributeView`），
但它被 `MidsummerStore.canContribute` 挡住，而该值来自
`NoticeCloudKitService.isAdmin()`——只认硬编码的**单个** iCloud `recordName`：

```swift
private let adminIDs: [String] = [
    "_819804d902cb79c2d6e4bf736ed6c50b",  // 主管理员
]
```

判定依赖 `CKContainer.userRecordID()`；**模拟器、未登录 iCloud、或换了 Apple ID 的设备
一律取不到**，于是 `canContribute` 恒为 `false`，入口永远不出现。
这在 `docs/MIDSUMMER_TALE_CLOUDKIT_SETUP.md:17` 里被写成「符合预期」——
对普通用户是符合预期，但**对内容维护者本人也生效**，这才是问题。

另外，时光馆 5 个日牌**没有 App 内上传通道**（内容由 Mac 侧发布流水线灌入，
见 `TIME_HALL_ACCEPTANCE_GUIDE.md`）。本轮按确认结论**暂不处理**。

---

## 二、修复清单

### A. 视觉可见性：把「隐形按钮」改成实底

`TimeHallCommerceItemCard`、`TimeHallCatalogItemCard` 的收藏/入库图标，
以及 `MidsummerItemCard` 的袋子图标，统一换成
**实色圆底 + 白色图标 + 细白描边 + 投影**：

```swift
.foregroundStyle(.white)
.padding(8)
.background(Color.pink, in: Circle())                  // 原：.ultraThinMaterial
.overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 1) }
.shadow(color: .black.opacity(0.22), radius: 3, y: 1)
```

### B. 点击语义：拆掉嵌套 Button

三张卡片统一从

```swift
Button(action: onTap) { ... 内层 Button ... }   // ❌ 未定义行为
```

改为

```swift
VStack { ... 内层 Button ... }
  .contentShape(Rectangle())
  .onTapGesture(perform: onTap)                 // ✅ 整卡可点，内层按钮照常工作
```

### C. 仲夏物语接入衣橱（两种形态）

新增 `ItemManager/Services/Midsummer/MidsummerWardrobeInsertion.swift`：

- `MidsummerWardrobeDraftBuilder.makeDraft(for:series:brandName:modelContext:)`
  —— `MidsummerItemDTO` → `ClothingEditDraft` 的字段映射。
  价格是**人民币**，所以落 `originalPrice`(CNY) 与 `deposit`，不走日牌的 JPY 字段。
- `MidsummerWardrobeInserter.quickInsert(...)` 落库**复用** `TimeHallWardrobeQuickInserter`，
  保证两条路径的写库逻辑（含失败回滚）完全一致。
- `MidsummerWardrobeInserter.openEditor(...)` 走既有 `TabNavigationManager.presentWardrobeCreation`。

落点：

| 页面 | 入口 |
|---|---|
| 品牌首页商品卡 | 右侧橙色按钮（形态 A 一键入库），成功后按钮变对勾 + 顶部浮出一条「已加入衣橱」 |
| 单品详情弹窗 | 「一键入库」「加入并编辑」双形态并列（复用 `TimeHallWardrobeInsertButtons`） |
| 系列详情页商品行 | 右侧图标按钮（形态 A），同样带就地反馈 |

抽出了共用组件 `MidsummerWardrobeIconButton`——以前那个袋子图标在**每个**列表页各画一遍，
现在收敛成一处。

### D. 创作者模式（本轮补的入口）

新增 `ItemManager/Services/CreatorMode.swift`：一个由 `UserDefaults` 支撑的开关，
把**「界面是否显示入口」**与**「CloudKit 是否真的允许写入」**解耦。

```swift
// MidsummerStore
var canContribute: Bool { isAdminUser || CreatorMode.isEnabledInDefaults() }
```

- 存档 key：`creator_mode.enabled.v1`（**不要改**，改了会丢使用者已设定的状态）
- 默认**关闭**：避免普通浏览者误入投稿页
- 两个开启入口：
  1. 设置 → 创作者 → 「创作者模式」开关（`settings-creator-mode-toggle`）
  2. 仲夏物语品牌页**页脚**的「我是内容维护者，开启创作者模式以补充缺项」
     （`midsummer-enable-creator-mode`）——只在页脚留设置入口等于让人自己猜，所以两处都给

**这不是安全边界**。真正的写入权限在 CloudKit Console 的 Security Roles。
所以投稿页在非管理员账号下会**如实提示**「当前 iCloud 账户不在创作者名单中」，
提交失败也会给明确文案，而不是让使用者填完一整页才吃到莫名其妙的错误。

---

## 三、怎么验

### 单元测试

```bash
cd /Users/sangyu/develop/Pink_House
xcodebuild test -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:ItemManagerTests \
  -IDEPackageSupportDisableManifestSandbox=YES \
  -skipPackagePluginValidation -skipMacroValidation \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'
```

### 交互验收（XCUITest）

```bash
xcodebuild test -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -resultBundlePath /tmp/ph_ui.xcresult \
  -only-testing:ItemManagerUITests/TimeHallEntryExplorationUITests \
  -IDEPackageSupportDisableManifestSandbox=YES \
  -skipPackagePluginValidation -skipMacroValidation \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'

# 取出截图（Xcode 27 的写法）
xcrun xcresulttool export attachments --path /tmp/ph_ui.xcresult --output-path /tmp/ph_ui_attach
```

用例与断言：

| 用例 | 断言什么 |
|---|---|
| `testA_BrandListHome` | 品牌列表出现「我的品牌 / 6个品牌 / 全部 / 有上新 / 国牌 / 日牌」；搜「仲夏」只命中仲夏物语 |
| `testB_MidsummerWardrobeEntries` | 默认无「上传上新」；商品行有「一键入库」；**点卡片能打开详情**（嵌套 Button 已修）；详情里两种形态都在；点卡片入库后出现「已加入衣橱」 |
| `testC_DedicatedBrandCommerceQuickInsert` | 日牌档案页下滚后能看到并点到商品卡的「一键入库」（要求元素**完整可见**，不只是 `isHittable`），且入库后出现就地反馈 |
| `testD_CreatorContributionEntry` | 页脚有可见可点的开启引导 → 开启后顶栏出现「上传上新」→ 点击真的打开投稿页 → 非管理员账号下投稿页显示权限提示，且表单含必填「原文出处」 |

> 访问性标识是测试与产品代码之间的契约。改产品文案时同步改测试：
> `进入品牌档案` / `更多操作` / `一键入库` / `加入并编辑` /
> `midsummer-enable-creator-mode` / `settings-creator-mode-toggle`。

---

## 四、验证边界（如实说明）

| 项目 | 状态 |
|---|---|
| 主 target 编译 | 已验证 `BUILD SUCCEEDED` |
| 单元测试回归 | 本轮相关 7 个测试类全绿（`Executed 114 tests, 0 failures`） |
| XCUITest 交互链路 | **4/4 通过**（`Executed 4 tests, 0 failures`，iPhone 18 Pro 模拟器） |
| 真机 + 已登录 iCloud 下的真实写入 | **未验证**——需要设备登录白名单内的 Apple ID，并已在 CloudKit Console 配好 `MidsummerEditor` 角色 |
| 5 个日牌的上传通道 | **未做**（按确认结论留到后续） |
| 尺码表 / 价格表的图片人工录入 | **未做**（同上） |

---

## 五、本轮结果

**主 target 编译**：`BUILD SUCCEEDED`
**交互验收**：`Executed 4 tests, with 0 failures` · `** TEST SUCCEEDED **`（220.6s，iPhone 18 Pro，Xcode 27.0 / build 27A266a）

```bash
xcodebuild test -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -resultBundlePath /tmp/ph_ui6.xcresult \
  -only-testing:ItemManagerUITests/TimeHallEntryExplorationUITests \
  -IDEPackageSupportDisableManifestSandbox=YES \
  -skipPackagePluginValidation -skipMacroValidation \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox'
```

### 逐条对照「用户提的三个问题」

| 用户原话 | 实测结论 | 证据 |
|---|---|---|
| 「一键入库 / 加入并编辑」看不到入口 | **已修复**。仲夏物语商品行右侧加号是真按钮（橙色实心圆 + 白加号）；单品详情页同时有实心的「一键入库」和描边的「加入并编辑」两种形态 | `B1`、`B2` |
| 点加号后空白 | **已修复**。点加号不再穿透到详情页；点卡片能正常打开详情（嵌套 Button 已拆）；详情 sheet 加了 `series` 兜底，取不到数据也不会白屏 | `B2` |
| 缺少创作者上传入口 | **已补上**。默认关闭时页脚有「我是内容维护者，开启创作者模式以补充缺项」；开启后顶栏出现「上传上新」，点开是真投稿页 | `D1` → `D4` |

### 入库链路实测（就地反馈可见）

| 场景 | 结果 | 证据 |
|---|---|---|
| 仲夏物语商品行「一键入库」 | 行内加号 → 橙色对勾，顶部浮出「已加入衣橱：樱花小羊 SK」 | `B3` |
| 日牌（Angelic Pretty）商品卡「一键入库」 | 卡片左上角加号 → 对勾，正下方浮出「已加入衣橱」胶囊 | `C2` |

### 创作者链路实测

`D1`（页脚引导）→ `D2`（确认弹窗）→ `D3`（顶栏出现「上传上新」）→ `D4`（投稿页，含「当前 iCloud 账户不在创作者名单中」权限提示）→ `D5`（表单下半部分，含必填「原文出处」）

### 本轮踩到的两个新坑（都已写进验收规则）

1. **`isHittable` 不足以判定「点得到」。**
   实测屏底最后一个卡片的「一键入库」frame 为 `y=855.5, h=32.7`，而窗口只有 874pt 高——
   `isHittable` 照样返回 `true`，但中心点 y≈872 已压在悬浮 dock / 系统手势区上，tap 下去毫无反应。
   这会把「测试挑错目标」误报成「功能坏了」。**判定标准要加上「元素完整落在可见区内」**
   （本工程底部有悬浮 dock，取 `maxY <= 窗口高 - 140`）。
2. **同一页面里「点了没反应」有两种截然不同的原因，断言必须能区分。**
   把待点元素的 `frame` / `isHittable` / 同名元素数量当附件留档，并把结局拆成
   「出现成功反馈」/「出现失败反馈」/「两者都没有」三条分支，否则只能得到一句含糊的
   「没有出现已加入衣橱」，无法判断是点没中还是写库失败。
3. **顺手修掉一处真实缺陷**：卡片入库失败原本只写 `AppLogger`，界面上毫无变化——
   使用者的观感就是「点了没反应」。现已补上橙色「加入失败，请重试」胶囊，
   失败与成功一样显眼。

### 截图归档

`output/timehall_entry_fix_shots/verified/`（A1 / B1–B3 / C1–C2 / D1–D5）。
修复前的对照图在 `output/timehall_entry_fix_shots/before/`。

