# 主题皮肤详情页 · 预览与组件开关 UX 最佳实践

> 范围：`ItemManager/Views/ThemeSkin/ThemeSkinDetailView.swift`、`ThemeSkinSlotToggleSection.swift`、`ThemeSkinSharedComponents.swift` 的「主题预览 / 实时组件预览 / 组件开关」三段。
> 状态：**仅调研归档，未改任何代码**。后续若动手实现，请遵循本文档。
> 与 Harness 的关系：本文档**不动** `temp/_harness/`、`MANIFEST.yaml`、`ThemeSkinSlot.rawValue`、`ThemeSkinManager` 行为，也**不增减 18 个 slot**。Codex 当前在执行的 `EXEC_PLAN.md` / `EXEC_PLAN_IOS26_UNIFY.md` 不受影响 —— 本文档只覆盖详情页的视觉层 / 信息架构。

## 1. 现状问题（2026-04-29 截图复盘）

| 现象 | 位置 | 用户感受 |
|---|---|---|
| "主题预览"卡片只是一张静态 hero 图 + 兜底"sparkles + 文字"占位 | `ThemeSkinDetailView.previewCard` / `heroFallback` | "我看到的是宣传画，不知道用上之后真长什么样" |
| "实时组件预览"卡片里"卡片 / 按钮 / 空状态"只有三个文字标签，没有真组件 | `ThemeSkinDetailView.livePreviewCard` | 文字无法承载视觉效果，名字 ≠ 样子 |
| `ThemeSkinSlotToggleSection` 18 个 slot 的开关只有 `displayName` + `rawValue` 两行字 | `ThemeSkinSlotToggleSection.slotGroupCard` | 用户必须**记住**「topBarMain 是顶栏容器、tabBarItem 是底栏单项」才能用，违反"识别优于回忆"原则 |
| 切开关时主预览没有任何反馈 | 同上 | 不知道这一拨开关到底改了 UI 的哪里 |

> **核心矛盾**：18 个 slot 是工程语言（按渲染入口拆的），不是用户语言（按视觉部位组织的）。用户脑子里只有"顶栏 / 底栏 / 卡片 / 按钮 / 空状态"五大块。

## 2. 调研到的成熟范式

| 范式 | 出处 | 可借鉴到哪里 |
|---|---|---|
| **Live 设备框预览**：mockup 手机壳里实时渲染当前主题 | iOS 壁纸选择器、Apple Watch 表盘编辑器、App Store Preview 模板（Figma iOS 26 模板）| 取代当前 hero 静态图，做成"迷你 App 内嵌帧" |
| **Live 反馈，所见即所得**：toggle / 滑动一改，预览毫秒级回应 | SwiftUI Live Preview、Telegram 主题编辑器预览面板、Discord 外观设置 | 切换 slot 开关时主预览同步刷新 |
| **行内缩略图**（Inline Thumbnail Row）：每个开关左侧放一张当前 slot 的真实迷你渲染 | Pages / Keynote 样式选择器、Notion 主题选择、UI Patterns "Thumbnail" pattern | 把 `ThemeSkinSlotToggleSection` 每行的 SF Symbol 换成真组件缩略图 |
| **图解（Annotated Hotspot Map）**：一张主预览图上用引线 + 数字标 5–8 个部位，下面列表呼应 | Apple 教程页、Figma "Variable Visualizer"、产品说明书 | 给"组件开关"加一张总览图解，建立"部位 ↔ slot 名"的视觉锚 |
| **双向锚点（Spatial Anchoring）**：点开关 → 预览滚动并高亮该部位；点预览 → 列表滚动到该 slot | Figma 选层联动画布、Xcode 视图调试器 | V3 阶段，最强用户体验 |
| **A / B 对照（默认 vs 主题）**：左右滑或前后切换 | iOS 字体大小预览、watchOS 表盘对比 | 在主预览顶部加 "默认 ⇄ 主题" 切换胶囊 |
| **分组 + 释义文案**（Progressive Disclosure）：分组卡 + 一句话副标题 | Material 1 Settings、NN/G 表单原则、当前已实现 | 当前已具雏形，保留并补强 |

## 3. 五条设计原则

1. **预览即真相，不是宣传画**。详情页主预览必须是 App 的真组件，不是 PSD 截图，更不是 SF Symbol 占位。
2. **识别优于回忆**。不要让用户记 18 个英文 slot key；每行都要有"看一眼就懂"的视觉锚（迷你渲染 / 缩略图 / 引线编号）。
3. **Live 反馈**。任何开关、任何价格刷新都必须 < 200ms 在预览里看到结果，否则用户会以为开关没生效。
4. **用户语言分组**。已有的 5 组（顶部与搜索 / 底部导航 / 卡片与列表 / 按钮与控件 / 面板与空状态）是对的，继续坚持；slot 的工程命名仍保留为副标题。
5. **降级路径不能丢**。`ThemeSkinManager` 已强制不允许跨主题混搭、缺图回退到程序化绘制 —— 预览也必须遵守同一规则，**不能直接拿主图渲染兜底**，否则用户买完发现"实物不符"。

## 4. 推荐方案（按落地成本分三阶段）

### V1 · 不动架构，只补视觉锚（最小改动，1–2 天）

目标：解决"用户不知道每个开关控制什么"。**不引入新组件、不动 `ThemeSkinManager`**。

- **组件开关每行加左侧迷你缩略图**：在 `ThemeSkinSlotToggleSection.slotGroupCard` 行内，左侧放一个 `36×36` 的迷你预览，渲染该 slot 的真实当前样式。
  - 数据来源：复用 `ThemeSkinSharedComponents` 里已有的程序化绘制（带主题缺图回退）。
  - 不要用 SF Symbol。SF Symbol 只用于分组头。
  - 缺图主题保留"程序化兜底" → 这与 harness 硬约束一致。
- **主预览卡换成"迷你 App 帧"图解**：把 `previewCard.heroFallback` 换成一张垂直堆叠的迷你帧：
  ```
  [顶栏样例] → 编号 ①
  [统计卡 / 商品卡 / 设置豆腐块 横向缩略] → ②③④
  [主按钮 + 圆形图标按钮 + 折扣徽标] → ⑤⑥⑦
  [底栏样例] → ⑧
  ```
  每块右侧用细引线和编号标记，编号与下方"组件开关"组的副标题对齐。
- **顶部加"默认 ⇄ 主题"对照胶囊**：用 `Picker(.segmented)` 或 `Capsule` 切换；切到"默认"时主预览渲染 App 默认样式，切到"主题"时渲染当前 slot 启用状态的合成结果。

> 完全不需要新增 slot、新增 manifest 字段、新增素材。

### V2 · Live 互动预览（中改动，3–5 天）

目标：解决"看不到效果"。

- **主预览改为可滚动的真实页面缩影**：在一个 `iPhone 帧` 形状（圆角矩形 + 安全区刘海）里，用 `ScrollView` 装载一个微型版的"我界面 / 衣橱主页 / 设置页"。可上下滑、可切 Tab，但所有交互"假按"（disabled，避免误操作）。
  - 每次 `themeSkinManager.setSlot(_:enabled:)` 调用后，预览通过 `@Published` 自然刷新（已有 `ObservableObject`，直接用）。
  - 把 `LivePreviewCard` 撤掉，合并到主预览里，避免两块"预览"用户分不清。
- **预览页面切换器**：在迷你机身下方放 3 个 segment："我界面 / 衣橱 / 设置"，对应当前主题影响最重的三个场景。
- **A / B 横向滑动对比**：左右滑动迷你机身切换"默认 / 主题"，参照 watchOS 表盘对比手势。

### V3 · 双向锚点（高改动，1 周+）

目标：把"我开了第几个开关"和"画面里哪一块变了"用空间联系起来。

- **toggle → 预览**：点开关行 → 主预览自动滚动到该部位 + 用 `ThemeSkinIconBadge` 风格的 highlight pulse 闪两次。
- **预览 → toggle**：点预览里的某块（disabled 的 `Button` 改成专门的 hotspot tap 区） → 列表自动滚动到对应 slot 行 + highlight。
  - 注意：项目记忆 `project_highlight_tap_todo.md` 记录过 `onHighlightTap` 在空间手帐 Step3/4 不生效，**这里不要复用那个方案**，改用 `ScrollViewReader` + 显式 `id` + `withAnimation` 的传统 SwiftUI 写法。
- **slot ↔ 部位映射表**：用一个 `[ThemeSkinSlot: PreviewAnchor]` 静态表维护 18 个 slot 的目标锚点；不要让映射散落在视图里。

## 5. 实现守则（写代码时不要踩的坑）

- 不要把 V1 缩略图渲染成"模拟图标 + 文字"，那只是把 SF Symbol 换皮。**必须复用真渲染组件**（`ThemeSkinPrimaryButtonStyle`、`ThemeSkinSectionCardContainer`、`statsCard` 真背景），缩小 + 禁用交互。
- 不要在迷你预览里塞过多内容。**一屏一个核心场景**，太密反而看不清。
- 不要用 `Image(uiImage: UIImage(named: "preview_store_hero"))` 这种静态图当主预览。商店列表页可以用，详情页必须是真组件。
- 不要把开关改成"批量切换组"。组级别只允许"折叠 / 展开"，**不要做组级别 master switch** —— 主题包内 slot 互相独立、不应被 UI 强行联动（项目硬约束）。
- 不要破坏 `themeSkinManager.isSlotEnabled` 的语义。预览只读取，不要写新 state。
- 不要把"使用中 / 已拥有 / 未购买"那个 Capsule 换成 `Tag` 之类全局组件 —— 这个状态有产品语义，跟 `ThemeSkinManager.activateTheme` 的返回值耦合，改样式可以，改控件位置要先和产品对齐。
- 文件 ≤ 500 行（项目硬约束）。如果 V2/V3 让 `ThemeSkinDetailView.swift` 超线，拆成 `ThemeSkinDetailPreviewFrame.swift` / `ThemeSkinDetailMiniScreens.swift` 等子视图。

## 6. 验收清单（V1 落地时直接套）

- [ ] 18 个 slot 行都有非 SF-Symbol 的真渲染缩略图，缺图主题走程序化兜底，不出现透明占位。
- [ ] 主预览不再是"宣传画 + sparkles"，至少替换为分块图解 + 编号 ↔ 分组对齐。
- [ ] "默认 ⇄ 主题" 对照胶囊可点，切换 < 200ms 出结果。
- [ ] 切任意一个 slot 开关，主预览中该部位的视觉立即变化（V2 起）。
- [ ] 离线/缺图状态：用程序化绘制兜底而不是空白。
- [ ] 暗黑模式 + iPad split view + 动态字体 XXL：版式不破。
- [ ] VoiceOver：每个开关 + 缩略图组合朗读为「{displayName}，{slot.rawValue}，{已启用/已停用}」一条，不要拆成两条。

## 7. 与 Harness 的边界（明确不冲突）

| Harness 关心 | 本文档关心 | 是否会撞 |
|---|---|---|
| `MANIFEST.yaml` 的 imageset / sticker_bbox / namespace | 详情页 SwiftUI 视图布局 | 否，文件不重叠 |
| `temp/_harness/EXEC_PLAN.md` 让 Codex 跑模拟器、写 Assets.xcassets | 详情页 UX 改造（V1 视觉锚 / V2 Live 预览 / V3 双向锚点）| 否，触达不同文件 |
| `ThemeSkinSlot` 18 个 case + 顺序 | 也只读取，不增减 | 否 |
| 程序化绘制兜底 | 视觉锚里复用程序化绘制 | 否，反而强依赖它 |
| `ThemeSkinManager` 的 `isSlotEnabled` / `activateTheme` 等 API | 只读，不改 | 否 |

> **如果 Codex 当前 PR 还在跑 `EXEC_PLAN.md` / `EXEC_PLAN_IOS26_UNIFY.md`，本文档对应的实现 PR 应排在其后**（避免合并冲突 `ThemeSkinDetailView.swift`）。先等天空音乐会 / 天鹅入梦验收 PASS、git tag 打完，再开本文档对应的 UX 改造分支。

## 8. 参考资料

- [Human Interface Guidelines | Apple Developer](https://developer.apple.com/design/human-interface-guidelines/)
- [iOS and iPadOS 26 · Figma 模板（含设备框 / 预览样例）](https://www.figma.com/community/file/1527721578857867021/ios-and-ipados-26)
- [iOS 26 Design Guidelines: Illustrated Patterns + free templates · learnui.design](https://www.learnui.design/blog/ios-design-guidelines-templates.html)
- [Telegram · Creating Custom Cloud Themes](https://core.telegram.org/themes)
- [How to Change Discord Color Themes and Customize Appearance Settings](https://support.discord.com/hc/en-us/articles/207260127-How-to-Change-Discord-Color-Themes-and-Customize-Appearance-Settings)
- [Settings design pattern · ui-patterns.com](https://ui-patterns.com/patterns/settings)
- [Settings · Material Design 1 Patterns](https://m1.material.io/patterns/settings.html)
- [Few Guesses, More Success: 4 Principles to Reduce Cognitive Load · NN/G](https://www.nngroup.com/articles/4-principles-reduce-cognitive-load/)
- [Thumbnail design pattern · ui-patterns.com](https://ui-patterns.com/patterns/Thumbnail)
- [Variable Visualizer (Design System Token Variables Management) · Figma Community](https://www.figma.com/community/plugin/1457362132545070106/variable-visualizer-design-system-token-variables-management)
- [Previewing your app's interface in Xcode · Apple Developer](https://developer.apple.com/documentation/xcode/previewing-your-apps-interface-in-xcode)

## 9. 项目内联的相关文件（实施时的入口）

- 详情页：`ItemManager/Views/ThemeSkin/ThemeSkinDetailView.swift`
- 开关组：`ItemManager/Views/ThemeSkin/ThemeSkinSlotToggleSection.swift`
- 共享卡片 / 徽标 / 主按钮样式：`ItemManager/Views/ThemeSkin/ThemeSkinSharedComponents.swift`
- 真组件渲染（V1/V2 缩略图 / 迷你帧的素材源）：`ItemManager/Views/ThemeSkin/HomeThemeSkinComponents.swift`、`TabBarThemeSkinComponents.swift`、`WardrobeThemeSkinComponents.swift`、`SkyConcertThemeSkinComponents.swift`
- Slot 枚举与 `displayName`（不要改）：`ItemManager/Services/ThemeSkin/ThemeSkinModels.swift:3`
- Manager（只读 API）：`ThemeSkinManager.shared.isSlotEnabled / setSlot / isPurchased / isActiveTheme / priceQuote`
- Harness 入口（**实施时一律不改**）：`temp/_harness/README.md`、`MANIFEST.yaml`、`EXEC_PLAN.md`、`EXEC_PLAN_IOS26_UNIFY.md`
