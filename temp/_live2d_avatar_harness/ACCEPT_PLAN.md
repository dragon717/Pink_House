# Live2D 少女人偶 Harness · 验收清单

## 静态资源
- [ ] `audit_avatar_assets.py` 返回 `ok: true`。
- [ ] `avatar_girl_v1_static.png` 不是透明占位，比例接近 3:4。
- [ ] `MANIFEST.yaml` 覆盖 11 个动作与 6 个表情。
- [ ] Live2D 目录缺失时只给 warning，不影响静态/视频 fallback。

## 魔法贴纸
- [ ] 旧 `ootd_mannequin_default` 仍显示为基础线稿人台。
- [ ] “更换底图”里出现 `少女小人`。
- [ ] 编辑器、缩略图、预览、分享/快照走同一背景解析。
- [ ] 选择少女小人后不会清空贴纸，也不会残留图库背景。

## 萌宠对话
- [ ] `idle` / `sleep` 循环语义不变。
- [ ] 点击、思考、欢迎语动作仍优先使用现有宠物视频。
- [ ] 缺少少女视频或 Live2D 包时不黑屏、不崩溃。

## Live2D Spike
- [ ] SwiftUI 可创建 `Live2DAvatarView`。
- [ ] `MTKView` 透明背景，不遮挡业务背景。
- [ ] 进入后台暂停渲染，回前台可恢复。
