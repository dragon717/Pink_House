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

调整对象集中在 `HomeThemeSkinComponents.swift` 与 `HomeView.swift` 顶栏按钮字号，不动逻辑。

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
