# 萌宠移动动画冻结与底部菱形轨迹复用指南

本文档沉淀两类在 `Pink_House` 内高频复用的萌宠动画方案：

1. **按素材时间轴冻结位移**：视频继续播放，但在指定时间段内不产生位移。
2. **iPhone iOS 26 底部导航最小化时的菱形轨迹猫**：悬浮猫进入底部中间留白区做菱形巡航。

目标是让后续实现同类需求时，直接复用统一思路，而不是在业务层到处打补丁。

---

## 1. 适用场景

### 1.1 素材继续播，但位移要暂停

典型例子：

- `naicha_left_front` 在素材时间轴 `3s ~ 5s` 内看起来是“站住/停步”状态
- 这段时间如果还继续移动，会产生明显违和感

此时正确做法是：

- **播放器继续播**
- **运动层暂停累计位移时间**
- 出了冻结区间后，**从当前位置继续走**

不要做成：

- 播放器暂停
- 或者 5 秒后瞬间追赶到理论位置

### 1.2 iOS 26 底部导航分散后，中间区域放一只巡航猫

典型例子：

- iPhone + iOS 26
- 底部 TabBar 在向下滚动后进入 compact/minimized 形态
- 左右按钮分散，中间留出一块空间
- 希望悬浮猫进入该区域，沿菱形轨迹巡航

---

## 2. 最佳实践总原则

### 2.1 播放器只负责“播放”，运动层只负责“位移”

推荐职责切分：

- `SeamlessVideoPlayer`
  - 负责播放、循环、镜像、进度回调
- Motion / ViewModel
  - 负责路径进度、转向、暂停、冻结位移、命中测试

这样做的好处：

- 不污染播放器通用逻辑
- 同一个素材冻结规则可以复用于多个移动场景
- 后续换素材时，只改策略层或配置层

### 2.2 用“素材时间轴”驱动冻结，不用“现实时间”

冻结判断必须基于：

- 当前素材名
- 当前素材播放进度 `clipTime`

不要基于：

- `Timer` 走了几秒
- 当前页面出现了多久
- 0.5 倍速后的现实时间

原因：

- 用户要的是“素材在第 3~5 秒看起来没走，就别位移”
- 即使改成 `0.5x` 播放，也应该仍然按照素材第 `3~5s` 判断

### 2.3 停位移时，要停“位移时间轴”，不是停“位置更新函数”

正确做法：

- 单独维护一个 `movementElapsed`
- 每帧只在“未冻结”状态下累计 `delta`
- 路径 progress 永远由 `movementElapsed / duration` 计算

这样：

- 冻结期间位置稳定
- 解冻后不会瞬移追帧
- 效果更像“小猫停停走走”

错误做法：

- 冻结时不更新 position，但 elapsed 仍继续增长
- 这样一过冻结窗口就会立刻跳到前面

### 2.4 对“视频名 -> 位移冻结规则”做统一策略层

不要在多个业务 ViewModel 里写这种散落特判：

- `if currentVideo == "naicha_left_front" && current > 3 && current < 5`

正确做法：

- 建立统一策略层，例如 `PetClipMotionFreezePolicy`
- 输入：`videoName + clipTime`
- 输出：`shouldFreezeTranslation`

这样方便：

- 后续新增别的素材冻结窗口
- 给某个素材加开关
- 换资源后关闭旧规则

---

## 3. 当前项目落地结构

### 3.1 冻结位移策略层

统一策略文件：

- `ItemManager/Services/PetClipMotionFreezePolicy.swift`

当前约定：

- `naicha_left_front`
- 冻结窗口：`3.0 ... 5.0`
- 保留全局开关，方便以后换素材关闭

### 3.2 已接入的运动场景

#### A. 小世界移动猫

- ViewModel：`ItemManager/ViewModels/SmallWorldPetViewModel.swift`
- View：`ItemManager/Views/SmallWorldPetOverlay.swift`

接法：

- `SeamlessVideoPlayer.onProgress`
- `viewModel.updateMotionClipProgress(current:duration:)`
- `SmallWorldPetViewModel` 内维护：
  - `movementElapsed`
  - `lastMovementTick`
  - `isTranslationFrozenByClip`

#### B. 底部菱形轨迹猫

- ViewModel：`ItemManager/ViewModels/BottomAccessoryCatDiamondOrbitViewModel.swift`
- View：`ItemManager/Views/Pet/Components/BottomAccessoryCatDiamondOrbitView.swift`

接法：

- `SeamlessVideoPlayer.onProgress`
- `viewModel.updateMotionClipProgress(current:duration:)`
- Orbit ViewModel 内维护：
  - `lapElapsed`
  - `lastMovementTick`
  - `isTranslationFrozenByClip`

---

## 4. iOS 26 底部菱形轨迹的设计要点

### 4.1 优先保留旧悬浮猫逻辑作为 fallback

推荐策略：

- compact/minimized 状态：显示菱形轨迹猫
- 非 compact/minimized 状态：继续显示旧 `PetOverlayView`

这样风险最低，也便于灰度调整。

### 4.2 不要优先使用 `tabViewBottomAccessory`

在本项目里，`tabViewBottomAccessory` 会引入额外的液态玻璃区域，视觉上不符合目标。

更稳妥的方案：

- 使用普通 overlay 渲染猫
- 用 UIKit introspection 读取当前 tab bar 状态

### 4.3 compact/minimized 状态识别要看真实 UIKit 结构

本项目最终采用的判断思路是：

- 通过 `TabBarItemAnchorResolver.compactCenterPlatterState()`
- 结合：
  - 主 `UIKit._UITabBarPlatterView` 的 `isHidden`
  - alpha
  - width ratio

原因：

- 单靠 frame 宽度不稳定
- UIKit 在 iOS 26 的 compact 形态下，真实可见性变化比尺寸阈值更可靠

### 4.4 菱形轨迹的起点必须先明确

常见两种需求：

- **顶部点启动**：旧悬浮猫看起来位于菱形上边
- **底部点启动**：旧悬浮猫看起来位于菱形下边

做法不要硬编码在 View 里，建议放到配置：

- `BottomAccessoryCatDiamondOrbitConfig.startAnchor`

### 4.5 菱形整体位置不要直接绑定 compact frame 中心

更稳妥的做法：

- 先算“旧悬浮猫基准锚点”
- 再反推 overlay 的 center 和 diamond center

这样调位置时更直观，只需要调锚点高度，而不是到处改 ratio。

当前关键参数位置：

- `ItemManager/Views/MainTabView.swift`
- `diamondOrbitLayout(frame:)`

建议优先调这些参数：

- `floatingCatAnchor.y`
- `overlayCenter.y`
- `diamondHeightRatio`
- `speedScale`

---

## 5. 推荐实现步骤

### 5.1 做“素材时间轴冻结位移”时

1. 找到实际产生位移的 ViewModel
2. 确认播放器是否已有 `onProgress`
3. 新增统一策略层
4. View 层把 `onProgress` 透传给 ViewModel
5. ViewModel 改成单独维护 `movementElapsed`
6. 冻结时只停 `movementElapsed`，不要停视频播放
7. 确认循环播放时，每一轮都能重复命中冻结窗口

### 5.2 做“底部菱形轨迹猫”时

1. 先确认 iPhone + iOS 26 可用性门槛
2. 保留旧悬浮猫 fallback
3. 用 introspection 判断 compact/minimized 状态
4. 把轨迹参数收敛到 `BottomAccessoryCatDiamondOrbitConfig`
5. 保持点击猫仍能跳到萌宠对话
6. 调整位置时优先改 anchor，不要先改动画逻辑

---

## 6. 参数调优建议

### 6.1 调“看起来太快”

要区分两种速度：

- **视频播放速度**
  - 由 `motionPlaybackRate` 控制
- **位移速度**
  - 由路径 duration 或 `speedScale` 控制

如果用户说：

- “动作播太快” -> 优先改 `motionPlaybackRate`
- “走路太快” -> 优先改 `speedScale` 或 path duration

不要把两者混在一起改。

### 6.2 调“菱形太低/太高”

优先级建议：

1. 改 `floatingCatAnchor.y`
2. 再看是否要改 `overlayCenter.y`
3. 最后才改 `diamondHeightRatio`

原因：

- 改 anchor 最容易保持轨迹形状不变
- 改 ratio 容易连带影响转向和可点击区域

### 6.3 调“冻结窗口不自然”

优先调：

- 冻结区间本身，例如 `3.0...5.0`

再调：

- 位移速度
- 视频播放速度

不要先去改播放器 seek 逻辑。

---

## 7. 调试建议

### 7.1 适合保留的日志

- compact 状态变化日志
- orbit layout 日志
- 当前视频名 + 当前 clip time + 是否冻结位移

### 7.2 不要长期保留的日志

- 大量 UIKit subview dump
- 高频每帧打印
- 临时试错日志

确认 root cause 后要尽量收敛，否则会影响后续问题定位。

---

## 8. 回归检查清单

每次调整这类萌宠移动动画，至少检查以下几点：

- `naicha_left_front` 在 `3~5s` 内视频继续播放，但位置不变
- 5 秒后从当前停住的位置继续移动
- 循环下一轮时仍会再次冻结
- 小世界移动猫行为正常
- 底部菱形轨迹猫行为正常
- 点击菱形猫仍能跳转到萌宠对话
- 非 compact 状态下旧悬浮猫正常显示
- iOS 可用性判断没有破坏低版本编译

---

## 9. 一句话复用口诀

> 播放器给进度，运动层管位移；冻结停时间轴，不停视频；底部轨迹先定锚点，再调菱形参数。
