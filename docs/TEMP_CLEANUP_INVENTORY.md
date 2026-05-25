# temp 文档清理盘点

> 盘点日期：2026-05-25
> 范围：主要阅读 `temp/` 下文档、manifest、RESULT/REPORT、提示词与配置；其中 iOS26 unify 项已在 2026-05-25 额外静态核对 `ItemManager/` 相关源码，但未跑构建 / 模拟器 / 真机。
> 追加核对：2026-05-25 P2 Worker 1 已对“产品框架体验”行只读核对当前 Swift 实现；2026-05-25 P3 Explorer H 已只读核对 runtime / 工程配置未直接依赖 `temp/design`、`temp/_harness`、`temp/主题1|2`、`temp/商品图`、`temp/人台.png`，并确认 Rococo / 图标两处历史口径差异。
> 目标：为后续删除 `temp/` 做迁移和核对清单。除已明确标注代码复核的条目外，本文件不代表代码已二次确认，所有“落地代码”均为 temp 文档中声明的对应关系。

## 判定规则

- 完成：temp 文档内有 PASS、STATIC PASS、BUILD PASS，或 README/清单明确写已落地；仍可能缺少视觉截图或代码复核。
- 未完成：temp 文档内写 PARTIAL、待验收、待实现、缺素材/缺 Cubism/缺模拟器截图，或只是计划/研究稿。
- 待代码核对：下一阶段应按本表列出的文件去读实际代码，确认功能是否仍在、是否已迁移到正式文档、是否还有 runtime 对 `temp/` 的依赖。
- 不删除原则：本轮不删除任何 `temp` 文件。

## 完成或基本完成

| temp 文档组 | 文档声明状态 | 文档声明的落地代码 / 资源 | 删除 temp 前动作 |
|---|---|---|---|
| `temp/_ootd_restore_harness/` | `RESULT.md` 写 M1-M5 代码落地，静态 harness PASS 7/7，commit `3c7f11b`；未跑 xcodebuild | `BackupRestoreIntegrationTests`、`BackupService`/restore flat book groups、`CloudSyncManager.localURLForRestoredFile`、`dataRestoreCompleted` / `ootdRestoreCompleted` 通知、SwiftData OOTD relationship rebuild、回收站 restore state | 读代码确认 restore 逻辑仍在；如已被 `docs/OOTD_JOURNAL_RESTORE_REFACTOR_*` 覆盖，可只保留正式 docs |
| `temp/_magicsticker_harness/runs/M5_20260501_015406/REPORT.json` | `ok: true`，历史人台源图与 Asset Catalog 人台一致；当前默认审计已改为只依赖 bundled asset | `ItemManager/Assets.xcassets/OOTD/Mannequin/ootd_mannequin_default.imageset/ootd_mannequin_default.png` | runtime 使用 `ootd_mannequin_default`；`temp/人台.png` 仅作为历史源图/显式 `--source` 审计输入，删除 temp 前不再是默认阻塞项 |
| `temp/house_rococo_menu_interaction/` | 历史静态验收 PASS，但当前代码核对显示口径已过期：未找到 `RococoSmallWorldView.swift` / `RococoSmallWorldView` | 当前小世界入口为 `SmallWorldView.swift`，实际渲染 `BookHouseSmallWorldView`；`SmallWorldStyle` 当前只有 `bookHouse` | 不应再按 `RococoSmallWorldView.swift` 作为落地代码判断。删除前把该 temp 记录标为历史过期，或改用 `BookHouseSmallWorldView` / `SmallWorldView` 重新核对小世界交互 |
| `temp/_harness/RESEARCH_CHECKLIST.md` | 主题 harness 结构、manifest、素材 dry-run、Swift 接入点全部勾选；sky_concert / swan_dream 已落地代码和 Asset Catalog 素材；历史占位 imageset 待清理 | `ThemeSkinProduct.skyConcert`、`ThemeSkinProduct.swanDream`、`ThemeSkinManager.products`、`HomeThemeSkinComponents.swift`、`TabBarThemeSkinComponents.swift`、`WardrobeThemeSkinComponents.swift`、`Assets.xcassets/ThemeSkin/sky_concert`、`Assets.xcassets/ThemeSkin/swan_dream` | `AGENTS.md` / `docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md` / `docs/skills/pink-house-theme-skin-replication-guide/SKILL.md` / 正式 ThemeSkin docs 已改为“历史 harness / 迁移前参考”口径；删除前仍需读代码与 Asset Catalog 二次确认，并清理历史占位 imageset |
| `temp/主题1/png/PENCIL_PROMPT.md`、`temp/主题2/png/PENCIL_PROMPT.md` | 两主题 PNG 装饰语义说明完整 | 对应 `sky_concert_decor_*`、`swan_dream_decor_*` imageset 语义用途 | 如果素材和主题代码已稳定，语义说明可迁移到主题正式文档；不应作为 runtime 依赖 |
| `temp/图标/icon.icon/icon.json` | 仅图标配置文件，非功能 harness；当前工程未指向它 | 正式图标配置为 `ASSETCATALOG_COMPILER_APPICON_NAME = "少女心愿logo"`，并存在 `ItemManager/少女心愿logo.icon/icon.json` 与 `ItemManager/Assets.xcassets/少女心愿logo.appiconset/Contents.json` | 删除前只需确认 `temp/图标/icon.icon` 是否有设计留档价值；从当前工程配置看不是构建必需项 |

## 部分完成 / 未闭环

| temp 文档组 | 文档声明状态 | 文档声明的落地代码 / 资源 | 未完成项 |
|---|---|---|---|
| `temp/产品框架体验/` | 已迁出当前有效状态到 `docs/PRODUCT_FRAMEWORK_EXPERIENCE_STATUS.md`；代码复核确认 P0/P1 四槽底栏已落地，P2 当前实现为 `bookHouse` / `BookHouseSmallWorldView`，旧 `journalRoom` 已过期；P3/P4 未实现 | `ItemManager/Models/AppFeatureRegistry.swift`、`BottomDockSettingsManager`、`ItemManager/Models/SmallWorldStyle.swift`、`ItemManager/Views/MainTabView.swift`、`FavoriteMenuSettingsView.swift`、`SmallWorldMenuOverlay.swift`、`SmallWorldView.swift`、`BookHouseSmallWorldView.swift` | `temp/产品框架体验/` 仅作历史 harness / 待迁移归档，不再作为 source of truth；P2 仍缺 UI 截图验收与 accept 归档；P3 萌宠手机未实现；P4 裙子股市外链情报站未实现；真实流程截图 / `accept/<ts>/RESULT.md` 待补 |
| `temp/尾款提醒体验/` | `PARTIAL`：静态检查与 Swift parse 通过，未模拟器视觉验收 | `ItemManager/Views/DepositPlan/DepositNotificationView.swift`、`ItemManager/Services/NotificationManager.swift`、`ThemeSkinSectionCardContainer` | 未跑有效 xcodebuild/模拟器；10 个场景未截图；需确认 `DepositNotificationRecord` schema/通知 key 未漂移 |
| `temp/来财体验/` | `PARTIAL`：集中 copy/token、禁词扫描、Swift parse、diff check 通过；未构建/截图 | `ItemManager/Views/Wealth/*`、`ItemManager/Services/WealthAppearanceManager.swift`、`WealthExperienceCopy`、`WealthExperienceStyle`、`VIPCenterView.swift`、`PetChat`、NewbieGuide T11/T12/T46/T47 | 视觉截图、引导回归、主题 slot 开关回归未验收 |
| `temp/_live2d_avatar_harness/` | 已新增正式状态文档 `docs/LIVE2D_AVATAR_GIRL_V1_STATUS.md`；当前主路径是 `AvatarCharacterKit` 分层 PNG / Hybrid runtime，不是完整 Cubism Live2D；正式 provenance 已迁到 `asserts/avatar/girl_v1/live2d/gpt_image2_source.json`，不再依赖 temp 中间图真实路径 | `ItemManager/Services/AvatarCharacterKit/*`、`ItemManager/Services/VideoResourceManager.swift`、`ItemManager/Views/OOTD/OOTDComponents.swift`、`OOTDCanvasView.swift`、`OOTDPreviewView.swift`、`PageSnapshotCache.swift`、`PageThumbnailView.swift`、`asserts/avatar/girl_v1/*`、`AvatarCharacter/girl_v1` asset | 本轮禁止删除；缺 `girl_v1_*.mov`；缺正式 Cubism `.model3.json`/`.moc3`；`edge_contact_warnings` 仍需人工视觉确认；真机缓存/首帧性能未验收；OOTD avatar mannequin 暂隐 gate 仍在 |
| `temp/_themeharness/` | ThemeSkin 审计发现问题；T0a 报告里仍有 P0 unthemed rows、dark contrast failures、density 未全过 | `DepositNotificationView.swift`、`SkyConcertThemeSkinComponents.swift` 等被报告点名 | T0b/T1/T2 未见结果闭环；需要判断后续深色可读性修复是否已在正式代码完成 |
| `temp/_harness/EXEC_PLAN_IOS26_UNIFY.md`、`ACCEPT_PLAN_IOS26_UNIFY.md` | 历史 iOS26 unify 执行/验收计划，已由 `docs/iOS26_导航栏统一与异形底栏方案.md` 的当前状态清单接管；未见独立 RESULT | 静态核对显示：`MainTabView.body` 已单分支进入 `LegacyTabView`，`ModernTabView` / iOS26 toolbar helper 已无检出，`ItemManagerApp.swift` 未见 iOS26 `UITabBar.appearance`，`SmallWorldMenuOverlay` 已退为 guide fallback helper，`ThemeSkinTabBarShapeStyle` / 主题底栏 shape 已存在；`BottomAccessoryCatDiamondOrbit*` 与 `TabBarItemAnchorResolver` 原生 probe 仍 deprecated 保留 | 不再把 temp 计划当正式手册；删除 temp 前只需迁移仍有效的验收点。未闭环：P2 搜索态 padding / fallback 度量、P3 56pt Legacy 外层布局与 62/66pt 主题 shape 的视觉确认、A-O 主题验收、xcodebuild、模拟器和真机截图、deprecated 残留删除窗口 |
| `temp/_harness/README.md`、`MANIFEST.yaml`、`EXEC_PLAN.md`、`ACCEPT_PLAN.md`、`ASSETS_SPEC.md`、`IMAGE2_FALLBACK_TEMPLATE.md` | 历史主题复刻 harness / 待迁移归档；README 写两个主题 manifest/代码/素材 dry-run 已完成，sky_concert / swan_dream 代码和 Asset Catalog 素材已落地，但验收待跑；正式 manifest 已迁入 `tools/theme_skin/theme_manifest.yaml`；素材 dry-run 脚本已迁入 `tools/theme_skin/materialize_manual_image2_assets.rb`；`ACCEPT_PLAN.md` 的 A-O 验收点已迁入 `docs/THEME_SKIN_ACCEPTANCE_CHECKLIST.md`；`temp/design/*` 的验收基准语义已迁入 `docs/THEME_SKIN_VISUAL_BASELINES.md`；PSD/image2 长期规则已迁入 `docs/THEME_SKIN_ASSET_PIPELINE.md` | ThemeSkin 模型、管理器、三件套 Components、ThemeSkin Store/Detail、主题 Asset Catalog、历史素材导入脚本、A-O 验收规则、视觉基准图语义和 PSD/image2 素材规则 | `AGENTS.md`、`docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md`、技能文档和正式 ThemeSkin docs 已不再把它写成永久 source of truth；两主题 A-O 视觉验收仍待跑；历史占位 imageset 待清理；正式 manifest 仍保留 `theme_dir: temp/主题1|2` artifact 输入路径；当前仓库未发现完整 `temp/design/` 基准图目录，删除 temp 前需迁移 artifact 输入位置并找回/替代视觉基准图片 |

## 计划稿 / 研究稿 / 不应视为已落地

| temp 文档组 | 文档性质 | 文档声明的目标代码 / 路径 | 建议 |
|---|---|---|---|
| `temp/复刻PLAN.md` | HarmonyOS ArkUI 迁移计划 | 只写 `/Users/muniao/Downloads/Pink_House/harmony_next`，iCloud 仅参考 | 不属于 iCloud iOS 落地代码；若仍有价值，迁到 Harmony 正式迁移文档 |
| `temp/拼豆开发书.md` | 拼豆/像素画功能产品与技术蓝图 | 未来 SwiftUI/Canvas/SpriteKit/Accelerate/SwiftData 等 | 未见落地结果；迁入产品 backlog 或删除 |
| `temp/对话/萌宠对话智能化*.md`、`萌宠智能v2.md`、`萌宠人工测试或mcp测试.md` | 萌宠 AI 搭配师/人设/测试计划；`萌宠人工测试或mcp测试.md` 中可复用的测试矩阵已迁入 `docs/PET_CHAT_TEST_MATRIX.md` | 计划新增 `OOTDLayoutEngine.swift`、`OutfitSuggestionService.swift`、`OutfitSuggestionCard.swift`，修改 `PetChatView.swift`、`PetChatBubble.swift`、`PetAIService.swift`、`WardrobeContextManager.swift` | 其余智能化 / 人设 / v2 方案仍需读代码确认是否已有新架构，再迁入正式 `docs/PET_*` 或 backlog；测试矩阵已迁移但不代表功能已全部实现 |
| `temp/imagegen/openai-homepage-ui.prompt.txt` | 与 Pink_House 业务无关的 imagegen prompt | 无项目落地代码 | 可直接归档或删除候选 |
| `temp/log.txt`、`temp/temp.txt` | 当前为空 | 无 | 删除候选，但需最后确认没有流程仍写入 |

## 工具 / 生成物目录

| temp 文档组 | 文档性质 | 对项目的关系 | 建议 |
|---|---|---|---|
| `scripts/rename_temp_files.py` | legacy/manual-only 重命名工具；当前要求显式传目标目录，默认 dry-run，只有 `--apply` 才会改文件 | 非 runtime 依赖；历史上用于把 `temp/` 下若干猫咪打工素材长文件名重命名为 `cat_*` 文件名 | 不作为常规 temp 迁移入口，不默认扫描整个 `temp/`；如需追溯旧素材整理，只对人工指定目录先跑 dry-run 并审阅输出 |
| `temp/商品图/appshot/` | 独立 `appshot-cli` 工具 checkout，含 `node_modules`、`.git`、CI、skill、frames、fonts | 非 Pink_House app runtime；用于 App Store 截图生成 | 已补正式说明：`docs/APP_STORE_SCREENSHOT_WORKFLOW.md`；建议迁到 `tools/appshot/` 或改用全局安装，不要把 `node_modules` 长期留在 `temp` |
| `temp/商品图/appshot-job/` | Pink_House 商品图生成作业配置和文案 | 输入/输出目录、截图 captions、富文案 overlay 配置；非 runtime 依赖 | 已补正式说明：`docs/APP_STORE_SCREENSHOT_WORKFLOW.md`；作业配置建议迁到 `tools/appshot-job/` 或发布素材文档，最终成品截图迁到正式发布素材目录 |

## 后续代码核对顺序

1. 先核对仍可能被验收 / 工具流程读取的路径：`temp/design/*`、`temp/主题1|2/png/*`、`temp/_harness/*`。当前未发现 iOS runtime / Xcode 工程配置直接依赖这些 temp 路径；`temp/design/*` 的语义已迁入 `docs/THEME_SKIN_VISUAL_BASELINES.md`，但完整图片本体当前未在本仓库找到；`tools/theme_skin/theme_manifest.yaml` 仍保留 `temp/主题1|2` 作为素材 artifact 输入路径；`temp/人台.png` 仅需确认没有显式 `--source` 审计需求；`temp/商品图/appshot/` 与 `temp/商品图/appshot-job/` 已按工具/生成作业记录为非 runtime 依赖，删除前只需确认迁移位置和最终发布素材归档。
2. 再按业务闭环核对：OOTD restore、人台 asset、Rococo 菜单、产品框架、尾款提醒、来财体验、Live2D、ThemeSkin。
3. 对已完成且正式 docs 覆盖的内容，只保留正式 docs；对未完成内容迁入 backlog 或执行计划。
4. 最后一轮用 `rg -n "temp/" ItemManager docs scripts *.md` 做删除前依赖扫描，再删除目录。
