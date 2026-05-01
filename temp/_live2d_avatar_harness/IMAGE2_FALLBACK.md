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
Full-body front-facing anime-inspired wardrobe assistant base body, matte warm white and pale blue
unitard, delicate magic sticker journal style, transparent PNG, 3:4 canvas, centered full body,
neutral A-pose, limbs visible and separable, suitable as a Live2D-riggable dress-up doll base.
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
- 发型包：后发、后发细节、前刘海、前发细节、左右侧发、左右侧发细节、前后高光
- 脸底、左右眼白、瞳孔、高光、眼皮、左右眉
- 嘴型 A/I/U/E/O
- 腮红、裙摆、配饰
- 肩、肘、腕、髋、膝、脖子、发根、裙摆必须有隐藏延展区域，避免骨骼旋转露空

## 输出 3：可替换发型包

每个发型都必须交付同一套层名，便于 Live2D runtime 切换：

- `hair_back_base`
- `hair_back_detail`
- `hair_side_left_base`
- `hair_side_right_base`
- `hair_side_left_detail`
- `hair_side_right_detail`
- `hair_front_bangs`
- `hair_front_detail`
- `hair_highlight_front`
- `hair_highlight_back`

默认发型：`default_long_pink`。首个替换发型：`short_bob`。

## 落地规则

- 最终 PNG 必须是 PNG-32，透明背景，3:4。
- 发型包和衣服包属于 Avatar 内嵌资源，必须 `show_in_sticker_list=false`，不进入普通贴纸列表。
- 不提交 `temp/_live2d_avatar_harness/generated/` 中间图。
- 没有 image2 正式稿时，可以暂用现有线稿人台作为静态 fallback，但验收报告必须标记为 `fallback_source=ootd_mannequin_default`。
