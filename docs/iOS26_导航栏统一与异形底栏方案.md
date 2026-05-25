# iOS 26 导航栏统一与异形底栏状态 / 待验收清单

> 更新时间：2026-05-25
> 范围：仅 iOS 客户端（`ItemManager` 工程）；不涉及鸿蒙 / Android 端口
> 文档状态：**当前状态核对 + 待验收清单**，不再作为“尚未落地”的执行计划
> 本轮代码动作：未修改 Swift，未删除 `temp/`
> 正式参考：`docs/少女衣橱主题皮肤重构方案.md`、`docs/SWIFTUI_NAVIGATION_BAR_BEST_PRACTICES.md`、`docs/TabView_Best_Practices.md`、`docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md`

## 0. 读者须知

本文按 2026-05-25 对当前源码的静态核对结果校正。旧文里同时出现“计划”“已完成”“P5-P7 已落地扩展”，容易误导后续执行；现在统一改为：已落地项写成事实，未闭环项写成验收或残留。

`temp/_harness/EXEC_PLAN_IOS26_UNIFY.md`、`temp/_harness/ACCEPT_PLAN_IOS26_UNIFY.md`、`temp/_harness/ACCEPT_PLAN.md` 只能作为历史参考和删除 `temp/` 前的核对输入，不能再作为唯一上游或唯一验收手册。正式验收点保留在本文；主题复刻通用规则以 `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md` 为准。

旧文 P5-P7 记录的是主题皮肤扩展到核心页面、VIP 等页面的历史落地范围，不属于 iOS26 unify 主线验收。后续如需保留这些记录，应迁入 ThemeSkin 专门文档，而不是继续混在本文件里。

## 1. 总体状态

| 阶段 | 当前状态 | 已核对事实 | 未闭环项 |
|---|---|---|---|
| P1 死代码清理 / 统一到 `LegacyTabView` | **大部分已落地** | `MainTabView.body` 当前单分支进入 `LegacyTabView`；`ModernTabView`、`applyTabBarMinimizeBehavior`、`applySearchToolbarBehavior`、`diamondOrbitOverlay` 未在 `ItemManager/` 搜到；`ItemManagerApp.swift` 未见 iOS26 `UITabBar.appearance` 配置；`SmallWorldMenuOverlay` 已退成 guide fallback helper | 未跑 build / 模拟器 / 真机；`BottomAccessoryCatDiamondOrbit*` 与 `TabBarItemAnchorResolver` 原生 tabbar probe 仍以 deprecated 形式保留；`MainTabView.swift` 还有一批 `@available(iOS 18.0, *)` wrapper，是否删除需单独评估 |
| P2 顶部导航栏紧凑化 | **部分已落地** | `HomeThemeSkinChromeStyle` 圆角 / 阴影已收紧；`HomeThemeSkinToolbarShell` 默认 padding 已改小且无 OS 分支；`HomeThemeSkinToolbarIconShell` 默认 24pt / 图标 12pt；`WardrobeTopBarMetrics` 已成为衣橱顶栏主要尺寸来源；普通 action 图标大多已收至 12/15pt，通知角标为 7pt、偏移 6/-5 | 搜索态 `HomeThemeSkinToolbarShell` 仍显式传 `horizontalPadding: 10` / `verticalPadding: 7`；fallback 背景描边 / 装饰圆点未完全对齐旧计划目标值；仍需 iPhone SE / iPhone 16 Pro / iPad 截图确认高度、拥挤和菜单打开状态 |
| P3 底部导航栏异形 + 主题相关 | **部分已落地** | 已新增 `ThemeSkinTabBarShapeStyle`，支持 default capsule、`sky_concert` stage path、`swan_dream` uneven rectangle；`ThemeSkinTabBarBackdrop` 已按 shape style 计算高度与横向 padding；`swan_dream` 月环已使用 `swan_dream_decor_crescent_planet_sparkle`；天空音乐会已使用 namespace 前缀素材名 | 实现形态是 enum shape style，不是旧计划里的 protocol/factory；`LegacyCustomTabBarLayout.barHeight`、`MainTabView.customTabBar` frame、`SmallWorldMenuOverlay.buildFallbackFrame` 仍固定 56pt，需视觉确认 62/66pt 主题底栏是否被布局 / 引导 / 悬浮避让影响；A-O 主题验收和 Asset Catalog missing 警告未跑 |
| P4 House 长按轮盘菜单主题色 | **历史计划已失效** | 当前 `SmallWorldMenuOverlay` 注释明确 House long-press quick menu 已退役；代码里未搜到 `WheelMenuView` / `WheelBackground` | 不作为当前待实现项。若未来恢复 House 长按轮盘，再单独开新需求评估主题色注入 |

## 2. 文件级状态

### 2.1 `MainTabView.swift`

- 当前入口：`MainTabView.body` 直接创建 `LegacyTabView`，并保留 `OpeningVideoOverlay`、`noticePopup()`、`withMagicTaskCompletions()` 修饰链。
- `LegacyTabView` 是现役底部导航容器，底栏仍通过 `LegacyCustomTabBarLayout.barHeight = 56` 控制主体高度。
- 主题底栏背景已接 `ThemeSkinTabBarBackdrop`，但外层 HStack frame 仍固定 56pt；这与 `sky_concert = 62`、`swan_dream = 66` 的 shape height 存在待验收风险。
- `WardrobeTabContent`、`SmallWorldTabContent`、`MeTabContent` 等内容 wrapper 仍在文件内；它们不等同于已删除的 `ModernTabView`，不要把它们误判成 iOS26 原生 tabbar 分支。

### 2.2 `ItemManagerApp.swift`

- 当前 `AppDelegate` 未见 iOS26 `UITabBar.appearance` 设置。
- 仍保留后台任务、内存警告、启动流等 App 级逻辑；本轮不改。

### 2.3 `SmallWorldMenuOverlay.swift`

- 当前文件只保留 `SmallWorldMenuOverlay.buildFallbackFrame(...)`，供 guide fallback 取 House 底栏段位置。
- 原 House 长按 quick menu 已退役，因此旧计划里的 `menuExpansionDirection`、轮盘菜单主题化不再适用。
- fallback 几何已按 `LegacyTabView` 全宽 16pt horizontal padding + 4 槽位计算，但高度仍固定 56pt；如果主题底栏 62/66pt 影响引导高亮，需要后续联动 `ThemeSkinTabBarShapeStyle` 或统一底栏 layout token。

### 2.4 `TabBarItemAnchorResolver.swift` 与 `BottomAccessoryCatDiamondOrbit*`

- `TabBarItemAnchorResolver.mainTabCount = 4` 是当前 Legacy 自绘底栏槽位数量来源。
- 原生 `UITabBar` probe 相关方法已标 `@available(*, deprecated, message: "旧原生底栏已退役...")`，仍作为调试 / fallback 残留存在。
- `BottomAccessoryCatDiamondOrbitConfig`、`BottomAccessoryCatDiamondOrbitViewModel`、`BottomAccessoryCatDiamondOrbitView` 也已 deprecated，但未删除。下一轮若删除，需要确认 `PetOverlayView`、新手引导、历史文档引用不会断。

### 2.5 顶栏主题组件

- `HomeThemeSkinComponents.swift` 已移除“仅 iOS26 phone 才紧凑”的分支，当前 padding / icon size 由传入值或默认值直接决定。
- `HomeView.swift` 已定义 `WardrobeTopBarMetrics`，经典 / 时尚衣橱顶栏大多使用同一组尺寸；主题态经典左侧双标签有固定宽度，避免被右侧 action group 或系统 `Menu` 打开状态挤压。
- `WardrobeNavigationStyle.swift` 的 `WardrobeFashionTabSwitcher` 已复用 `WardrobeTopBarMetrics`。
- 搜索态主题输入框仍有 `10 / 7` 的硬编码 padding，属于 P2 残留。

### 2.6 底栏主题组件

- `ThemeSkinTabBarShapes.swift` 已存在，当前实现名是 `ThemeSkinTabBarShapeStyle`，不是旧计划里的 `ThemeSkinTabBarShape` protocol。
- `TabBarThemeSkinComponents.swift` 已使用 shape style 做 clip、fallback stroke、height、horizontal padding。
- `SkyConcertThemeSkinComponents.swift` 已使用 `sky_concert_decor_*` / `swan_dream_decor_*` 形式的素材名；部分字符串用拼接方式规避短名误匹配，不应按缺失处理。

## 3. `temp/_harness` 口径

以下引用只保留为历史参考：

- `temp/_harness/EXEC_PLAN_IOS26_UNIFY.md`
- `temp/_harness/ACCEPT_PLAN_IOS26_UNIFY.md`
- `temp/_harness/MANIFEST.yaml`
- `temp/_harness/ACCEPT_PLAN.md`
- `temp/design/IMG_7936.png`、`IMG_7937.png`、`IMG_8204.PNG`、`IMG_8208.PNG`、`IMG_8211.PNG`

正式执行 / 验收口径：

- iOS26 unify 当前状态：以本文为准。
- ThemeSkin 通用架构、slot、素材命名和复刻规则：以 `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md` 与主题皮肤正式文档为准。
- A-O 主题视觉验收点：可从历史 harness 迁入正式 docs 后执行；迁移完成前允许对照 `temp/_harness/ACCEPT_PLAN.md`，但不得把 `temp/_harness` 写成永久 source of truth。

本轮明确不删除 `temp/`。

## 4. 待验收清单

### 4.1 静态核对

- [x] `ModernTabView` 在 `ItemManager/` 当前未检出。
- [x] `applyTabBarMinimizeBehavior` / `applySearchToolbarBehavior` 在 `ItemManager/` 当前未检出。
- [x] `diamondOrbitOverlay` 在 `ItemManager/` 当前未检出。
- [x] `ItemManagerApp.swift` 未见 iOS26 `UITabBar.appearance` 配置。
- [x] `SmallWorldMenuOverlay` 已退为 guide fallback helper。
- [ ] 复查 `@available(iOS 18.0, *)` wrappers 是否仍有存在价值；不要与 iOS26 原生 tabbar 分支混淆。
- [ ] 决定 deprecated `BottomAccessoryCatDiamondOrbit*` / `TabBarItemAnchorResolver` 原生 probe 的删除窗口。
- [ ] 复查 `git grep -n "iOS 26\|@available(iOS 26\|#available(iOS 26"` 的剩余结果：当前仍有日历、设置、空间背景、来财等非 tabbar/chrome 场景，不能再沿用旧文“只剩 HomeView 两条”的判断。

### 4.2 构建与资源

- [ ] 运行 `xcodebuild -scheme ItemManager -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -quiet build`，记录通过 / 失败和验证边界。
- [ ] 检查 Asset Catalog 是否有 `ThemeSkin/sky_concert`、`ThemeSkin/swan_dream` missing imageset 或未入 target 警告。
- [ ] 如构建失败，先归因是文档外已有改动、资源缺失、还是 iOS26 unify 残留。

### 4.3 模拟器截图验收

- [ ] iPhone 16 Pro：默认皮肤、`theme_skin.sky_concert`、`theme_skin.swan_dream` 各截衣橱主页、搜索态、排序 / 筛选 / 更多菜单打开态。
- [ ] iPhone SE 或小屏：确认顶栏双标签、右侧 action group、搜索输入框不拥挤、不截断。
- [ ] iPad：确认 iPad 也走 Legacy 自绘底栏，底栏位置 / 宽度 / safe area 与 iPhone 规则一致。
- [ ] House / 新手引导：确认 House tab 高亮框与 `SmallWorldMenuOverlay.buildFallbackFrame` 对齐，尤其是主题底栏 62/66pt 时不偏高、不偏低。
- [ ] 悬浮宠物 / RewardBubble / 其它底部浮层：确认 `customBottomNavigationAvoidanceInset` 仍能避开主题异形底栏。

### 4.4 真机验收

- [ ] iPhone 真机：确认 Dynamic Island / safe area / 底部 home indicator 下主题底栏无遮挡。
- [ ] iPad 真机或模拟器替代：确认横屏 / 分屏下顶栏和底栏不漂移。
- [ ] 若可用 iOS26 runtime，至少跑一轮 iOS26；若当前机器没有 iOS26 runtime，必须在结果中写明“仅 iOS18/当前可用 runtime 验收”。

### 4.5 主题 A-O 验收

- [ ] 天空音乐会 A-O 视觉验收：衣橱主页、统计、House、财富、穿搭手帐等基准版式不变，颜色 / 装饰跟随主题。
- [ ] 天鹅入梦 A-O 视觉验收：同上。
- [ ] 连续切换默认 / 天空 / 天鹅 5 次，无跨主题贴纸混用、旧主题残影、默认皮肤装饰泄漏。
- [ ] 关闭相关 slot 后，顶部栏 / 底栏 / 图标按钮能回退默认样式。

## 5. 当前阻塞 / 风险

1. 尚未跑本轮 `xcodebuild`、模拟器截图、真机验收；本文只代表静态源码核对。
2. P2 搜索态 padding 与部分 fallback 装饰度量未完全收敛，可能仍导致截图中的大顶栏感。
3. P3 主题底栏 shape 高度已经是 62/66pt，但 Legacy 外层 layout / guide fallback / bottom avoidance 仍按 56pt 计算，需要视觉确认或后续代码统一。
4. Deprecated 原生 tabbar probe 与 BottomAccessoryCatDiamondOrbit 仍保留，不能把 P1 写成“完全无残留”。
5. `temp/_harness` 里的 iOS26 unify 计划 / 验收稿尚未迁移完成；删除 `temp/` 前要确保正式 docs 已覆盖仍有效的检查点。

## 6. 本轮不在范围

- 不改 Swift。
- 不删除 `temp/`。
- 不改 `ThemeSkinSlot.rawValue`、`ThemeSkinManager` 持久化 key、历史主题商品静态定义。
- 不处理鸿蒙 / Android。
- 不恢复 House 长按轮盘菜单。
