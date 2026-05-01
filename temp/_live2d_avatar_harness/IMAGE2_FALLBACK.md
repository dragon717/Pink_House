# image2 交接单 · girl_v1 少女小人

## 输出 1：静态小人 PNG

文件名：

```text
avatar_girl_v1_static.png
```

输出到：

```text
ItemManager/Assets.xcassets/AvatarCharacter/girl_v1/avatar_girl_v1_static.imageset/avatar_girl_v1_static.png
```

Prompt：

```text
Full-body front-facing anime-inspired wardrobe assistant girl, delicate magic sticker journal style,
clean line art with soft pastel accents, transparent PNG, 3:4 canvas, centered full body, neutral pose,
suitable as a mannequin-like sticker background in a dress coordination editor.
```

Negative prompt：

```text
text, letters, watermark, logo, photorealistic, realistic 3D, harsh shadow, dirty background,
cropped limbs, fused fingers, missing joints, opaque background
```

## 输出 2：Live2D 分层 PSD 规范稿

文件名：

```text
avatar_girl_v1_layered_psd_spec.psd
```

分层要求：

- 头、脖子、身体、上臂、前臂、手、腿、鞋
- 前发、后发、侧发
- 脸底、左右眼白、瞳孔、高光、眼皮、左右眉
- 嘴型 A/I/U/E/O
- 腮红、裙摆、配饰
- 肩、肘、腕、髋、膝、脖子、发根、裙摆必须有隐藏延展区域，避免骨骼旋转露空

## 落地规则

- 最终 PNG 必须是 PNG-32，透明背景，3:4。
- 不提交 `temp/_live2d_avatar_harness/generated/` 中间图。
- 没有 image2 正式稿时，可以暂用现有线稿人台作为静态 fallback，但验收报告必须标记为 `fallback_source=ootd_mannequin_default`。
