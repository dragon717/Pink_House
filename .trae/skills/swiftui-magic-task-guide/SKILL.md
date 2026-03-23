---
name: "swiftui-magic-task-guide"
description: "魔法任务引导（含跨页面高亮）实现技能。Invoke when fixing onboarding step jumps, misaligned spotlight frames, or cross-screen guide targets in SwiftUI."
---

# SwiftUI 魔法任务引导技能

## 适用场景

- 魔法任务某个“新手引导”步骤被自动跳过
- 高亮框与真实 UI 控件位置/大小不一致
- 引导跨页面（例如「我」页 -> VIP 中心）需要持续定位目标控件
- 需要最小改动修复引导流程，不想重构整套系统

---

## 核心思路（先稳后优）

1. **步骤推进事件化**：避免 `onAppear` 直接跳步，改为“事件 + 条件”推进。  
2. **高亮锚点真实化**：优先采集真实控件 frame，而非硬编码 `CGRect`。  
3. **坐标转换标准化**：统一使用 global -> overlay local 转换。  
4. **兜底可用性**：保留 fallback frame，保证引导不“黑屏失效”。  
5. **临时状态清理**：开始/结束/取消引导时清空目标 frame。  

---

## 推荐落地流程（Checklist）

### Step 1：定位引导状态机

- 找到引导 manager（`@Published` 的当前步骤、开关状态）
- 标记每一步的真实推进触发条件（tab、通知、按钮点击、目标 frame 可用）
- 去掉与用户动作无关的自动跳步逻辑

### Step 2：接入目标控件 frame 采集

- 在目标页面给关键控件挂 `captureGlobalFrame`
- 只在 `width/height > 0` 时更新 frame
- 把 frame 存进引导 manager（按业务语义命名）

### Step 3：引导 Overlay 读取并渲染

- 先尝试真实 frame，拿不到再 fallback
- 转换坐标：
  - `localX = global.minX - overlayGlobalOrigin.x`
  - `localY = global.minY - overlayGlobalOrigin.y`
- 高亮与挖空使用同一 frame，避免视觉错位

### Step 4：做视觉微调参数

- 为每个步骤预留 `offset`（如 `dy = +10`）
- 用小常量调焦点，不改业务布局

### Step 5：回归验证

- 未解锁/已解锁两种卡片尺寸
- 小屏/大屏
- 深色/浅色
- 正常路径 + 中断路径（跳过引导/中途退出）

---

## 代码模板（可直接套）

### 1) 通用 frame 采集修饰器

```swift
private extension View {
    func captureGlobalFrame(onChange: @escaping (CGRect) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear {
                        guard frame.width > 0, frame.height > 0 else { return }
                        onChange(frame)
                    }
                    .onChange(of: frame) { newValue in
                        guard newValue.width > 0, newValue.height > 0 else { return }
                        onChange(newValue)
                    }
            }
        )
    }
}
```

### 2) Overlay 坐标转换

```swift
private func guideTargetFrame(
    globalFrame: CGRect?,
    in geometry: GeometryProxy,
    fallback: CGRect
) -> CGRect {
    guard let globalFrame, globalFrame.width > 0, globalFrame.height > 0 else {
        return fallback
    }

    let overlayOrigin = geometry.frame(in: .global).origin
    return CGRect(
        x: globalFrame.minX - overlayOrigin.x,
        y: globalFrame.minY - overlayOrigin.y,
        width: globalFrame.width,
        height: globalFrame.height
    )
}
```

### 3) 安全推进 step（示例）

```swift
if currentStep == .step1,
   currentTab == "me",
   manager.targetFrame != nil {
    withAnimation(.easeInOut(duration: 0.3)) {
        currentStep = .step2
    }
}
```

---

## 常见坑位

1. 在 `onAppear` 直接推进 step，用户未操作就跳步。  
2. 高亮 frame 和挖空 frame 不是同一套数据。  
3. 忘记坐标系转换，导致偏移。  
4. 未重置上一次 frame，导致“幽灵高亮”。  
5. 高亮层拦截点击，业务按钮点不到。  

---

## 最小化抽象建议（可选）

> 仅在同类引导 >= 2 个时再抽，避免过度设计。

### 方案 A（推荐）

- `GuideTargetStore`：统一存储 `key -> CGRect`
- `GuideTargetCaptureModifier(key:)`
- `GuideOverlayResolver`：统一做坐标转换 + fallback

### 方案 B（再下一步）

- `GuideStepDefinition` 配置化
- 新功能引导只加配置，不改大量 `switch`

---

## 关联文档

- `docs/MAGIC_TASK_GUIDE_BEST_PRACTICES.md`
- `docs/HOTSPOT_INTERACTION_FIX_SUMMARY.md`

