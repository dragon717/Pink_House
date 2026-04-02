# Rococo House 萌宠等轴视频最佳实践

本文档沉淀 Rococo House 萌宠（毛毛/奶茶）在“透明通道视频 + 路径行走 + 转向过渡”场景下的稳定实现方式，覆盖方向判定、镜像策略、turn 播放时机、无缝切片和调参规范。

## 1. 目标与范围

适用范围：

- `ItemManager/ViewModels/SmallWorldPetViewModel.swift`
- `ItemManager/Views/SmallWorldPetOverlay.swift`
- `ItemManager/Views/Pet/SeamlessVideoPlayer.swift`
- `asserts/maomao/*`、`asserts/naicha/*`

核心目标：

1. 行走方向与等轴视角一致（左上/右上/左下/右下）。
2. 行走循环、转向 turn、跨段切片可控且可预测。
3. 切片过程自然（淡入淡出、避免重叠和镜像闪反）。
4. 支持宠物差异化速度调参。

---

## 2. 视频资源契约（Contract）

每只宠物至少包含：

- `*_right_back.mov`：上行（右上基准）
- `*_left_front.mov`：下行（左下基准）
- `*_left_turn.mov`：上->下转向（通过镜像支持左右）

当前目录约定：

- `asserts/maomao/maomao_right_back.mov`
- `asserts/maomao/maomao_left_front.mov`
- `asserts/maomao/maomao_left_turn.mov`
- `asserts/naicha/naicha_right_back.mov`
- `asserts/naicha/naicha_left_front.mov`
- `asserts/naicha/naicha_left_turn.mov`

说明：

- 非 turn 动画遵循“上行/下行 + 镜像”复用。
- `turn` 只作“上行转下行”过渡，且只播放一次。

---

## 3. 等轴方向判定（必须统一）

### 3.1 判定原则

禁止按房间写死方向轴。统一采用等轴角（约 35°）做四方向最近轴判定：

1. 将屏幕坐标转为数学坐标（`vy = -dy`）。
2. 用运动向量与四个等轴基向量（右上/左上/右下/左下）做点积。
3. 取点积最大者作为当前方向。

这样可以避免 `Room2 F1/F2/F4` 等路径段因“房间轴偏置”误判成相反方向。

### 3.2 方向到视频映射

- `右上` -> `*_right_back`，不镜像
- `左上` -> `*_right_back`，左右镜像
- `右下` -> `*_left_front`，左右镜像
- `左下` -> `*_left_front`，不镜像

---

## 4. turn 触发与节奏控制

### 4.1 触发条件（严格）

仅在以下两类方向变化触发 turn：

- `左上 -> 左下`
- `右上 -> 右下`

也就是“上行 -> 下行，且左右侧不变”。

### 4.2 提前量（lead time）

- turn 触发采用前瞻判定，默认提前量：`120ms`。
- 实现方式：用当前时刻 + `120ms` 的 lookahead 方向作为目标方向。

### 4.3 单次播放防抖

- turn 期间要有“已提交目标”锁（如 `turnCommittedTarget`）。
- turn 未完成前，方向回弹不允许再次触发 turn。

---

## 5. 切片与镜像稳定性

### 5.1 切片策略

- 非 turn 方向变化：直接切目标循环（避免“等旧循环播完”造成方向滞后）。
- turn：立即打断循环并播放一次 turn。

### 5.2 淡入淡出

- 切换时先旧层淡出，再新层淡入。
- 不让新旧层同时明显可见，避免重叠感。

### 5.3 镜像位置（关键）

镜像必须作用在播放器内部 layer 上，而不是外层 SwiftUI `scaleEffect`：

- 正确：对 `AVPlayerLayer.transform` 做左右翻转。
- 风险：外层翻转会在切片瞬间把旧层也翻转，出现“一闪反向”。

---

## 6. 循环视频收尾规则

统一约束：

1. 循环视频切换到其他行为时，先停循环，再播到尾（停在末帧）。
2. turn 是单次视频，播完回目标循环。
3. 首次新手引导中涉及的跑动/过渡视频也遵循同一收尾语义。

---

## 7. 速度调参与宠物差异化

推荐分两层调参，避免只改其中一层导致观感割裂：

1. **视频播放速率**（`motionPlaybackRate`）
2. **路径移动时长**（`path.duration * scale`）

示例（仅毛毛）：

- 循环播放倍率：`0.9x`
- 路径时长倍率：`1.18x`

这样会表现为“动作稍慢、走完整段更久”。

---

## 8. 回归测试矩阵（最小集）

每次改动后至少验证：

1. `Room1 F1~F4`
2. `Room2 F1~F4`
3. `Room2 B1~B4`
4. `Room1 B1~B4`
5. 跨房 `2 -> 1` 首段独立过渡
6. turn 只播一次
7. 转场镜像无闪反
8. 切片淡入淡出无明显重叠

---

## 9. 常见错误与根因

1. **方向整体反了**：使用了“房间深度轴”而非统一等轴四向。
2. **Room2 前段方向错**：切循环时等旧片尾，导致方向滞后显示。
3. **turn 连播两次**：缺少 turn 提交锁，前瞻判定重复命中。
4. **镜像一闪反向**：镜像挂在外层容器而非播放器 layer。
5. **速度改了但路程节奏没变**：只改播放速率，没改路径 duration。

---

## 10. 实施清单（Checklist）

- [ ] 使用等轴 35° 四方向最近轴判定
- [ ] 方向->视频映射遵循统一 contract
- [ ] turn 仅上->下且同侧触发
- [ ] turn 提前量为业务约定值（当前 120ms）
- [ ] turn 增加单次锁防重入
- [ ] 非 turn 方向变化立即切循环
- [ ] 切片按“旧淡出 -> 新淡入”执行
- [ ] 镜像在 `AVPlayerLayer` 内部处理
- [ ] 宠物速度调参同时覆盖“视频倍率 + 路径时长倍率”

