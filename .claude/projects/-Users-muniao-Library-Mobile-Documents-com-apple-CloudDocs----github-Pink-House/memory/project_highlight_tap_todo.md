---
name: 高亮点击消失方案待调研
description: onHighlightTap callback 未生效，空间手帐 Step3/Step4 点击高亮后高亮未消失，需调研替代方案
type: project
---

空间手帐引导 Step 3（点击手帐卡片→3D翻页动画）和 Step 4（点击菜单项→自定义图片书页）的高亮在用户点击后未消失。

**已尝试方案（均未生效）：**
1. `.simultaneousGesture(TapGesture())` — 因 `allowsHitTesting(false)` 在遮罩层上，gesture 接收不到事件
2. `onHighlightTap` callback（在 `highlightedRectGuideContent` 内部加 `Color.clear` + `contentShape(Rectangle())` + `onTapGesture`）— 实测未生效，可能因为 ZStack 层级或 hit testing 传播问题

**Why:** 用户操作后高亮残留在动画/选择器上方，体验很差

**How to apply:** 需要进一步调研：
1. `Color.clear` 在 `allowsHitTesting(false)` 的 ZStack 中是否真正可接收点击
2. 是否应改在业务层（如手帐卡片的 onTapGesture、Menu action）直接发送通知推进步骤
3. 已记录到 `docs/MAGIC_TASK_GUIDE_BEST_PRACTICES.md` 3.3 和 3.11 节
