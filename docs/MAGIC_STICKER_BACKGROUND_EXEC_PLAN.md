# 魔法贴纸底图与静态人台选择 · 执行计划（harness）

> 状态：2026-05-01 首版落地。iOS 阶段允许按任务需要运行 `xcodebuild` 构建/测试/模拟器验收；Codex 仍需完成静态检查、脚本校验，并在报告中写明实际验证命令、结果和未覆盖边界。

## 范围

- 魔法贴纸与穿搭手帐书页统一为三类底图：空白、人台、图库自定义图片。
- 静态人台 runtime 使用 bundled asset：`ootd_mannequin_default`。
- `temp/人台.png` 仅是历史源图；默认审计不依赖它，如需核对源图需显式传 `--source <path>`。
- Live2D/Cubism SDK 仍不接入；当前先用 `AvatarCharacterKit` 的分层 PNG 轻动效作为魔法贴纸 v1 小人。

## Harness 约定

- 可提交脚本：`scripts/magic_sticker_harness/audit_mannequin_assets.py`。
- 默认运行只审计 `ootd_mannequin_default` imageset；显式传 `--source temp/人台.png` 时才额外审计历史源图。
- 运行产物：`temp/_magicsticker_harness/runs/<phase>_<ts>/REPORT.json`，默认不提交。
- 每个小版本建议独立 commit：`[M0] harness`、`[M1] asset`、`[M2] data-backup`、`[M3] render`、`[M4] ui-sheet`、`[M5] accept`。

## 执行步骤

1. 校验 `Assets.xcassets/OOTD/Mannequin/ootd_mannequin_default.imageset/` 存在、接近 3:4、不是透明或过小占位。
2. 如需追溯历史源图，再运行 `python3 scripts/magic_sticker_harness/audit_mannequin_assets.py --source temp/人台.png`；不把 `temp/人台.png` 作为默认依赖。
3. 在 `Outfit` 增加可选人台 ID；旧 `canvasType == mannequin` 且 ID 为空时回退默认人台。
4. 备份 DTO 新字段全部 optional；恢复旧备份时默认 nil，新备份保留人台选择。
5. 统一编辑器、缩略图、快照导出的底图解析，消除 `ootd` / `ootd_background` 混用。
6. 接入共享“更换底图” sheet：空白、人台列表、图库自定义图片。
7. 输出验收报告；不通过项继续小版本修复。

## Live2D / 分层动效 TODO

- 当前正式状态见 `docs/LIVE2D_AVATAR_GIRL_V1_STATUS.md`；`temp/_live2d_avatar_harness/` 仍不能删除。
- 当前 `live2d` 后端优先走分层 PNG 轻动效；无分层资源时才进入透明 `MTKView` spike shell。
- 少女小人运行时默认显示素体 + 发型，不自动挂默认裙装；身体分层需覆盖大臂、小臂、手、大腿、小腿、脚。
- 分层渲染层独立于 OOTD 贴纸坐标；后续提供骨骼挂点/贴纸绑定 API 给搭配系统调用。
- 快照、缩略图、后台和低电量都固定静态帧；编辑页可手动开启动效。
- `asserts/avatar/girl_v1/live2d/gpt_image2_source.json` 是正式资源 provenance；退役 harness 生成的 chroma-key/alpha 中间图仅保留历史说明，不作为当前文件依赖。
- 后续拿到官方 Cubism Core、`.model3.json`、`.moc3` 后再替换 renderer，不改魔法贴纸业务层。
