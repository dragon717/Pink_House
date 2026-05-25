# ThemeSkin 主题皮肤正式验收清单

> 迁移日期：2026-05-25
> 迁移来源：历史 `temp/_harness/ACCEPT_PLAN.md`
> 当前状态：正式 checklist 已沉淀；`sky_concert` / `swan_dream` 的 A-O 视觉验收尚未跑完，不应据本文直接判定 PASS。

## 1. 适用范围

本清单用于 Pink_House iOS `ThemeSkin` 主题皮肤验收，覆盖主题商店、主题详情、购买 / 应用、核心 UI slot、停用恢复与跨主题隔离。

当前已知待验收主题：

| Theme ID | Namespace | 状态 |
|---|---|---|
| `theme_skin.sky_concert` | `sky_concert` | 代码与 Asset Catalog 已落地；A-O 视觉验收待跑 |
| `theme_skin.swan_dream` | `swan_dream` | 代码与 Asset Catalog 已落地；A-O 视觉验收待跑 |

## 2. 验收前置条件

- 在 iCloud 主仓库执行，不使用 `/Users/muniao/Downloads/Pink_House` 副本。
- 按当前项目规则先重新 build / install / launch，再读取模拟器画面；具体流程见 `docs/XCODE_SIMULATOR_COMPUTER_USE_ACCEPTANCE.md`。
- 截图验收建议使用 iPhone 16 Pro；若使用其他设备，结果中写明设备、OS 与验证边界。
- 每轮验收记录 commit hash、主题 ID、设备、OS、构建命令与 PASS / PARTIAL / FAIL。
- 验收基准图的语义、对应页面和删除 `temp` 前迁移路径见 `docs/THEME_SKIN_VISUAL_BASELINES.md`。当前 iCloud 仓库未发现完整的 `temp/design/` 基准图目录；删除 `temp` 前需找回、迁移这些基准图，或记录正式替代来源。

## 3. 静态与素材检查

视觉验收前先做素材完整性检查：

- `Assets.xcassets/ThemeSkin/<namespace>/` 下主题 imageset 存在。
- 关键 `@3x` PNG 不是空壳或透明 placeholder。
- `Contents.json` 的素材来源注释可追溯；缺失时记录为 `unknown`，但不能因此直接判失败。
- 未新增或改名 `ThemeSkinSlot.rawValue`。
- 未改 `ThemeSkinManager` 持久化 key：`theme_skin.owned`、`theme_skin.active_selection`。
- 主题未启用时，默认皮肤不得出现任何主题装饰。

## 4. A-O 视觉验收点

| 点位 | 范围 | 验收标准 | 当前状态 |
|---|---|---|---|
| A | 主题商店列表 | 出现当前主题卡片；预览首图清晰；基础价 / VIP 价展示正确 | 待跑 |
| B | 主题详情 hero | 详情页视觉调性符合主题；按钮文案和价格正确 | 待跑 |
| C | 购买与应用 | 购买成功后状态变为已购买 / 已应用；主按钮进入管理组件 | 待跑 |
| D | 衣橱主页顶栏 | 顶栏胶囊形状正确；左右图标按钮带主题装饰，不是裸系统按钮 | 待跑 |
| E | 搜索栏 | 搜索胶囊背景跟随主题色调，不是 iOS 默认灰底 | 待跑 |
| F | 商品卡 | 商品卡有花边描框和左上角标；图片素材或程序化兜底均可 | 待跑 |
| G | 统计卡 | 统计页四个胶囊卡有可辨识色彩分区；胶囊形状和数字字号保持基准版式 | 待跑 |
| H | 标签分类统计 | 横条柱状图与 `IMG_7937` 的结构风格一致 | 待跑 |
| I | TabBar 背景 | TabBar 为主题特色长条和边角装饰；选中态清晰，未选态干净 | 待跑 |
| J | TabBar 图标 | 选中 tab 图标颜色与主题契合 | 待跑 |
| K | “我”页设置豆腐块 | 卡片背景、圆角和整体密度符合主题与基准版式 | 待跑 |
| L | Slot 关闭 | 在管理组件关闭 `tabBarMain` 后，TabBar 立刻回默认，其它 slot 仍主题化 | 待跑 |
| M | Slot 恢复 | 重新开启 `tabBarMain` 后，TabBar 主题状态正确恢复 | 待跑 |
| N | 停用主题 | 停用后所有 UI 回默认 iOS 风格，无主题装饰泄漏 | 待跑 |
| O | 再启用主题 | 再启用后状态正确恢复，slot 集合按默认启用配置重置 | 待跑 |

## 5. 跨主题隔离

至少抽查一项：

- 已购两个主题时，从一个主题切到另一个主题，不残留前一主题 slot 装饰。
- UI 层所有启用 slot 都解析自当前 `activeThemeId`，不得出现跨主题拼盘。

## 6. 结果判定

| 结果 | 标准 | 后续动作 |
|---|---|---|
| PASS | A-O 全通过，跨主题隔离通过，无素材阻塞 | 可登记主题视觉验收完成 |
| PARTIAL | 1-3 个点位不通过，或素材来源存在非阻塞 `unknown` | 记录问题、截图和修复建议 |
| FAIL | 4 个及以上点位不通过，或存在透明 placeholder / 主题泄漏 / 持久化破坏 | 整体回退给实现端修复 |

结果文档至少包含：主题 ID、commit、设备 / OS、构建命令、截图目录、A-O 表格、跨主题隔离结论、不通过项明细。

## 7. 不迁移的历史细节

以下内容不进入正式 checklist，只作为历史迁移来源留在 temp 归档中：

- 历史 harness 的变量解析脚本片段。
- Claude / Codex 双角色会话流程。
- 写入 `temp/<theme-dir>/_artifacts/accept/` 的固定目录约定。
- 旧 harness 里的 tag / push 操作建议。
