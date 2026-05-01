# Live2D 少女人偶 Harness · 当前验收结果

日期：2026-05-01

## 结论

- 静态资源审计：PASS
- Swift 解析检查：PASS
- Git diff 空白检查：PASS
- GPT Image 2 少女小人静态图：PASS
- Live2D bootstrap 分层 PNG：PASS（18 层）
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
- `asserts/avatar/girl_v1/live2d/layers/` 已生成 18 个首版分层 PNG。
- `asserts/avatar/girl_v1/live2d/rig_manifest.json` 已记录 layer、zIndex、骨骼父子关系和 anchor。
- 后续拿到 `girl_v1_*.mov` 后放入 `asserts/avatar/girl_v1/video/`。
- 后续拿到 Cubism 包后放入 `asserts/avatar/girl_v1/live2d/`，再移除 `--allow-missing-live2d` 验收参数。
- 这批分层是工程 bootstrap，真正 Cubism 绑定前仍建议由美术补肩、肘、腕、髋、膝、脖子、发根、裙摆的隐藏延展。
