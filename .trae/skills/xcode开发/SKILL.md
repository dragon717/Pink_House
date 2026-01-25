---
name: xcode开发
description: 很强的开发
---

# 📱 App Skills & Intelligence Integration (iOS 26)

本文件定义了 **[Your App Name]** 如何通过 **App Intents** 协议向 iOS 26 系统（Apple Intelligence）暴露其核心能力。

---

## 🏗 架构概览 (Architecture)

在 iOS 26 中，App 的功能不再孤立。我们通过以下维度与系统深度融合：
* **App Intents**: 定义可被执行的原子操作。
* **App Entities**: 定义系统可识别的数据对象（如：账单、联系人、项目）。
* **App Shortcuts**: 提供开箱即用的自动化组合。
* **Deep Links**: 确保从系统 AI 建议中能够精准直达 UI 页面。

---

## 🚀 核心技能列表 (Core Skills)

### 1. 生产力与操作 (Productivity)
| 技能名称 (Skill) | 意图 ID (Intent ID) | 描述 | 关键参数 |
| :--- | :--- | :--- | :--- |
| **快速录入** | `QuickEntryIntent` | 通过语音或文本快速创建记录 | `content`, `tags`, `timestamp` |
| **深度搜索** | `DeepSearchIntent` | 在 App 内部进行语义化内容检索 | `query`, `dateRange` |
| **智能归档** | `AutoArchiveIntent` | AI 自动识别并整理过期项目 | `category`, `priorityThreshold` |

### 2. 系统集成 (System Integration)
* **灵动岛 (Dynamic Island)**: 支持实时活动 (Live Activities) 状态更新的意图触发。
* **锁屏小组件**: 暴露最常用的 Skill 快捷入口。
* **Siri 全局调用**: 无需唤醒 App，通过“嘿 Siri，用 [App Name] ...”直接执行。

---

## 🛠 技术实现 (Implementation)

### 数据实体定义 (App Entity)
为了让系统理解 App 内的数据对象，我们实现了以下实体：

```swift
struct MyProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "项目"
    static var defaultQuery = MyProjectQuery()
    
    @Property(title: "项目名称")
    var name: String
    
    @Property(title: "最后修改日期")
    var lastModified: Date
}