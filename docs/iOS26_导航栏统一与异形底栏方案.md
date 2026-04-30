# iOS 26 导航栏统一与异形底栏方案

> 更新时间：2026-04-28
> 范围：仅 iOS 客户端（`ItemManager` 工程）；不涉及鸿蒙 / Android 端口
> 状态：**计划**（尚未落地代码）
> 关联文档：`docs/少女衣橱主题皮肤重构方案.md`、`docs/SWIFTUI_NAVIGATION_BAR_BEST_PRACTICES.md`、`docs/TabView_Best_Practices.md`、`temp/_harness/MANIFEST.yaml`

## 0. 背景与目标

### 产品诉求

1. **iOS 26 直接复用 iOS 18 自定义组件**：不再为 iOS 26 维护一份"原生 `TabView` + Liquid Glass + searchToolbarBehavior" 的并行实现；两个版本共用同一套自绘容器。
2. **顶部导航栏小一些、精致优雅些**：当前主题皮肤态下顶栏胶囊偏大、阴影偏重、图标偏粗。
3. **底部导航栏自定义 + 异形 + 主题相关**：当前 `swan_dream` 已是 `UnevenRoundedRectangle` 异形，其它主题仍是 `Capsule()`。每个主题应有自己的底栏剪影。
4. **下拉菜单**：维持 SwiftUI `Menu` 系统行为，仅触发标签接管主题；轮盘菜单（按住 House Tab 弹出）注入主题色。

### 工程目标

- 删除已退役的 `ModernTabView` + 一族仅供其使用的 iOS 26 专属 helper，让 `MainTabView.body` 单分支落到 `LegacyTabView`。
- 把"按 OS 紧凑"逻辑下线，紧凑度改为按主题皮肤态恒定生效。
- 维持 iOS 18 最低支持线、维持 `ThemeSkinSlot` rawValue / 持久化 key / `历史主题商品静态定义` 字段不变。

---

## 1. 现状盘点

### 1.1 已经完成（不要重做）

| 项 | 位置 | 备注 |
|---|---|---|
| `MainTabView.body` 顶层分发统一到 `LegacyTabView` | `ItemManager/Views/MainTabView.swift:1537-1582` | iOS 26 / iOS 18-25 都进 `LegacyTabView`，注释已写明原因 |
| `LegacyTabView.customTabBar` 底栏自绘胶囊 | `ItemManager/Views/MainTabView.swift:859-924` | 已接 `ThemeSkinTabBarBackdrop` 与 `ThemeSkinLegacyTabLabel` |
| 主题皮肤运行时容器 | `ItemManager/Views/ThemeSkin/*.swift` | 顶栏 / 底栏 / 卡片 / 装饰层均已落地，能跑兜底 |

### 1.2 仍有问题 / 残留

| 类别 | 位置 | 状态 |
|---|---|---|
| `ModernTabView` 整体 | `MainTabView.swift:48-495` | 自统一到 `LegacyTabView` 后无人调，~450 行死代码 |
| `applyTabBarMinimizeBehavior` / `applySearchToolbarBehavior` View 扩展 | `MainTabView.swift:27-46` | 仅 `ModernTabView` 调用 |
| `supportsBottomAccessoryCat` / `diamondOrbitLayout` / `diamondOrbitOverlay` | `MainTabView.swift:158-167, 258-264, 441-494` | 仅 `ModernTabView` 用；`BottomAccessoryCatDiamondOrbitView` / `...ViewModel` / `TabBarItemAnchorResolver` iOS 26 probe 同链路 |
| `AppDelegate` iOS 26 设 `UITabBar.appearance` | `ItemManager/ItemManagerApp.swift:23-33` | TabBar 已自绘，原生 appearance 不再生效 |
| `SmallWorldMenuOverlay.menuExpansionDirection` iPad iOS 26 朝下 | `ItemManager/Views/SmallWorldMenuOverlay.swift:100-108` | iPad 也走 LegacyTabView，方向逻辑已无依据 |
| `SmallWorldMenuOverlay.buildFallbackFrame` iOS 26 偏左 fallback | `SmallWorldMenuOverlay.swift:308-339` | 按"Liquid Glass tab bar 偏左 0.05W、宽 0.74W"算的坐标，与现役全宽胶囊不符 |
| `HomeThemeSkinToolbarShell.shouldUseCompactChrome` 仅 iOS 26 phone | `ItemManager/Views/ThemeSkin/HomeThemeSkinComponents.swift:113-129, 199-223` | 双系统视觉应一致，紧凑度不该按 OS 分 |
| `SkyConcertThemeSkin.tabBarPlacements` 引用废弃装饰名 | `ItemManager/Views/ThemeSkin/SkyConcertThemeSkinComponents.swift` | 需对一遍 manifest 新约定（`sky_concert_decor_<basename>`） |
| `HomeView.swift:50, 570` 切换 SF Symbol | `HomeView.swift` | **合理保留**（SF Symbol 可用性判断，与 chrome 无关） |

> 自检命令：
>
> ```bash
> git grep -n "iOS 26\|@available(iOS 26\|#available(iOS 26" ItemManager/Views ItemManager/ItemManagerApp.swift ItemManager/Services/TabBarItemAnchorResolver.swift
> ```
>
> 计划 P1 落地后这条命令应只剩 `HomeView.swift:50` 与 `HomeView.swift:570` 两条 SF Symbol fallback。

---

## 2. 分阶段执行计划

四个阶段串行；P1 先做（清地基），P2 / P3 可并行，P4 可选。

### P1 — 死代码清理（统一到 `LegacyTabView` 这一条路径）

| 动作 | 文件 | 处理 |
|---|---|---|
| 删 `ModernTabView` 全体 | `MainTabView.swift:48-495` | 整段删除，约 -450 行 |
| 删 `applyTabBarMinimizeBehavior` / `applySearchToolbarBehavior` View 扩展 | `MainTabView.swift:27-46` | 整段删除 |
| 折叠 `MainTabView.body` 双分支 | `MainTabView.swift:1537-1582` | 单分支 `LegacyTabView`，保留 `OpeningVideoOverlay` / `noticePopup` / `withMagicTaskCompletions` 修饰链 |
| 删 `AppDelegate` iOS 26 `UITabBar.appearance` 配置 | `ItemManagerApp.swift:23-33` | 整段删除（自绘底栏接管后无效） |
| `WardrobeTabContent` / `SmallWorldTabContent` / `MeTabContent` / `SearchContainerView` / `SmallWorldContainerView` 的 `@available(iOS 18.0, *)` 标注 | `MainTabView.swift:498-720` | 工程最低支持已 ≥ iOS 18，标注可去；调用方若仅 `ModernTabView`，结构体一并删 |
| 简化 `SmallWorldMenuOverlay.menuExpansionDirection` | `SmallWorldMenuOverlay.swift:100-108` | 直接 `return .upward` |
| 重写 `SmallWorldMenuOverlay.buildFallbackFrame` | `SmallWorldMenuOverlay.swift:308-339` | 按 LegacyTabView 几何（横向 padding 16、`safeAreaBottom`、56pt 主体高）算单一 fallback；`isIPad` 仍保留（用于横向居中） |
| 标记 `BottomAccessoryCatDiamondOrbitView*` / `TabBarItemAnchorResolver` iOS 26 platter probe 为 `@available(*, deprecated)` | `Views/Pet/Components/BottomAccessoryCatDiamondOrbit*`、`Services/TabBarItemAnchorResolver.swift` | 暂不删（避免连带改动 PetOverlayView 行为）；下个 cycle 评估归并到 `PetOverlayView` |

**风险点**

- `ModernTabView` 删除前先 `git grep "ModernTabView\|applyTabBarMinimizeBehavior\|applySearchToolbarBehavior\|diamondOrbitOverlay"`，确认没有 widget / deeplink / 单元测试在引用；`WardrobeTabContent` 等子视图若被 widget extension 调用，结构体保留但去掉 `@available` 即可。
- iPad iOS 26 此前走"顶部 floating pill"路径的体验会回到 `LegacyTabView` 的底部胶囊，这是用户期望（"复用一样的"），但需在 P1 验收里截 iPad 模拟器图归档。

### P2 — 顶部导航栏紧凑化（"小一些，精致优雅"）

调整对象集中在 `HomeThemeSkinComponents.swift`、`HomeView.swift` 和 `WardrobeNavigationStyle.swift` 顶栏视觉度量，不动导航逻辑。

> 2026-04-29 补充：`HomeThemeSkinComponents.swift` 的默认圆角、阴影和按钮尺寸已经收紧，但非 iOS 26（iOS 17.4 / iOS 18）仍会出现截图中的大顶栏。根因不是系统版本分支，而是 `HomeView` 在实际调用 `HomeThemeSkinToolbarShell` 时仍显式传入 `horizontalPadding: 10` / `verticalPadding: 7`，同时 `tabSwitcher` 内部两个 tab 仍有 `frame(height: 44)`，两者叠加后会把主题胶囊撑到约 58pt。后续规范以 `WardrobeTopBarMetrics` 为唯一来源，视觉高度收紧，点击仍依赖系统 inline toolbar 的 44pt 可用区域。

#### 2.1 `HomeThemeSkinChromeStyle` 度量收紧

| 字段 | 当前 | 目标 |
|---|---:|---:|
| `group.cornerRadius` | 19 | 16 |
| `group.shadowRadius` | 11 | 7 |
| `segment.cornerRadius` | 21 | 17 |
| `segment.shadowRadius` | 10 | 6 |
| `searchEntry.cornerRadius` | 15 | 13 |
| `searchEntry.shadowRadius` | 8 | 5 |

#### 2.2 `HomeThemeSkinToolbarShell` 默认 padding

| 字段 | 当前 | 目标 |
|---|---:|---:|
| `horizontalPadding` 默认 | 12 | 8 |
| `verticalPadding` 默认 | 8 | 5 |
| `shouldUseCompactChrome` 整段 | 仅 iOS 26 phone 触发 | **删除**，`effective*` 直接返回原值 |

#### 2.3 `HomeThemeSkinToolbarIconShell` 默认 padding

| 字段 | 当前 | 目标 |
|---|---:|---:|
| `minWidth` / `minHeight` 默认 | 30 / 30 | 24 / 24 |
| `effectivePadding` | 6 | 3 |
| `effectiveIconSize` | 14 | 12 |
| `shouldUseCompactChrome` 整段 | 仅 iOS 26 phone 触发 | **删除** |
| 阴影 `radius: 8` | 硬编码 | 改用 `style.shadowRadius`（与 Shell 统一） |

#### 2.4 `HomeThemeSkinChromeBackground.fallbackBackground` 描边

| 字段 | 当前 | 目标 |
|---|---:|---:|
| 外环 `stroke` lineWidth | 1.1 | 0.9 |
| 内描边圈 lineWidth | 0.6 | 0.5 |
| 装饰小圆点直径（左 / 右） | 8 / 7 | 6 / 5 |
| 装饰圆点 offset (x) | -26 / +28 | -20 / +22 |

#### 2.5 `HomeView` 顶栏按钮字号

把 `sortButton` / `filterButton` / `notificationButton` / `moreMenuButton` / `addButton` / `doneEditButton` / `doneSortButton` 内 `.font(.system(size: 14))` / `.font(.system(size: 18))` 收一档：

- `size: 18` → `size: 15`（done 类按钮）
- `size: 14` → `size: 12`（普通操作按钮）
- `bell.badge` 数字 `size: 8` → `size: 7`，`offset(x: 8, y: -6)` → `offset(x: 6, y: -5)`

#### 2.6 `HomeView` / `WardrobeNavigationStyle` 衣橱主顶栏统一度量

新增 `WardrobeTopBarMetrics` 作为衣橱主顶栏单一尺寸规范：

| 字段 | 目标 |
|---|---:|
| shell horizontal / vertical padding | 8 / 4 |
| 分段视觉高度 | 32 |
| 分段间距 | 8 |
| 普通图标 / 日历图标 | 13 / 15 |
| 日历图标 frame | 20 |
| 分段文字 | 9 |

执行要求：

- `HomeView` 中所有衣橱顶栏 `HomeThemeSkinToolbarShell` 调用都使用 `WardrobeTopBarMetrics.shellHorizontalPadding` / `shellVerticalPadding`，禁止再硬编码 `10 / 7`。
- `tabSwitcher` 的两个 tab 改为 `frame(height: WardrobeTopBarMetrics.segmentVisualHeight)`，禁止再用 `frame(height: 44)` 撑大主题胶囊。
- `WardrobeFashionTabSwitcher` 复用同一组 metrics，经典/时尚导航栏不再各自维护一套尺寸。

#### 2.7 主题态经典导航左侧双标签与菜单图案层规范

> 2026-04-29 补充：截图反馈显示，主题态经典导航栏在点击排序 / 筛选 / 更多等系统 `Menu` 后，左侧双标签容易被右侧操作组或弹层视觉挤占；同时顶部装饰图案需要保留，但必须位于文字下面。

执行要求：

- 经典导航左侧仍保留「少女衣橱 / 心愿尾款」双标签，不折叠成单标签；主题态使用固定宽度的左侧分段容器，避免右侧 action group 或系统 `Menu` 打开时挤压左侧。
- 主题态左侧分段使用 `WardrobeTopBarMetrics.classicSegment*` 专用尺寸；默认皮肤继续走原有尺寸，禁止主题装饰泄漏到默认皮肤。
- 顶部栏 / 菜单触发器的主题装饰图案属于**背景纹理层**：可以保留图案氛围，但必须放在文字、图标和按钮内容下方，且不参与点击命中。
- SwiftUI 系统 `Menu` 弹层本体继续保持系统行为，不接管菜单气泡内部样式；本规范只约束菜单触发器和顶部栏主题背景层。

### P3 — 底部导航栏异形 + 主题相关

#### 3.1 抽出 `ThemeSkinTabBarShape` 协议

新增文件：`ItemManager/Views/ThemeSkin/ThemeSkinTabBarShapes.swift`

```swift
protocol ThemeSkinTabBarShape: Shape {
    var height: CGFloat { get }                  // 主体高（不含 safeAreaBottom）
    var horizontalPadding: CGFloat { get }       // 与屏幕边的留白
}

enum ThemeSkinTabBarShapeFactory {
    static func shape(for descriptor: ThemeSkinDescriptor?) -> (any ThemeSkinTabBarShape)?
}
```

| 主题 namespace | 形状提案 | 高度 | 备注 |
|---|---|---:|---|
| `sky_concert` | 顶部一道大五线谱波 + 左右两个云峰隆起；左上圆 28 / 右上圆 18（不对称舞台幕布剪影） | 62 | 透明边内放装饰 PNG |
| `swan_dream` | 保留现 `UnevenRoundedRectangle(34/30/34/24)` | 66 | 无几何变更，但内嵌月光圆改用装饰 PNG（见 3.3） |
| 默认 / 兜底 | `Capsule()` | 56 | descriptor 不在两主题时仍走默认 |

#### 3.2 `ThemeSkinTabBarBackdrop` 重构

`TabBarThemeSkinComponents.swift`：

- 把 `standardBackdrop` / `swanDreamBackdrop` 合并为单一 `themedBackdrop(shape:)`；用 `shape` 替代 `Capsule()` / `UnevenRoundedRectangle`。
- 高度计算：`(ThemeSkinTabBarShapeFactory.shape(for: descriptor)?.height ?? 58) + safeAreaBottom`，淘汰当前 `(SwanDreamThemeSkin.isSwanDream(descriptor) ? 66 : 58)` 三元判断。
- 装饰层不变，仍用 `SkyConcertDecorationLayer(placements:)`。

#### 3.3 装饰 PNG 对齐 manifest 新名

校对并修正以下文件里的 `decor_*` 引用，使其与 `temp/_harness/MANIFEST.yaml` 在上一轮（2026-04-28）确定的 `<namespace>_decor_<png_basename>` 约定一致：

- `ItemManager/Views/ThemeSkin/SkyConcertThemeSkinComponents.swift`：`tabBarPlacements` / `toolbarPlacements(for:)` 把废弃名（`decor_cherub` / `decor_violin` / `decor_cloud_left` / `decor_cloud_right` / `decor_music_note` / `decor_staff_banner`）替换为新名：

  | 旧 | 新（manifest 已收录） |
  |---|---|
  | `decor_cherub` | `sky_concert_decor_winged_unicorn_prince`（飞马王子接管"主天使位"） |
  | `decor_violin` | `sky_concert_decor_violin_cloud` |
  | `decor_cloud_left` / `decor_cloud_right` | `sky_concert_decor_whale_cloud_stars` / `sky_concert_decor_sky_balloon_doves` |
  | `decor_music_note` | `sky_concert_decor_music_scroll_clouds` |
  | `decor_staff_banner` | `sky_concert_decor_moon_star_clouds` |

- `SwanDreamThemeSkinComponents.swift`：把 `swanDreamBackdrop` 当前内嵌 `Circle()` 月光圆改为 `swan_dream_decor_crescent_planet_sparkle` 装饰位（manifest 已收录）。

#### 3.4 `LegacyTabView.customTabBar` 高度自适应

`MainTabView.swift:896` 的 `.frame(height: 56)` 改为读 `ThemeSkinTabBarShapeFactory.shape(for: descriptor)?.height ?? 56`。`bottomPadding` 仍由 `safeAreaBottom > 0 ? 2 : 4` 控制。

### P4 — 下拉菜单主题化（可选）

#### 4.1 顶栏 `Menu { ... }`（`sortButton` / `moreMenuButton`）

- 维持 SwiftUI `Menu` 系统弹出气泡；不接管气泡内部样式（私有 UIKit 不接）。
- 触发标签 `label:` **已经**包在 `HomeThemeSkinToolbarIconShell` 里（`HomeView.swift:643, 614`）。**P4 不动这一块**。

#### 4.2 `SmallWorldMenuOverlay` 轮盘菜单注入主题色

- `WheelMenuView` 增 `themedAccent: Color` 入参；
- `SmallWorldMenuOverlay` 解析 `ThemeSkinManager.shared.activeThemeDescriptor(for: .tabBarMain, state: .default)`，主题命中时 `themedAccent = TabBarThemeSkinTokens.accent(for: descriptor)`，否则 fallback 到当前 `monicaPink`；
- `WheelBackground` 内 gradient 第一段、stroke 各替换为 `themedAccent.opacity(0.15)` / `themedAccent.opacity(0.45)`。

#### 4.3 `ClothingFilterMenu` / `FavoriteMenuSettingsView`

未在本轮范围；如后续要主题化，单独提需求。

---

## 3. 验收

### 3.1 P1 验收

- [ ] `git grep -n "iOS 26\|@available(iOS 26\|#available(iOS 26" ItemManager/Views ItemManager/ItemManagerApp.swift` 仅剩 `HomeView.swift:50` / `HomeView.swift:570` 两条 SF Symbol fallback
- [ ] iOS 26 / iOS 18 模拟器（iPhone 16 Pro + iPad Pro）TabBar 视觉一致：底栏胶囊位置、宽度、装饰一致
- [ ] `ModernTabView` / `applyTabBarMinimizeBehavior` / `applySearchToolbarBehavior` / `BottomAccessoryCatDiamondOrbitConfig` 在工程中无残留 import / 调用
- [ ] House Tab 长按弹出轮盘的位置与底栏胶囊几何对齐（不再"偏左 0.05W"）

### 3.2 P2 验收

- [ ] 顶栏胶囊高度 ≈ 36-40pt（基准 `temp/design/IMG_7936.png`）
- [ ] 图标按钮直径 ≈ 26-30pt
- [ ] 胶囊阴影投影柔和（视觉判 `radius ≤ 7`）
- [ ] iPhone SE / iPhone 16 Pro / iPad 各跑一遍，三图标 + 标题不溢出

### 3.3 P3 验收

- [ ] `sky_concert` 底栏顶部有非圆角剪影（云峰 + 五线谱波）
- [ ] `swan_dream` 月环位置改用 `swan_dream_decor_crescent_planet_sparkle` 装饰 PNG，inline `Circle` 已删
- [ ] 两主题切换无 TabBar 几何错位（连续切 5 次回到默认无残影）
- [ ] `xcodebuild` Asset Catalog 无 missing imageset 警告

### 3.4 P4 验收（如做）

- [ ] 两主题激活态下，长按 House Tab 弹出的轮盘背景颜色与主题主色相符
- [ ] 主题未激活时回到 `monicaPink` 默认色

---

## 4. 不在范围内

- `temp/_harness/`（已上一轮 2026-04-28 修正完成）
- `ThemeSkinManager` 持久化逻辑、`ThemeSkinSlot.rawValue`、`历史主题商品静态定义` 字段（兼容性）
- 衣橱卡片 / 统计卡 / 设置豆腐块（`WardrobeThemeSkinComponents.swift` 不变）
- 鸿蒙 `harmony_next/` / Android `android/` 端口（独立 skill 处理）
- iOS 18 最低支持线（保持）
- `HomeView.swift:50`（`CalendarDayIcon` 的 `\(day).calendar` SF Symbol fallback）
- `HomeView.swift:570`（`doneSortButton` 的 `list.number.badge.ellipsis` SF Symbol fallback）

## 5. 执行顺序与影响面

| 阶段 | 任务 | 影响文件数 | 行数变化（估） | 依赖 |
|---|---|---:|---:|---|
| P1 | 死代码清理 | 4-5 | -1100 | 无 |
| P2 | 顶栏紧凑化 | 2 | ±60 | P1 完成 |
| P3 | 底栏异形 + 装饰名对齐 | 新 1 + 改 3 | +200 / -80 | P1 完成 |
| P4 | 轮盘菜单主题色 | 1 | +30 | 独立 |

落地节奏建议：P1 单独一组 commit；P2 / P3 各自一组 commit；P4 视余力独立 commit。所有改动留 `tag` 前缀 `theme-skin-ios26-unify-vN`，**只 tag 不 push**。

---

## 6. 关联与索引

- 上游素材：`temp/_harness/MANIFEST.yaml`、`temp/主题1/png/PENCIL_PROMPT.md`、`temp/主题2/png/PENCIL_PROMPT.md`
- 上游设计基准：`temp/design/IMG_7936.png` / `IMG_7937.png` / `IMG_8204.PNG` / `IMG_8208.PNG` / `IMG_8211.PNG`
- 已有架构文档：`docs/少女衣橱主题皮肤重构方案.md`
- 验收手册：`temp/_harness/ACCEPT_PLAN.md`（A–O 15 验收点 + 跨主题混搭抽查）
- iOS 26 TabBar 历史决策：用户记忆 `project_ios26_tabbar_positioning.md`（UITabBarButton 消失，改用 PlatterView 等分定位）—— 本方案因彻底改自绘底栏，PlatterView fallback 路径在 P1 后退役

---

## 7. P5 — 核心页面主题皮肤扩展（2026-04-28 落地）

### 7.1 范围

本阶段在不新增必需美术素材、不修改 `ThemeSkinSlot.rawValue` 与既有持久化 key 的前提下，把主题皮肤从顶部栏 / 底部栏 / 衣橱卡片扩展到核心内容页：

- 衣橱详情页：主信息、裙装信息、价格、购买信息、小金库存钱进度与主按钮。
- 我界面：魔法任务卡、非 VIP 卡、账户卡、设置豆腐块与常用设置卡。
- 平面 / 空间手帐：书架、书本封面外框、书页列表卡、选择徽标、拖拽徽标与空状态。
- 主题商店 / 主题详情：精品画廊式 Hero、当前状态、实时组件预览、购买 / 应用 CTA、分组组件开关。

### 7.2 实现原则

- 新增共享 SwiftUI 程序化容器：`ThemeSkinSectionCardContainer`、`ThemeSkinPrimaryButtonStyle`、`ThemeSkinIconBadge`、`ThemeSkinEmptyStateSurface`。
- 共享容器优先读取 `.sectionCard` / `.primaryButton` / `.iconCircleButton` / `.emptyState` 槽位；槽位关闭时回退到默认 `CardBackgroundView` 风格。
- 不新增 `MANIFEST.yaml` 必需 imageset；只复用现有主题贴纸 PNG 与程序化渐变、描边、阴影。
- 用户内容不染色：书本封面、书页截图、3D 预览只加外框 / 徽标 / 标题胶囊，不对图片内容套滤镜。
- 已激活老主题执行一次性迁移，仅补开本阶段新增核心槽位；用户后续手动关闭某槽位后不会反复强制打开。

### 7.3 验收补充

- 主题详情页必须能看到 18 个 slot，按“顶部与搜索 / 底部导航 / 卡片与列表 / 按钮与控件 / 面板与空状态”分组。
- 关闭 `.sectionCard` 后，详情页与手帐列表卡应回退默认样式；关闭 `.primaryButton` 后主按钮回退默认按钮色。
- 默认皮肤、`theme_skin.sky_concert`、`theme_skin.swan_dream` 连续切换时，不得出现跨主题贴纸混用或旧主题残影。

---

## 8. P6 — 心愿尾款 / 统计 / 梦裙日历 / 萌宠对话 / 马上来财扩展（2026-04-28 落地）

### 8.1 范围

本阶段继续沿用 P5 的共享容器与槽位策略，扩展到以下高频核心页面：

- 心愿尾款：总待付尾款卡、月 / 系列选择器、年份统计、明细 / 简略尾款行、小金库存钱按钮。
- 衣橱统计：总览、标签分类、心愿尾款统计、购买时间统计，以及统计小盒子与表头。
- 梦裙日历：最近 / 月度 / 年度卡片、事件行、弹窗分组、周标题与迷你月份卡。
- 萌宠对话：对话气泡、衣橱 / 统计内嵌卡片、快捷选项、iPad / Legacy 输入区、数钱与请签内嵌面板。
- 马上来财：请签按钮与解签卡、数钱总额卡、安财内黄金 / 白银 / 虚拟币卡、尾款小金库 Hero / 统计 / 存钱 / 空状态 / 列表行。

### 8.2 实现原则

- 新增 `ThemeSkinAdaptiveSectionCardContainer`：用于“主题启用时走主题皮肤、未启用时保留原页面 fallback 背景”的场景，尤其是萌宠对话气泡、日历主题色卡与来财毛玻璃卡。
- 继续只使用现有 18 个 slot：`.sectionCard`、`.statsCard`、`.filterChip`、`.searchBar`、`.primaryButton`、`.iconCircleButton`、`.emptyState` 等；不新增 rawValue。
- 用户内容不染色：裙装图片、日历缩略图、萌宠头像 / 表情、请签视频、数钱纸币 / 金银豆 / 虚拟币物理内容不套滤镜，只装饰外框、背景、徽标与按钮。
- 默认皮肤回退保持可读：需要保留原 `CalendarTheme` / `PetChatSkinTheme` / `.regularMaterial` 的区域使用 adaptive fallback，避免主题未启用时视觉断层。

### 8.3 验收补充

- 关闭 `.sectionCard` 后：心愿尾款行、统计卡、日历弹窗、萌宠气泡、来财小金库卡片回退默认卡片或原毛玻璃背景。
- 关闭 `.primaryButton` 后：请签 / 再请一签、萌宠内嵌按钮、尾款小金库存钱 CTA 回退默认按钮色。
- 心愿尾款与来财尾款统计金额只改变外观，不改变 `WealthSavingLedger` 计算语义。
- 萌宠对话的图片 / 视频 / 小物图标不被主题滤镜污染；只卡片壳与快捷按钮跟随主题。

---

## 9. P7 — VIP 界面与 VIP 卡片主题皮肤适配（2026-04-29 落地）

### 9.1 范围

本阶段继续复用 P5/P6 的共享主题容器，不新增必需素材、不修改 `ThemeSkinSlot.rawValue` 与 `theme_skin.owned` / `theme_skin.active_selection`：

- VIP 中心页：背景、顶部栏、权益卡、套餐卡、购买面板、CTA 与标签胶囊跟随当前激活主题；默认皮肤保留原黑玻璃 / 粉玻璃视觉。
- VIP 卡片：新增 `跟随当前主题`、`天空音乐会 VIP卡`、`天鹅入梦 VIP卡` 三种样式；旧 `blackGold` / `monicaPink` rawValue 保持不变。
- 卡片皮肤选择页：展示新增三项、主题选中描边、锁定态与主题商店引导。
- 试用弹窗与应用图标选择页：弹窗卡、说明卡、操作按钮、图标选项外壳接入主题；图标预览图不套滤镜。

### 9.2 实现原则

- `themeSkinAdaptive` 只在当前激活天空 / 天鹅主题时渲染主题 VIP 卡；无主题或对应 slot 不可用时回退莫妮卡粉。
- 固定天空 / 天鹅 VIP 卡属于对应主题商品权益；未购买时只显示锁定预览，不允许应用；如果历史存档异常持有固定主题卡但未拥有主题，实际 VIP 卡渲染回退莫妮卡粉。
- 固定主题卡只影响 `VIPCardView`；VIP 页面整体 chrome 始终跟随当前 App 激活主题，不跟随固定 VIP 卡样式跨主题混搭。
- 用户内容不染色：VIP 号码、有效期、App 图标预览只调整卡片壳、徽标、按钮与文字颜色，不做图片滤镜。

### 9.3 验收补充

- 默认皮肤：VIP 中心页维持原玻璃视觉；`跟随当前主题` 卡片回退莫妮卡粉。
- 启用 `theme_skin.sky_concert` / `theme_skin.swan_dream`：VIP 中心、试用弹窗、应用图标页、卡片选择页统一跟随主题。
- 未购买固定主题卡：卡片选择页出现锁定态，点击引导主题商店，不能持久化应用。
- 已购买固定主题卡：可应用并重启后保持；VIP 页面 chrome 仍按当前激活主题显示。
