# Discount Badge UI Best Practices

更新时间：2026-04-03

## 1. 适用场景

这份规范用于 Pink_House 里所有折扣、优惠、限时立减、套餐省钱提示等标识。

典型场景：

- VIP 套餐卡里的 `-5% OFF`
- 商店卡片里的 `-40% OFF`
- 主题皮肤商店里的 `-10% OFF`
- 活动页里的限时折扣标签

## 2. 设计目标

折扣标识的职责不是“补一句说明”，而是用最短时间告诉用户：

- 这里有优惠
- 优惠幅度是多少
- 这是可感知的价格激励

所以折扣标识必须满足三点：

- 一眼能看到
- 不抢主标题
- 在不同容器里都稳定

## 3. 推荐的两种样式

### 3.1 胶囊折扣角标

适合：

- 套餐卡
- 价格选择卡
- 需要单独贴在右上角的优惠标签

设计要求：

- 使用独立胶囊容器
- 字号小于卡片标题
- 可发光，但不要大过卡片主标题
- 必须 `fixedSize`

为什么要 `fixedSize`：

- 否则像 `Capsule()` 这类 `Shape` 很容易被父布局拉伸
- 尤其在 `HStack + Spacer + minHeight` 场景里，会被撑成大红条

### 3.2 行内发光折扣字

适合：

- “萌宠商店 -40% OFF”
- “主题皮肤商店 -10% OFF”
- 权益描述中的局部优惠强调

设计要求：

- 只让折扣字发光
- 业务说明文字仍保持白灰层级
- 不要整段话一起用红色

## 4. 当前统一实现

当前共享组件：

- [DiscountBadgeView.swift](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/Components/DiscountBadgeView.swift)

当前支持：

- `DiscountBadgeStyle.capsuleGlow`
- `DiscountBadgeStyle.inlineGlow`
- `DiscountBadgeSize.small`
- `DiscountBadgeSize.medium`

建议默认值：

- 套餐卡角标：`capsuleGlow + small`
- 权益卡行内折扣：`inlineGlow + small/medium`

## 5. 视觉 token 建议

当前折扣高亮方向：

- 亮红：`#FF4D5E`
- 深红柔光：`#FF2446`

使用原则：

- 红色只给折扣本体
- 不要把整张卡的边框和标题都染成同一种红
- 发光半径要小于主按钮 glow，避免页面视觉优先级反转

## 6. 常见错误

### 错误 1：用可扩张 Shape 直接包在 ZStack 里

错误写法的结果：

- 胶囊背景会被父布局撑满高度
- 折扣字看起来像被做成整列大红条

避免方式：

- 使用 `Text + padding + background(Capsule())`
- 并加 `.fixedSize()`

### 错误 2：整句说明一起发光

错误结果：

- 视觉噪音过大
- 用户看不出真正重点是折扣数字

避免方式：

- 把说明文字和折扣字拆开布局

### 错误 3：折扣标识比价格标题更抢

错误结果：

- 用户先看到“噪音”，再找不到主信息

避免方式：

- 折扣标识始终小于主标题
- glow 强度可高，但面积必须更小

## 7. 落地流程

以后遇到新的折扣 UI，按这个顺序做：

1. 先判断是角标还是行内折扣。
2. 优先复用 `DiscountBadgeView`。
3. 不够用时，先扩 style 或 size，不要在页面里直接手写一套。
4. 如果出现新视觉风格，先更新这份文档，再更新组件。

## 8. 当前使用示例

当前已落地页面：

- [VIPCenterView.swift](/Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/VIP/VIPCenterView.swift)

建议后续接入页面：

- 萌宠商店商品卡
- 主题皮肤商店
- 运营活动页
- 首购优惠弹窗
