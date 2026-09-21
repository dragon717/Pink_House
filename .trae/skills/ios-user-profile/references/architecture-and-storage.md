# 架构与存储布局

**权威来源：`ItemManager/Services/AuthenticationManager.swift`。** 下面是对它的描述，不是替代。

## 类型与隔离

```swift
@MainActor
class AuthenticationManager: NSObject, ObservableObject { ... }
```

单例；`init` 里做两件事：`checkCredentialState()` + `loadCurrentUserProfile()`。

## 模型

```swift
struct UserProfile: Codable {
    var nickname: String = ""
    var avatarPath: String = ""   // 只存文件名，见 avatar-files.md
    var updatedAt: Date = Date()
}
```

## UserDefaults key 清单

| key | 类型 | 说明 |
|---|---|---|
| `userIdentifier` | String | 当前 Apple ID 标识，多用户字典的 key |
| `userGivenName` / `userFamilyName` / `userEmail` | String | Apple ID 侧信息 |
| `cachedUserIdentifier` / `cachedGivenName` / `cachedFamilyName` / `cachedEmail` | String（private） | 退出登录后的缓存 |
| `customNickname` | String | 当前用户自定义昵称 |
| `customAvatarPath` | String | 当前用户头像**文件名** |
| `userProfiles` | String（private） | JSON，`[userIdentifier: UserProfile]` |

## 多用户存取路径

- `loadUserProfile(for:)` → 解码 `userProfiles`，取不到返回空 `UserProfile()`。
- `saveUserProfile(_:for:)` → 全量解码 → 改一个 key → 全量编码回写；
  **若 `userID == self.userIdentifier`，会顺带同步 `customNickname` / `customAvatarPath`。**
- `loadCurrentUserProfile()` → 用 `userIdentifier` 拉一次并写入当前属性。

`userID` 为空时两个方法都直接 return，不写库。

### 判空陷阱

`userProfiles` 的解码用 `try?`，**损坏的 JSON 会静默变成空字典**，不报错、不丢日志。
排查"资料莫名丢失"时先确认这个字符串的实际内容，而不是只看 `customNickname`。

## 显示优先级

- 昵称：自定义昵称 → Apple ID givenName → `"已登录用户"`
- 头像：自定义头像文件存在 → Apple ID 首字母缩写（`PersonNameComponentsFormatter`） → 默认图标

`hasCustomAvatar` 的判定是 `!customAvatarPath.isEmpty && FileManager.default.fileExists(atPath: avatarFileURL.path)`
——**两个条件都要满足**，只改 `customAvatarPath` 而文件不存在时不会显示自定义头像。

## 什么时候会串号

资料按 `userIdentifier` 存，切换 Apple ID 后应重新 `loadCurrentUserProfile()`。
若只在登录回调里同步而不在切换时同步，会出现"A 的昵称显示在 B 的账号上"。
