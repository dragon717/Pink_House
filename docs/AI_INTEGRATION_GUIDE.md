# 萌宠 AI 对话系统 (Gemini 3 Flash) 开发文档

## 1. 背景与目标
本项目旨在通过接入 Google 的 **Gemini 3 Flash** 模型，为“萌宠”赋予具备角色扮演（Role-Play）能力的智能对话系统。目标是让宠物不仅能进行通用对话，还能根据自身性格（如傲娇小猫、热情金毛）进行符合人设的回复，并通过特定指令驱动端上表现（如表情包、动作）。

## 2. 需求拆解

| 模块 | 功能点 | 描述 | 状态 |
| :--- | :--- | :--- | :--- |
| **核心对话** | 文本交互 | 支持用户发送文本，AI 返回文本回复。 | ✅ 已完成 |
| **角色扮演** | 人设注入 | 根据当前宠物类型（奶茶/毛毛），动态注入 System Prompt。 | ✅ 已完成 |
| **表现力** | 动作/表情指令 | AI 可输出 `[IMAGE:xxx]` 指令，客户端解析并展示对应图片/动画。 | ✅ 已完成 |
| **配置管理** | API Key 安全 | 将敏感 Key 分离至 `plist` 文件，不直接硬编码进代码。 | ✅ 已完成 |
| **UI 交互** | 聊天界面 | 仿微信/Messages 的气泡对话流，支持自动滚动、加载状态。 | ✅ 已完成 |
| **调试入口** | Debug 模式 | 在开发环境下快速唤起 AI 对话窗口。 | ✅ 已完成 |

## 3. 架构设计

系统采用 **MVVM** 架构，利用 SwiftUI 的声明式 UI 和 Combine 的响应式数据流。

### 3.1 模块依赖关系

```mermaid
graph TD
    UI[ChatView (View)] --> VM[PetAIService (ViewModel)]
    VM --> SDK[GoogleGenerativeAI SDK]
    VM --> Config[AIConfigManager]
    UI --> Input[PetHomeView (Debug入口)]
    VM --> Role[PetRole (Enum)]
```

### 3.2 核心类说明

*   **`PetAIService` (ViewModel)**
    *   **职责**：管理与 Gemini API 的连接、维护会话历史 (`Chat`)、解析 AI 响应。
    *   **关键逻辑**：
        *   `init`: 初始化 `GenerativeModel`，注入 `systemInstruction`。
        *   `sendMessage`: 发送消息，并使用正则解析 `[IMAGE:xxx]` 指令。
        *   `isProcessing`: 使用 `@Published` 暴露加载状态。
*   **`AIConfigManager` (Service)**
    *   **职责**：单例模式，负责从 `GenerativeAI-Info.plist` 安全读取配置。
    *   **设计**：如果文件缺失或 Key 为空，返回 `nil`，以此控制功能入口的显隐。
*   **`ChatView` (View)**
    *   **职责**：展示对话流。
    *   **特性**：自动滚动到底部、气泡圆角处理、图片指令渲染。

## 4. 核心流程详解

### 4.1 System Prompt 注入
在 `PetAIService` 初始化时，根据 `PetRole` 生成对应的 Prompt：

```swift
// 伪代码示例
let systemPrompt = """
角色：\(petName)
性格：傲娇、粘人
限制：回复 50 字以内
指令：开心时使用 [IMAGE:happy_cat]
"""
self.model = GenerativeModel(..., systemInstruction: systemPrompt)
```

### 4.2 指令解析协议
AI 输出的原始文本可能包含：`"主人真好！[IMAGE:happy_cat]"`。
客户端解析逻辑 (`parseResponse`)：
1.  **正则匹配**：`\\[IMAGE:(\\w+)\\]`。
2.  **提取指令**：获取 `happy_cat` 作为 `imageName`。
3.  **清洗文本**：移除指令部分，仅保留 `"主人真好！"` 用于气泡展示。
4.  **UI 渲染**：`MessageBubble` 组件根据 `imageName` 显示对应资源。

## 5. 落地与配置指南

### 5.1 配置文件
在 `ItemManager` 目录下创建 `GenerativeAI-Info.plist`（**请勿提交到 Git**）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>API_KEY</key>
    <string>YOUR_GEMINI_API_KEY</string>
</dict>
</plist>
```

### 5.2 开启入口
1.  确保上述 plist 文件存在且 Key 有效。
2.  运行 App (Debug 模式)。
3.  在主界面底部（竖屏）或通过 Debug 手势，点击“对话”按钮。
4.  系统会自动检测 Key，如果存在则打开 AI Chat 界面，否则打开旧版指令输入框。

## 6. 后续迭代规划

1.  **流式响应 (Streaming)**：
    *   目前使用 `sendMessage` 等待完全返回。后续可升级为 `sendMessageStream`，实现打字机效果，降低感知延迟。
2.  **多模态输入**：
    *   允许用户上传图片给宠物看（Gemini 支持 Vision），例如：“看看这件衣服好看吗？”
3.  **语音集成**：
    *   结合现有的 `AudioManager`，将用户的语音转文字发给 AI，再将 AI 回复通过 TTS 播放，实现纯语音通话。
4.  **持久化存储**：
    *   使用 SwiftData 存储 `ChatMessage`，保留与宠物的共同回忆。
5.  **动作驱动升级**：
    *   将 `[IMAGE:xxx]` 指令扩展为 `[ACTION:dance]`，直接驱动首页的视频状态机 (`GKStateMachine`)，让宠物动起来。
