---
name: pink-house-theme-skin-replication-guide
description: Pink_House 主题皮肤复刻与主题扩展技能。用于接入 sky_concert/swan_dream 或新增主题、维护 temp/_harness、处理 ThemeSkinSlot/素材 fallback/placeholder 审计、把主题皮肤扩展到衣橱列表和核心 SwiftUI 页面。
---

# Pink House Theme Skin Replication Guide

在 Pink_House 里做主题复刻、主题素材接入、主题验收、主题皮肤扩展到新页面或修复主题泄漏/混搭时使用这个技能。

## 先读

1. `temp/_harness/MANIFEST.yaml`
2. `temp/_harness/EXEC_PLAN.md` 或 `temp/_harness/EXEC_PLAN_IOS26_UNIFY.md`
3. `temp/_harness/ACCEPT_PLAN.md` 或 `temp/_harness/ACCEPT_PLAN_IOS26_UNIFY.md`
4. `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md`
5. 如果涉及衣橱列表滚动或 cell 外观，再读 `docs/WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md`

## 必守规则

- 不改 `ThemeSkinSlot.rawValue`，不增减 18 个 slot。
- 不改 `theme_skin.owned` / `theme_skin.active_selection`。
- 不新增 manifest 必需 imageset；优先复用现有 assets、贴纸和程序化 fallback。
- 不让主题装饰泄漏到默认皮肤；不跨主题混搭。
- 不把透明 placeholder 当安全素材；必须审计 `missing` 和 `placeholder_suspect`。
- 用户图片/截图/视频/3D 预览不染色，只加外壳、徽标或背景。

## 默认工作流

1. 明确 `PROJ` 和 `THEME_ID`，从仓库根执行 harness。
2. 先查 manifest 中主题 namespace、imageset、默认 slot、装饰 PNG 命名。
3. SwiftUI 接入优先复用：
   - `HomeThemeSkinComponents.swift`
   - `TabBarThemeSkinComponents.swift`
   - `WardrobeThemeSkinComponents.swift`
   - `ThemeSkinSharedComponents.swift`
4. 新页面主题化时，读取对应 slot descriptor；slot 关闭必须回退默认样式。
5. 滚动列表中只使用轻量渐变、描边、低阴影；不要在 cell 内加载大 PNG 装饰或引入 observable object。
6. 完成后跑静态检查和 dry-run，视觉验收按 ACCEPT_PLAN 归档。

## 衣橱列表约定

- `ClothingCard`、`ClothingRow`、`ClothingRowBrief` 共用 `.wardrobeItemCard`。
- `listBrief` / `listDetailed` 不新增专用 slot。
- 心愿尾款、库存、价格、原价、品牌字段语义不变。
- 如果性能和主题视觉冲突，优先降低阴影/装饰成本，不取消主题 token。

## 验收命令

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"

git diff -- ItemManager/Services/ThemeSkin/ThemeSkinModels.swift temp/_harness/MANIFEST.yaml

git grep -n "ClothingRowBrief(\|ClothingRow(" -- ItemManager/Views

git diff --check
```

如涉及素材导入：

```bash
THEME_ID="theme_skin.sky_concert"
ruby temp/_harness/scripts/materialize_manual_image2_assets.rb --theme-id "$THEME_ID" --dry-run
```

## 输出要求

交付时说明：改动范围、是否触碰 slot/manager/manifest、已跑检查、未跑的构建或模拟器验证。
