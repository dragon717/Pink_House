# ThemeSkin 背景贴纸排布与边框装饰执行计划

> 状态：2026-05-01 执行中 / 可验收。本文是 ThemeSkin 运行时优化计划；长期主题复刻口径以 `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md` 以及后续迁入的 `tools/` / 正式 docs 为准。`temp/_harness` 仅作为历史 harness / 迁移前参考。本文不新增主题素材，不改变主题商品注册与持久化边界。

## 0. ThemeSkin 边界

- source of truth：`/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House`
- 不改 `ThemeSkinSlot.rawValue`，不增减 18 个 slot。
- 不改 `theme_skin.owned` / `theme_skin.active_selection` 存档 key。
- 背景贴纸新增字段只扩展 `theme_skin.background_sticker_selection_v1` 的 Codable optional 字段，旧数据缺字段时按默认值恢复。
- 不改 `temp/_harness/MANIFEST.yaml`；迁移完成前可对照历史 manifest 已登记的 `imageset_common + imageset_extras`，长期素材映射应迁入正式 docs 或 `tools/`。
- 不用 SF Symbol 替代主题贴纸作为常态；SF Symbol 只在缺图 fallback 中出现。
- 默认主题不得泄漏主题贴纸或装饰。

## 1. 目标

1. 框框边缘装饰不要都是蝴蝶结，同类型装饰不能过量。
2. 每个页面背景不同：同一主题下按页面上下文改变贴纸 seed、密度、偏移与底色 tint。
3. 主题设置里的「背景贴纸排布」改成设置大主图 / 小主图的排列方式。
4. 大主图选择不再作为主交互，改放到弹窗菜单里。
5. 继续符合 ThemeSkin 硬约束：默认主题无泄漏、跨主题不混搭、缺图有程序化/空 fallback。

## 2. 小版本拆分

### v1 边框装饰去重复

- `ThemeSkinEdgeStickerRole` 增加四角/中心语义角色。
- 天鹅主题的普通 card 边角从 bow 优先改为皇冠天鹅、水晶星、月亮瓶、城堡等贴纸；bow 只保留在个别主题特色位置。
- 天空主题继续使用乐谱云、小提琴云、星球、流星、云鲸等多样贴纸。

### v2 背景排布 preset

新增 `ThemeSkinWallpaperLayoutPreset`：

| preset | 含义 | 对应参考 |
|---|---|---|
| `mixedFocus` | 大小混合，大主图 + 小贴纸 | 截图 1 |
| `heroStatement` | 大主图铺陈，小图数量减少 | 截图 2 |
| `balancedScatter` | 均匀散点，元素大小接近 | 截图 3/4 |
| `miniPattern` | 小图满铺，不强调大主图 | 全部小主图 |

### v3 设置 UI

- 预览区显示当前 preset + 当前大主图。
- 排列方式用 2×2 选择卡作为主交互。
- 「选择大主图」按钮打开弹窗菜单，包含「全部小主图」和主题贴纸列表。

### v4 页面背景上下文

新增 `ThemeSkinWallpaperContext`，P0 先接入：

- `wardrobe`
- `depositPlan`
- `house`
- `wealth`
- `journal`
- `me`
- `petChat`
- `themeDetail`

各 context 通过 assetIndexOffset / xOffset / yOffset / rotationOffset / opacityMultiplier / tintColor 生成不同背景。

## 3. 验收清单

- [ ] 天鹅主题普通框边不再大面积重复蝴蝶结。
- [ ] 天空主题框边贴纸类型保持多样。
- [ ] 背景排布卡先展示 4 种排列方式，选中态明显。
- [ ] 大主图选择在弹窗菜单中完成。
- [ ] `全部小主图` 能取消大主图视觉焦点。
- [ ] 衣橱、尾款、House、财富、手帐、我的、萌宠、主题详情背景有可见差异。
- [ ] 主题停用后 `LiquidBackground` 回普通背景，不泄漏主题贴纸。
- [ ] 两个现有主题 asset dry-run 不新增 missing。

## 4. 验证命令

```bash
PROJ="/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House"
cd "$PROJ"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PYTHONUTF8=1

git diff --check
ruby tools/theme_skin/materialize_manual_image2_assets.rb --theme-id "theme_skin.sky_concert" --dry-run
ruby tools/theme_skin/materialize_manual_image2_assets.rb --theme-id "theme_skin.swan_dream" --dry-run
```

> 上述 dry-run 使用正式 `tools/theme_skin` 入口；脚本默认读取 `tools/theme_skin/theme_manifest.yaml`，仍可用 `--manifest-path` 复核历史清单。当前正式 manifest 的主题 `_artifacts/generated/image2_manual/` 输入仍在 temp，删除 `temp` 前需要把 artifact 输入位置迁入正式 docs/tools。

> iOS 阶段可按任务需要运行 `xcodebuild` 构建/测试/模拟器验收；如跑截图归档，需同步记录构建命令、模拟器 destination、截图路径和失败边界。
