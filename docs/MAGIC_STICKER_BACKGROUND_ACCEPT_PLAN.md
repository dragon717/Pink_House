# 魔法贴纸底图与静态人台选择 · 验收清单

## 静态校验

- [ ] `python3 scripts/magic_sticker_harness/audit_mannequin_assets.py` 返回 `ok: true`，且 `source.skipped: true` 表示未提供可选历史源图。
- [ ] 如需核对历史源图，显式运行 `python3 scripts/magic_sticker_harness/audit_mannequin_assets.py --source temp/人台.png`；`temp/人台.png` 不属于默认审计依赖。
- [ ] `ootd_mannequin_default` imageset 存在且文件名为 ASCII-safe。
- [ ] 新增备份 DTO 字段均为 optional，旧备份不会因缺 key 解码失败。
- [ ] 已记录 `xcodebuild` 验证状态：未运行 / PASS / FAIL；如已运行，附命令、scheme、destination 与结果。

## 功能验收

- [ ] 旧人台书页无新字段时显示默认人台。
- [ ] 魔法贴纸编辑页“更换底图”展示空白 / 人台 / 图库三入口。
- [ ] 穿搭手帐新增书页使用同一套底图选择体验。
- [ ] 选择 `基础线稿人台` 后，编辑器、缩略图、分享/快照导出一致。
- [ ] 选择空白后清除图库图与人台 ID，不残留旧底图。
- [ ] 选择图库图片后继续走 3:4 裁剪，并清除人台 ID。
- [ ] 历史缺失人台 ID 回退默认人台，不崩溃。
