---
name: ios-user-profile
description: "Pink_House iOS 端的用户资料（自定义头像 + 昵称）模块。当要改头像或昵称的持久化、增删 Documents/UserAvatars 下的头像文件、调整 UserDefaults 的 userProfiles / customNickname / customAvatarPath 存取、把用户资料接入备份与恢复、改 UserProfileEditView / UserAvatarView 的展示或尺寸、处理多 Apple ID 切换后的资料归属、或在 MainActor 默认隔离下从非主线程读取用户资料时使用。也用于这些具体症状：头像换了却不刷新、重装或换机后头像路径失效、退出再登录资料串号、备份恢复后头像丢失。"
---

本技能描述的是 Pink_House 仓库里**已经存在的实现**，不是一份可照抄的教程。

**铁律：动这块代码前先读真实文件，不要照本技能或任何文档里的片段直接覆盖。**
仓库里的实现会演进，脱离仓库的示例代码必然漂移（历史上就发生过：`customAvatarPath` 从
"存完整路径"改成"只存文件名"，而文档里还留着旧口径）。

## TRIGGER / DO NOT TRIGGER

TRIGGER 当：改头像 / 昵称的存储或展示、把用户资料接进备份、处理多 Apple ID 资料归属、排查头像不刷新或恢复后丢失。
DO NOT TRIGGER 当：只改与用户资料无关的 UI、只做 SwiftUI 通用版式调整、或只跑不涉及落盘的纯逻辑单测。

## 真实文件地图

| 关注点 | 文件 |
|---|---|
| 资料模型 + 持久化 + 多用户存取 | `ItemManager/Services/AuthenticationManager.swift` |
| 头像编辑页（相册 / 拍照 / 删除） | `ItemManager/Views/Settings/UserProfileEditView.swift` |
| 头像展示组件 | `ItemManager/Components/UserAvatarView.swift` |
| 备份 / 恢复 | `ItemManager/Services/BackupService.swift`、`ItemManager/Services/BackupModels.swift` |
| 账户卡片（40pt 头像） | `ItemManager/Views/Settings/Components/AccountCard.swift` |
| 「我」页（80 / 50pt 头像） | `ItemManager/Views/MeView.swift` |

## 四条最容易出错的口径

1. **`customAvatarPath` 只存文件名，不存绝对路径。** 完整 URL 由 `avatarFileURL` 动态拼
   （`Documents/UserAvatars/<filename>`）。存绝对路径会在重装 / 换机后失效。
2. **`userProfiles` 是一个 JSON 字符串**（`@AppStorage` 存不了字典），
   key 为 `userIdentifier`，格式 `[String: UserProfile]`。解析失败时静默回落空字典，不抛错。
3. **`AuthenticationManager` 是 `@MainActor` 隔离的。** 非主线程读取必须 `await MainActor.run { }`。
   （工程开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。）
4. **落盘测试不准指向真实沙盒。** 单测宿主就是主 App，`FileManager.default` = 用户数据目录。
   见 `concurrency-and-testing.md`。

## References

- `references/architecture-and-storage.md`: 动手改这块之前读。存储布局、UserDefaults key 清单、多用户字典的读写路径。
- `references/avatar-files.md`: 改头像写入 / 清理 / 命名时读。目录、命名规则、旧文件清理、以及"只存文件名"的正确口径。
- `references/backup-and-restore.md`: 把用户资料接进备份 / 排查恢复后头像丢失时读。manifest 字段与恢复顺序。
- `references/ui-and-sizing.md`: 改头像展示或编辑页版式时读。各调用点的真实尺寸与显示优先级。
- `references/concurrency-and-testing.md`: 在非主线程访问资料、或为这块写单测时读。MainActor 访问方式 + 测试数据隔离硬规则。
