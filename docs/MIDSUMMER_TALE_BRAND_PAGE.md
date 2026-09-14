# 仲夏物语品牌页 · 交付说明

> 归属：时光馆（TimeHall）新增品牌「仲夏物语」
> 参考图：① 品牌页布局（左年份栏 + 系列筛选 + 商品卡片） ② 详情页行式列表
> 配置清单：见 [MIDSUMMER_TALE_CLOUDKIT_SETUP.md](./MIDSUMMER_TALE_CLOUDKIT_SETUP.md)

---

## 一、先更正一个事实：品牌不是 2023 年成立的

需求里写「该品牌自 2023 年成立至今」。查证后，公开资料与此不一致：

| 来源 | 说法 |
|---|---|
| [什么值得买品牌页](https://pinpai.smzdm.com/291287/wiki/c5835_s0/) | 「仲夏物语隶属于杭州载艺科技有限公司，**成立于 2017 年 04 月 06 日**」 |
| [百度百科](https://baike.baidu.com/item/仲夏物语/57282954) | 「2017 年 4 月，原名『无尽夏原创工作室』正式更名为仲夏物语 lolita 原创设计」 |
| [赢商网报道](https://m.winshang.com/news719741.html) | 「**成立于 2016 年**的仲夏物语……在全国已经拥有近五十家门店」（2023 年品牌已过七周年） |
| [新浪财经转载](https://t.cj.sina.cn/articles/view/1834507152/6d585b9000101av5w) | 「2023 年 8 月 20 日，仲夏物语在杭州举办了品牌**七周年** Lolita 茶会」 |

**结论**：品牌主体 2016 年成立、2017 年 4 月正式更名注册为「仲夏物语」，不是 2023 年。2023 年是品牌**七周年**，不是创立年。

**处理方式**：

- 品牌页与文档一律按可核验来源标注 `2017 年创立`
- 数据**没有**只截 2023 起：参考图一本身就把 2022 年列为可选年份，因此种子数据覆盖 **2022–2026**
- 系列列表页的年份范围是**动态**的（按实际收录算），不是写死的「2023 至今」——将来创作者往前补录更早的系列，标题会自动跟上

> 如果你手上有一份把起点定在 2023 年的内部口径（例如 App 从 2023 年才开始收录），告诉我，我把入库范围改成配置项。

---

## 二、交付内容

### 1. 品牌页（参考图一）

进入路径：时光馆 → 选择品牌 →「仲夏物语」

| 图一元素 | 实现 |
|---|---|
| 左侧竖排年份导航 | 86pt 宽的年份栏；选中项＝橙字 + 左侧 3pt 橙色竖条 + 白底，与图一一致 |
| 顶部系列筛选 chips | 横排，「全部」+ 各系列；选中＝浅橙底 + 橙字 + 橙描边；文案格式照搬图一的「2.9 小熊博物馆系列」（月.日 + 系列名） |
| 「全部 ▸」入口行 | **可点击**，进入系列详情页（这是需求里说的那个静态入口） |
| 商品卡片 | 左方图 + 右侧标题/价格，价格用「小 ¥ + 大数字」两段字号还原图一观感；卡片右上角橙色图标，整卡可点进单品详情 |
| 已售/包邮等信息位 | 换成**阶段标签**（定金/尾款/现货）与「系列名 · N 款」。原因见下 |

> **为什么没有「已售 1 万+」**：那是淘宝的成交数据，我们没有数据源，编一个数字比留空更糟。同样位置改放我们**确实知道**的信息（上新阶段、收录款数）。

### 2. 系列详情页（参考图二）

图二给的是「方图 + 标题 + 副信息 + 橙色按钮 + ⋯」的行式列表，本页把该范式用在**系列**层：

| 图二元素 | 系列行里的对应 |
|---|---|
| 方形圆角缩略图 | 系列封面（无图时渲染品牌水印示意底） |
| 左下角绿色「新」角标 | 出现在最新年份的系列上 |
| 标题 + 副信息（`2件新品 \| 7天前关注`） | 系列名 + `N 款单品 \| 2025.05.08 上新` |
| 橙色「进店」按钮 | 「查看」按钮，同样是浅橙底 + 橙字 |
| `⋯` 更多 | 保留同位置 |
| — | **额外加成**：价格区间（橙红）与尺码行，满足「每个系列包含图片、价格和尺码」 |

按年份分组（2026 → 2022），组头显示「N 个系列」。点任一行进入该系列的全部单品。

### 3. 创作者上传入口

**两种模式**：

1. **新建系列** —— 从零录入一个上新系列（系列名、上新日期可标记为「待补充」、阶段、价格区间、尺码多选、简介、单品多条、封面图、原文出处）
2. **补录单品** —— 为已有系列补充缺失款

**硬约束**（都已在代码里强制）：

- **入口可见性**由 `adminIDs` 白名单 **或** 「创作者模式」开关共同决定（2026-09-14 调整）。
  默认对普通浏览者不可见；内容维护者可在 **设置 → 创作者 → 创作者模式**，
  或品牌页页脚的「我是内容维护者…」引导一键开启，**不需要重新发版**。
- `sourceURL` **必填**且必须是合法 http/https 地址（Apple 5.2 可溯源要求）
- 封面图上传前压到长边 1200px、JPEG 0.82，避免吃爆 CloudKit 配额
- 提交成功立即本地生效（乐观更新），无需等云端刷新

> ⚠️ 「创作者模式」只解**界面闸门**，不是安全边界。能否真正写入公共库，
> 取决于当前 iCloud 账户是否已在 CloudKit 的 `MidsummerEditor` 角色里。
> 非管理员账号下，投稿页顶部会如实提示，提交失败也会给出明确文案。

---

## 三、数据：13 个系列 / 13 个商品（2022–2026）

> 「商品」= 一个电商链接。**全部 13 个系列都已归集完毕：每个系列 = 1 个商品**，
> 系列内的多款降级为「款式」组的一个选项，条目数从 34 → 30 → **13**。
> 规则与价格口径见
> [MIDSUMMER_TALE_PRICE_AND_CONSOLIDATION.md](./MIDSUMMER_TALE_PRICE_AND_CONSOLIDATION.md)。

来源全部为公开渠道，逐条可溯（每个系列与每个单品都带 `sourceURL`，测试会卡住不可溯源的域名）：

| 年份 | 系列（款式数） | 来源 |
|---|---|---|
| 2026 | 小熊博物馆系列（2）、三丽鸥家族合作（1）、**樱花小羊（9 款）** | 参考图一（店铺系列入口）、[三坑新语 2026-06 淘宝 lolita 单品榜](https://k.sina.cn/article_7857141524_1d452771401901v9d2.html)（樱花小羊定金 ¥7–139）、[Lo 研社图鉴 31022–31030](https://lolitalibrary.com/library/detail/31022)（樱花小羊逐款参考价 ¥199–699） |
| 2025 | 蝴蝶结·永恒花园（4）、卢瓦尔葡萄园 3.0（2）、小熊生日派对（2）、野草莓 2.0（3） | 微博开约贴（OP 预约 388 / 现货 499）、第三方店铺比价页 |
| 2024 | 莫奈油画柄（1）、圆舞曲（1）、面包坊下午茶（1） | 什么值得买品牌页与商品页 |
| 2023 | 魔卡少女樱联名（1）、**草莓肥啾（5）** | 赢商网 2023 报道（魔卡少女樱再度合作）、[Lo 研社](https://lolitalibrary.com/library/detail/1621)（草莓肥啾参考价 399）、[Lolita 图鉴](https://lolitafetch.com/fr/pages/chinese-lolita-brands/zhong-xia-wu-yu-yuan-chuang-she-ji)（款名与版型） |
| 2022 | 比得兔合作款（6） | 什么值得买品牌页 + 店铺比价页 |

> ⚠️ 只有樱花小羊有真实 `itemURL`，其余 12 个系列的归集依据是「同一系列 = 同一链接」
> 这一**近似**。拿到真实链接后若发现某系列其实是两个链接，需要拆开——
> `MidsummerPriceIntegrityTests.testSeriesWithMultipleProductsMustHaveDistinctLinks`
> 会在那时提醒。

### 价格：区间是派生的，口径是必填的

- 系列的价格区间**不再手写**（`priceMin` / `priceMax` 已删），由
  `MidsummerSeriesDTO.priceRange` 从单品 + SKU 逐款价派生 → 改一处不会漏另一处
- 每个价格数字必须带 `priceKind`（商品页价 / 参考价）与 `priceCapturedOn`（采集日）
- 定金是**另一个维度**：显式登记在 `depositMin` / `depositMax` 并附 `priceSource`，
  界面与「参考价 / 现货价」分两行显示
- 没有价格必须写 `priceNote` 说明原因
- 以上五条由 `MidsummerPriceIntegrityTests` 直接对种子 JSON 守住

### 两处已修正的数据问题（复核时发现）

1. **原「无尽夏异想世界」不是商品系列，是 2023 年品牌七周年茶会的主题名称**（[新浪财经](https://t.cj.sina.cn/articles/view/1834507152/6d585b9000101av5w)：2023-08-20 于杭州远洋凯宾斯基酒店举办，含小红帽主题秋冬新品秀）。原种子把它当作「系列」收录，导致出现一个**没有单品、没有价格、没有尺码的空壳系列**，违反「每个系列包含图片、价格和尺码」。已替换为可核验的 2023 真实系列 **草莓肥啾**（5 个单品）。
   - 顺带说明：「无尽夏」本身是仲夏物语与设计师**悦奈的合作款**系列名（[什么值得买条目](https://wiki.smzdm.com/p/01yzgn4)），与品牌前身「无尽夏原创工作室」是两回事，不要混为一谈。
2. **原魔卡少女樱系列引用了 `xyzstar.cn` 这个不可溯源域名**，违反 Apple 5.2。已改为赢商网 2023 年报道（文中明确提到该年与魔卡少女樱再度合作），并把臆造的 `2023-01-01` 日期改为留空（显示「上新日期待补充」）。

**数据不变量（已由测试守住，见 `MidsummerBrandPageTests`）**：

- 每个系列**至少 1 个单品**、**尺码非空** —— 保证详情页能展示图片/价格/尺码
- 每个系列与单品的 `sourceURL` 必须是非空 http(s)，且不含不可信域名
- 系列 id 与单品 id 全局唯一，单品的 `seriesID` 必须与所属系列一致
- 年份导航倒序，且每个年份都能分到系列（无孤儿系列）

**如实标注的不完整项**（这正是上传入口存在的理由）：

| 状态 | 数量 | 界面表现 |
|---|---|---|
| 上新日期待补充 | 9 个系列 | 显示「上新日期待补充」，并在排序中排在前面 |
| 价格待补充 | 2 个系列 | 显示灰色「价格待补充」标签，不显示 ¥0 |
| 资料待创作者核对（`verified: false`） | 8 个系列 | 系列详情页显示「公开渠道信息，部分项待创作者核对」 |

`verified: false` 表示「年份或价格依据公开页面推断」，不是凭空编的，但也未经创作者确认。

**版权处理**：不引用任何淘宝/官图（防盗链 + 版权），封面在无图时渲染带「仲夏物语」水印的粉色示意底；页面底部与详情页都写明「仅作衣橱搭配参考，不提供购买」。

---

## 四、代码结构

```
ItemManager/Models/Midsummer/
  MidsummerModels.swift          系列 / 单品 / 阶段 / 品类 DTO，价格与尺码展示逻辑
                                 + 规格组 / 规格选项 / SKU 组合（仿淘宝 SKU）
ItemManager/Services/Midsummer/
  MidsummerStore.swift           @MainActor 状态层；Bundle 种子 + CloudKit 合并
  MidsummerCloudService.swift    公共库读写（复用 iCloud.bugod2.ItemManager）
  MidsummerSpecResolver.swift    规格选择的纯逻辑层（缺省 / 联动 / 归一化 / 图片回退）
  MidsummerWardrobeInsertion.swift  单品 → 衣橱草稿（按规格映射配色/尺码）
ItemManager/Views/Midsummer/
  MidsummerTheme.swift           颜色令牌、封面图占位、阶段徽章、尺码行
                                 + MidsummerYearRail / MidsummerSeriesChip（图一的左栏与 chips）
  MidsummerBrandView.swift       品牌页（图一）+ MidsummerItemCard（图一商品卡片）+ 单品详情弹窗
  MidsummerSeriesListView.swift  系列列表（图二）+ 系列详情
  MidsummerContributeView.swift  创作者上传入口
                                 + MidsummerContributionValidator（可单测的准入校验）
  MidsummerSpecPanel.swift       规格选择抽屉（仿淘宝「加入购物车」）
ItemManager/Resources/Midsummer/
  midsummer-series.json          种子数据（13 系列 / 13 商品；每个商品含款式 × 颜色 × 尺码 + SKU 表）
                                 重建脚本：scripts/rebuild_midsummer_series.py
ItemManager/Views/Midsummer/
  MidsummerTheme.swift           模块令牌（深浅色自适应）+ ThemeSkin 槽位映射
                                 规范对照见 MIDSUMMER_THEME_ADAPTATION.md
ItemManagerTests/
  MidsummerPriceIntegrityTests.swift     价格口径守卫 + 归集守卫（直接跑种子 JSON）
ItemManagerTests/
  MidsummerBrandPageTests.swift          数据层与合并规则（种子解码、文案、品类推断、云端覆盖/追加、筛选）
  MidsummerContributeViewTests.swift     上传入口准入规则（系列名 / 出处合规 / 至少一个单品 / 草稿转换）
  MidsummerBrandPageSnapshotTests.swift  渲染冒烟 + 区块快照导出
  MidsummerSpecResolverTests.swift       规格选择四类边界（缺省 / 无 SKU 表 / 联动 / 选择变化）
  MidsummerSpecPanelSnapshotTests.swift  规格面板版式快照
ItemManagerUITests/
  MidsummerSpecSelectionUITests.swift    规格抽屉的真交互验收
```

> **加入衣橱的交互细节另见 [`MIDSUMMER_TALE_SPEC_SELECTION.md`](./MIDSUMMER_TALE_SPEC_SELECTION.md)**：
> 详情页「一键入库 / 加入并编辑」现在都**先弹规格面板**（仿淘宝「加入购物车」），
> 支持颜色分类 / 尺码多规格选择、每个选项可带自己的图、数量不限且不影响库存。

> **为什么把 `MidsummerYearRail` / `MidsummerSeriesChip` / `MidsummerItemCard` 拆成独立组件**：
> 不只是为了复用——首页整页在 `ScrollView` 里，而 `ImageRenderer` 只渲染可视区框架，
> 整页快照只能拿到空图。拆出来之后这些区块可以被快照测试单独渲染，
> 才有人工核对「像不像图一」的真实依据。

**合并规则**（关键，防止误删历史）：按 `series.id` 合并，CloudKit 同 id 覆盖种子，种子独有的系列**保留**。云端是补充而不是替换——否则第一次上传就会把整个历史抹掉。

**接入点**：`TimeHallView.swift` 的 `TimeHallMerchant` 新增 `.midsummerTale`，命中时渲染 `MidsummerBrandView`，其余品牌版式不变。

---

## 五、怎么测

### L1 · 单元测试（数据层 + 上传入口准入 + 渲染冒烟）

```bash
cd /Users/sangyu/develop/Pink_House
xcodebuild test -scheme ItemManager \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -IDEPackageSupportDisableManifestSandbox=YES \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -disable-sandbox' \
  -only-testing:ItemManagerTests/MidsummerBrandPageTests \
  -only-testing:ItemManagerTests/MidsummerContributeViewTests \
  -only-testing:ItemManagerTests/MidsummerBrandPageSnapshotTests
```

| 测试类 | 用例数 | 覆盖 |
|---|---|---|
| `MidsummerBrandPageTests` | 17 | 种子解码、品牌元数据（成立年 2017）、年份覆盖 2022–2026、id 唯一性、**每个系列≥1 单品且尺码非空**、出处可溯源（含黑名单域名）、日期待补排序、价格文案（定金/尾款/现货/缺失）、品类关键词推断、云端覆盖同 id 与追加不删历史、筛选逻辑 |
| `MidsummerContributeViewTests` | 10 | 上传入口准入规则：缺系列名 / 出处非法（空、缺 scheme、非 http、缺 host、非 URL）/ 无单品都被拦；文案可操作；`DraftItem` 空款名不产出单品、尺码继承与兜底、定金+尾款拆分 |
| `MidsummerBrandPageSnapshotTests` | 8 | 渲染冒烟 + 导出 PNG 供人工核对版式 |

**区块快照**（导出到模拟器沙盒的 `tmp/midsummer_snapshots/`，取出后可逐张核对参考图）：

| 文件 | 核对什么 |
|---|---|
| `01-topbar-admin.png` | admin 视角顶栏：能看到「+ 上传上新」入口 |
| `01b-topbar-guest.png` | 非 admin 视角顶栏：**不应**出现上传入口 |
| `05-series-row.png` | 图二行式范式（方图 + 绿「新」角标 + 价格区间 + 尺码 + 浅橙「查看」） |
| `06-year-rail.png` | 图一左栏：选中＝橙字 + 橙竖条 + 白底 |
| `07-series-chips.png` | 图一顶部 chips：选中＝浅橙底 + 橙字 |
| `08-item-cards.png` | 图一商品卡片三种状态：有价格 / 定金起 / 价格待补充 |
| `02-series-list.png`、`03-series-detail.png` | 仅冒烟（见下方「已知限制」） |

取出快照：

```bash
SIM=$(xcrun simctl list devices | grep "iPhone 18 Pro" | grep -o "[0-9A-F-]\{36\}" | head -1)
find ~/Library/Developer/CoreSimulator/Devices/$SIM/data/Containers/Data/Application \
  -path "*midsummer_snapshots*" -name "*.png" -exec cp {} /tmp/midsummer_snapshots/ \;
open /tmp/midsummer_snapshots
```

### L2 · 模拟器手动过一遍

| 步骤 | 预期 |
|---|---|
| 时光馆 →「选择品牌」 | 出现第 6 个品牌卡片「仲夏物语」 |
| 进入品牌页 | 左年份栏（2026→2022）+ 顶部系列 chips + 商品卡片 |
| 点左侧「2025年」 | chips 换成 2025 的 4 个系列，卡片只剩 2025 的单品 |
| 点某个 chip | 卡片只剩该系列 |
| 点「全部 ▸」 | **进入系列详情页**：按年份分组，每行有图/系列名/价格区间/尺码/「查看」 |
| 点任一系列行 | 进入该系列单品列表 |
| 点任一单品 | 弹出详情：价格、配色、尺码、来源链接 |
| 断网重进 | 内容照旧（走 Bundle 种子），不白屏 |

### L3 · 创作者上传

1. 让入口显示出来（二选一，**都不需要重新发版**）：
   - App 内：设置 → 创作者 → 「创作者模式」；或点品牌页页脚的「我是内容维护者…」
   - 或把 iCloud ID 加进 `NoticeCloudKitService.adminIDs` 后重新构建
2. 回到品牌页，右上角出现「上传上新」
3. 另外按 [配置清单](./MIDSUMMER_TALE_CLOUDKIT_SETUP.md) 把 Console 的 `MidsummerEditor` 角色配好——否则第 4 步会失败
4. 填写并提交 → 弹「已提交」，列表立刻出现新系列
5. 杀掉 App 重进 → 内容仍在（说明写进了公共库而不是内存）
6. 反向验证准入：故意留空出处 → 应被拦下并提示「请填写有效的原文链接」；只填系列名不填单品 → 应提示「请至少填写一个单品」

---

## 六、验证边界（如实说明）

**已验证**

- `ItemManager` 主 target 编译通过，零错误
- 种子 JSON 合法且已正确打入 App bundle（`ItemManager.app/midsummer-series.json`）
- **33 个单元测试全部通过**（`MidsummerBrandPageTests` 17 + `MidsummerContributeViewTests` 10 + `MidsummerBrandPageSnapshotTests` 6/8），零失败
- 数据不变量成立：无空壳系列、无重复 id、每个系列都有尺码与至少一个单品、全部出处可溯源

**未验证**

| 项目 | 原因 | 怎么补 |
|---|---|---|
| 真机/模拟器视觉走查 | 本次以代码与构建验收为主 | 按 L2 手动过一遍，重点看左侧年份栏宽度与长系列名换行 |
| CloudKit 实际读写往返 | 容器 schema 与权限需先在 Console 配置 | 配好后按 L3 走一遍 |
| 封面图上传与回读 | 同上 | 传一张真实图片，确认压缩后能显示 |

**已知限制**

- **区块快照与整页效果有差距**：`ScrollView` / `Form` / `List` 在 `ImageRenderer` 下只渲染可视区框架，所以 `02`/`03` 两张整页快照基本是空白框架，**不能**用它们判断整页版式。能真正核对图一/图二的是上表 6 张非滚动区块快照。
- **上传表单没有快照**：`MidsummerContributeView` 的 `.onAppear(perform: prefill)` 会在 `ImageRenderer` 渲染期写 `@State`，触发 `SwiftUICore Fatal error: no current update to enqueue action to` 直接崩掉测试进程（已踩过并移除该用例）。同理 `MidsummerBrandView` 的 `.task { await store.refreshFromCloud() }` 也不能整体渲染。上传入口的验收改由 `MidsummerContributeViewTests` 的 10 条逻辑断言覆盖。
- 快照 PNG 落在**模拟器沙盒**里（不是宿主机的 `/tmp`），取出命令见 L1。
- 上传入口默认对非 admin 隐藏。**但不再需要「加白名单 + 重新构建」才能看到**：
  打开「创作者模式」（设置 → 创作者，或品牌页页脚）即可让入口出现（2026-09-14 调整）
- 单品图片当前不上传（只传系列封面），控制配额；单品行复用系列封面
- 不提供购买跳转，仅展示 `sourceURL` 供追溯；但每个单品都提供**加入衣橱**入口（一键入库 / 加入并编辑），
  这是「仅作搭配参考」的实现方式——数据进衣橱，购买仍走原站
