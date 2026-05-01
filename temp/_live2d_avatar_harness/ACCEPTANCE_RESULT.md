# Live2D 少女人偶 Harness · 当前验收结果

日期：2026-05-01

## 结论

- 静态资源审计：PASS
- Swift 解析检查：PASS
- Git diff 空白检查：PASS
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

- `avatar_girl_v1_static.png` 当前使用线稿人台 fallback，尺寸 1024x1366，比例通过。
- 后续拿到 image2 正式少女概念稿后，直接覆盖同名 PNG 并重跑审计。
- 后续拿到 `girl_v1_*.mov` 后放入 `asserts/avatar/girl_v1/video/`。
- 后续拿到 Cubism 包后放入 `asserts/avatar/girl_v1/live2d/`，再移除 `--allow-missing-live2d` 验收参数。
