# 魔法任务引导定位与高亮最佳实践

本文档基于两条已落地链路沉淀：
- 萌宠智能对话（`aiAnalysis`）三步跨页面引导
- 来财（`wealth`）五步跨页面引导  

目标：让后续魔法任务引导改造可复用、可验证、低风险。

---

## 1. 问题复盘（本轮已修）

### 1.1 问题现象（AI 引导）

1. 点击“新手引导”后，第一步（返回「我」）被直接跳过。  
2. 第二步 VIP 卡片高亮与真实卡片容器尺寸不一致。  
3. 第三步“兑换会员时长”高亮偏上，视觉焦点不准。  

### 1.2 根因（AI 引导）

1. **错误的自动跳步时机**：`onAppear` 里直接推进 step1 -> step2，未等待真实用户路径。  
2. **硬编码 frame**：高亮区域用固定 `CGRect`，无法适配不同卡片尺寸/布局变化。  
3. **未做局部微调能力**：高亮与视觉焦点没有“轻量偏移参数”。  

---

### 1.3 问题现象（Wealth 引导）

1. 启动引导后错误跳到萌宠对话，不符合“先点 House”的用户路径。  
2. “马上来财”高亮范围偏大，与真实热区不一致。  
3. 热区理论可穿透，但首次点击命中率低（用户体感“点不进去”）。  
4. House 第一步高亮圈与猫爪视觉焦点不贴合，需要联动微调。  

### 1.4 根因（Wealth 引导）

1. **导航抢跑**：触发引导时做了自动 Tab 跳转。  
2. **采集层级错误**：对带 `position` 的容器做 frame 采集，得到的是大容器而非目标热区。  
3. **命中区过小**：视觉区域小、热区也小，虽能穿透但点击容错不足。  
4. **焦点只调一层**：只调猫爪或只调圈会造成“看着不准”。  

---

## 2. 已落地方案（当前实现）

### 2.1 步骤推进从“时间驱动”改为“事件驱动”

- 不在 `onAppear` 自动推进 step。  
- step1 -> step2 必须满足：
  - 用户回到 `me` tab；
  - 且已采集到 VIP 卡片真实 frame。  
- step2 -> step3 由 VIP 中心打开事件推进（`.vipCenterOpened`）。  

### 2.2 高亮从“硬编码”改为“真实控件坐标”

- 在 `MeView` 捕获 VIP 卡片全局 frame。  
- 在 `VIPCenterView` 捕获“兑换会员时长”按钮全局 frame。  
- Overlay 内把全局 frame 转成本地 frame 后绘制挖空与高亮。  

### 2.3 兼容策略

- 提供 fallback frame（兜底），避免采集失败时引导完全不可用。  
- VIP 卡片 fallback 同时适配两种高度：`100`（未开通）与 `180`（已开通）。  
- “兑换会员时长”高亮支持微调偏移（当前 `dy = +10`）。  

### 2.4 生命周期清理

- 每次开始/完成/关闭引导都清理引导目标 frame，避免旧页面坐标污染。  

### 2.5 Wealth 顺序与事件收敛

- 强制路径：`House tab -> 马上来财 -> 请签 -> 数钱 -> 安财`。  
- 不自动跳萌宠，不抢用户操作。  
- 通过通知驱动推进：`.homeTabChanged`、`.wealthDestinationOpened`、`.wealthViewOpened`、`.wealthMainTabChanged`。  

### 2.6 热区采集与命中区策略（关键）

- **采集**：用独立透明锚点采集目标 frame（`allowsHitTesting(false)`），不要直接对“可能被定位/缩放的容器”采集。  
- **命中**：对难点中的小热区，允许“仅扩命中区，不扩视觉文案区域”。  
- **一致**：命中区扩展后，高亮锚点也要同步扩展，避免“看得到点不到”。  

---

## 3. 最佳实践清单（可直接复用）

### 3.1 引导步骤推进

- [ ] 不在 `onAppear` 直接跳步骤。  
- [ ] 每个步骤定义明确“推进条件”（通知、状态、frame 可用性）。  
- [ ] 条件不满足时停留当前步骤，不抢跑。  

### 3.2 高亮定位

- [ ] 优先使用真实控件 frame。  
- [ ] 必须做 global -> local 坐标转换。  
- [ ] fallback 只作为兜底，不作为主路径。  
- [ ] 高亮圆角应与真实控件视觉风格一致。  

### 3.3 交互穿透

- [ ] 遮罩和高亮动画默认 `.allowsHitTesting(false)`。  
- [ ] 只让真实业务控件处理点击，减少误触。  
- [ ] 若用户反馈“第一下难点中”，先检查命中区尺寸，不要先怀疑穿透失效。  

### 3.4 状态管理

- [ ] 引导临时状态和业务状态分离。  
- [ ] 退出引导时重置临时锚点。  
- [ ] 日志打印只保留步骤关键路径。  

### 3.5 微调参数治理

- [ ] 把焦点偏移写成常量（如 `houseGuideXOffset/YOffset`），不要散落魔法数。  
- [ ] “圈 + 猫爪”联动调整，保持同一视觉目标。  
- [ ] 猫爪透明度/位置作为独立参数，便于按页面做细调。  

---

## 4. 建议的最小化抽象（按阶段）

> 目标：不做大重构，优先复用现有逻辑。

### Phase 0（已可用）

- 继续沿用当前模式：  
  `captureGuideTarget`（或旧链路 `captureGlobalFrame`）+ `GuideManager` 存储目标 frame + Overlay 渲染。  

### Phase 1（低成本建议）

抽出一个通用锚点采集修饰器与键名体系：

- `GuideTargetKey`（如 `ai.vipCard`, `ai.exchangeButton`）  
- `GuideTargetCaptureModifier(key:)`  
- `GuideTargetStore`（统一存取/重置）  

收益：减少多个页面重复写 `captureGlobalFrame` 与 `updateXXXFrame`。
收益：减少多个页面重复写目标采集与 `updateXXXFrame`。

### Phase 2（可选）

抽象步骤配置模型：

- `GuideStepDefinition`：
  - `title/message`
  - `highlightKey`
  - `highlightStyle`
  - `advanceWhen`（条件闭包）  

收益：后续新增魔法任务引导步骤只加配置，不改大量 if/switch。

---

## 5. 回归测试建议

### 5.1 核心流程

1. 从“魔法任务 -> 萌宠智能对话 -> 新手引导”进入。  
2. 验证第一步不会自动跳过。  
3. 点击返回到「我」，验证第二步显示且高亮贴合 VIP 卡片。  
4. 点击 VIP 卡片进会员中心，验证第三步高亮落在“兑换会员时长”按钮中心偏下。  

### 5.2 变体覆盖

- [ ] `vipManager.isVIP == false`（小卡片高度）  
- [ ] `vipManager.isVIP == true`（大卡片高度）  
- [ ] 不同屏幕尺寸（小屏/大屏）  
- [ ] 深浅色模式（观察对比度）  

### 5.3 Wealth 专项补充

- [ ] 从魔法任务点击“新手引导”后，第一步停留在“先进入 House”（不自动跳萌宠）。  
- [ ] “马上来财”第一下点击命中率可接受（建议连续测 10 次，>= 9 次成功）。  
- [ ] 点中“马上来财”后可立即推进步骤，且无点击拦截体感。  
- [ ] House 第一步高亮圈与猫爪位置一致，且在目标右下微调后视觉合理。  

---

## 6. 关键冲突与决策建议

### 冲突 A：严格顺序 vs 自动导航便捷

- 决策：引导优先“用户操作感知”，不抢跳页面。  
- 原因：自动导航虽快，但会造成“我没点就过去了”的失控感。

### 冲突 B：高亮精准 vs 点击容错

- 决策：视觉高亮贴近真实热区，同时可对点击目标做小幅命中扩展。  
- 原因：移动端真实使用中，命中容错比像素级精度更影响体验。

### 冲突 C：穿透正确 vs 首次命中失败

- 决策：先验证命中框大小，再验证遮罩 hit-testing。  
- 原因：大量“点不进去”并非穿透失败，而是热区过小。

---

## 7. 相关文件（当前实现）

- `ItemManager/Services/NewbieGuideManager.swift`
- `ItemManager/Views/MeView.swift`
- `ItemManager/Views/VIP/VIPCenterView.swift`
- `ItemManager/Views/MainTabView.swift`
- `ItemManager/Views/RococoSmallWorldView.swift`
- `ItemManager/Views/FrenchRetroSmallWorldView.swift`
- `docs/MAGIC_TASK_GUIDE_TEST_MATRIX.md`
