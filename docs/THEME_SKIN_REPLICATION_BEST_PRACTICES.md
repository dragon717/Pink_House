# 主题皮肤复刻最佳实践

> 更新时间：2026-05-25
> 范围：Pink_House iOS `ThemeSkin` 主题复刻、主题扩展与主题验收。
> 目标：让后续主题接入从正式文档/工具、同一组 slot、同一条验收链路出发，避免素材/代码/验收各自发散；历史 `temp/_harness` 只作为待迁移参考。

## 1. Source of Truth

- `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md` 承接长期主题复刻规则；脚本、生成器和可执行清单应迁入 `tools/` 或正式 docs 后再删除 `temp`。
- `docs/THEME_SKIN_ASSET_PIPELINE.md` 承接 PSD 导图层、manual image2、placeholder 风险和 source audit 长期规则。
- `tools/theme_skin/theme_manifest.yaml` 是当前正式 ThemeSkin manifest，承接有效主题元数据、shared imageset 清单和默认工具输入。
- `temp/_harness/MANIFEST.yaml`、`EXEC_PLAN*.md`、`ACCEPT_PLAN*.md` 是历史 harness / 待迁移归档，不再作为永久 source of truth。
- 删除 `temp/_harness` 前，必须确认仍有效的主题字段、素材清单、导入脚本、A-O 验收规则已经迁入正式位置；PSD/image2 说明以 `docs/THEME_SKIN_ASSET_PIPELINE.md` 为正式口径。
- 当前正式 manifest 内的 `theme_dir: temp/主题1` / `theme_dir: temp/主题2` 仍是 artifact 输入位置，尚未迁移；`shared.accept_design_refs` 也仍引用 `temp/design` 版式基准。
- `theme_skin.sky_concert` 与 `theme_skin.swan_dream` 已落地代码和 Asset Catalog 素材；A-O 视觉验收与历史占位 imageset 清理仍未闭环。
- 旧下线主题只保留必要的历史兼容静态定义，不重新注册商品、不恢复已删素材。

## 2. 绝对不改的兼容边界

- 不改 `ThemeSkinSlot.rawValue`，不增减 18 个 slot。
- 不改 `theme_skin.owned` / `theme_skin.active_selection` 持久化 key。
- 不随意新增必需 imageset；新增主题只在正式主题元数据中追加可选装饰或映射，迁移前临时使用历史 manifest 时也要保持兼容。
- 不绕过 `ThemeSkinManager` 的主题互斥规则；禁止 UI 层跨主题混搭组件。
- 用户内容不染色：裙装图片、书页截图、3D 预览、宠物头像/视频、财富资产图只允许加外壳、徽标、背景或按钮装饰。

## 3. 素材导入与 fallback

- 素材必须进入 `ItemManager/Assets.xcassets/ThemeSkin/<namespace>/`，不走 Bundle 文件路径。
- PSD / PNG / image2 产物按 `tools/theme_skin/theme_manifest.yaml` 的正式素材映射导入；迁移完成前可对照历史 manifest，短名 fallback 只在明确安全的主题中使用。
- 透明或极小 placeholder 是硬风险：`UIImage(named:)` 会把透明图当作“已存在”，导致程序化 fallback 不触发。
- PSD 图层导出、manual image2 交接、`.meta.json` source audit、9-slice 和 placeholder 禁止项详见 `docs/THEME_SKIN_ASSET_PIPELINE.md`。
- 每次素材导入后必须跑：

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
THEME_ID="theme_skin.sky_concert" # 或 theme_skin.swan_dream
cd "$PROJ"
ruby tools/theme_skin/materialize_manual_image2_assets.rb --theme-id "$THEME_ID" --dry-run
```

该正式脚本默认读取 `tools/theme_skin/theme_manifest.yaml`，仍可通过 `--manifest-path` 或 `THEME_SKIN_MANIFEST_PATH` 指向其他清单。当前 manifest 的 `theme_dir` 仍指向 `temp/主题1` / `temp/主题2`，所以人工 image2 PNG 输入仍来自 `temp/<theme-dir>/_artifacts/generated/image2_manual/`；删除 `temp` 前还需要迁移这些 artifact 输入位置。

验收时重点看 `missing=0`、无 `placeholder_suspect`、无 fallback-incomplete。

## 4. SwiftUI 接入原则

- 首选复用现有主题容器：`HomeThemeSkin*`、`TabBarThemeSkin*`、`WardrobeTheme*`、`ThemeSkinSectionCardContainer`、`ThemeSkinPrimaryButtonStyle`、`ThemeSkinIconBadge`、`ThemeSkinEmptyStateSurface`。
- 主题激活时读取对应 slot descriptor；slot 关闭时必须回退默认皮肤。
- 滚动热路径优先用程序化渐变/描边/低阴影，不在 cell 内加载大装饰 PNG、不加高成本动画、不引入 cell 级 `@ObservedObject` / `@StateObject`。
- 衣橱商品卡、单行详细、单行简略统一使用 `.wardrobeItemCard`；不要为了 list row 新增 slot。
- 主题扩展到新页面时，先找“工作正常的对应组件”再复用，避免同一类卡片出现两套颜色来源。

## 5. 衣橱列表专项规则

- `ClothingCard`、`ClothingRow`、`ClothingRowBrief` 必须同源读取 `.wardrobeItemCard`。
- `listBrief` / `listDetailed` 只装饰 cell 外壳、文字 token、占位图和徽标；真实裙装图片不能加滤镜。
- 价格、原价、库存、心愿尾款金额语义不变，只调整显示颜色与外壳。
- 切换默认、天空音乐会、天鹅入梦后立刻滚动列表，不允许出现主题色 cell 与默认 cell 混排超过一帧。
- 如列表性能变差，先对照 `docs/WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md` 降低阴影/装饰成本，不回退主题语义。

## 6. 验收清单

### 静态验收

```bash
cd "$PROJ"

git diff -- ItemManager/Services/ThemeSkin/ThemeSkinModels.swift docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md docs/TEMP_CLEANUP_INVENTORY.md

git grep -n "decor_cherub\|decor_violin\|decor_cloud_left\|decor_cloud_right\|decor_music_note\|decor_staff_banner\|decor_swan_main\|decor_swan_feather\|decor_lake_ripple\|decor_pearl_string\|decor_lace_veil\|decor_moon_swan" ItemManager/Views

git grep -n "ClothingRowBrief(\|ClothingRow(" -- ItemManager/Views

git diff --check
```

期望：slot rawValue / 必需素材映射无意外 diff；废弃装饰名清零；衣橱 row 入口要么显式传 descriptor，要么有合理默认；diff 无空白错误。

### 视觉验收

- 默认、`theme_skin.sky_concert`、`theme_skin.swan_dream` 各跑一次衣橱主页。
- sky_concert / swan_dream 虽已落地代码和素材，仍需补齐 A-O 视觉验收记录后才能把主题复刻闭环标为完成。
- 切换 `grid2 / grid3 / grid6 / listBrief / listDetailed`，确认网格卡与单行列表都跟随主题。
- 关闭 `.wardrobeItemCard` 后衣橱商品卡和单行列表回退默认外壳。
- 连续切换主题 5 次，无跨主题贴纸、颜色或旧背景残影。

### 性能验收

- 参考 `docs/WARDROBE_LIST_SCROLL_PERFORMANCE_EXEC_PLAN.md` 的静态检查：列表 cell 不新增 material、动画、hover、cell 级 observable object。
- 若做模拟器验收，截图和性能记录优先归档到正式 docs/tools 约定位置；迁移完成前可临时沿用 `temp/_harness/_artifacts/runs/<ts>/` 或 `temp/_perf/wardrobe_list/<ts>/`。

## 7. 交付说明模板

交付时至少说明：

- 改了哪些主题接入点和文档/技能。
- 是否改动 `ThemeSkinSlot` / `ThemeSkinManager` / `MANIFEST.yaml`。
- 是否仍依赖历史 `temp/_harness`，以及对应迁移项是否已进入 `docs/` 或 `tools/`。
- 跑过哪些静态检查、哪些视觉或性能检查未跑。
- 如未跑 Xcode build 或模拟器，明确写“未跑构建/未跑模拟器”。
