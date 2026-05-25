# ThemeSkin 素材 Pipeline 长期规则

> 更新时间：2026-05-25
> 范围：Pink_House iOS `ThemeSkin` 的 PSD 导图层、manual image2 交接、placeholder 风险、素材 provenance / source audit。
> 目标：把历史 `ASSETS_SPEC.md` 与 `IMAGE2_FALLBACK_TEMPLATE.md` 中仍有效的资产规则迁入正式文档；历史 harness 仅保留为迁移来源与核对输入，不再作为长期 source of truth。

## 1. 长期入口

- 正式主题 manifest：`tools/theme_skin/theme_manifest.yaml`。
- 正式素材入库工具：`tools/theme_skin/materialize_manual_image2_assets.rb`。
- 正式主题复刻总则：`docs/THEME_SKIN_REPLICATION_BEST_PRACTICES.md`。
- 正式视觉验收清单：`docs/THEME_SKIN_ACCEPTANCE_CHECKLIST.md`。
- 当前正式 manifest 的 `theme_dir` 仍指向 `temp/主题1` / `temp/主题2`；删除 `temp` 前，必须把 artifact 输入位置迁到正式路径，或在工具配置中明确新的输入来源。

## 2. 通用素材规则

- 最终素材必须进入 `ItemManager/Assets.xcassets/ThemeSkin/<namespace>/<imageset>.imageset/`，不走 Bundle 文件路径。
- 主题 namespace 的 `Contents.json` 必须设置 `provides-namespace: false`，确保 SwiftUI 能用短名读取 imageset。
- imageset 名、文件夹名和 PNG basename 必须一致，使用小写下划线。
- 中间产物只放在主题 artifact 目录；最终 @2x / @3x PNG 才进入 Asset Catalog。
- PNG 默认使用 PNG-32 透明底；只有 `wallpaper_main` 和 `preview_store_hero` 允许是不透明整图。
- 可拉伸 UI 壳体必须保留 9-slice；cap-insets 的权威表在 `tools/theme_skin/materialize_manual_image2_assets.rb` 的 `CAP_INSETS`，不要手工改已生成的 `Contents.json` 当作长期修复。

## 3. PSD 图层导出规则

- `source_type=psd` 的主题优先从 PSD 图层或已预导出的 PNG 切片生成素材，image2 只作为确实缺图层时的兜底。
- 首次处理 PSD 时先列出图层，把图层名映射到正式 imageset 名；未确认的 `<TBD>` 不得当作已交付。
- 导出单层时需要确保目标图层可见；如果导出全空，先检查图层可见性和 group 层级，再判断是否需要 image2 兜底。
- `preview_store_hero` 这类商店首图可来自 PSD 整体合成导出，不要求拆成单层。
- 每个导出的素材应保留同名 `.meta.json` 或等价 provenance，至少记录 imageset 名、PSD 文件、图层名或切片来源、尺寸和生成时间。
- PSD 主题如要走 manual image2 写入，必须是明确的兜底动作；正式工具写入时需要显式允许 PSD fallback，避免把“缺 layer_map”误判成正常 image2 流程。

## 4. Manual image2 规则

- 当当前会话不能直接调用 image2 / imagegen，或者美术需要用户手工生成时，Codex 只生成交接清单和可复核的粗切/来源说明，不用 PIL 或 SwiftUI 程序化图冒充最终美术素材。
- 用户手工生成的 PNG 放入主题 artifact 的 `generated/image2_manual/<imageset_name>.png`，旁边必须放同名 `.meta.json`。
- manual image2 的 `.meta.json` 至少包含：`name`、`model`、`mode` 或 `source`、最终 prompt、negative prompt、输出路径；`name` 必须等于 imageset 名。
- 贴纸清理必须以源图/粗切为唯一主体参考，只允许修边、补边、透明底优化，不应发明不同物件。
- UI 壳体、贴纸、extras 的缺口由 expected imageset 集合与已有来源对比得到，不在文档里硬编码固定数量。

## 5. Placeholder 与 fallback 风险

- 禁止创建透明 PNG、空 imageset 或极小占位图来“占坑”。SwiftUI 只要能 `UIImage(named:)` 到资源，就会认为素材存在，程序化 fallback 不会触发，最终可能显示空白。
- 只有人工 PNG、meta 和 expected 集合全部通过 dry-run 后，才允许写入 Asset Catalog。
- 已存在 imageset 也要审计 @3x 文件大小；极小文件同样可能是历史透明占位。
- 如果素材缺失，正确状态是让 imageset 缺失并暴露 `MISSING`，而不是提交不可见占位素材。

## 6. Source Audit

- 每次素材入库前运行正式工具 dry-run，检查 `missing=0`、`missing_meta=0`、`placeholder_suspect=0`。
- `MISSING [common[...]]` 表示共享 UI 壳体缺来源；`MISSING [sticker[...]]` 表示贴纸清理缺来源；`MISSING [extras[...]]` 表示主题额外装饰或 PSD 切片缺来源。
- `MISSING-META` 必须补齐来源记录；不要为了通过检查删除 meta 要求。
- `PLACEHOLDER-SUSPECT` 必须替换素材或解释并修正阈值/来源，不得直接写入。
- 入库后再跑 `git diff --check`，必要时补跑 xcodebuild / 模拟器视觉验收，并在交付中说明验证边界。

## 7. 仍未迁完

- 主题 artifact 输入位置仍在 `temp/<theme-dir>/_artifacts/generated/image2_manual/`；删除 `temp` 前需迁到正式 artifact 目录或工具配置。
- `temp/design/` 验收图片本体仍需正式替代来源或迁移位置接管。
- sky_concert / swan_dream 的 A-O 视觉验收与历史占位 imageset 清理仍未闭环。
