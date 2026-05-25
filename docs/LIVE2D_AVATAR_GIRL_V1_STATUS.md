# Live2D 少女人偶 girl_v1 正式状态

> 核对日期：2026-05-25
> 结论：`temp/_live2d_avatar_harness/` 仍不能删除；本文件只是把当前正式状态迁到 `docs/`，避免 `temp` 成为唯一记录。

## 当前主路径

- `girl_v1` 当前主路径不是完整 Cubism Live2D，而是 `AvatarCharacterKit` 的分层 PNG / Hybrid runtime。
- 运行时资源从 `asserts/avatar/girl_v1/live2d/` 读取：`rig_manifest.json`、身体分层 PNG、`surface_plates/`、`hairstyles/`、`outfits/default/` 与 `clothing_sticker_split_rules.json`。
- `AvatarLayerAssetResolver` 优先构造 Hybrid package：整人 `surface_plates` 作为安全底板，再叠少量分层 overlay，降低首版分层缝隙风险。
- `AvatarCharacterView` 的 `.live2d` backend 当前优先进入 `AvatarLayeredMotionView`；只有分层包不可用时才落到 `Live2DAvatarView`。
- `Live2DAvatarView` 只是透明 `MTKView` / Metal spike shell，不是当前主渲染路径，也不能作为 Live2D 完成依据。
- 透明视频包尚未交付；`VideoResourceManager` 已有 `girl_v1_*.mov` 解析路径，但 `asserts/avatar/girl_v1/video/` 当前只有占位。
- 正式 provenance 记录在 `asserts/avatar/girl_v1/live2d/gpt_image2_source.json`；退役 harness 生成的 chroma-key / alpha 中间图仅是历史记录，不再是当前文件依赖。

## 已迁入正式资源的内容

| 类别 | 正式位置 | 状态 |
|---|---|---|
| 静态图 | `ItemManager/Assets.xcassets/AvatarCharacter/girl_v1/avatar_girl_v1_static.imageset/` | 已作为 fallback / 静态资产 |
| 身体分层 | `asserts/avatar/girl_v1/live2d/layers/` | 已接入分层 runtime |
| Hybrid 底板 | `asserts/avatar/girl_v1/live2d/surface_plates/` | 当前主路径优先使用 |
| 发型包 | `asserts/avatar/girl_v1/live2d/hairstyles/default_long_pink/`、`short_bob/` | 已接入，可替换发型 |
| 默认服装包 | `asserts/avatar/girl_v1/live2d/outfits/default/` | 保留为内置包；普通魔法贴纸小人默认不自动挂裙装 |
| 分层规则 | `asserts/avatar/girl_v1/live2d/clothing_sticker_split_rules.json` | 保留后续服装贴纸拆分约定 |
| 来源记录 | `asserts/avatar/girl_v1/live2d/gpt_image2_source.json` | 正式 provenance；不依赖 temp 中间图路径 |

## OOTD / 魔法贴纸集成状态

- `OOTDMannequinBackground` 仍定义 `girl_v1` 与 `girl_v1_short_bob` 两个人台 ID。
- 当前存在暂隐 gate：`temporarilyHideAvatarMannequins = true`，选择列表通过 `available` 过滤 avatar-backed mannequins。
- `resolve(_:)` 对暂隐 avatar mannequin 回退到 `ootd_mannequin_default`，避免新渲染继续露出少女素体人台。
- `shouldUseStoredSnapshot(canvasType:mannequinAssetID:)` 会让隐藏的 avatar mannequin 页面不再信任旧 `snapshotPath`，缩略图/翻页等路径应重新生成或回退展示。
- 因此，当前 OOTD 中 avatar mannequin 属于“已接入但暂不展示”的状态，不是上线完成状态。

## 未闭环项

- `girl_v1_*.mov` 透明视频包未交付；后续应放入 `asserts/avatar/girl_v1/video/`，并补资源审计与回退验收。
- 正式 Cubism 包未交付：缺 `.model3.json` / `.moc3`，也未接入官方 Cubism renderer。
- `edge_contact_warnings` 仍需人工视觉确认；现有 edge audit 的 PASS 只能说明脚本跑通和预览已生成，不能替代视觉验收。
- 真机性能、首帧缓存、重复打开缓存命中、低电量/后台静态帧策略仍需实机验收。
- OOTD avatar mannequin 暂隐 gate 仍在；后续解除前需重新核对 picker、编辑页、快照、缩略图、翻页、分享图和旧页面迁移行为。
- `temp/_live2d_avatar_harness/` 仍保留历史脚本、预览和验收结果；删除 temp 前，需要确认正式 docs/tools 已覆盖仍有价值的脚本、manifest 字段和视觉证据。

## 删除 temp 前检查

1. 确认 `asserts/avatar/girl_v1/live2d/gpt_image2_source.json` 已覆盖当前资源来源，不再需要 temp 中间图真实路径。
2. 确认所有运行时路径只读 Bundle / Asset Catalog / `asserts/avatar/girl_v1/*`，没有默认读取 `temp/_live2d_avatar_harness/*`。
3. 交付或明确放弃透明视频包与 Cubism 包，并更新验收参数，不能继续只依赖 `--allow-missing-video` / `--allow-missing-live2d` 口径。
4. 完成人工 edge 视觉确认和真机性能/首帧缓存验收。
5. 决定是否解除 OOTD avatar mannequin 暂隐 gate；若解除，需要重新跑 OOTD 选择、编辑、快照、缩略图和分享链路。
