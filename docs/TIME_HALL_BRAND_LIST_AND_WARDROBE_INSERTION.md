# 时光馆主页（图一品牌列表）与衣橱双形态交付说明

> 本轮交付时间：2026-09-14
> 参考图：`微信图片_20260914032045_2326_72.jpg`（关注店铺列表）
> 关联文档：[TIME_HALL_REBUILD_AND_COMMERCE_PLAN.md](./TIME_HALL_REBUILD_AND_COMMERCE_PLAN.md)

---

## 一、参考图一 → 实现对应表

图一的范式是**「关注店铺列表」**，与原来的「左右滑动轮播选品牌」完全不同。
本轮**彻底替换**了主页渲染（旧轮播实现保留在文件里但不再被主页使用，便于对照回退）。

| 图一元素 | 实现 | 代码位置 |
|---|---|---|
| 方形缩略图 | 60×60、圆角 14、描边 4% 黑 | `TimeHallBrandThumbnail` |
| 缩略图左下绿「新」角标 | 圆角 4、白字、10pt bold，**仅有可核验上新时出现** | 同上 |
| 品牌名 | 17pt semibold、近黑 `#1A1A1A`、最多两行 | `TimeHallBrandListRow` |
| 绿字主指标 | 13pt medium、`#3DC759`；文案「N件新品」 | 同上 |
| 竖线分隔 | 1×10、`#E6E6E8` | 同上 |
| 灰字时间 | 13pt、`#99999E`；文案「N天前加入」 | 同上 |
| 橙色「进店」 | 浅橙底 `#FFF0E6` + 橙字 `#FF6B35`、圆角 6、15pt semibold | `TimeHallBrandEnterButton` |
| 灰色「⋯」 | 17pt semibold、`#C7C7CC`，展开菜单（进入品牌档案／访问官网） | `TimeHallBrandListRow` |
| 上下滑动浏览 | `ScrollView + LazyVStack`（刻意不用 `List`，便于快照核对） | `TimeHallBrandListHome` |
| 搜索（图一未截到，按要求新增） | 顶部圆角搜索框，按品牌名／副标题／渠道匹配，带清除按钮 | 同上 |
| 筛选（同上） | 胶囊条：全部／有上新／国牌／日牌，与搜索为**交集**关系 | `TimeHallBrandFilterChip` |

配色令牌集中在 `TimeHallBrandListTheme`，视图里不散落硬编码色值。

---

## 二、数据诚实性：关于「N 件新品」

这是本轮**唯一需要额外说明**的一处，因为它涉及「能不能编」的边界。

**事实**：现有 catalog 只有 `listingStatus`（`in_stock` / `sold_out`）和单一批次的
`observedAt`（日牌为 2026-08-11、Pink House 为 2026-08-01）。**这两项都推不出「新品」**。

因此本轮的规则是：

1. `newItemCount > 0` 必须同时给出来源说明 `newItemCountSource`，由单测强制
   （`testNewItemCountMustCarryVerifiableSource`）——**不允许出现没有出处的上新数**
2. 没有可核验上新数据的品牌，主指标**退化为真实的在售件数**（`N件在售`），
   且**不出现**绿色「新」角标——而不是假装有新品
3. 图一本身也不是每行都有「N件新品」（其第 3 行只有关注时间），所以这个降级不违背参考图

当前种子里唯一填了新品数的是**仲夏物语**，口径可核验：

> 仲夏物语种子数据 2026 年 3 个上新系列（小熊博物馆系列、三丽鸥家族合作、樱花小羊）合计 8 件单品

「N 天前加入」的时间取 `addedAt`，**一律等于该品牌 catalog 的 `observedAt`**（抓取观测日），
是可核验的真实日期，而不是为了凑出好看的「7 天前／半年前」而臆造。
用户真实进入过某个品牌后，`TimeHallBrandFollowStore` 会记下真实时间并**优先使用**
（且重复进入不刷新，语义始终是「加入时间」）。

---

## 三、本轮改动清单

### 新增文件

| 文件 | 作用 |
|---|---|
| `ItemManager/Resources/TimeHall/timehall-brand-meta.json` | 品牌列表页元数据种子（6 个品牌） |
| `ItemManager/Services/TimeHall/TimeHallBrandListing.swift` | 展示模型、相对时间计算、搜索／筛选纯函数、关注时间存取 |
| `ItemManager/Views/TimeHall/Rebuild/TimeHallBrandListHome.swift` | 图一范式主页（标题 + 搜索 + 筛选 + 列表行 + 缩略图 + 按钮） |
| `ItemManager/Views/TimeHall/Rebuild/TimeHallBrandListingsBuilder.swift` | 元数据 + 在售统计 → 展示模型；含在售件数缓存 |
| `ItemManager/Services/TimeHall/TimeHallWardrobeInsertion.swift` | 衣橱两种加入形态的枚举与「一键入库」落库实现 |
| `ItemManager/Views/TimeHall/Rebuild/TimeHallWardrobeInsertButtons.swift` | 双形态按钮 + 卡片上的紧凑入口 |
| `ItemManagerTests/TimeHallBrandListingTests.swift` | 19 个用例 |
| `ItemManagerTests/TimeHallBrandListSnapshotTests.swift` | 5 张区块快照 |

### 修改文件

| 文件 | 改动 |
|---|---|
| `TimeHallView.swift` | `TimeHallMerchant` 由 `private` 提升为 internal；主页分支由 `merchantSelection` 改为 `brandListHome`；新增 `enterBrand(id:)` / `openBrandWebsite(id:)`；`TimeHallWardrobeDraftBuilder` 提升为 internal 供一键入库复用；两个详情页的「加入衣橱」替换为双形态按钮；商品卡片左上角新增一键入库图标 |

### 隔离策略（踩过的编译坑）

工程是 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，而 `String.appLocalized` 依赖
`LanguageManager.shared`（MainActor 隔离）。因此 `TimeHallBrandListing.swift` 做了切分：

- 纯逻辑（匹配、筛选、相对时间**计算**）标 `nonisolated`，可直接单测
- 含本地化文案的展示属性放在文件末尾的 `@MainActor extension` 里

否则 `nonisolated` 上下文调用 `appLocalized` 会直接编译失败。

---

## 四、衣橱：两种形态并行保留

按要求**两种都实现、都出现**，不预设默认值。

| 形态 | 行为 | 入口 |
|---|---|---|
| **A 一键入库** | 不打开编辑页，直接把草稿落成 `Clothing` 写入 SwiftData，留在当前页并就地提示 | 商品卡片左上角图标；详情页左按钮 |
| **B 加入并编辑** | 复用既有 `TabNavigationManager.presentWardrobeCreation(with:)`，跳衣橱编辑页并预填 | 详情页右按钮 |

视觉权重刻意做成对等（A 实心、B 描边），下方有一行小字解释两者差别。

**关键一致性保证**：形态 A 走 `TimeHallWardrobeDraftBuilder.makeDraft(...)`，
**与形态 B 完全同一套字段映射**，所以两种形态入库的内容不会走偏。
`TimeHallCommerceItemDetailView` 里的图片预取也抽成了共用的 `makeDraftWithRemoteImage()`。

落库失败时会 `modelContext.delete(clothing)` 回滚，避免留下只有内存态的幽灵条目。

---

## 五、怎么验

```bash
cd /Users/sangyu/develop/Pink_House
xcodebuild test -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:ItemManagerTests/TimeHallBrandListingTests \
  -only-testing:ItemManagerTests/TimeHallBrandListSnapshotTests \
  -IDEPackageSupportDisableManifestSandbox=YES \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' \
  ENABLE_USER_SCRIPT_SANDBOXING=NO
```

快照 PNG 落在**模拟器沙盒**的 `tmp/timehall_brand_snapshots/`，取出方式见 skill
`pink-house-xcodebuild-acceptance`（注意 macOS 是 BSD `find`，`-newermt` 不吃相对时间）。

| 快照 | 核对什么 |
|---|---|
| `01-brand-row-new` | 有上新：绿字「8件新品」+ 缩略图左下绿「新」角标 |
| `02-brand-row-stock` | 无上新：灰字「N件在售」，且**不出现**绿「新」角标 |
| `03-brand-rows` | 6 个品牌叠成一列的整列观感（最接近图一） |
| `04-filter-chips` | 筛选胶囊选中态 |
| `05-wardrobe-insert-modes` | 双形态按钮并列、无默认偏向 |

模拟器手动过一遍：

| 步骤 | 预期 |
|---|---|
| 进入时光馆（未选品牌） | 出现图一形态的品牌列表，不是左右滑动轮播 |
| 上下滑动 | 6 个品牌行可滚动 |
| 搜索「仲夏」 | 只剩仲夏物语；搜索「lolita」等词可命中副标题 |
| 筛选「有上新」 | 只剩仲夏物语（唯一有可核验上新数据的品牌） |
| 筛选「国牌」/「日牌」 | 分别只剩仲夏物语 / 其余五个 |
| 点「进店」 | 进入该品牌档案（仲夏物语进独立品牌页） |
| 点「⋯」 | 菜单：进入品牌档案 / 访问官网 |
| 商品卡片左上角图标 | 一点即入库，图标变对勾；去衣橱能看到该条目 |
| 详情页两个按钮 | 左「一键入库」留在原页并提示；右「加入并编辑」跳衣橱编辑页且已预填 |

---

## 六、验证边界（如实说明）

**已验证**

- 主 target `BUILD SUCCEEDED`
- 新增 19 个数据层用例 + 既有 67 个时光馆用例：`Executed 86 tests, with 0 failures`，`TEST SUCCEEDED`
- 5 张区块快照可导出（版式核对见上表）

**未验证**

| 项目 | 原因 | 怎么补 |
|---|---|---|
| 真机／模拟器视觉逐项对照 | 本轮以代码、单测与区块快照为主 | 按上表手动过一遍，重点看长品牌名换行与行距 |
| 一键入库在真实 iCloud 同步下的表现 | 需要已登录 iCloud 的账号与容器 | 登录后加一件、杀掉重进，确认云端也有 |

**已知限制**

- 旧轮播选品牌的实现（`merchantSelection` 及其配套函数）**仍在 `TimeHallView.swift` 里**，
  只是不再作为主页渲染。若要彻底删除，需要先确认无其他引用（目前仅主页分支使用）
- 新品数依赖元数据维护：日牌当前一律显示「N件在售」。要真正显示「N件新品」，
  需要接一条上新抓取管道或创作者上传入口（与仲夏物语的投稿入口同理）
- 商品卡片的快捷入口只做形态 A；形态 B 在详情页——避免卡片上按钮过密
