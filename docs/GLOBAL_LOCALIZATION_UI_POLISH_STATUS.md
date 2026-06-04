# 全局多语言与界面美化阶段状态

更新日期：2026-06-04

## 多语言推进状态

当前主 App 声明语言：`en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`、`fr`、`de`、`es`、`pt-BR`。

当前真实完成线：`en`、`zh-Hans`、`zh-Hant`。`ja`、`ko`、`fr`、`de`、`es`、`pt-BR` 已开放入口和部分资源，但截至 2026-06-04 仍有 1744 个 `Localizable.xcstrings` key 缺对应翻译，应按英文 fallback / 待补全状态管理，不能标记为完整全球化完成。

| 阶段 | Commit | 状态 | 覆盖范围 | 验收 |
|---|---|---|---|---|
| 多语言文本审计与验收基线 | `e662dea` | 已提交 | 资源覆盖、subagent 分区审计、高优先级风险池、后续 stage gate | 静态校验通过；文档阶段未跑模拟器 |
| 萌宠旧版快捷菜单 | `74ce4ac` | 已提交 | `PetChatViewLegacy` 的 AI 搭配/快捷功能菜单与按钮 label 接入 `.appLocalized`；不改 command id、prompt payload、quick outfit 参数 | index 快照构建通过；安装并重启 `Codex iPhone 17 Pro`；Computer Use 观察到每日打卡界面，未进入 Legacy 菜单 |
| 首次启动引导首屏 | `b9a03b5` | 已提交 | `WelcomeBubbleView`、`PointingBubbleView`、`SkipGuideConfirmationView` 的首屏/跳过确认文案接入 `.appLocalized`，使用既有 key 与英文 fallback | index 快照增量构建通过；安装并重启 `Codex iPhone 17 Pro`；Computer Use 观察到启动页，未强制清数据触发首次引导 |
| 设置任务引导卡片 | `477f3c6` | 已提交 | `NewbieGuideSettingsTasks` 的数据备份/iCloud 同步卡片标题、说明、跳过、了解更多、收起、知道了按钮接入 `.appLocalized`，不改任务状态与引导流程 | index 快照增量构建通过；安装并重启 `Codex iPhone 17 Pro`；Computer Use 观察到启动后白屏，日志显示 app 进程存活且无本切片相关崩溃，未触达设置任务卡片 |
| 引导气泡跳过按钮 | `89d6e9f` | 已提交 | `GenericFeatureGuideBubbleView` 与 `HorizontalSwipeHintView` 的“跳过”按钮接入 `.appLocalized`；默认下滑提示因 catalog 缺 key 留待补 key 阶段 | index 快照增量构建通过；安装并重启 `Codex iPhone 17 Pro`；Computer Use 仍观察到启动后白屏，近一分钟无 crash 日志，未触达目标引导气泡 |
| 萌宠主页控件文案 | `7758721` | 已提交 | 萌宠主页按钮、状态、交互控件 | `xcodebuild` 通过 |
| 萌宠打工选择页 | `463ca29` | 已提交 | 打工选择、收益/消耗提示 | `xcodebuild` 通过 |
| 萌宠背包商店面板补充 | `3365393` | 已提交 | 背包/商店面板固定文案 | `xcodebuild` 通过 |
| 萌宠状态与互动提示 | `ebd17c3` | 已提交 | 状态说明、互动反馈 | `xcodebuild` 通过 |
| 品牌/标签管理页 | `67467db` | 已提交 | 品牌、标签列表与删除提示 | `xcodebuild` 通过 |
| 编辑页基础信息与图片选择 | `e6a617d` | 已提交 | 编辑页基础字段、图片选择 | `xcodebuild` 通过 |
| 编辑页价格与汇率区域 | `e368e91` | 已提交 | 价格、汇率、计算提示 | `xcodebuild` 通过 |
| 编辑页购买与预约区域 | `c1921ea` | 已提交 | 购买、尾款、预约相关字段 | `xcodebuild` 通过 |
| 梦裙日历基础界面 | `da45894` | 已提交 | 日历视图切换、日期、定金/尾款、近期列表 | `xcodebuild` 通过 |
| 梦裙日历主题选择器 | `828e3d5` | 已提交 | 主题选择器固定文案、内置主题名展示 | `xcodebuild` 通过 |
| VIP 试用弹窗 | `73cc868` | 已提交 | 试用弹窗标题、福利、倒计时、确认按钮 | `xcodebuild` 通过 |
| 衣橱空态主题化 | `9c3aa8f` | 已提交 | 无衣物/筛选无结果空态、主题 empty surface、空态入口按钮 | `xcodebuild` 通过 |
| 每日打卡界面壳层 | `3ae1449` | 已提交 | 打卡主页、周签到、分享卡、日历星期/月年、日期与计数字符串 | `xcodebuild` 通过 |
| 喵币商店购买提示 | `1d53806` | 已提交 | 喵币商店标题/协议/优惠码/问题反馈、IAP 错误、成功 toast、商品包名与描述 | `xcodebuild` 通过 |
| VIP 中心兑换界面 | `91365ba` | 已提交 | VIP Center hero、状态、权益、菜单、优惠码/兑换确认、浮动购买栏、VIPManager 计划与结果消息 | `xcodebuild` 通过 |
| 回收站界面 | `d4a19e2` | 已提交 | 回收站导航、分段、空态、section、行内页数/像素/删除时间、批量删除/恢复 alert | `xcodebuild` 通过 |
| 衣橱合并目标筛选 | `5a835c7` | 已提交 | 合并为小物目标选择 sheet、筛选 sheet、系统占位 chip、数量格式、共享筛选模式/心愿尾款展示名 | `xcodebuild` 通过 |
| Home 顶栏排序布局 | `78ceabc` | 已提交 | 排序/布局 picker、衣橱/心愿尾款搜索 prompt、取消按钮、心愿尾款详情/简略展示名；保留 rawValue 持久化兼容 | `xcodebuild` 通过 |
| 衣橱统计详情 | `a5952bd` | 已提交 | 统计详情导航/筛选摘要、总览/标签/心愿尾款/购买时间标题、金额/百分比格式 key、月份 label、图表轴标题；补齐 9 语言 | `xcodebuild` 通过 |
| Home 筛选与菜单入口 | `b1da749` | 已提交 | 经典筛选清除/无标签/无品牌/无类型等展示名、字段名、更多/新增菜单、引导菜单 overlay、社区导入提示；保留 sentinel/rawValue/用户数据 | `xcodebuild` 通过 |
| 功能解锁提示 | `8e48603` | 已提交 | Home/批量导入/FeatureUnlockButton 解锁 alert、条件描述、进度 message、MagicTasks/MagicColor/FeatureUnlockSettings/小屋/尾款入口条件展示；保留 Codable description 和测试页 | `xcodebuild` 通过（临时源码快照） |
| VIP 图标与卡片动态名称 | `e582e6c` | 已提交 | VIPAppIcon option 名称/副标题/badge、切换结果消息、VIPCardStyle displayName、卡片皮肤 hint、VIP 卡片角标；保留 rawValue/option id/alternateIconName | `xcodebuild` 通过（临时源码快照） |
| 心愿尾款月度与系列选择 | `b29ee98` | 已提交 | DepositPlan 快捷入口/解锁弹窗/钱包提示、月度/系列 selector、最近月/最近添加卡片、年/月/金额格式；补齐 9 语言 | `xcodebuild` 通过（临时源码快照） |
| 尾款提醒通知流程 | `0bebbec` | 已提交 | DepositNotificationView 导航/权限/设置/记录/测试/诊断文案、DatePicker/time formatter、NotificationManager 正式/测试通知 title/body、支付期/金额短语；保留 payload/UserDefaults/identifier | `xcodebuild` 通过（临时源码快照） |
| 萌宠 AI 兜底回复 | `45876f7` | 已提交 | `PetPersonaProfile.warmthSuffixes`、`PetAIService` 空回复/timeout/error fallback、`PetResponseHumanizer` JSON 输出外壳；新增 19 key/9 语言 | `xcodebuild` 通过（临时源码快照） |
| 衣橱属性标签溢出修复 | `4fac66f` | 已提交 | `AttributePill` 移除横向 fixedSize，补 `minimumScaleFactor`/tail truncation/tightening，避免详细列表长字段顶开布局 | `xcodebuild` 通过（临时源码快照） |
| 每日问候本地模板 | `9d4ab3c` | 已提交 | `GreetingTemplates` 60 条本地诗意问候、6 条默认问候、`DailyGreeting.localizedMessages` 展示层本地化；本地缓存保留 raw key，AI/CloudKit 内容不误翻译 | `xcodebuild` 通过（index 源码快照） |
| 每日打卡本地穿搭色 | `0f1f552` | 已提交 | `DailyCheckInManager` 本地 fallback 的小物/描述展示层本地化，`DailyCheckInView` 天气/季节/颜色/分享卡展示本地化；`ColorInfo`/`ColorCard` 分离 rawName 与 displayName；新增 81 key/9 语言 | `xcodebuild` 通过（index 源码快照） |

## 2026-06-04 审计刷新

- 新增审计文档：`docs/localization/STRING_AUDIT_AND_ACCEPTANCE_2026-06-04.md`。
- `Localizable.xcstrings` 当前 3090 个 key：`en`、`zh-Hans`、`zh-Hant` 全覆盖；`ja`、`ko`、`fr`、`de`、`es`、`pt-BR` 各缺 1744 个 key。
- 主 App 9 个 `InfoPlist.strings` 文件均存在且 lint 通过；非中文新增语言权限文案当前复用英文。
- Widget 本地化落后主 App，目前只看到 `en`、`zh-Hans`、`zh-Hant` 覆盖。
- 本轮新派发 subagent：Archimedes 负责资源/文档，Hypatia 负责 SwiftUI 视图层，Huygens 负责服务/模型层。三者均只读完成，未修改文件。
- iCloud 工程路径下 `xcodebuild -list` 与 `xcodebuild build` 会卡在 `NSFileCoordinator coordinateReadingItemAtURL` 递归读工程阶段。当前 workaround：用 `git checkout-index` 把 index 快照导出到 `/private/tmp/pink-house-index-build`，复制 `build/SourcePackages` 到 `/private/tmp/pink-house-sourcepackages`，再从 `/private/tmp` 构建。该方式已用于 `74ce4ac`、`b9a03b5`、`477f3c6` 和 `89d6e9f`。

## Subagent 最新盘点

| Subagent | 分工 | 已完成/已验证 | 还没有做 | 需要重点优化 |
|---|---|---|---|---|
| Peirce | Home 顶栏/筛选/菜单审计 | 确认 `SortOption`、`ViewLayout`、`ClothingField` rawValue 都是持久化/偏好边界，不能直接改；顶栏排序/布局、搜索 prompt、经典筛选、更多/新增菜单和 Home 解锁 alert 已落地 | 测试页 `condition.description` 暂按测试页后置；Home 其它深层动态文案继续滚动审计 | 后续继续避免改 rawValue/sentinel；Home 不再把解锁 alert 列为 P0 阻塞 |
| Hubble | VIP 子页审计 | 确认 VIP Center 主体已完成；`VIPVisualSystem.displayHint(for:)`、`VIPCardSkinSelectionView`、`VIPCardView` tag、`VIPAppIconSelectionView`、`VIPAppIconManager` option/result message 已按 `e582e6c` 落地 | VIP 子页仍可继续复核低频 literal 与 IAP 价格/权益边界 | 动态名称已完成；后续 VIP/IAP 转向价格、权益和低频购买/兑换失败态复核 |
| Euclid | 萌宠 prompt/fallback 最小切片选择 | 从 P0 prompt/fallback 候选中确认 `PetPersonaProfile.swift` 是最小且收益最高的第一刀 | PromptBuilder marker、PetAIService system prompt、Vision/Outfit prompt、IntentRouter command payload 仍后置 | 下一刀萌宠建议只做 `PetPersonaProfile`：prompt 字段走 `ai.prompt.*`，用户 fallback 走 `pet.chat.fallback.*`，不要混改 marker/JSON/command |
| Nietzsche | 衣橱统计详情审计 | P0 本地化已按 `a5952bd` 落地：导航/筛选栏、概览、标签表头/占比、心愿尾款、购买时间标题、月份/坐标轴、金额/百分比格式 key | 统计图表硬编码色、标签无数据空态 surface、金额货币地区化仍需 P1/P2 处理 | 下一步不再把统计详情列为 P0 文案阻塞；后续走 UI 主题色/空态专项 |
| Meitner | 修改/编辑页表单审计 | 确认 `ClothingEditSections` 主表单大多已通过组件内部本地化；`未到货`/`待付尾款` 是存储语义，UI 已局部本地化，不能直接改语义值 | 精确 key `裙装名称` 缺失；`¥ %.2f`、`¥%.2f`、`1 CNY = ... JPY` 等币种/汇率格式仍需单独 formatter 切片 | 编辑页 P0 补缺失字段 key；金额/汇率放到后续格式化治理，不和表单文案混改 |
| Cicero | Home 剩余 P0 审计 | 普通 UI 菜单/经典筛选已按 `b1da749` 落地；`FeatureUnlockManager.localizedDescription`、状态消息、Home/批量导入解锁 alert 已按 `8e48603` 落地；`FilterMode`、noTag/noBrand/noType sentinel 和 `@AppStorage` rawValue 未改 | 测试页与低频开发/内测提示继续后置；仍需滚动扫 Home 新增入口 | Home P0 当前可降级为跟踪项；下一刀转向 VIP 动态名称或编辑页精确缺 key |
| Anscombe | 萌宠 prompt/fallback 审计 | 明确 P0 不动 prompt marker、JSON schema、command 白名单；用户可见 fallback 和 humanizer 文案要先做 | S1 用户可见兜底、S2 Vision 展示文案、S3 Outfit 展示/错误文案、S4 intent/search payload 显示与 command 分离、S5 AI prompt 多语言化 | 下一刀萌宠从 S1 开始：`warmthSuffixes`、`PetAIService` 低频 fallback、`PetResponseHumanizer`、消歧标题；不要翻译 `ask:` 前缀和 command id |
| Goodall | VIP 子页复核 | 确认 P0 集中在变量 `String`/模型字段/动态 result message；最高收益切片已按 `e582e6c` 完成，插值消息用 localized helper | VIPCardSkinSelectionView 和 VIPAppIconSelectionView 仍可做低频 literal/翻译校对；IAP 失败态需另行扫 | VIP 动态名称不再是 P0 阻塞；下一刀转 DepositPlan 或萌宠 fallback |
| Schrodinger | 编辑/品牌标签复核 | 确认品牌/标签壳层和删除确认 key 基本已有；用户 brand/tag/option 不应本地化；存储 rawValue 不动 | P0 最明确缺口是 `ClothingEditSections` 的 `裙装名称` key；价格/汇率展示、toast 参数和汇率服务错误需要独立格式化切片 | 下一刀编辑页可先补 `裙装名称` key；金额/汇率另开 formatter，不和品牌/标签管理混改 |
| Lorentz | 详情/分享/查看器 P1 审计 | 确认详情页主体验不再是 P0 文案阻塞；剩余高收益点集中在 viewer 保存结果、分享卡 chrome、分享卡内容 label | `ImageViewer`/`ChartImageViewer` 的保存结果变量、`ShareCardManager` 的分享标题/准备中/按钮、`ClothingShareCardView` 的 `型色` key 未做 | 先做 viewer 保存结果，再做分享卡 chrome，最后补分享卡内容 label；用户输入/品牌/衣物状态值不翻译 |
| Huygens | 日历/打卡 P0 审计 | 已派发；本轮两次 `wait_agent` 未返回最终结果，随后关闭，前置状态为 running | 未产出可采纳审计结论，暂不据此改代码或调整优先级 | 下轮重新派发或恢复同类审计，再决定每日打卡/日历是否还有 P0 切片 |
| Descartes | 日历/打卡 P0 审计 | 确认 `DailyCheckInView` 主 UI 基本已覆盖；DepositPlan 月/系列选择按 `b29ee98` 落地，尾款通知流程按 `0bebbec` 落地；DailyGreeting 本地模板按 `9d4ab3c` 落地；DailyCheckIn 本地 fallback 展示层按 `0f1f552` 落地 | DailyGreeting/DailyCheckIn 的 AI prompt 多语言与 CloudKit 公共内容 locale 维度未处理 | 日历/打卡下一刀不再回头做本地 fallback；后续若做 AI/CloudKit locale 维度，必须单独设计共享内容分区 |
| Sartre | 萌宠 fallback/prompt 审计 | 确认 P0 是用户可见 fallback/humanizer 与会生成并同步用户内容的每日 prompt；`PetAIService`/`PetPersonaProfile.warmthSuffixes`/`PetResponseHumanizer` 已按 `45876f7` 落地 | PetChat/Legacy 共享 fallback、DailyGreeting/DailyCheckIn 内容生成仍需切片 | 下一刀转每日内容或 PetChat 低频 fallback；`ask:`、command id、JSON schema 和存储字段保持稳定 |
| Fermat | 萌宠 fallback/prompt 复核 | 明确第一刀应只做用户可见 fallback/humanizer；该第一刀已按 `45876f7` 落地，未触碰 prompt/schema/command | prompt key 化、PetGenerativePromptBuilder、PetConversationV2Support、PetRole、CloudKit 公共内容 locale 维度后置 | key 前缀建议 `daily.greeting.*`、`daily.checkin.*`；不翻译 JSON schema、command id、`ask:` 前缀 |
| Chandrasekhar | 尾款通知服务审计 | 指出正式/测试系统通知 title/body、支付期/金额短语需与 View 同刀处理；已按 `0bebbec` 落地，测试秒数由硬写 5 秒改为动态 `%d` | 复数规则和货币格式仍是后续格式化治理；既有 pending request 语言切换后会因 title/body 变化触发重排属预期 | payload keys、UserDefaults keys、threadIdentifier、`depositPlan`/`test`/`_catchup` identifier token 继续禁止翻译 |
| Plato | 萌宠 fallback/humanizer 最小切片 | 收窄第一刀到 `PetPersonaProfile.warmthSuffixes`、`PetAIService` user fallback、`PetResponseHumanizer` 输出外壳；已按 `45876f7` 落地 | `makeInitialHistory`、`stylePrompt`、`modulePrompts`、JSON 识别 key、command 值、Daily raw 模式后置 | 下一刀不要回头混改 prompt/schema；继续分离 Daily 内容生成和 PetChat/Legacy 低频 fallback |
| Bacon | Settings/Me P1 审计 | 确认实际落点是 `MeView.swift`、`UserProfileEditView.swift`、`PrivacySettingsView.swift`、Refactored settings 子页；Profile 目录不存在 | System/Wardrobe/Magic/PetAI/SmallWorld/Widget/Network settings 仍有大量壳文案；TestEffects 最后 | 下一刀建议 `MeView` 首屏/CloudSyncSheet + `UserProfileEditView` + `PrivacySettingsView`；保留 navigation tag、AppStorage key、URL、用户昵称/邮箱 |
| Jason | UI 美化静态复核 | 确认衣橱空态已完成；小屋素材基本齐但缺失素材无主题化 fallback；`AttributePill.fixedSize` 风险已按 `4fac66f` 修复 | 统计图表硬编码色、详情页无图 placeholder/hero offset、编辑页首屏/图片 tile、小屋素材缺失空态仍未做 | UI 下一刀转统计图表主题色或小屋素材缺失空态；仍需窄屏/大字号模拟器验收 `AttributePill` |
| Leibniz | AttributePill 溢出最小修法 | 定位 `AttributePill` 只在 `ClothingRow` 详细列表属性行使用；6 列缩略图和普通网格不走该路径；最小修法已按 `4fac66f` 落地 | 详细列表长类型/颜色/尺码仍需真机/模拟器大字号视觉复核 | 后续如仍溢出，再给中间列 `minWidth:0,maxWidth:.infinity`，不要扩大到普通网格卡片 |
| Lovelace | AttributePill worker 实现 | 直接修改 `ClothingCard.swift`，移除横向 fixedSize，补 `minimumScaleFactor(0.78)`、tail truncation、tightening；主代理已验收并提交 `4fac66f` | worker 未返回最终验收报告，关闭时状态仍为 running；未做 Computer Use 视觉截图 | 该切片仅静态/构建验收，下一轮 UI 验收需跑窄屏和大字号页面截图 |
| Kierkegaard | DailyCheckIn 本地 fallback/AI prompt 边界审计 | 确认本地 fallback 应分层改 `DailyCheckInManager`、`DailyCheckInView`、`Season`/`WeatherCondition` display、`ColorInfo` 展示名；本地 fallback 展示层已按 `0f1f552` 落地 | AI prompt 与 CloudKit public 内容暂无 locale 维度，仍需单独设计 | 本阶段已遵守 rawName/hex 与 displayName 分离；后续继续禁止翻译 `DailyOutfitColor` record/key、`source` token、enum rawValue、JSON schema、record id |
| Parfit | PetChat/Legacy fallback 与 command 边界审计 | 确认剩余中文直出集中在 disambiguation、搜索 fallback、投喂/摸摸/玩耍反馈、搭配/天气低频失败和 Legacy 菜单 label | 两份 PetChat 实现重复，尚未改；`localizedCatchphraseText` 仍只做喵/汪替换 | 下一刀建议同刀改两份 View 的用户可见文案或先抽 `PetChatCopy`；command id、`ask:` 前缀、widget command、JSON schema、transcript/memory 字段不翻译 |

## UI 美化盘点

| 界面/模块 | 核心文件 | 当前状态 | 已完成设计点 | 主要问题或缺口 | 优先级 | 下一小步 |
|---|---|---|---|---|---|---|
| 小屋主界面 | `SmallWorldView.swift`、`BookHouseSmallWorldView.swift` | 已固定走书本小屋形态 | `.house` 主题背景、舞台氛围、房间/功能物件图片、摆放模式、弹簧动效 | 样式被强制为 `bookHouse`；素材缺失时缺少主题化空态；部分旧小屋组件未接入当前入口 | P1 | 补主题化“小屋素材缺失/空状态”兜底，并核对当前入口实际组件 |
| 小屋子页：萌宠/大世界 | `PetHomeView.swift`、`BigWorldView.swift` | 功能丰富，视觉体系混用 | 萌宠状态头、底部面板、浮动按钮；大世界航行/签到/分享/彩带动效 | 硬编码颜色和材质较多；主题皮肤覆盖不足；提示层视觉不统一 | P2 | 从萌宠浮动按钮和提示面板开始替换为共享主题按钮/卡片样式 |
| 衣橱主页导航/工具栏 | `HomeView.swift`、`WardrobeNavigationStyle.swift`、`HomeThemeSkinComponents.swift` | 主入口美化较完整 | 衣橱/存钱计划背景切换、主题化顶部栏、搜索、菜单、时装导航 | 工具栏逻辑密；部分菜单标签和按钮不是统一视觉组件；文本可读性标记效果需复核 | P1 | 给顶部工具栏整理视觉验收清单，统一按钮、菜单标签、搜索态 |
| 衣橱列表/网格/卡片 | `WardrobeView.swift`、`ClothingCard.swift`、`WardrobeThemeSkinComponents.swift` | 当前最成熟的视觉区域；`AttributePill` 第一刀已修 | 网格/列表切换、统计浮层、选择底栏、拖拽排序、主题衣物卡片、徽标、无衣物/筛选无结果主题空态；`AttributePill` 已去掉横向 fixedSize | 旧 `ClothingListView` 可能与新入口视觉分叉；详细列表长字段仍需窄屏/大字号视觉复核 | P1 | 用窄屏大字号模拟器验收详细列表行，再转统计图表主题色 |
| 衣橱统计/筛选 | `WardrobeStatisticsDetailView.swift`、`WardrobeView.swift` | 功能完整，视觉仍可统一 | 统计卡、Charts、筛选 sheet、filter chips、清除筛选工具栏 | 图表和金额色仍有硬编码；空态多为纯文字；筛选 sheet 与主题卡片体系不完全一致 | P1 | 把统计图表色改为主题 palette token，并补“暂无统计/暂无筛选结果”主题空态 |
| 修改/编辑页表单 | `ClothingEditView.swift`、`ClothingEditSections.swift` | 功能强，视觉统一度中等 | 衣橱背景、主题 section card、草稿持久化、取消/保存、防误删、校验 toast | 长表单阅读疲劳；工具栏偏系统文字按钮；输入区、toast、分段控件仍偏系统默认 | P1 | 先美化首屏：图片区、基础信息卡、顶部保存/取消工具栏 |
| 修改/编辑页图片展示 | `ImagePickerGrid.swift`、`ChartImagePicker.swift` | 交互完整，视觉偏系统控件 | 相册/相机、横向缩略图、主图徽标、删除、拖拽排序、预览、裁剪 | 添加/删除/裁剪控件较灰；无图片时缺少品牌化引导；表图入口发现性一般 | P1 | 把添加 tile、缩略图边框、无图提示抽成主题化媒体控件 |
| 单件详情页 | `ClothingDetailView.swift` | 已有完整详情体验 | hero 轮播、主题信息卡、可复制字段、品牌/标签/定金徽标、编辑/分享/复制/删除 | hero 与卡片固定负 offset 小屏/横屏较脆弱；无图 placeholder 灰底；社区 FAB 和工具栏未主题化 | P1 | 替换无图轮播为空态组件，并把 hero 间距抽成响应式常量 |
| 图片查看/图表详情 | `ImageViewer.swift`、`ChartImageViewer.swift` | 工具型查看器可用 | 黑底全屏、缩放、双击缩放、保存到相册、页码、关闭按钮 | 图片加载失败状态不明显；保存提示和顶部按钮较系统；与主题页切换有视觉落差 | P2 | 保留黑底体验，补失败占位和更精致的顶部控制按钮 |
| 共用主题/卡片基础 | `ThemeSkinModels.swift`、`ThemeSkinSharedComponents.swift` | 主题 slot 架构已搭好 | 18 个 slot、天空音乐会/天鹅入梦全 slot、section/card/button/icon/empty state、暗色可读性 helper | `themeSkinLegibleText` 多数是语义标记；`emptyState` slot 应用面少 | P0 | 全局盘点 `.themeSkinLegibleText` 调用点，明确哪些需要真正接 `themeSkinLegibilityBackdrop` |

## 下一阶段建议

1. 萌宠用户可见 fallback/humanizer 已按 `45876f7` 完成；下一刀可按 Parfit 做 PetChat/Legacy 低频 fallback，不要混改 command、JSON、transcript。
2. 日历/打卡 P0：`DailyGreeting` 本地模板已按 `9d4ab3c` 完成，`DailyCheckIn` 本地 fallback 展示层已按 `0f1f552` 完成；AI prompt 多语言和 CloudKit locale 维度仍需单独切片。
3. Settings/Me P1 可按 Bacon 建议做 `MeView` 首屏/CloudSyncSheet + `UserProfileEditView` + `PrivacySettingsView`。
4. 详情页 P1 可接 Lorentz 建议：先 viewer 保存结果，再分享卡 chrome，最后补分享卡内容 label。
5. 编辑页 P0 仍保留精确小切片：补 `裙装名称` key；金额/汇率另开 formatter。
6. UI 美化 `AttributePill` 第一刀已按 `4fac66f` 完成；下一步做窄屏/大字号模拟器验收，再转统计图表主题色或小屋素材缺失空态。
