# 仲夏物语 · 主题样式统一

> 本文回答三件事：**哪些新功能要适配**、每个功能**对应哪条现有规范**、**怎么算做完**。
> 目标是「新模块长得像这个 App 里本来就有的东西」，而不是另起一套视觉。

---

## 一、适配范围与规范对照

本次新开发的功能都在 `ItemManager/Views/Midsummer/` 与 `Models/Midsummer/` 下。
下表逐项列出**功能 → 现有主题规范**；「规范」一列指的是这个 App 里**已经在用的**东西，
不是为仲夏物语新造的。

| # | 新功能 | 形态 | 对应的现有主题规范 | 落点 |
|---|---|---|---|---|
| 1 | 品牌页顶栏 | 容器 + 图标按钮 + 新增按钮 | `ThemeSkinSlot.topBarMain` / `.topBarIconButton` / `.topBarAddButton`；容器用 `themeSkinLegibilityBackdrop` | `MidsummerBrandView` 顶栏 |
| 2 | 左侧年份栏 | 竖排筛选列表 | 与 `MultiDimensionalFilterSheet` 的筛选 chip 同构 → `ThemeSkinSlot.filterChip`；文字用 `themeSkinLegibleText(level: .chip / .inline)` | `MidsummerTheme.MidsummerYearRailContent` |
| 3 | 系列 chip 横排 | 筛选胶囊 | `ThemeSkinSlot.filterChip`（这是 App 内筛选胶囊的既有槽位） | `MidsummerSeriesChip` |
| 4 | 商品卡 / 系列卡 | 分组卡片 | `themeSkinAdaptiveSectionCard(slot: .sectionCard)` + **fallback 背景**（无皮肤时逐像素等同改前） | `MidsummerItemCard`、系列行、概览卡 |
| 5 | 规格抽屉（一键入库） | 底部升起面板 | `ThemeSkinSlot.filterSheet`——与 `MultiDimensionalFilterSheet` **同一个槽位**，两者是同一种形态 | `MidsummerSpecPanel` |
| 6 | 规格选项（缩略图 / 文字 chip） | 可多选的 chip | `ThemeSkinSlot.filterChip` | `MidsummerSpecGroupsSection` 的两种 cell |
| 7 | 数量步进器 | 分组卡片 | `themeSkinAdaptiveSectionCard(slot: .sectionCard, showsDecoration: false)` | `MidsummerSpecPanel.quantityRow` |
| 8 | 主按钮「加入衣橱」 | 主按钮 | `ThemeSkinSlot.primaryButton` + `themeSkinLegibleText(level: .badge)` | `MidsummerSpecPanel.confirmBar` |
| 9 | 关闭 ✕ / 入库图标按钮 | 圆形图标按钮 | `ThemeSkinSlot.iconCircleButton` + `themeSkinLegibleSymbol` | 抽屉关闭、`MidsummerWardrobeIconButton` |
| 10 | 空状态 | 空状态容器 | `ThemeSkinSlot.emptyState` | 品牌页空列表、规格缺省提示 |
| 11 | 上传页尺码多选 | 与 #6 同形态的 chip | 复用 `ThemeSkinSlot.filterChip`（不新增槽位） | `MidsummerContributeView.sizeChips` |

### 刻意**不**接入的部分（写下来免得下次又改回去）

- **上传页的系统 `Form` / `Section`**：分组底色由 UIKit 提供，本来就跟随系统深浅色。
  硬套 `themeSkinAdaptiveSectionCard` 只会把原生分组列表变成一层自绘卡面，
  反而和其他设置页不一致。
- **底部抽屉的容器本身**：**没有**用 `themeSkinAdaptiveSectionCard`。
  那个修饰符会把四个角都圆掉，而底部抽屉下沿必须贴着屏幕边，
  圆角会在屏幕最下方露出页底色。所以只取 `.filterSheet` 槽位的
  **深色可读性背板**（`themeSkinLegibilityBackdrop`），版式一行没动。
- **抽屉容器上的 `accessibilityIdentifier`**：容器标识会覆盖直接子元素的标识
  （`spec-confirm` 曾因此从层级里消失）。「面板是否打开」一律用叶子元素判定。

---

## 二、模块令牌：全部深浅色自适应

`MidsummerTheme` 是仲夏物语**唯一的取色入口**，视图里不许出现裸颜色。

```swift
static func adaptive(light: Color, dark: Color) -> Color   //  UIColor { traits in … }
```

用 `UIColor` 的 trait provider 而不是 `@Environment(\.colorScheme)`：
调用点（`MidsummerTheme.primaryText`）因此**一行都不用改**就获得了深色支持，
快照测试里 `ImageRenderer` 带上的 `\.colorScheme` 也能让取值正确。

| 令牌 | 用途 | 替代掉的老写法 |
|---|---|---|
| `surface` | 卡片 / 抽屉 / 行背景 | `Color.white` |
| `scrim` | 抽屉背板遮罩 | `Color.black.opacity(0.35)` |
| `subtleFill` | 未选中 chip / 待补充标签 | `Color.black.opacity(0.04~0.05)` |
| `onAccent` | 橙色按钮上的文字 | `.white` |
| `shadow` | 图标按钮投影 | `.black.opacity(0.18)` |
| `divider` | 分割线 | `Color.black.opacity(0.07)` |
| `pageBackground` / `railBackground` | 页面底 / 年份栏底 | — |
| `primaryText` / `secondaryText` | 主次文字 | — |
| `brandOrange` / `priceRed` / `orangeSurface` / `freshGreen` | 品牌色系 | — |
| `coverPlaceholderTop/Mid/Bottom` | 无图占位渐变三段 | 写死的三段粉紫渐变 |

**亮色取值与设计图逐一对齐，深色只做同色系压暗，不改版式。**

---

## 三、三条硬约束

1. **不往视图里写死颜色**，包括 `Color.white` / `Color.black.opacity(…)` 这类
   「看起来无害」的写法——它们锁死亮色皮肤，深色下会白底黑字糊在一起。
   自检：`rg -n "Color\.white|Color\.black|Color\(red:" ItemManager/Views/Midsummer`
   （应只剩 `MidsummerTheme.swift` 内部的令牌定义）。
2. **皮肤未启用时不泄漏任何装饰**。靠 `themeSkinAdaptiveSectionCard` 的
   `fallbackBackground` 分支保证：没皮肤就走我们自己的令牌底色，版式逐像素不变。
3. **槽位只挂在结构性容器上**，不往每个叶子视图上撒。
   仲夏物语一共只用了 6 个槽位（见上表），没有新增任何槽位。

---

## 四、验收

- 构建：`xcodebuild -scheme ItemManager … build` 必须为 `BUILD SUCCEEDED`。
- 快照：`MidsummerBrandPageSnapshotTests` / `MidsummerSpecPanelSnapshotTests`
  在亮色下与改前逐像素一致（深色令牌不影响亮色取值）。
- 肉眼：系统设置切深色 → 品牌页、系列页、规格抽屉、上传页都不出现
  「亮底黑字」或「白字压白底」。
- 皮肤：启用任一 ThemeSkin 主题 → 卡片、chip、主按钮、顶栏跟随主题，
  未启用时回落到仲夏自己的令牌底色。
