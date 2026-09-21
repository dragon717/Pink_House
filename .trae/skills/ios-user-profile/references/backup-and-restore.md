# 备份与恢复中的用户资料

**权威来源：`BackupService.swift`（导出约 730-775 行，`restoreUserProfile` 约 2724 行）、`BackupModels.swift`。**

## Manifest 字段（v1.6 起）

```swift
let userProfile: UserProfileDTO?     // nil 表示备份时未登录
let userAvatarFile: String?          // 头像文件名，不是路径
```

```swift
struct UserProfileDTO: Codable {
    let userIdentifier: String
    let nickname: String
    let updatedAt: Date
}
```

另外，`BackupService` 的 UserDefaults 备份 key 列表里包含 `"userProfiles"`（v1.6 注释），
**整个多用户字典会随 UserDefaults 一起走**，不只备份当前用户。

## 导出流程

1. `await MainActor.run` 里读 `AuthenticationManager.shared`：`isAuthenticated` / `userIdentifier` /
   `customNickname` / `hasCustomAvatar` / `avatarFileURL`。
2. **未登录时 `userProfile` 为 nil，整个用户资料块跳过**（不是写空 DTO）。
3. 有自定义头像且文件存在时：以 `lastPathComponent` 作文件名加入 `imageFiles`，
   并写进 `externalHashes` 供增量同步。
4. 头像文件是**按文件名**进备份包的，所以恢复时只认文件名、不认原路径。

## 恢复流程

`restoreUserProfile(manifest:imageFiles:documentsDir:fileManager:)`：

1. 从 `UserDefaults` 读 `userProfiles`，解成 `[String: UserProfile]`；
2. 用 `manifest.userProfile.userIdentifier` 作 key 写入（昵称 + `updatedAt`，`avatarPath` 先置空）；
3. 回写 `userProfiles`；
4. 再把头像文件落到 `UserAvatars/` 并补上 `avatarPath`。

### 两个已知的静默边界

- **整段恢复依赖 `userProfiles` 能被解码。** 若该 key 不存在（全新安装还没写过资料），
  `UserDefaults.standard.string(forKey:)` 返回 nil → `if let` 不成立 → **用户资料整块跳过**，且不报错。
- 恢复写入的 `UserProfile` 用 `avatarPath: ""` 起步，靠后续步骤补；中间失败会留下"昵称回来了但头像没了"。

排查"恢复后头像丢失"时按这条链路查：manifest 里 `userAvatarFile` 有没有值 → 头像文件是否真在备份包里
→ `UserAvatars/` 是否落地 → `userProfiles` 里该用户的 `avatarPath` 是否被补上。

## 版本兼容

manifest 用 `decodeIfPresent` 读这两个字段，旧备份没有它们时得到 nil，不会崩。
新增字段一律 Optional + `decodeIfPresent`，保持向后兼容。
