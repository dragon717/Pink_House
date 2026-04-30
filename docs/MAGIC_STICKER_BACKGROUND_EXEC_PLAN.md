# 魔法贴纸底图与静态人台选择 · 执行计划（harness）

> 状态：2026-05-01 首版落地。iOS 阶段默认不主动跑 `xcodebuild`；Codex 做静态检查、脚本校验和可选模拟器验收，用户本地编译后再按报错修复。

## 范围

- 魔法贴纸与穿搭手帐书页统一为三类底图：空白、人台、图库自定义图片。
- 静态人台首批素材来自 `temp/人台.png`，入库为 `ootd_mannequin_default`。
- Live2D 可动人台仅保留 TODO，不接 SDK、不新增运行时依赖。

## Harness 约定

- 可提交脚本：`scripts/magic_sticker_harness/audit_mannequin_assets.py`。
- 运行产物：`temp/_magicsticker_harness/runs/<phase>_<ts>/REPORT.json`，默认不提交。
- 每个小版本建议独立 commit：`[M0] harness`、`[M1] asset`、`[M2] data-backup`、`[M3] render`、`[M4] ui-sheet`、`[M5] accept`。

## 执行步骤

1. 校验 `temp/人台.png` 存在、接近 3:4、不是透明或过小占位。
2. 将素材入 `Assets.xcassets/OOTD/Mannequin/ootd_mannequin_default.imageset/`。
3. 在 `Outfit` 增加可选人台 ID；旧 `canvasType == mannequin` 且 ID 为空时回退默认人台。
4. 备份 DTO 新字段全部 optional；恢复旧备份时默认 nil，新备份保留人台选择。
5. 统一编辑器、缩略图、快照导出的底图解析，消除 `ootd` / `ootd_background` 混用。
6. 接入共享“更换底图” sheet：空白、人台列表、图库自定义图片。
7. 输出验收报告；不通过项继续小版本修复。

## Live2D TODO

- 后续新增 `mannequinBackend = staticImage/live2d`，静态 PNG 与 Live2D 模型共用同一人台 ID 层。
- Live2D 渲染层独立于 OOTD 贴纸坐标；提供骨骼挂点/贴纸绑定 API 给搭配系统调用。
- 快照导出需支持静态帧渲染；页面离开、进入后台和低电量时暂停动画。
