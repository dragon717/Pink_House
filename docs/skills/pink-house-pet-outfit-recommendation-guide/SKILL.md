---
name: pink-house-pet-outfit-recommendation-guide
description: Pink_House 萌宠智能搭配技能。用于实现或调整智能搭配、加一件、换一件、魔法贴纸、天气穿衣建议等推荐链路，统一上衣/外套语义、温度约束、配色排序、本地后处理与文案一致性。
---

# Pink House Pet Outfit Recommendation Guide

在 Pink_House 里处理这些需求时使用这个技能：

- 萌宠 `智能搭配`
- `+1 / 加一件`
- `换一件`
- `魔法贴纸`
- 天气穿衣建议
- 上衣 / 外套 / 开衫分类修正

## 先读

1. [../../PET_OUTFIT_RECOMMENDATION_BEST_PRACTICES.md](../../PET_OUTFIT_RECOMMENDATION_BEST_PRACTICES.md)
2. [../../AI_BEST_PRACTICES.md](../../AI_BEST_PRACTICES.md)
3. 如果任务涉及 Pet Chat 气泡和快捷入口，再读 [../../PET_CHAT_SINGLE_BUBBLE_PROTOCOL_V1.md](../../PET_CHAT_SINGLE_BUBBLE_PROTOCOL_V1.md)

## 工作流

1. 先确认用户改的是哪条链路：
   - 智能搭配
   - 加一件
   - 换一件
   - 魔法贴纸
   - 天气穿衣建议
2. 检查分类语义是否统一：
   - `top` 和 `outerwear` 是否独立
   - `开衫` 是否保持主类为 `outerwear`
   - `开衫` 是否只在缺上衣时补 `top` 位
3. 检查温度约束是否合理：
   - 是否基于 `feelsLikeTemperature`
   - `20°C+` 是否屏蔽重外搭
   - `23°C+` 是否避免默认推荐厚秋装外套
4. 检查颜色排序：
   - 是否优先同色系 / 邻近色
   - 是否控制主色数量
   - 鞋包小物是否承担中和作用
5. 检查本地后处理：
   - 最终重排是否保留独立的 `top` 槽位
   - 是否允许 `top + outerwear` 同时出现
6. 检查文案与 UI：
   - 文案是否基于最终单品重建
   - 快捷入口是否和当前缺口一致
   - OOTD / 抠图分类是否没有把上衣重新并回外套

## 必守规则

- 不要把 `上衣 / 内搭 / 衬衫 / 短袖 / 长袖` 重新并回 `outerwear`。
- 不要在高温场景默认推荐厚外套。
- 不要让 AI 原始描述覆盖本地最终结果。
- 不要只改推荐逻辑，不同步快捷入口、失败兜底文案和 OOTD 分类。
- 不要在一个模块里引入 `top`，却在另一个后处理模块又把它并回 `outerwear`。

## 优先检查的代码位置

- `ItemManager/Services/AI/ClothingSemanticAnalyzer.swift`
- `ItemManager/Services/AI/OutfitSuggestionService.swift`
- `ItemManager/Services/AI/WardrobeContextManager.swift`
- `ItemManager/Views/PetChat/PetChatCoreHelpers.swift`
- `ItemManager/Views/PetChat/PetChatView.swift`
- `ItemManager/Views/PetChat/PetChatViewLegacy.swift`
- `ItemManager/Services/CutoutService.swift`
- `ItemManager/Views/OOTD/OOTDCutoutListView.swift`

## 默认实现策略

- 用户没指定时，`+1` 优先补 `top`，再补 `accessory`、`shoes`、`outerwear`。
- `23°C` 左右默认优先 `内搭 / 短袖 / 长袖 / 衬衫 / 轻薄开衫`。
- `开衫` 仅在“缺上衣”或“明确要轻薄外搭”时升权。
- 摘要文案优先描述最终的上身结构和主色系，不复用已经失真的 AI 原文。

## 什么时候必须补文档

如果你改了这些内容，必须同步更新 [../../PET_OUTFIT_RECOMMENDATION_BEST_PRACTICES.md](../../PET_OUTFIT_RECOMMENDATION_BEST_PRACTICES.md)：

- 温度阈值
- 分类口径
- 快捷引导优先级
- 配色规则
- 推荐链路结构

## 输出要求

如果任务涉及智能搭配推荐：

1. 明确说明改动影响的是哪条链路。
2. 明确说明是否涉及 `top / outerwear / cardigan` 语义调整。
3. 明确说明温度规则是否变更。
4. 说明文案、贴纸、快捷引导是否同步更新。
