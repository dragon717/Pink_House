# 头像文件

**权威来源：`AuthenticationManager.updateCustomAvatar(image:)` / `clearCustomAvatar()`。**

## 目录与命名

- 目录：`Documents/UserAvatars/`（`updateCustomAvatar` 里 `createDirectory` 保证存在）
- 文件名：`avatar_<userIdentifier 后 8 位>_<Unix 时间戳>.jpg`
- 压缩：`jpegData(compressionQuality: 0.8)`

## 头号易错：`customAvatarPath` 只存文件名

```swift
customAvatarPath = filename   // ✅ 仓库现状
// customAvatarPath = fileURL.path  ❌ 旧口径，绝对路径会在重装/换机后失效
```

完整 URL 由计算属性动态拼，**不要缓存绝对路径**：

```swift
var avatarFileURL: URL {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let avatarDir = documentsPath.appendingPathComponent("UserAvatars", isDirectory: true)
    return avatarDir.appendingPathComponent(customAvatarPath)
}
```

`UserAvatarView` 里也有一份同样的动态拼接逻辑。改任何一侧都要同时改另一侧。

## 旧文件清理

`updateCustomAvatar` 在写新文件成功后删旧文件：

```swift
if !customAvatarPath.isEmpty {
    let oldFileURL = avatarDir.appendingPathComponent(customAvatarPath)
    if oldFileURL.path != fileURL.path {
        try? FileManager.default.removeItem(at: oldFileURL)
    }
}
```

注意点：

- 删除用的是 `try?`，**失败是静默的**；磁盘上会留下孤儿文件。
- 因文件名带时间戳，同一秒内连续替换会产生同名文件——上面的 `!=` 判断正是为了防自删。
- `clearCustomAvatar()` 只删文件并把 `avatarPath` 置空，**不会**清 `userProfiles` 里的历史条目。

## 写入失败的处理

`updateCustomAvatar` 的 `do/catch` 只打日志（`AppLogger.error`），**不向 UI 抛错**。
如果上层不给就地反馈，用户看到的就是"选完图没反应"。改这块时要保证失败和成功一样显眼。
