---
name: pink-house-discount-badge-guide
description: Pink_House 折扣标识UI技能。用于实现和复用 -xx% OFF、折扣角标、行内优惠提示、发光优惠标签，以及避免 Capsule 被父布局拉伸等折扣UI常见问题。
---

# Pink House Discount Badge Guide

在 Pink_House 里做折扣角标、优惠标签、`-40% OFF`、`-10% OFF`、套餐省钱提示时使用这个技能。

## 先读

1. [../../DISCOUNT_BADGE_UI_BEST_PRACTICES.md](../../DISCOUNT_BADGE_UI_BEST_PRACTICES.md)
2. 如果当前页面属于 VIP 体系，再读 [../../VIP_UI_PLAYBOOK.md](../../VIP_UI_PLAYBOOK.md)

## 默认做法

优先复用共享组件：

- [DiscountBadgeView.swift](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/Components/DiscountBadgeView.swift)

### 推荐映射

- 套餐卡右上角：`DiscountBadgeStyle.capsuleGlow`
- 权益描述中的局部折扣：`DiscountBadgeStyle.inlineGlow`

## 必守规则

- 不要在页面里重复手写一套新的折扣样式。
- 不要让整段说明文字一起发光。
- 不要把 `Shape` 直接丢进会拉伸的 `ZStack/HStack` 里做角标背景。
- 胶囊角标必须使用内容驱动尺寸，优先 `Text + padding + background + fixedSize`。

## 什么时候扩组件

遇到这些情况时，先改共享组件，再改页面：

- 需要新的折扣颜色体系
- 需要新的 badge 尺寸
- 需要新的 badge 样式，例如描边贴纸、斜角标签、角落旗帜

## 输出要求

如果任务涉及折扣 UI：

1. 优先说明使用哪种 badge 样式
2. 优先复用共享组件
3. 如果新增样式，更新文档
4. 保持数字醒目，但不要盖过价格和主 CTA
