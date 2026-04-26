# Pink_House Android 复刻 Backlog

> 跨 session 进度看板。规范见 [PORT_HARNESS.md](PORT_HARNESS.md) §八。
> 新 session 接手前必读：本文 + PORT_HARNESS.md + 最近 5 个 commit。

---

## In Progress

无 — BATCH-M3-05 已验证；下一批建议进入 M4-01 Daily CheckIn 首屏。

---

## Ready

按优先级倒序，下回合从顶端取。

UX 优先路线：先把 `衣橱核心功能 → 数据查询 → 数据统计` 做扎实（用户最高频、最高决策价值），再补每日留存入口（签到、日历、通知），随后继续 `House / 宠物 / 小世界` 体验，最后推进财富/VIP/拼豆/OOTD 等低频或商业模块。

### 阶段 ARCH 已收尾 ✅（4 批全过）

### 阶段 CLEANUP（pre-existing tech debt，可在 ARCH 之后任意穿插）

- [ ] **BATCH-CLEANUP-01** AssetImage 占位渐变迁出硬编码
  - SCOPE: 2 文件 — `core/ui/PinkHouseDesignTokens.kt` + `core/ui/PinkHouseComponents.kt`
  - 把 `Color(0xFFF7F2F4)` / `Color(0xFFEFE8EC)` 提取到 token，遵循 R4 单一真源

### 阶段 WARDROBE-DATA（衣橱核心查询 / 统计优先）已阶段性收尾 ✅

### 阶段 M3（宠物 + 小世界 F-11 ~ F-25）

阶段 M3 当前 Ready 已清空；后续热区坐标精调可作为 polish 批次再加入。

### 阶段 M4（签到/日历/通知 F-26 ~ F-29、F-36 ~ F-38）

- [ ] **BATCH-M4-01** CheckInRoute（每日签到 F-26）
  - UPSTREAM: `ItemManager/Views/CheckIn/DailyCheckInView.swift` (1205 LOC)
  - F5 触发：超 1500 LOC 的话拆首屏 + 子区两批

- [ ] **BATCH-M4-02** CalendarRoute（梦裙日历 F-28）
  - UPSTREAM: `ItemManager/Views/Calendar/DreamDressCalendarView.swift` (918 LOC)

- [ ] **BATCH-M4-03** NoticeCenterRoute（通知中心 F-36）
  - 数据：本地表 `local_notification`，schema 升级走 Migration

### 阶段 M5（财富 + 拼豆 + OOTD）

- [ ] **BATCH-M5-01** WealthRoute 主页（F-30）
  - UPSTREAM: `ItemManager/Views/Wealth/WealthView.swift` (394 LOC)

- [ ] **BATCH-M5-02** Wealth 金币掉落动画（F-31）
  - 必须用 Compose 粒子，PRD 禁物理引擎

- [ ] **BATCH-M5-03** PerlerBeads 拼豆图案列表（F-39）
- [ ] **BATCH-M5-04** PerlerBeads 编辑器（F-40 / F-41）
- [ ] **BATCH-M5-05** OOTD 列表 + 编辑器（F-50 ~ F-53）

### 阶段 M6（VIP + IAP）

- [ ] **BATCH-M6-01** VipCenterRoute 视觉（F-32）— 仅 UI，支付下批
- [ ] **BATCH-M6-02** 微信/支付宝 SDK 接入决策与单批 gradle 改动
- [ ] **BATCH-M6-03** 喵币充值页（F-33）
- [ ] **BATCH-M6-04** VIP 开通 + 试用（F-34、F-54）

### 阶段 M7（备份/设置/分享/引导）

- [ ] **BATCH-M7-01** 数据备份导入导出（F-42 / F-43）
- [ ] **BATCH-M7-02** 设置页主体（F-44 ~ F-46）
- [ ] **BATCH-M7-03** 分享卡片（F-47 / F-48）
- [ ] **BATCH-M7-04** 新手引导（F-49）

---

## Blocked

- [ ] **BATCH-M5-01** WealthRoute — blocker: 缺 `mcoin_*.webp` / 纸币 / 金条贴图
- [ ] **BATCH-M6-02** 微信/支付宝 SDK — blocker: 决策（接入时机、商户号、合规）
- [ ] **BATCH-WEATHER-01** F-55 天气集成 — blocker: 和风 API key 申请

---

## Done

最近完成的在顶。每条带 commit hash + 链接到详细记录。

- [x] **BATCH-M3-05** SmallWorld 热点交互（点击场景元素） — `SmallWorldRoute.kt` 在小世界主图上叠加响应式热区标签，按 `日常 / 洛可可` 风格分别提供 `少女衣橱`、`萌宠对话`、`心愿尾款`、`马上来财`、`梦裙日历`、`穿搭手帐` 等入口；热区可跳衣橱、心愿尾款、萌宠对话或 House 内已有目的地。assembleDebug 通过；红线 grep 无命中；装机验证可见热区标签，点主图 `心愿尾款` 可进入心愿尾款页。详见 [android_migration_smallworld.md](android_migration_smallworld.md)。
- [x] **BATCH-M3-04** SmallWorld 主图 + 风格切换（日常/洛可可） — `SmallWorldRoute.kt` 为 `SmallWorldDestination.SmallWorld` 增加专用主图舞台，复用已有 `small_world_bg_normal.png` / `small_world_rococo_1.png` 资产，随顶部 `日常 / 洛可可` 分段切换主图与说明，保留 `少女衣橱`、`萌宠对话` 与 `热区待接入` 软圆入口。assembleDebug 通过；红线 grep 无命中；装机验证 House 小世界页可见 `日常小世界`，切到 `洛可可` 后可见 `洛可可小世界`。详见 [android_migration_smallworld.md](android_migration_smallworld.md)。
- [x] **BATCH-WARDROBE-DATA-08** 筛选 Sheet 候选值 Chips — `WardrobeHomeViewModel.kt` 新增 `WardrobeFilterSuggestions`，从全量衣橱数据提取品牌/类型/颜色/状态候选并按频次取前 8；`WardrobeRoute.kt` 在筛选 Sheet 对应输入框下方展示候选 Chips，点按即可填入草稿字段并高亮。assembleDebug 通过；红线 grep 无命中；装机验证 `筛选 → 类型候选 → 裙装 → 应用筛选` 后首页显示 `当前结果统计` 与 `类型：裙装`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-DATA-07** 当前查询/筛选条件 Chips + 单项移除 — `WardrobeHomeViewModel.kt` 新增 `WardrobeFilterChipKind`、`clearSearchQuery()` 与 `clearFilterChip(kind)`；`WardrobeRoute.kt` 在 `当前结果统计` 下方展示活跃搜索/筛选条件 Chips，支持点单个 Chip 移除。assembleDebug 通过；红线 grep 无命中；装机验证品牌筛选 `Baby` 应用后显示 `当前条件（点按单项移除）` 与 `品牌：Baby`，点按 Chip 后回到 `衣橱总览`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-DATA-06** 统计明细均价 / 占比条 — `WardrobeHomeViewModel.kt` 为统计分组桶新增 `averageValue` 与 `valueShare`，按当前统计口径计算件均价与价值占比；`WardrobeRoute.kt` 将详细统计行升级为标题/金额、件款+均价、软圆粉色占比条三层结构，继续保留点击反向筛选。assembleDebug 通过；红线 grep 无命中；装机验证 `少女衣橱 → 详细统计` 中可见 `均价 ¥1314.50`、`占比 86%`、`均价 ¥259.00` 与 `占比 8%`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-DATA-05** 统计明细项一键反向筛选 — `WardrobeHomeViewModel.kt` 新增统计分组反向筛选映射，支持品牌/类型/颜色/状态与尾款状态生成对应 `WardrobeFilterState`；`WardrobeRoute.kt` 让详细统计分组行可点击，关闭 Sheet 后回到 `当前结果统计`，并补充现货/已拥有筛选状态。assembleDebug 通过；红线 grep 无命中；装机验证点击 `详细统计 → 未填写品牌` 后首页显示 `当前结果统计`、`筛选 1 项`、`命中 2/4 款`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-UI-07** 筛选 Sheet / 查询条件面板软圆还原 — `WardrobeRoute.kt` 将筛选 Sheet 内容区改为轻粉底，筛选字段归入 `筛选条件` 软玻璃分组，快捷无值条件与 `只看心愿尾款` 改为 `SoftSearchPill`，底部 `清空 / 取消 / 应用筛选` 改为固定软圆操作条；保留原筛选逻辑与统计联动。assembleDebug 通过；红线 grep 无命中；装机验证可见 `筛选条件`、`快捷条件`、`无品牌`、`无标签`、`无小物`、`只看心愿尾款` 与 `应用筛选`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-UI-06** 创建/编辑表单软圆还原 — `WardrobeRoute.kt` 将新增/编辑衣物 Sheet 内容区改为轻粉底，`FormSection` 复用软玻璃面板，`DraftTextField` 从 Material `OutlinedTextField` 改为自定义 `BasicTextField` 软圆输入块，日期入口改为自定义圆角日期行，图片导入按钮与测试素材 Chip 改为粉色软圆组件，心愿尾款开关包入柔和白底容器。assembleDebug 通过；红线 grep 无命中；装机验证可见 `手动创建`、`裙装信息`、`相册`、`测试图片`、软圆输入框、`价格信息`、`购买日期`、`加入心愿尾款` 与 `备注`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-UI-05** 衣物详情 Sheet / 信息行软圆还原 — `WardrobeRoute.kt` 对照 iOS 详情页，把 Android 详情 Sheet 内容区改为轻粉底 + 软玻璃卡：图片外框、名称/品牌/价格摘要、`裙装信息`、`价格信息`、`备注` 与 `移入回收站` 均使用自定义圆角容器和轻描边。assembleDebug 通过；红线 grep 无命中；装机打开 `奶油白半身裙` 详情并滚动验证可见 `裙装信息`、`价格信息`、`备注`、`移入回收站`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-UI-04** 衣橱顶部操作栏 / 分段控件软圆还原 — `WardrobeRoute.kt` 对照 iOS fashion 导航，把 `少女衣橱 / 心愿尾款` 分段改为图标+文字的紧凑软圆按钮，操作按钮组改为自定义圆形热区 `Surface`，排序/更多图标替换为更接近 iOS 的上下箭头与横向省略号，并移除本区新增硬编码色值。assembleDebug 通过；红线 grep 无命中；装机验证可见 `少女衣橱`、`心愿尾款`、`排序`、`筛选`、`布局`、`更多`、`添加`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-UI-03** 衣橱列表/网格卡片软圆还原 — `WardrobeRoute.kt` 将网格卡与列表行从 Material `Card` 改为自定义软圆 `Surface`，统一 26–28dp 圆角、半透明白底、轻描边主图框、粉色尾款角标与价格胶囊；空图占位渐变改为现有 token 色系。assembleDebug 通过；红线 grep 无命中；装机验证可见 `奶油白半身裙`、`¥129.00`、`粉色针织开衫` 与 `心愿尾款`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-UI-02** 衣橱统计卡 / 详细统计 Sheet 软圆还原 — `WardrobeRoute.kt` 将统计卡外层、指标块、功能入口、详细统计 Sheet 汇总块与分组行从 Material `ElevatedCard`/方正入口改为自定义软圆半透明面板、轻描边块和粉色内容底。assembleDebug 通过；红线 grep 无命中；装机验证可见 `衣橱总览`、软圆统计块、`详细统计` Sheet、`统计口径：全量衣橱`、`按品牌` 与 `按类型`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-DATA-04B** 最近搜索持久化 — `UserPreferencesDataStore.kt` 新增 `wardrobe_recent_searches` 持久化键与 UTF-8 percent-encoding 编解码；`WardrobeHomeViewModel.kt` 从 DataStore 读取最近搜索并在提交查询时写回。assembleDebug 通过；红线 grep 无命中；装机验证点击 `价格 100-300` 后 force-stop 重启，重新打开搜索仍可见 `最近搜索` 与 `100-300`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-DATA-04A** 最近搜索 UI + 搜索区软圆还原 — `WardrobeHomeViewModel.kt` 新增会话内 `recentSearches` 与 `submitSearchQuery`，`WardrobeRoute.kt` 将搜索区从 `OutlinedTextField` / Material `AssistChip` 改为自定义 `BasicTextField` 胶囊、圆形关闭按钮、软圆玻璃面板与自定义查询 Pill。assembleDebug 通过；红线 grep 无命中；装机验证打开搜索可见 `快捷查询`，点击 `价格 100-300` 后出现 `最近搜索`、`100-300`、`当前结果统计` 与 `命中 3/4 款`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-DATA-03** 衣橱详细统计 Sheet — `WardrobeHomeViewModel.kt` 新增品牌/类型/颜色/状态/尾款状态分组统计，`WardrobeRoute.kt` 将统计卡「详细统计」改为可点击 Sheet；统计口径随搜索/筛选切换为全量或当前结果。assembleDebug 通过；红线 grep 无命中；装机验证可见 `详细统计`、`统计口径：全量衣橱`、`按品牌`、`按类型`、`按颜色`，滚动后可见 `按状态` 与 `按尾款状态`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-DATA-02** 高级查询语法提示 + 快捷筛选 Chip — `WardrobeBusinessLogic.kt` 支持 `字段:关键词`、无值查询、尾款查询与价格区间；`WardrobeRoute.kt` 将搜索框升级为查询小抄卡，展示价格、无品牌、无标签、无小物、心愿尾款与动态品牌/类型/颜色/状态快捷 Chip。assembleDebug 通过；红线 grep 无命中；装机验证点击 `价格 100-300` 与 `无品牌` 后统计卡联动为「当前结果统计」。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-WARDROBE-DATA-01** 查询/筛选结果联动统计 — `WardrobeHomeViewModel.kt` 增加 `visibleStatistics` 与活跃查询判断，`WardrobeRoute.kt` 让统计卡在搜索/筛选时切换为「当前结果统计」，展示命中数、筛选数与当前关键词。assembleDebug 通过；红线 grep 无命中；装机验证搜索 `100-200` 后出现 `当前结果统计`、`命中`、`100-200`、`2/2`、`¥297.00`。详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)。
- [x] **BATCH-M3-03** PetRoute 完整化（F-11 ~ F-17 宠物 home）— 重做 `PetRoute.kt` + 新增 `PetViewModel.kt`，并按用户确认追加 `PinkHouseApp.kt` 挂载入口：`我 → 智能萌宠` 与底部奶茶浮层进入宠物 Home，`萌宠对话` Tab 保持聊天页。assembleDebug 8s 通过；红线 grep 无命中；装机截图确认 `萌宠小家`、双宠切换、状态条、货币、喂食/饮水/清洁/抚摸/打工与互动记录。详见 [android_migration_pet.md](android_migration_pet.md)。
- [x] **BATCH-M3-02** PetChat 兜底文案池 — 新增 `strings_petchat.xml` 的 `pet_chat_fallback_replies` string-array（10 条），`PetChatRoute.kt` 改为 `stringArrayResource` 随机抽取；行为保持意图/输入后立即本地兜底回复。assembleDebug 8s 通过；红线 grep 无命中；装机截图确认点击 `B. 看天气穿搭` 后出现资源数组回复。详见 [android_migration_petchat.md](android_migration_petchat.md)。
- [x] **BATCH-M3-01** PetChatRoute 首屏 + 3 个意图按钮 — 新增 `feature/petchat/PetChatRoute.kt`，`PinkHouseApp.kt` 将底部 `萌宠对话` Tab 绑定到新聊天首屏；保留输入框与本地兜底回复降级，无 AI/TTS/VIP 智能入口。assembleDebug 4s 通过；红线 grep 无命中；装机截图确认欢迎气泡、3 个意图按钮、底部输入与意图点击回复。详见 [android_migration_petchat.md](android_migration_petchat.md)。
- [x] **BATCH-ARCH-04** SmallWorld 默认页左上图标语义调整 — `SmallWorldRoute.kt` SmallWorldFeatureScreen 内：destination == SmallWorld 时显 ☰ Menu 图标（语义"打开菜单"），子页保留 ← ArrowBack（语义"返回"），onClick 行为不变。assembleDebug 5s 通过。装机截图确认 ☰ 图标显示。 BackHandler 行为保留（按返回先进 Menu 再退 Tab），后续可继续优化但不阻塞 M3。
- [x] **BATCH-ARCH-03** 删除浮动 `PetChatFloatingButton` — 与底部 PetChat Tab 重复入口。改 2 文件：`PinkHouseApp.kt`（删 import + 删调用）+ `PinkHouseComponents.kt`（删函数定义）。naichaPeeking 装饰保留。assembleDebug 5s 通过。装机截图确认右下角浮动按钮消失，4 Tab 完整。
- [x] **BATCH-ARCH-02** House Tab 默认入口从 `Menu` 改为 `SmallWorld` — 改 1 处：`SmallWorldRoute.kt` line 105。装机截图确认 House Tab 直接落小世界页。assembleDebug 6s 通过。遗留：浮层菜单按钮 → ARCH-04。
- [x] **BATCH-ARCH-01** 启用第 4 底部 Tab `PetChat`（萌宠对话）— 改 1 处：`AppDestination.kt` `showInBottomBar` 默认走 true。  装机截图确认 4 Tab 对齐 iOS。assembleDebug 12s 通过。遗留：浮动猫与 Tab 重复入口 → ARCH-03。
- [x] **M2 衣橱闭环 F-01 ~ F-09** — 详见 [android_migration_wardrobe.md](android_migration_wardrobe.md)
- [x] **本地尾款通知 F-29 部分** — `core/notification/DepositReminder*.kt` (commit 913c417)
- [x] **M1 主题 + Shell + 三 Tab + Room v1~v3** — 含资产入仓、SplashScreen 接入

---

**End of backlog**.
