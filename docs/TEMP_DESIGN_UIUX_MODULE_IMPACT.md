# temp/design UI/UX 设计分析与模块关联

> 设计来源：`/Users/muniao/Downloads/Pink_House/temp/design`
> 当前仓库路径：`/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House`
> 记录日期：2026-04-21

## 1. 结论

`temp/design` 这组图不是单页视觉改版，而是一次完整的信息架构统一：衣橱、House、宠物聊天、心愿尾款、财富、穿搭手帐、我/VIP/设置都被组织到同一套“浅粉水彩 + 液态玻璃 + 宠物陪伴”的体验里。

现有 iOS 工程已经具备大部分业务模块，后续重点应是先统一全局视觉 token、导航壳层和共享组件，再分模块替换页面。HarmonyOS Next 当前是功能子集骨架，应该只承接跨端 PRD 允许的基础体验，不同步 iOS 独占 AI、RealityKit、CloudKit、完整裙子股市等能力。

## 2. 设计图清单与页面识别

| 文件 | 识别页面 | 主要 UI/UX 信息 |
|---|---|---|
| `IMG_7936.png` | 衣橱首页 | 水彩背景、衣橱/尾款分段、衣物网格、总件数/总价值、今日穿搭色、穿搭手帐、详细统计、底部浮动 Tab、聊天浮钮、宠物露出 |
| `IMG_7937.png` | 衣橱统计 | 资产汇总卡、裙装/小物统计、标签统计、横向柱状比例、返回胶囊 |
| `IMG_8200.PNG` | 宠物聊天首页 | 宠物头像、AI/规则回复卡、快捷问题、底部输入搜索、历史日记提示 |
| `IMG_8201.PNG` | 宠物聊天商店 | 背包/商店分段、商品网格、VIP 折扣、拖拽投喂区域、喵币/金币状态 |
| `IMG_8204.PNG` | House 小世界 | 房间式功能地图、热点入口、衣橱/尾款/梦裙日历/拼豆/财富/来财导航 |
| `IMG_8205.PNG` | 我/VIP/设置 | VIP 卡、魔法任务、资料与备份、梦幻衣橱设置、House 设置、智能萌宠设置 |
| `IMG_8206.PNG` | 心愿尾款 | 月/系列视图、尾款列表、筛选排序、总待付尾款、尾款提醒入口 |
| `IMG_8207.PNG` | 马上来财：请签 | 三段式导航：请签/数钱/安财，签文卡、再求一签 |
| `IMG_8208.PNG` | 马上来财：数钱-纸币 | 人民币/日元/美元切换，大额资产数字，纸币散落视觉 |
| `IMG_8209.PNG` | 马上来财：安财-黄金 | 黄金/白银/虚拟切换，实时金价、刷新、音效/震动控制、金币物理散落 |
| `IMG_8211.PNG` | 穿搭手帐 | 水彩背景、手帐网格、图片卡片、列表/更多控制、底部动态 Tab |

## 3. 全局 UI/UX 规则

- 背景：以浅粉纯色和水彩国风园林图为主，页面主体不再使用纯白平铺。
- 材质：顶部控制、底部 Tab、卡片、筛选器统一使用半透明玻璃/胶囊视觉。
- 导航：底部保持四入口结构：衣橱、动态中位入口、我、聊天；动态中位随 House 子模块显示 `House`、`来财`、`穿搭手帐` 等名称。
- 陪伴层：宠物不是单独页面元素，而是跨衣橱、House、聊天、底部 Tab 的陪伴线索。
- 数据表达：金额、件数、金价、尾款等关键数字使用大字号，弱化传统表格感。
- 交互入口：常用功能通过图标胶囊、分段控件和卡片入口呈现，避免深层菜单。

## 4. 模块影响矩阵

| 设计能力 | iOS 关联模块 | 需要确认/统一的内容 |
|---|---|---|
| 全局粉色水彩 + 液态玻璃 | `ThemeManager`、`MagicThemeDesignSystem`、`AdaptiveColorSystemV2`、`docs/UI_DESIGN_GUIDE.md` | 背景 token、玻璃卡片、胶囊分段、资产数字、统一阴影和透明度 |
| 底部浮动导航和聊天浮钮 | `MainTabView`、`SmallWorldMenuOverlay`、`SmallWorldPetOverlay`、`NewbieGuideManager` | 四入口布局、动态中位标题、聊天入口、安全区、宠物露出层、引导捕获点 |
| House 功能地图 | `SmallWorldView`、`RococoSmallWorldView`、`FrenchRetroSmallWorldView`、`SmallWorldHotspotInfrastructure`、`FeatureUnlockManager` | 热点坐标、功能解锁、House 子路由、全屏/收起按钮 |
| 衣橱首页 | `WardrobeView`、`ClothingListView`、`ClothingCard`、`ClothingFilterMenu`、`GlobalSearchView` | 衣橱/尾款分段、网格卡、排序筛选、统计入口、今日穿搭色、手帐入口 |
| 衣橱统计 | `WardrobeStatisticsDetailView`、衣橱统计数据聚合 | 总件数/总价值、裙装/小物拆分、标签柱状统计、金额格式 |
| 心愿尾款 | `DepositPlanView`、`DepositPlanComponents`、`DepositItemRow`、`DepositNotificationView`、`CalendarViewModel` | 月视图/系列视图、待付尾款汇总、提醒入口、尾款状态标签 |
| 梦裙日历 | `DreamDressCalendarView`、`DreamCalendarComponents` | House 入口与尾款/衣橱数据联动 |
| 宠物聊天首页 | `PetChatView`、`PetChatBubbleView`、`PetChatHistorySearchSheet`、`PetChatTranscriptStore` | 历史日记提示、快捷问题、底部输入搜索、聊天气泡风格 |
| 宠物聊天跨模块 widget | `PetGenerativeUIViews`、`PetChatWidgetFactory`、`PetChatIntentRouter`、`WardrobeContextManager`、`WeatherService` | 帮我搭一套、看天气穿搭、找裙子、衣橱搜索、天气建议卡 |
| 宠物商店/背包/投喂 | `PetChatCoreHelpers`、`PetDataManager`、`PetViewModel`、`PetHomeView`、`PetBottomPanel` | 背包/商店分段、商品价格、VIP 折扣、拖拽投喂、喵币不足跳转 |
| 我/VIP/设置 | `MeView`、`VIPCenterView`、`VIPCardView`、`VIPVisualSystem`、`VIPManager`、`MeowCoinStoreView`、设置子页 | VIP 卡、尊贵编号、魔法任务、用户资料、备份状态、主题/House/宠物设置入口 |
| 财富三段式 | `WealthView`、`WealthViewModel`、`DivinationViews`、`MoneyCountingViews`、`GoldPhysicsView`、`SilverPhysicsView`、`SoundManager`、`HapticEngineManager` | 请签/数钱/安财分段、金额/金价、刷新、音效/震动、物理散落 |
| 穿搭手帐 | `OOTDView`、`OOTDEditorView`、`OOTDCanvasView`、`BookShelfView`、`BookDetailView` | 手帐网格、图片卡、聊天里的搭配建议入口、底部动态 Tab |
| 商业化与奖励 | `VIPManager`、`IAPServerManager`、`StoreManager`、`RewardManager`、`FeatureUnlockManager` | 喵币、VIP 折扣、功能解锁、魔法任务、消费/奖励状态一致性 |

## 5. HarmonyOS Next 影响

HarmonyOS Next 侧应以 `docs/migration/00_PRODUCT_SPEC_CROSS_PLATFORM.md` 的子集规则为准，优先同步这些基础能力：

- `Index.ets` / `FeatureShell.ets`：四入口导航、动态中位入口、全局粉色/玻璃主题。
- `WardrobePage.ets`：衣橱列表、基础统计、搜索筛选、尾款字段展示。
- `SmallWorldPage.ets`：House 功能地图和热点入口。
- `PetPage.ets`：规则式气泡、宠物状态、商店/投喂的降级版。
- `WealthPage.ets`：请签/数钱/安财视觉骨架，物理动效降级为普通动画。
- `VipPage.ets`：VIP/喵币基础状态和 HMS IAP 后续接入点。
- `AppTheme.ets`：粉色、水彩、玻璃、卡片、分段控件 token。

不应同步到鸿蒙 Next 的能力：

- LLM 智能宠物聊天。
- Vision/自动抠图/AI 穿搭推荐。
- RealityKit/空间场景/3D 手帐。
- CloudKit 同步。
- iOS 运行时 App Icon 切换。
- iOS 版完整裙子股市。

## 6. 建议实施顺序

1. P0：沉淀共享 UI token 和壳层组件，包括背景、玻璃卡片、胶囊分段、底部 Tab、聊天浮钮、宠物露出层。
2. P1：优先重做衣橱首页、统计页、心愿尾款页、House 热点页，因为它们是主路径且设计图覆盖最完整。
3. P2：整合宠物聊天跨模块 widget，包括衣橱搜索、天气穿搭、商店/背包、拖拽投喂、喵币不足跳转。
4. P3：调整我/VIP/设置和财富页，接入现有 VIP、喵币、魔法任务、财富动效配置。
5. P4：从稳定后的 iOS 规则中提炼鸿蒙 Next 子集，按 ArkUI 页面骨架逐步同步。

## 7. 验收清单

- iOS 视觉：小屏和大屏下底部 Tab、聊天浮钮、宠物露出、玻璃卡片、长文案、价格数字不重叠。
- iOS 业务：衣橱统计总数/总价、尾款月份/系列分组、VIP 折扣价、喵币余额、宠物背包、财富金额显示与真实数据一致。
- iOS 导航：衣橱、House、我、聊天、尾款、梦裙日历、穿搭手帐、马上来财之间往返不丢状态。
- 引导与解锁：底部 Tab、House 热点、聊天入口、VIP/喵币入口仍能被 `NewbieGuideManager` 和 `FeatureUnlockManager` 正确捕获。
- HarmonyOS Next：只展示跨端 PRD 允许的功能子集，不出现 iOS 独占能力入口。

## 8. 当前约束

- 本文只记录设计分析和模块影响面，不代表已完成 UI 代码实现。
- 不移动 `/Users/muniao/Downloads/Pink_House/temp/design` 下的设计图。
- 当前 iCloud 仓库没有 `temp/design` 同名设计目录；后续若要让设计资源随仓库走，需要单独决定资源同步策略。
- iOS 不执行 Xcode 编译；编译错误由用户粘贴后再处理。
