# Live2D 少女人偶 Harness · 执行计划

## A0 Baseline
- 读取 `MANIFEST.yaml`，确认 `avatar_id`、动作、表情、三类后端路径和 `acceptance.magic_sticker_v1` 齐全。
- 运行 `scripts/audit_avatar_assets.py --manifest temp/_live2d_avatar_harness/MANIFEST.yaml --allow-missing-video --allow-missing-live2d`。
- 运行 `scripts/audit_avatar_layer_edges.py --out-dir temp/_live2d_avatar_harness/runs/<phase>`，固定输出长发素体、短发素体、默认裙装四帧预览。

## A1 Visual Cleanup
- 美术拆层按身体、发型、内置衣服三类 package 维护；发型和默认衣服继续 `show_in_sticker_list: false`。
- 身体 package 必须保留大臂、小臂、手、大腿、小腿、脚独立层；优先修头发破碎、alpha 边缘残片、肩肘腕髋膝断层、裙摆/袖口遮挡层级。
- 每次素材替换后跑边缘审计，`edge_contact_warnings` 需要人工看图确认是否可接受。

## A2 Motion Profile
- 业务层仍只传 `AvatarRenderRequest`，不暴露 Cubism 参数。
- `AvatarMotionQualityProfile` 集中管理 24/30fps、动作幅度、静态帧、低功耗暂停和魔法贴纸小人缩放。
- `AvatarLayeredMotionView` 使用分层 PNG + 骨骼锚点模拟轻动效；快照、缩略图、后台、低电量都固定静态帧。

## A3 Runtime Integration
- `OOTDMannequinBackground` 保留基础线稿人台，少女素体长发/短发继续共用 `girl_v1`；运行时默认只显示素体 + 发型，不自动合成默认裙装。
- 魔法贴纸编辑页可手动开启动效；离页或换成非少女人台时自动关闭。
- 编辑器、缩略图、预览、分享/快照继续走同一背景解析路径。

## A4 Performance
- 分层资源通过 `AvatarLayerAssetResolver` 内存缓存复用，避免每个 SwiftUI 视图重复磁盘解码。
- 当前 `live2d` 后端优先走分层 PNG；无分层资源时才落到透明 `MTKView` spike shell，且 shell 限制 24fps。
- 不接入第三方 SDK 二进制；拿到官方 Cubism Core、`.model3.json`、`.moc3` 后再进入独立 Cubism 阶段。

## A5 Verification
- iOS 阶段默认不主动跑 `xcodebuild`；用 Swift parse、`git diff --check`、manifest JSON/YAML 解析和 harness 脚本做静态验收。
- 模拟器只做第一轮编辑页交互观察；最终性能仍以真机 Instruments 为准。
