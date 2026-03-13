---
name: "ai-daily-content"
description: "AI生成每日内容（问候语/穿搭色等）并同步到CloudKit公共数据库。Invoke when implementing daily AI-generated content with multi-device sync."
---

# AI每日内容生成与同步 Skill

## 概述

本 Skill 用于实现 APP 中每日变化的 AI 生成内容功能，如：
- 每日问候语（早安/午安/晚安等）
- 每日穿搭色推荐
- 每日运势/签文
- 其他需要每日更新且跨设备同步的内容

## 核心设计原则

### 1. 三级数据获取策略
```
内存缓存 → CloudKit公共数据库 → AI生成 → 本地模板
```

1. **内存缓存**：优先从内存获取，保证速度
2. **CloudKit公共数据库**：所有设备共享同一份数据
3. **AI生成**：CloudKit没有时，任意设备请求AI生成
4. **本地模板**：AI失败时的优雅降级

### 2. 时间段感知
内容根据一天中的不同时段变化：
- `dawn` (0-5点): 凌晨
- `morning` (5-12点): 清晨/早晨
- `noon` (12-14点): 中午
- `afternoon` (14-18点): 下午
- `evening` (18-22点): 晚上
- `night` (22-24点): 深夜

### 3. 缓存键设计
```swift
"yyyy-MM-dd_timeOfDay"  // 例如: "2025-03-13_morning"
```

## 文件结构

```
ItemManager/
├── Models/
│   └── DailyGreeting.swift          # 数据模型 + 本地模板
├── Services/
│   └── DailyGreetingManager.swift   # 管理器（核心逻辑）
└── Views/
    └── CheckIn/
        └── DailyCheckInView.swift   # UI使用示例
```

## 实现步骤

### 步骤1: 创建数据模型

```swift
// MARK: - 时间段类型
enum TimeOfDay: String, Codable, CaseIterable {
    case dawn, morning, noon, afternoon, evening, night
    
    static func from(hour: Int) -> TimeOfDay {
        switch hour {
        case 0..<5:   return .dawn
        case 5..<12:  return .morning
        case 12..<14: return .noon
        case 14..<18: return .afternoon
        case 18..<22: return .evening
        default:      return .night
        }
    }
    
    static var current: TimeOfDay {
        let hour = Calendar.current.component(.hour, from: Date())
        return from(hour: hour)
    }
}

// MARK: - 每日内容数据
struct DailyContent: Codable, Identifiable {
    let id: String
    let date: Date
    let timeOfDay: TimeOfDay
    let content: [String]  // 多条内容
    let source: String     // cloudkit/ai/local
    let createdAt: Date
}

// MARK: - AI响应结构
struct ContentAIResponse: Codable {
    let items: [String]
}

// MARK: - 本地模板（AI失败时回退）
struct ContentTemplates {
    static let templates: [TimeOfDay: [[String]]] = [
        .morning: [["早安内容1", "早安内容2", "早安内容3"]],
        // ... 其他时间段
    ]
}
```

### 步骤2: 创建管理器

```swift
@MainActor
final class DailyContentManager: ObservableObject {
    static let shared = DailyContentManager()
    
    @Published var currentContent: DailyContent?
    @Published var isLoading = false
    
    private var contentCache: [String: DailyContent] = [:]
    private let container = CKContainer(identifier: "iCloud.your.bundle.id")
    
    // 主入口：获取当前内容
    func getCurrentContent() async -> DailyContent? {
        if let content = currentContent, isContentValid(content) {
            return content
        }
        await fetchOrGenerateContent()
        return currentContent
    }
    
    // 判断内容是否有效
    private func isContentValid(_ content: DailyContent) -> Bool {
        let calendar = Calendar.current
        return calendar.isDate(content.date, inSameDayAs: Date()) 
            && content.timeOfDay == TimeOfDay.current
    }
    
    // 核心逻辑：获取或生成内容
    private func fetchOrGenerateContent() async {
        let now = Date()
        let timeOfDay = TimeOfDay.current
        let cacheKey = generateCacheKey(date: now, timeOfDay: timeOfDay)
        
        isLoading = true
        defer { isLoading = false }
        
        // 1. 内存缓存
        if let cached = contentCache[cacheKey] {
            currentContent = cached
            return
        }
        
        // 2. CloudKit
        if let cloudContent = await fetchFromCloudKit(date: now, timeOfDay: timeOfDay) {
            currentContent = cloudContent
            contentCache[cacheKey] = cloudContent
            saveToCache(cloudContent)
            return
        }
        
        // 3. AI生成
        if let aiResponse = await generateWithAI(timeOfDay: timeOfDay) {
            let aiContent = DailyContent(...)
            await uploadToCloudKit(aiContent)
            currentContent = aiContent
            contentCache[cacheKey] = aiContent
            saveToCache(aiContent)
            return
        }
        
        // 4. 本地模板
        let localContent = DailyContent(...)
        currentContent = localContent
        contentCache[cacheKey] = localContent
        saveToCache(localContent)
    }
}
```

### 步骤3: 添加AI生成功能

```swift
extension PetAIService {
    func generateDailyContent(timeOfDay: TimeOfDay) async -> ContentAIResponse? {
        guard isAPIKeyAvailable else { return nil }
        
        let prompt = """
        请生成3条文艺、温柔的内容...
        
        当前时间段：\(timeOfDay.displayName)
        
        要求：
        1. 每条15-30字
        2. 以 "•" 符号开头
        3. ...
        
        JSON格式返回：
        {
          "items": ["• 内容1", "• 内容2", "• 内容3"]
        }
        """
        
        let response = await sendMessage(prompt, enableVoice: false)
        // 解析JSON...
    }
}
```

### 步骤4: 在UI中使用

```swift
struct DailyView: View {
    @StateObject private var contentManager = DailyContentManager.shared
    @State private var isExpanded = false
    
    var body: some View {
        VStack {
            // 可展开的卡片
            Button { isExpanded.toggle() } label: {
                Text(contentManager.getTitle())
            }
            
            if isExpanded {
                // 显示完整内容
                ForEach(contentManager.currentContent?.content ?? [], id: \.self) { item in
                    Text(item)
                }
            }
        }
        .task {
            _ = await contentManager.getCurrentContent()
        }
    }
}
```

## CloudKit 配置

### 记录类型定义

在 CloudKit Dashboard 中创建记录类型：

**DailyGreeting**（或你的内容类型）
- `messages`: String[] (列表)
- `source`: String
- `date`: Date
- `timeOfDay`: String
- `createdAt`: Date

### 记录ID命名规范
```
"greeting_yyyy-MM-dd_timeOfDay"
// 例如: "greeting_2025-03-13_morning"
```

## 关键要点

1. **CloudKit使用公共数据库**：`container.publicCloudDatabase`，让所有用户共享同一份每日内容

2. **AI生成后上传**：任意设备生成后上传到CloudKit，其他设备直接从CloudKit获取

3. **优雅降级**：AI失败时使用本地模板，保证功能可用

4. **时间段感知**：同一天不同时段（早晨/中午/晚上）显示不同内容

5. **缓存策略**：内存缓存 → UserDefaults → CloudKit

## 参考实现

- 数据模型: `ItemManager/Models/DailyGreeting.swift`
- 管理器: `ItemManager/Services/DailyGreetingManager.swift`
- UI使用: `ItemManager/Views/CheckIn/DailyCheckInView.swift`
