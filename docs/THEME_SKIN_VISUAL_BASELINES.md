# ThemeSkin 视觉验收基准图说明

> 迁移日期：2026-05-25
> 迁移来源：`AGENTS.md` 中“验收图基准（所有主题共用）”与历史 `temp/design/` 设计基准。
> 当前状态：本文只迁移基准图语义和后续迁移路径；当前 iCloud 仓库未发现 `temp/design/` 目录，本轮未移动、复制或删除任何图片。

## 0. 当前文件可见性

2026-05-25 静态核对结果：

- `temp/design/IMG_7936.png`、`temp/design/IMG_7937.png`、`temp/design/IMG_8204.PNG`、`temp/design/IMG_8208.PNG`、`temp/design/IMG_8211.PNG` 是历史文档引用路径。
- 当前 iCloud 仓库没有 `temp/design/` 目录，也没有 `.icloud` 占位文件。
- 在 `temp/商品图/appshot-job/` 下可找到 `IMG_8204.PNG`、`IMG_8208.PNG`、`IMG_8211.PNG` 的截图 / 成品副本，但这不是完整的 ThemeSkin 基准图集合。
- 当前仓库未找到 `IMG_7936.png`、`IMG_7937.png`。

因此，删除 `temp` 前不能把这些基准图视为已迁出；需要先找回原始基准图、选定 `appshot-job` 中可替代的截图，或用新的正式设计稿 / 截图基准替代。

## 1. 用途

这些图片是 ThemeSkin A-O 视觉验收的版式基准，用于确认不同主题在核心页面上的布局密度、模块结构、导航层级和信息分组是否保持一致。

主题视觉允许随主题改变颜色、装饰和素材风格；但页面结构、可读性、主要控件位置和信息层级应与对应基准图一致。

## 2. 基准图清单

| 历史引用路径 | 对应页面 | 主要验收用途 | 删除 `temp` 前迁移目标建议 |
|---|---|---|---|
| `temp/design/IMG_7936.png` | 衣橱主页 | 校对衣橱首页顶栏、搜索栏、商品卡网格、底部 TabBar 的版式密度和信息层级 | 迁入正式设计基准目录，例如 `docs/assets/theme_skin/baselines/wardrobe_home.png`，或替换为正式设计稿 / 截图基准 |
| `temp/design/IMG_7937.png` | 衣橱统计页 | 校对统计卡、标签分类统计、横条柱状图和数字信息的结构风格 | 迁入正式设计基准目录，例如 `docs/assets/theme_skin/baselines/wardrobe_stats.png`，或替换为正式设计稿 / 截图基准 |
| `temp/design/IMG_8204.PNG` | 大世界 House 页 | 校对 House / 大世界页的主视觉区域、入口层级和底部导航关系 | 迁入正式设计基准目录，例如 `docs/assets/theme_skin/baselines/house_world.png`，或替换为正式设计稿 / 截图基准 |
| `temp/design/IMG_8208.PNG` | 财富页 | 校对财富页卡片分组、数据区域和主题背景下的可读性 | 迁入正式设计基准目录，例如 `docs/assets/theme_skin/baselines/wealth.png`，或替换为正式设计稿 / 截图基准 |
| `temp/design/IMG_8211.PNG` | 穿搭手帐页 | 校对穿搭手帐页内容布局、记录入口和页面层级 | 迁入正式设计基准目录，例如 `docs/assets/theme_skin/baselines/ootd_journal.png`，或替换为正式设计稿 / 截图基准 |

## 3. 与 A-O 验收的关系

- `docs/THEME_SKIN_ACCEPTANCE_CHECKLIST.md` 是正式 A-O 验收清单。
- 本文记录 A-O 验收引用的跨主题页面基准图语义。
- A-O 验收结果应记录使用的基准图来源。如果临时使用 `temp/商品图/appshot-job/` 的截图副本，或重新找回 `temp/design/` 历史图，需在结果中注明这是删除 `temp` 前的临时来源。

## 4. 删除 `temp` 前必须完成

删除 `temp` 前，需要完成以下任一方案：

1. 将上述五张图片迁入正式设计基准目录，并更新本文与验收清单中的路径。
2. 用正式设计系统、设计稿导出物或新截图基准替代上述图片，并在本文记录替代关系。
3. 如果某张基准图不再适用，记录废弃原因、替代验收点和对应页面负责人。

在图片本体找回、迁出或替代前，`tools/theme_skin/theme_manifest.yaml` 中的 `temp/design/*` 只能视为历史引用路径，不能视为可用的正式基准资源。
