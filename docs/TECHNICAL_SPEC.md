# 技术规格说明书 (Technical Specification)

## 1. 项目概况
*   **项目名称**: 少女心愿 - ItemManager
*   **平台**: iOS 26 (Target), macOS (Compatible via Catalyst/SwiftUI)
*   **语言**: Swift 6.0+
*   **UI 框架**: SwiftUI
*   **数据存储**: SwiftData

## 2. 系统架构

### 2.1 架构模式: MVVM (Model-View-ViewModel)
鉴于 SwiftUI 的声明式特性，MVVM 是最自然的适配架构。
*   **Model**: SwiftData `@Model` 类 (Item, Tag 等)。
*   **View**: SwiftUI 视图，负责 UI 呈现和用户交互。
*   **ViewModel**: `ObservableObject` 或 `@Observable` (iOS 17+ 宏)，负责业务逻辑、数据处理、状态绑定。

### 2.2 目录结构规划
```
ItemManager/
├── App/
│   ├── ItemManagerApp.swift  (入口)
│   └── Constants.swift       (全局配置)
├── Models/                   (数据模型)
│   ├── Item.swift            (物品实体)
│   ├── Tag.swift             (标签实体)
│   └── PaymentStatus.swift   (枚举状态)
├── ViewModels/               (业务逻辑)
│   ├── ItemListViewModel.swift
│   └── ItemEditorViewModel.swift
├── Views/                    (UI组件)
│   ├── Components/           (通用组件: GlassCard, CustomTextField)
│   ├── ItemList/             (列表页)
│   └── ItemEditor/           (编辑/详情页)
├── Services/                 (服务层)
│   ├── NotificationService.swift (本地通知)
│   └── ImageStorageService.swift (图片文件管理)
└── Resources/                (资源)
    └── Assets.xcassets
```

## 3. 数据模型设计 (SwiftData)

### 3.1 Item (物品)
```swift
@Model
final class Item {
    var id: UUID
    var name: String
    var brand: String?
    var types: [String] = []    // JSK, OP...
    var colors: [String] = []   // Pink, White...
    var sizes: [String] = []    // S, M...
    var accessories: [String] = [] // BNT, KC...
    
    // 媒体
    var imagePaths: [String] = [] // 存储文件名，而非二进制数据
    var coverImageIndex: Int = 0
    
    // 财务
    var priceTotal: Decimal?
    var deposit: Decimal?
    var balance: Decimal?         // 尾款
    var accessoriesPrice: Decimal?
    
    // 状态与时间
    var status: PaymentStatus     // enum
    var purchaseDate: Date
    var expectedBalanceDate: Date? // 预计补款日
    var createdAt: Date
    var note: String?
    
    // 关联
    @Relationship(deleteRule: .nullify) 
    var tags: [Tag]?
    
    init(...) { ... }
}
```

### 3.2 Tag (标签)
```swift
@Model
final class Tag {
    var name: String
    var colorHex: String
    
    @Relationship(inverse: \Item.tags)
    var items: [Item]?
    
    init(name: String, colorHex: String) { ... }
}
```

## 4. 关键技术实现

### 4.1 图片存储
*   **策略**: 不要将图片直接存入 SwiftData/CoreData (会导致数据库臃肿)。
*   **实现**: 将图片保存到 App 的 `Documents/Images` 目录下，数据库仅存储文件名 (UUIDString.jpg)。
*   **优化**: 列表页使用缩略图，详情页加载原图。

### 4.2 iOS 26 新特性兼容 (假设)
*   使用最新的 `@Observable` 宏进行状态管理。
*   适配深色模式和动态字体。
*   利用 `TipKit` (如果适用) 展示新功能引导。

### 4.3 补款提醒
*   使用 `UserNotifications` 进行本地调度。
*   逻辑封装在 `NotificationService` 中，当 `Item` 的 `expectedBalanceDate` 变更时，自动更新通知队列。

## 5. UI 规范实现 (Liquid Glass)
*   封装 `GlassModifier`：
    ```swift
    struct GlassEffect: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(...)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
        }
    }
    ```
