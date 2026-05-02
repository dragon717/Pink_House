# Live2D 少女人偶 Harness · 当前验收结果

日期：2026-05-02

## 结论

- 静态资源审计：PASS
- 分层边缘审计：PASS（`temp/_live2d_avatar_harness/runs/hair_cleanup_20260502_234027/`，12 张预览，27 组 `edge_contact_warnings` 待人工视觉确认）
- Swift 解析检查：PASS
- Manifest JSON/YAML 解析：PASS（JSON 走 `jq`，YAML 走 Ruby `YAML.load_file`；本机无 PyYAML）
- Git diff 空白检查：PASS
- GPT Image 2 少女小人静态图：PASS
- Live2D bootstrap 素体分层 PNG：PASS（15 层，头发已迁移到可替换发型包；大腿/小腿/脚已拆分）
- 可替换发型分层 PNG：PASS（2 个发型，每个 10 层；默认基础发已清理侧发碎片和脸部误抠色块）
- 默认衣服内置分层 PNG：PASS（10 层，隐藏于普通贴纸列表；当前限定长发成品）
- 魔法贴纸运行时默认裙装：PASS（运行时只合成素体 + 发型，默认裙装保留为隐藏内置包）
- 魔法贴纸贴纸缩放上限：PASS（`OOTDCanvasTransformLimits.maxStickerScale = 3.0`）
- 魔法贴纸小人显示尺寸：PASS（`AvatarMotionQualityProfile.magicStickerCanvasScale = 0.72`）
- 分层资源缓存：已接入，待真机观察首帧和重复打开表现
- 动效刷新策略：idle/talkLoop 24fps，手势类 30fps；后台、低电量、快照、缩略图静态帧
- 透明视频包：未交付，当前允许 fallback
- Live2D Cubism 包：未交付，当前仅保留透明 `MTKView` spike shell，不作为主路径

## 本轮验收命令

```bash
python3 temp/_live2d_avatar_harness/scripts/audit_avatar_assets.py \
  --manifest temp/_live2d_avatar_harness/MANIFEST.yaml \
  --allow-missing-video \
  --allow-missing-live2d

python3 temp/_live2d_avatar_harness/scripts/audit_avatar_layer_edges.py \
  --out-dir temp/_live2d_avatar_harness/runs/hair_cleanup_20260502_234027

xcrun swiftc -parse \
  ItemManager/Services/AvatarCharacterKit/AvatarCharacterModels.swift \
  ItemManager/Services/AvatarCharacterKit/AvatarMotionQualityProfile.swift \
  ItemManager/Services/AvatarCharacterKit/AvatarCharacterView.swift \
  ItemManager/Services/AvatarCharacterKit/AvatarPetDialogueAdapter.swift \
  ItemManager/Services/AvatarCharacterKit/AvatarLayeredMotionView.swift \
  ItemManager/Services/AvatarCharacterKit/Live2DAvatarView.swift \
  ItemManager/Services/VideoResourceManager.swift \
  ItemManager/Views/OOTD/OOTDComponents.swift \
  ItemManager/Views/OOTD/OOTDCanvasView.swift \
  ItemManager/Views/OOTD/OOTDPreviewView.swift \
  ItemManager/Views/OOTD/PageFlip/PageSnapshotCache.swift \
  ItemManager/Views/OOTD/BookDetail/PageThumbnailView.swift

jq empty \
  asserts/avatar/girl_v1/live2d/rig_manifest.json \
  asserts/avatar/girl_v1/live2d/hairstyles/hairstyle_index.json \
  asserts/avatar/girl_v1/live2d/hairstyles/default_long_pink/hairstyle_manifest.json \
  asserts/avatar/girl_v1/live2d/hairstyles/short_bob/hairstyle_manifest.json \
  asserts/avatar/girl_v1/live2d/outfits/default/outfit_manifest.json \
  asserts/avatar/girl_v1/live2d/clothing_sticker_split_rules.json

ruby -ryaml -e 'YAML.load_file("temp/_live2d_avatar_harness/MANIFEST.yaml")'

git diff --check
```

## 资源状态

- `avatar_girl_v1_static.png` 当前是浅色素体，不再包含默认裙装。
- `asserts/avatar/girl_v1/live2d/layers/` 包含 15 个身体素体首版分层 PNG：大臂、小臂、手、大腿、小腿、脚均为独立层。
- `asserts/avatar/girl_v1/live2d/hairstyles/` 包含 `default_long_pink` 和 `short_bob` 两个发型包。
- `asserts/avatar/girl_v1/live2d/outfits/default/layers/` 包含默认衣服内置分层 PNG。
- `asserts/avatar/girl_v1/live2d/clothing_sticker_split_rules.json` 继续记录后续衣服贴纸拆分 slot 和隐藏列表策略。
- 后续拿到 `girl_v1_*.mov` 后放入 `asserts/avatar/girl_v1/video/`。
- 后续拿到 Cubism 包后放入 `asserts/avatar/girl_v1/live2d/`，再移除 `--allow-missing-live2d` 验收参数。

## 2026-05-03 短发追加优化

- 短发碎发：PASS（`temp/_live2d_avatar_harness/runs/short_hair_cap_cleanup_20260503_003847/`）
- 处理方式：`short_bob` 改为单一前景发片承载整顶短发，其他短发分层保留透明占位，避免同一束头发被多个骨骼重复位移后撕裂。
- 颈侧碎片：已裁掉参考图里断开的 bob 下摆/颈侧发丝，v1 先保留“短发帽 + 刘海”的安全轮廓；真正 bob 下摆留给后续手工 PSD/Cubism 分层补齐。
- 已看预览：`short_bob_phase_0.png`、`short_bob_phase_1.png`，没有再出现两侧断开的碎发块。

```bash
python3 temp/_live2d_avatar_harness/scripts/materialize_avatar_layers.py

python3 temp/_live2d_avatar_harness/scripts/audit_avatar_layer_edges.py \
  --out-dir temp/_live2d_avatar_harness/runs/short_hair_cap_cleanup_20260503_003847

python3 -m py_compile \
  temp/_live2d_avatar_harness/scripts/materialize_avatar_layers.py \
  temp/_live2d_avatar_harness/scripts/audit_avatar_layer_edges.py \
  temp/_live2d_avatar_harness/scripts/audit_avatar_assets.py

python3 temp/_live2d_avatar_harness/scripts/audit_avatar_assets.py \
  --manifest temp/_live2d_avatar_harness/MANIFEST.yaml \
  --allow-missing-video \
  --allow-missing-live2d

jq empty \
  asserts/avatar/girl_v1/live2d/rig_manifest.json \
  asserts/avatar/girl_v1/live2d/hairstyles/hairstyle_index.json \
  asserts/avatar/girl_v1/live2d/hairstyles/default_long_pink/hairstyle_manifest.json \
  asserts/avatar/girl_v1/live2d/hairstyles/short_bob/hairstyle_manifest.json \
  asserts/avatar/girl_v1/live2d/outfits/default/outfit_manifest.json \
  asserts/avatar/girl_v1/live2d/clothing_sticker_split_rules.json

ruby -ryaml -e 'YAML.load_file("temp/_live2d_avatar_harness/MANIFEST.yaml")'

git diff --check -- \
  temp/_live2d_avatar_harness/scripts/materialize_avatar_layers.py \
  temp/_live2d_avatar_harness/ACCEPTANCE_RESULT.md \
  asserts/avatar/girl_v1/live2d/hairstyles/short_bob
```

备注：全仓 `git diff --check` 仍会被本任务外的 `ItemManager/Views/Pet/*` trailing whitespace 拦住，本轮未改那些无关文件。
