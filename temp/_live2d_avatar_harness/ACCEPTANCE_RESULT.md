# Live2D 少女人偶 Harness · 当前验收结果

日期：2026-05-01

## 结论

- 静态资源审计：PASS
- Swift 解析检查：PASS
- Git diff 空白检查：PASS
- GPT Image 2 少女小人静态图：PASS
- Live2D bootstrap 素体分层 PNG：PASS（13 层，头发已迁移到可替换发型包）
- 可替换发型分层 PNG：PASS（2 个发型，每个 10 层）
- 默认衣服内置分层 PNG：PASS（10 层，隐藏于普通贴纸列表）
- 魔法贴纸小人显示尺寸：PASS（少女小人画布缩放为 0.72）
- 贴纸最大缩放限制：PASS（上限 2.0，避免最大衣服贴纸覆盖完整小人）
- 透明视频包：未交付，当前允许 fallback
- Live2D Cubism 包：未交付，当前仅启用透明 `MTKView` spike shell

## 已跑命令

```bash
python3 temp/_live2d_avatar_harness/scripts/audit_avatar_assets.py \
  --manifest temp/_live2d_avatar_harness/MANIFEST.yaml \
  --allow-missing-video \
  --allow-missing-live2d

xcrun swiftc -parse \
  ItemManager/Services/AvatarCharacterKit/AvatarCharacterModels.swift \
  ItemManager/Services/AvatarCharacterKit/AvatarCharacterView.swift \
  ItemManager/Services/AvatarCharacterKit/AvatarPetDialogueAdapter.swift \
  ItemManager/Services/AvatarCharacterKit/Live2DAvatarView.swift \
  ItemManager/Services/VideoResourceManager.swift \
  ItemManager/Views/OOTD/OOTDComponents.swift \
  ItemManager/Views/OOTD/OOTDCanvasView.swift \
  ItemManager/Views/OOTD/OOTDPreviewView.swift \
  ItemManager/Views/OOTD/PageFlip/PageSnapshotCache.swift \
  ItemManager/Views/OOTD/BookDetail/PageThumbnailView.swift \
  ItemManager/Views/PetChat/PetChatView.swift \
  ItemManager/Views/PetChat/PetChatViewLegacy.swift

git diff --check
```

## 资源状态

- `avatar_girl_v1_static.png` 已替换为 `gpt-image-2` 生成的少女小人，并通过 chroma-key 去底。
- `avatar_girl_v1_static.png` 当前是浅白/淡蓝 unitard 素体，不再包含默认裙装。
- `asserts/avatar/girl_v1/live2d/layers/` 已生成 13 个身体素体首版分层 PNG。
- `asserts/avatar/girl_v1/live2d/hairstyles/` 已生成 `default_long_pink` 和 `short_bob` 两个发型包，每个包含前景、后景、侧发、细节、高光 10 层。
- `asserts/avatar/girl_v1/live2d/outfits/default/layers/` 已生成 10 个默认衣服内置分层 PNG。
- `asserts/avatar/girl_v1/live2d/clothing_sticker_split_rules.json` 已记录后续衣服贴纸拆分 slot 和隐藏列表策略。
- `temp/_live2d_avatar_harness/LIVE2D_RESEARCH.md` 已记录 Live2D 官方素材分离、ArtMesh、Motion 与 Native sample 调研结论。
- `asserts/avatar/girl_v1/live2d/rig_manifest.json` 已记录 layer、zIndex、骨骼父子关系和 anchor。
- 后续拿到 `girl_v1_*.mov` 后放入 `asserts/avatar/girl_v1/video/`。
- 后续拿到 Cubism 包后放入 `asserts/avatar/girl_v1/live2d/`，再移除 `--allow-missing-live2d` 验收参数。
- 这批分层是工程 bootstrap，真正 Cubism 绑定前仍建议由美术补肩、肘、腕、髋、膝、脖子、发根、裙摆的隐藏延展。
