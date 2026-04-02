---
name: "swiftui-rococo-pet-isometric-video"
description: "Rococo House 萌宠等轴方向与视频转场实现技能。Invoke when fixing pet walk direction, mirror glitches, turn timing, or seamless video switching in SmallWorld."
---

# SwiftUI Rococo 萌宠等轴视频技能

## 适用场景

- 萌宠在 House 里“左上/右上/左下/右下”方向判断错误
- `*_right_back` / `*_left_front` / `*_left_turn` 映射错乱
- turn 播放两次、触发时机不稳定、提前量不一致
- 转场时镜像闪反、淡入淡出不自然
- 毛毛/奶茶行走节奏需要分别调参

---

## 核心约束（必须遵守）

1. 使用统一等轴角（约 35°）四方向最近轴判定，不按房间写死方向轴。
2. turn 仅在 `左上->左下` 或 `右上->右下` 触发。
3. turn 默认提前量为 `120ms`（可参数化）。
4. turn 必须单次播放（需要“已提交目标”锁，防重复触发）。
5. 非 turn 的方向变化直接切目标循环，不等待旧循环自然结束。
6. 镜像在播放器 layer 内处理，不用外层 `scaleEffect` 翻转。

---

## 文件定位

- 方向与状态机：`ItemManager/ViewModels/SmallWorldPetViewModel.swift`
- 覆盖层渲染：`ItemManager/Views/SmallWorldPetOverlay.swift`
- 无缝切片播放器：`ItemManager/Views/Pet/SeamlessVideoPlayer.swift`
- 资源目录：`asserts/maomao/`、`asserts/naicha/`
- 参考文档：`docs/ROCOCO_PET_ISOMETRIC_VIDEO_BEST_PRACTICES.md`

---

## 落地步骤（Checklist）

### Step 1：确认资源契约

- 每只宠物都应有：
  - `*_right_back.mov`
  - `*_left_front.mov`
  - `*_left_turn.mov`
- 优先按“方向 + 镜像”复用，不新增冗余方向视频。

### Step 2：统一方向判定

- 输入：相邻位置向量 `(dx, dy)`
- 转数学坐标：`vy = -dy`
- 与四个等轴基向量（35°）点积取最大值，得到四方向。

### Step 3：方向映射到视频

- 右上 -> `*_right_back`，不镜像
- 左上 -> `*_right_back`，镜像
- 右下 -> `*_left_front`，镜像
- 左下 -> `*_left_front`，不镜像

### Step 4：turn 规则

- 只允许“上->下且同侧”触发。
- 采用 `120ms` lookahead 预判，避免转向滞后。
- 进入 turn 后锁定目标，直到 turn 播放完成。

### Step 5：切片与镜像稳定

- 非 turn 方向变化：立即切目标循环。
- turn：立即中断循环，播放一次 `*_left_turn`。
- 切片顺序：旧层淡出 -> 新层淡入（避免重叠感）。
- 镜像切换通过 `AVPlayerLayer.transform` 完成。

### Step 6：速度调参

- 同时调：
  1) 循环视频播放倍率
  2) 路径时长倍率
- 允许按宠物单独配置（如仅毛毛）。

### Step 7：回归核对

- `Room1 F1~F4`
- `Room2 F1~F4`
- `Room2 B1~B4`
- `Room1 B1~B4`
- 跨房 `2->1` 首段
- turn 单次播放
- 转场镜像无闪反

---

## 常见坑位

1. 用“房间深度轴”导致方向整体反向。
2. 等旧循环结束才切方向，导致展示方向滞后。
3. turn 无锁，lookahead 连续命中导致连播。
4. 外层镜像翻转导致切片瞬间旧层反向闪烁。
5. 只改视频速率不改路径时长，体感仍“跑太快”。

