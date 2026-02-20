---
name: "ios-user-profile"
description: "iOS用户资料管理（头像+昵称）实现指南。包含持久化、备份恢复、多用户支持。Invoke when implementing user avatar/nickname features with Apple ID integration."
---

# iOS 用户资料管理最佳实践

## 功能概述
实现用户自定义头像和昵称功能，支持与 Apple ID 绑定，实现多用户独立存储。

## 核心架构

### 1. 数据模型设计

```swift
// 用户资料结构体
struct UserProfile: Codable {
    var nickname: String = ""
    var avatarPath: String = ""
    var updatedAt: Date = Date()
}
```

### 2. 持久化策略

**存储位置：**
- 头像文件：`Documents/UserAvatars/{filename}.jpg`
- 用户资料：`@AppStorage("userProfiles")` (JSON 格式)

**多用户支持：**
```swift
// 存储格式: [userID: UserProfile]
@AppStorage("userProfiles") private var userProfilesData: String = "{}"
```

### 3. 核心类设计

```swift
@MainActor
class AuthenticationManager: ObservableObject {
    // 当前用户资料（实时同步）
    @AppStorage("customNickname") var customNickname: String = ""
    @AppStorage("customAvatarPath") var customAvatarPath: String = ""
    
    // 显示名称（优先自定义，其次 Apple ID）
    var displayName: String {
        if !customNickname.isEmpty { return customNickname }
        if !givenName.isEmpty { return givenName }
        return "已登录用户"
    }
    
    // 按用户ID存取资料
    func loadUserProfile(for userID: String) -> UserProfile
    func saveUserProfile(_ profile: UserProfile, for userID: String)
}
```

## 实现步骤

### 步骤 1: 头像存储

```swift
func updateCustomAvatar(image: UIImage) {
    // 1. 创建专用目录
    let avatarDir = documentsDir.appendingPathComponent("UserAvatars", isDirectory: true)
    try? FileManager.default.createDirectory(at: avatarDir, withIntermediateDirectories: true)
    
    // 2. 生成唯一文件名
    let filename = "avatar_\(userIdentifier.suffix(8))_\(Int(Date().timeIntervalSince1970)).jpg"
    let fileURL = avatarDir.appendingPathComponent(filename)
    
    // 3. 压缩保存
    if let data = image.jpegData(compressionQuality: 0.8) {
        try? data.write(to: fileURL)
        
        // 4. 删除旧头像
        if !customAvatarPath.isEmpty {
            try? FileManager.default.removeItem(atPath: customAvatarPath)
        }
        
        // 5. 更新路径
        customAvatarPath = fileURL.path
    }
}
```

### 步骤 2: 编辑界面

```swift
struct UserProfileEditView: View {
    @ObservedObject var authManager: AuthenticationManager
    @State private var nickname: String = ""
    @State private var avatarImage: UIImage?
    
    // 功能：相册选择、拍照、删除头像
}
```

**关键组件：**
- `PhotosPicker`：相册选择
- `UIImagePickerController`：拍照
- `UserAvatarView`：头像显示（优先自定义，其次首字母）

### 步骤 3: 备份/恢复集成

**备份流程：**
1. 收集当前用户资料（userID、nickname）
2. 如有头像，添加文件到备份列表
3. 更新 manifest 版本号

**恢复流程：**
1. 恢复 `userProfiles` 到 UserDefaults
2. 复制头像文件到 `UserAvatars/` 目录
3. 更新头像路径
4. 如当前登录用户匹配，刷新显示

```swift
// BackupManifest 添加字段
struct BackupManifest: Codable {
    let userProfile: UserProfileDTO?
    let userAvatarFile: String?
}
```

## 最佳实践

### 1. Actor 隔离处理

```swift
// 从非主线程访问 @MainActor 属性
let userInfo = await MainActor.run { () -> (userId: String, nickname: String)? in
    let auth = AuthenticationManager.shared
    guard auth.isAuthenticated else { return nil }
    return (auth.userIdentifier, auth.customNickname)
}
```

### 2. 文件管理

- **压缩质量**：0.8 平衡清晰度和大小
- **唯一命名**：包含用户ID后缀 + 时间戳
- **旧文件清理**：更新时删除旧头像

### 3. 显示优先级

```swift
// 头像显示优先级：
// 1. 自定义头像
// 2. Apple ID 首字母缩写
// 3. 默认图标

// 昵称显示优先级：
// 1. 自定义昵称
// 2. Apple ID 名称
// 3. "已登录用户"
```

### 4. 版本管理

备份版本升级策略：
- 新增字段使用 Optional
- 恢复时检查字段存在性
- 保持向后兼容

## 界面规范

### Sheet 尺寸
```swift
// 账户与同步页面占 90% 屏幕
.sheet(isPresented: $showingSheet) {
    CloudSyncSheetView(...)
        .presentationDetents([.fraction(0.9)])
}
```

### 头像尺寸
- 编辑页面：120pt
- 账户卡片：40-50pt
- 账户详情：80pt

## 常见问题

### Q: 如何处理多个 Apple ID？
A: 使用 `userProfiles` 字典，key 为 `userIdentifier`，每个用户独立存储。

### Q: 退出登录后资料会丢失吗？
A: 不会。资料按 userID 存储，重新登录相同 Apple ID 会自动恢复。

### Q: 备份时未登录怎么办？
A: 备份流程检查 `isAuthenticated`，未登录时跳过用户资料备份。

## 相关文件

- `AuthenticationManager.swift` - 核心管理类
- `UserProfileEditView.swift` - 编辑界面
- `UserAvatarView.swift` - 头像显示组件
- `BackupService.swift` - 备份/恢复逻辑
- `BackupModels.swift` - 备份数据结构
