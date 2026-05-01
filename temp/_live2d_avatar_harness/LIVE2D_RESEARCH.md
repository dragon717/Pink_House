# Live2D 少女小人调研落地记录

日期：2026-05-01

## 结论

- 魔法贴纸里的小人应按 Live2D 素体来做：头、脸、躯干、髋、上臂、前臂、手、腿、脚都独立成层；头发和衣服都不是画死在身体上，而是独立可替换 package。
- 头发需要独立发型包：后发、前刘海、侧发、细节层、高光层拆开；换发型时替换整个 hairstyle package，不改身体素体。
- 小人自带的默认衣服属于角色包的一部分，不进普通贴纸列表；普通列表只放用户可以拖拽摆放的贴纸。
- 用户新增衣服贴纸如果要跟随 Live2D 动作，需要先按 slot 拆分，再绑定到相同骨骼：上衣到 torso，袖子到 upper/lower arm，裙摆到 skirt，鞋到 foot。
- SwiftUI 侧只消费 `AvatarCharacterID`、`AvatarAction`、`AvatarExpression`、`AvatarHairStyleID`，业务页不直接碰 Cubism 参数；以后 Cubism 上线时替换 renderer，不改魔法贴纸和萌宠对话的调用方式。

## 官方规范摘要

- Live2D 官方 Material Separation 文档说明，素材分离就是把插画拆成眼睫、眼球、轮廓等部件，这是建模必需流程；并且分得越细，模型质量越好。参考：[About Material Separation](https://docs.live2d.com/en/cubism-editor-manual/divide-the-material/)。
- 同一文档建议保留两套 PSD：素材分离 PSD 用于可回退编辑，导入 PSD 用于 Cubism Editor。我们的 harness 因此保留 `rig_manifest.json` 和 `outfit_manifest.json`，后续美术 PSD 可以直接替换 bootstrap PNG。
- ArtMesh 文档说明 PSD 导入后每个层或组会成为 ArtMesh，通过移动顶点实现变形和动作。参考：[About ArtMeshes](https://docs.live2d.com/en/cubism-editor-manual/concept-of-artmesh/)。
- Motion 文档说明 Native 运行时加载 `.motion3.json`，使用 `CubismMotionManager` 播放，并在每帧调用 update；动作可以设置 fade、loop 和优先级。参考：[About Motion](https://docs.live2d.com/en/cubism-sdk-manual/motion/)。

## 开源 Native 示例摘要

- 官方 Native Framework 负责模型显示、参数操作、motion、physics、rendering；Cubism Core 不在 GitHub 仓库内，需要从官方 SDK 包获得。参考：[CubismNativeFramework](https://github.com/Live2D/CubismNativeFramework)。
- 官方 Native Samples 里 iOS Metal sample 提供 `MetalUIView`、`ViewController.mm`、`LAppLive2DManager.mm`、`LAppModel.mm` 等文件，结构是：平台 view 管理 Metal layer 和 render loop，manager 负责模型集合，model 负责加载 `.model3.json`、motion、expression、physics、pose 并在每帧 update/draw。参考：[CubismNativeSamples Metal iOS src](https://github.com/Live2D/CubismNativeSamples/tree/develop/Samples/Metal/Demo/proj.ios.cmake/src)。

## 本项目拆分规则

- 素体层：`body_torso_base`、`head_face`、`arm_upper_left/right`、`arm_lower_left/right`、`hand_left/right`、`hip_base`、`leg_left/right`、`foot_left/right`。
- 发型包：`default_long_pink` 和 `short_bob` 都遵守同一层契约：`hair_back_base`、`hair_back_detail`、`hair_side_left/right_base`、`hair_side_left/right_detail`、`hair_front_bangs`、`hair_front_detail`、`hair_highlight_front/back`。
- 默认衣服内嵌层：`dress_bodice`、`dress_skirt`、`sleeve_left/right`、`wrist_cuff_left/right`、`hair_bows`、`neck_bow`、`shoe_left/right`。
- 默认衣服 manifest 必须标记 `show_in_sticker_list: false`，普通贴纸列表不读取这些层。
- 发型 manifest 也必须标记 `replaceable: true` 和 `show_in_sticker_list: false`，它属于人偶配置，不属于普通贴纸列表。
- 所有衣服 slot 必须记录目标骨骼和推荐 bbox；后续真正接 Cubism 时，这些 slot 映射到同名 Part/Drawable 或约定的 costume layer。

## 动作落地

- `idle` 循环，其它一次性动作如 `greet`、`wave`、`thinking`、`touchHead`、`touchBody` 播完回 `idle`。
- `talkLoop` 可以单独 motion manager 或 action group，避免和表情/眨眼同参数强冲突。
- 低电量、后台、页面离开时暂停 render loop；截图时取静态帧，魔法贴纸当前阶段继续用静态素体 fallback。
