---
name: pink-house-theme-skin-replication-guide
description: Pink_House 主题皮肤复刻与主题扩展技能。用于接入 sky_concert/swan_dream 或新增主题、迁移历史 temp/_harness 规则、处理 ThemeSkinSlot/素材 fallback/placeholder 审计、把主题皮肤扩展到衣橱列表和核心 SwiftUI 页面。
---

# Pink House Theme Skin Replication Guide

在 Pink_House 里做主题复刻、主题素材接入、主题验收、主题皮肤扩展到新页面或修复主题泄漏/混搭时使用这个技能。

## 先读

1. `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md`
2. `docs/THEME_SKIN_ASSET_PIPELINE.md`（涉及 PSD 导图层、manual image2、placeholder 或 source audit 时必读）
3. `docs/TEMP_CLEANUP_INVENTORY.md` 中 `temp/_harness` 相关行
4. `tools/theme_skin/theme_manifest.yaml`（正式 ThemeSkin manifest）
5. 迁移完成前如需查历史字段，再读 `temp/_harness/MANIFEST.yaml`
6. 迁移完成前如需查历史执行/验收步骤，再读 `temp/_harness/EXEC_PLAN.md`、`ACCEPT_PLAN.md` 或 iOS26 unify 版本
7. 如果涉及衣橱列表滚动或 cell 外观，再读 `docs/WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md`

`temp/_harness` 是历史 harness / 待迁移归档，不是永久 source of truth。PSD/image2 说明已迁入 `docs/THEME_SKIN_ASSET_PIPELINE.md`；删除 `temp` 前，仍需确认 artifact 输入位置、素材导入脚本和 A-O 验收规则均由正式 docs/tools 承接。

## 必守规则

- 不改 `ThemeSkinSlot.rawValue`，不增减 18 个 slot。
- 不改 `theme_skin.owned` / `theme_skin.active_selection`。
- 不新增 manifest 必需 imageset；优先复用现有 assets、贴纸和程序化 fallback。
- 不让主题装饰泄漏到默认皮肤；不跨主题混搭。
- 不把透明 placeholder 当安全素材；必须审计 `missing` 和 `placeholder_suspect`。
- manual image2 PNG 必须带同名 `.meta.json`；PSD 主题优先导图层，缺图层时才走显式 image2 兜底。
- 用户图片/截图/视频/3D 预览不染色，只加外壳、徽标或背景。
- sky_concert / swan_dream 已有代码和 Asset Catalog 素材落地；仍不能把 A-O 视觉验收或历史占位 imageset 清理标为完成。

## 默认工作流

1. 明确 `PROJ` 和 `THEME_ID`，从仓库根执行；优先按正式 docs/tools，历史 harness 只作迁移前参考。
2. 先查 `tools/theme_skin/theme_manifest.yaml` 和正式文档中的主题 namespace、imageset、默认 slot、装饰 PNG 命名；缺字段时再对照历史 manifest。
3. SwiftUI 接入优先复用：
   - `HomeThemeSkinComponents.swift`
   - `TabBarThemeSkinComponents.swift`
   - `WardrobeThemeSkinComponents.swift`
   - `ThemeSkinSharedComponents.swift`
4. 新页面主题化时，读取对应 slot descriptor；slot 关闭必须回退默认样式。
5. 滚动列表中只使用轻量渐变、描边、低阴影；不要在 cell 内加载大 PNG 装饰或引入 observable object。
6. 完成后跑静态检查和 dry-run，视觉验收按正式 A-O 清单归档；迁移前可临时沿用历史 ACCEPT_PLAN。

## 衣橱列表约定

- `ClothingCard`、`ClothingRow`、`ClothingRowBrief` 共用 `.wardrobeItemCard`。
- `listBrief` / `listDetailed` 不新增专用 slot。
- 心愿尾款、库存、价格、原价、品牌字段语义不变。
- 如果性能和主题视觉冲突，优先降低阴影/装饰成本，不取消主题 token。

## 验收命令

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"

git diff -- ItemManager/Services/ThemeSkin/ThemeSkinModels.swift docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md docs/TEMP_CLEANUP_INVENTORY.md

git grep -n "ClothingRowBrief(\|ClothingRow(" -- ItemManager/Views

git diff --check
```

如涉及素材导入：

```bash
THEME_ID="theme_skin.sky_concert"
ruby tools/theme_skin/materialize_manual_image2_assets.rb --theme-id "$THEME_ID" --dry-run
```

这条正式脚本默认读取 `tools/theme_skin/theme_manifest.yaml`，仍保留 `--manifest-path` 和 `THEME_SKIN_MANIFEST_PATH` 覆盖能力。当前正式 manifest 的 `theme_dir` 仍指向 `temp/主题1` / `temp/主题2`，所以 `temp/<theme-dir>/_artifacts/generated/image2_manual/` 仍是尚未迁移的人工 image2 artifact 输入位置。

素材 pipeline 的长期规则以 `docs/THEME_SKIN_ASSET_PIPELINE.md` 为准；历史 `ASSETS_SPEC.md` / `IMAGE2_FALLBACK_TEMPLATE.md` 只作为迁移来源。

## 输出要求

交付时说明：改动范围、是否触碰 slot/manager/manifest、是否依赖历史 `temp/_harness`、已跑检查、未跑的构建或模拟器验证，以及 A-O 视觉验收/历史占位 imageset 清理是否仍未闭环。
