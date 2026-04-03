---
name: pink-house-vip-ui-guide
description: Pink_House VIP页与高级权益UI设计技能。用于复刻截图风格、抽象深色玻璃视觉系统、设计VIP权益信息架构、统一试用弹窗风格，以及把图标/皮肤等会员身份能力落到可扩展的SwiftUI结构中。
---

# Pink House VIP UI Guide

在 Pink_House 里做 VIP、试用弹窗、会员权益卡、个性图标页这类高级权益 UI 时使用这个技能。

## 目标

把“截图风格”转成可复用的产品化界面，而不是只做一次性的样式拼贴。

## 工作流

1. 先读 [../../VIP_UI_PLAYBOOK.md](../../VIP_UI_PLAYBOOK.md)
2. 再读 [../../VIP_REDESIGN_AND_CAPABILITY_LAYERING.md](../../VIP_REDESIGN_AND_CAPABILITY_LAYERING.md)
3. 如果涉及 `-xx% OFF`、优惠角标或折扣胶囊，再读 [../pink-house-discount-badge-guide/SKILL.md](../pink-house-discount-badge-guide/SKILL.md)
4. 按下面顺序工作：
   - 先抽视觉 token
   - 再定信息架构
   - 再映射业务权益
   - 最后接 SwiftUI 页面和入口

## 必守规则

- 不要先堆组件，先抽主题和玻璃卡样式。
- 不要把 VIP 入口做成硬拦截，优先拦第三方模型/API 能力。
- 不要把“专属感”只写成文案，优先落成真实可切换能力。
- 新权益优先抽成模型，不要直接写死在 view 里。

## 代码落地方向

- 视觉 token 放进独立系统文件，例如 `VIPVisualTheme`、`VIPGlassStyle`
- 页面级 UI 放在 `ItemManager/Views/VIP/`
- 权益与价格规则放在 `ItemManager/Services/VIP/`
- 与 VIP 相关但跨模块的能力入口，优先做成 manager 或 support helper

## 图标切换场景

做 VIP 图标库时，遵循这条路线：

1. 补齐 icon asset 和预览 asset
2. 用 manager 统一封装系统切图标
3. 让 VIP 页提供入口，不把切换逻辑散落在多个页面
4. 在 UI 上把图标视为“VIP 身份延伸”，不是普通设置项

## 什么时候继续补充参考

如果本次任务涉及：

- 新会员主题
- 新玻璃卡变体
- 新的图标库方案
- 主题皮肤商店

先更新 `VIP_UI_PLAYBOOK.md`，再改代码。
