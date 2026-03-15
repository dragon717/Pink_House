# AI 对话精确性与信息展示最佳实践 (AI Conversation & UX Best Practices)

## 1. 核心理念 (Core Philosophy)

### 1.1 角色优先 (Persona First)
- **AI 不仅仅是回答机器**，更是有性格的“萌宠/闺蜜”。所有的回复必须符合设定（如：喵/汪的口癖，贴心闺蜜的语气）。
- **拒绝机械感**：严禁出现“根据图片显示”、“作为一个AI模型”等打破沉浸感的词汇。

### 1.2 价值导向 (Value Driven)
- **展示的信息必须对用户当前场景有实际价值**。用户不关心“这是一张图片”，用户关心“这张图片里的裙装值不值得买”、“好不好看”。
- **主动服务**：AI 应当能够预判用户的潜在需求（如看到价格 -> 判断性价比；看到新款 -> 判断截团时间）。

---

## 2. 提高 AI 对话精确性 (Improving Accuracy)

### 2.1 上下文注入 (Context Injection)
AI 的回答质量取决于输入的信息量。单纯的文本输入往往不足以生成高质量回复。
- **视觉增强 (Vision)**: 在用户发送图片前，先通过 Vision/多模态模型提取关键信息（价格、物体类型、文字），作为“系统提示词”的一部分注入。
    - *代码参考*: [VisionAnalysisService.swift](file:///Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Services/AI/VisionAnalysisService.swift)
- **数据感知 (Data Awareness)**: 将用户的资产（衣柜、库存）、状态（VIP、好感度）作为背景信息告知 AI。
    - *代码参考*: `PetAIService.swift` 中的 `wardrobeContext`。

### 2.2 结构化提示词 (Structured Prompting)
- **明确指令**: 避免开放式提问。要求 AI 按照特定格式输出（如 `【视觉描述】`, `【猜你想问】`），便于程序解析和 UI 展示。
- **约束条件**: 明确设定字数限制（如“50字以内”）、语气（“贴心闺蜜”）、禁语（“不要说根据图片”）。
- **示例 (Few-Shot)**: 在 Prompt 中给出 1-2 个优秀的回复示例，让 AI 模仿语气和格式。

### 2.3 分层处理 (Layered Processing)
- **预处理**: 本地 Vision 快速识别 -> 确定意图 -> 组装 Prompt。
- **后处理**: 过滤 AI 幻觉（如错误提及不存在的功能），提取动作指令（如 `imageName` 触发动画）。

---

## 3. 用户展示信息遴选 (Information Curation)

### 3.1 提问优化：从“这是什么”到“更有价值的问题”
- **痛点**: 用户往往不知道该问什么，或者默认提问太宽泛，导致 AI 回复也很泛。
- **方案**: AI 预判用户可能感兴趣的点（如价格、截团时间、搭配建议），自动生成“猜你想问”，并直接作为用户的提问展示。
    - *案例*: 识别到 Lo裙 -> 自动生成“这个价格划算吗？” -> 用户点击/拖拽 -> AI 回复“亲爱的，这条裙装做工看着不错，价格也合理，不过要注意截团时间哦~”
    - *代码参考*: `VisionAnalysisService.swift` 中的 `suggestedQuestion` 生成逻辑。

### 3.2 回复优化：拒绝“说明书式”回答
- **情感化**: 将冷冰冰的参数（如“棉质，价格500”）转化为情感表达（“哇，是纯棉的呢，穿起来肯定很舒服，500元也很良心哦~”）。
- **引导性**: 回复末尾抛出钩子（Hook），引导下一轮对话（“要不要看看搭配的鞋子？”）。

### 3.3 UI 呈现最佳实践
- **折叠与展开**: 默认展示精炼结论，点击可查看完整推理/原始数据。
- **视觉反馈**: 使用状态机动画（思考中、开心、困惑）配合文字，增强沉浸感。
    - *代码参考*: [PetOverlayView.swift](file:///Users/muniao/Library/Mobile%20Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/Views/Pet/Components/PetOverlayView.swift) 中的 `isAnalyzing` 状态。

---

## 4. 落地实施指南 (Implementation Guide)

### 4.1 新增 AI 功能流程
1. **定义场景**: 用户在做什么？（拖拽、聊天、闲置）
2. **确定输入**: 需要哪些上下文？（图片、位置、历史对话）
3. **设计 Prompt**:
    - 角色设定 (System Prompt)
    - 任务描述 (User Prompt)
    - 输出格式 (Output Format)
4. **解析与展示**: 解析结构化输出，更新 UI 状态。

### 4.2 调试与迭代
- 建立 `Prompt` 版本控制。
- 收集 Bad Case（AI 说胡话、出戏），反向优化 `System Prompt` 中的 `Negative Constraints`（负向约束）。
- 定期更新 `PROJECT_CONCEPTS.md`，让 AI 理解最新的项目术语（如“尾款天使”不是系列，是支付模式）。

---

## 5. 关键代码模块 (Key Modules)

- **视觉分析服务**: `VisionAnalysisService.swift`
    - 负责调用本地 Vision 或云端模型，生成结构化的视觉描述和推荐问题。
- **AI 对话服务**: `PetAIService.swift`
    - 负责维护对话历史、注入角色设定、调用 LLM API。
- **交互视图**: `PetOverlayView.swift` / `AIAnalysisResultView.swift`
    - 负责捕捉用户操作（拖拽、长按），触发 AI 分析，并展示结果。
