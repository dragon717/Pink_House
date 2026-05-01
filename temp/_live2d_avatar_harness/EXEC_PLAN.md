# Live2D 少女人偶 Harness · 执行计划

## A0 Harness
- 读取 `MANIFEST.yaml`，确认 `avatar_id`、动作、表情、三类后端路径齐全。
- 运行 `scripts/audit_avatar_assets.py --manifest temp/_live2d_avatar_harness/MANIFEST.yaml --allow-missing-video --allow-missing-live2d`。
- 产物放入 `temp/_live2d_avatar_harness/runs/A0_<ts>/REPORT.json`。

## A1 image2 素材
- 按 `IMAGE2_FALLBACK.md` 生成 `avatar_girl_v1_static.png` 与分层 PSD 规范稿。
- 静态 PNG 入 `ItemManager/Assets.xcassets/AvatarCharacter/girl_v1/avatar_girl_v1_static.imageset/`。
- 不提交 `generated/` 中间图；只提交最终 asset catalog 产物和 manifest/spec。

## A2 角色协议与后端
- 新增 `AvatarCharacterKit`：角色 ID、动作、表情、渲染后端、SwiftUI 统一视图。
- `.staticImage` 直接渲染 asset catalog；`.transparentVideo` 通过现有 `SeamlessVideoPlayer`；`.live2d` 先提供透明 `MTKView` spike shell。
- Swift 业务页只传 `AvatarRenderRequest`，不直接碰 Live2D/Cubism 参数。

## A3 魔法贴纸接入
- `OOTDMannequinBackground` 保留基础线稿人台，新增 `少女小人` 选项。
- 魔法贴纸与穿搭手帐的编辑器、缩略图、预览、快照都使用同一背景解析路径。
- 首版只作为背景小人层，不绑定贴纸到骨骼。

## A4 萌宠对话适配
- 新增 PetChat 动作到 `AvatarAction` 的映射。
- 现有宠物视频继续优先；未来少女角色视频/Live2D 只替换 resolver，不改对话业务。

## A5 Live2D Spike
- `Live2DAvatarView` 使用 `MTKView` 透明渲染壳，预留 Cubism Native SDK 接入点。
- 没有官方 Cubism Core/授权资源时不提交第三方 SDK 二进制，不阻断静态/视频 fallback。

## A6 验收修复
- 静态审计通过。
- 魔法贴纸默认页可打开，旧人台数据不变，少女小人选择后快照一致。
- PetChat 动作映射不改变现有宠物表现。
