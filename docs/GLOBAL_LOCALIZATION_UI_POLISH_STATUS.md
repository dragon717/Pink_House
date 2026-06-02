# 全局多语言与界面美化阶段状态

更新日期：2026-06-02

## 多语言推进状态

当前主流语言基线：`en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`、`fr`、`de`、`es`、`pt-BR`。

| 阶段 | Commit | 状态 | 覆盖范围 | 验收 |
|---|---|---|---|---|
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

## UI 美化盘点

| 界面/模块 | 核心文件 | 当前状态 | 已完成设计点 | 主要问题或缺口 | 优先级 | 下一小步 |
|---|---|---|---|---|---|---|
| 小屋主界面 | `SmallWorldView.swift`、`BookHouseSmallWorldView.swift` | 已固定走书本小屋形态 | `.house` 主题背景、舞台氛围、房间/功能物件图片、摆放模式、弹簧动效 | 样式被强制为 `bookHouse`；素材缺失时缺少主题化空态；部分旧小屋组件未接入当前入口 | P1 | 补主题化“小屋素材缺失/空状态”兜底，并核对当前入口实际组件 |
| 小屋子页：萌宠/大世界 | `PetHomeView.swift`、`BigWorldView.swift` | 功能丰富，视觉体系混用 | 萌宠状态头、底部面板、浮动按钮；大世界航行/签到/分享/彩带动效 | 硬编码颜色和材质较多；主题皮肤覆盖不足；提示层视觉不统一 | P2 | 从萌宠浮动按钮和提示面板开始替换为共享主题按钮/卡片样式 |
| 衣橱主页导航/工具栏 | `HomeView.swift`、`WardrobeNavigationStyle.swift`、`HomeThemeSkinComponents.swift` | 主入口美化较完整 | 衣橱/存钱计划背景切换、主题化顶部栏、搜索、菜单、时装导航 | 工具栏逻辑密；部分菜单标签和按钮不是统一视觉组件；文本可读性标记效果需复核 | P1 | 给顶部工具栏整理视觉验收清单，统一按钮、菜单标签、搜索态 |
| 衣橱列表/网格/卡片 | `WardrobeView.swift`、`ClothingCard.swift`、`WardrobeThemeSkinComponents.swift` | 当前最成熟的视觉区域 | 网格/列表切换、统计浮层、选择底栏、拖拽排序、主题衣物卡片、徽标 | 旧 `ClothingListView` 可能与新入口视觉分叉；主衣橱空态不明显；属性 pill 窄网格有溢出风险 | P0 | 确认唯一主入口，并给“无衣物/筛选无结果”接入 `ThemeSkinEmptyStateSurface` |
| 衣橱统计/筛选 | `WardrobeStatisticsDetailView.swift`、`WardrobeView.swift` | 功能完整，视觉仍可统一 | 统计卡、Charts、筛选 sheet、filter chips、清除筛选工具栏 | 图表和金额色仍有硬编码；空态多为纯文字；筛选 sheet 与主题卡片体系不完全一致 | P1 | 把统计图表色改为主题 palette token，并补“暂无统计/暂无筛选结果”主题空态 |
| 修改/编辑页表单 | `ClothingEditView.swift`、`ClothingEditSections.swift` | 功能强，视觉统一度中等 | 衣橱背景、主题 section card、草稿持久化、取消/保存、防误删、校验 toast | 长表单阅读疲劳；工具栏偏系统文字按钮；输入区、toast、分段控件仍偏系统默认 | P1 | 先美化首屏：图片区、基础信息卡、顶部保存/取消工具栏 |
| 修改/编辑页图片展示 | `ImagePickerGrid.swift`、`ChartImagePicker.swift` | 交互完整，视觉偏系统控件 | 相册/相机、横向缩略图、主图徽标、删除、拖拽排序、预览、裁剪 | 添加/删除/裁剪控件较灰；无图片时缺少品牌化引导；表图入口发现性一般 | P1 | 把添加 tile、缩略图边框、无图提示抽成主题化媒体控件 |
| 单件详情页 | `ClothingDetailView.swift` | 已有完整详情体验 | hero 轮播、主题信息卡、可复制字段、品牌/标签/定金徽标、编辑/分享/复制/删除 | hero 与卡片固定负 offset 小屏/横屏较脆弱；无图 placeholder 灰底；社区 FAB 和工具栏未主题化 | P1 | 替换无图轮播为空态组件，并把 hero 间距抽成响应式常量 |
| 图片查看/图表详情 | `ImageViewer.swift`、`ChartImageViewer.swift` | 工具型查看器可用 | 黑底全屏、缩放、双击缩放、保存到相册、页码、关闭按钮 | 图片加载失败状态不明显；保存提示和顶部按钮较系统；与主题页切换有视觉落差 | P2 | 保留黑底体验，补失败占位和更精致的顶部控制按钮 |
| 共用主题/卡片基础 | `ThemeSkinModels.swift`、`ThemeSkinSharedComponents.swift` | 主题 slot 架构已搭好 | 18 个 slot、天空音乐会/天鹅入梦全 slot、section/card/button/icon/empty state、暗色可读性 helper | `themeSkinLegibleText` 多数是语义标记；`emptyState` slot 应用面少 | P0 | 全局盘点 `.themeSkinLegibleText` 调用点，明确哪些需要真正接 `themeSkinLegibilityBackdrop` |

## 下一阶段建议

1. 代码主线继续补 P0 本地化：`DailyCheckInView`、VIP/IAP 购买链路、通知/设置中仍裸露的用户可见文案。
2. UI 美化先从衣橱 P0 开刀：无衣物/筛选无结果空态接入 `ThemeSkinEmptyStateSurface`，并复核窄网格 pill 溢出。
3. 小屋美化排 P1：先补素材缺失空态，再处理萌宠/大世界子页的主题按钮与提示面板统一。
