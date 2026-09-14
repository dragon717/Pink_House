# 运营入口（上传上新）的白名单门控与调试日志

> 面向的问题：「我这个 iCloud key 到底在不在运营白名单里？在 Xcode 里搜什么才能看到？」、
> 「不在白名单的话，运营上传界面就不该对普通用户显示」。

## 一、在 Xcode 里搜什么关键词

**搜 `CreatorGate`。**

App 启动时（以及每次进入仲夏物语品牌页刷新时）都会打一组固定格式的日志：

```
🔑 [CreatorGate] 本机 iCloud 用户标识 = _819804d902cb79c2d6e4bf736ed6c50b
🔑 [CreatorGate] 白名单            = ["_819804d902cb79c2d6e4bf736ed6c50b"]
🔑 [CreatorGate] 命中白名单        = true
🔑 [CreatorGate] 判定结果          = allowed
```

取不到身份时（模拟器、未登录 iCloud、断网）是另一组：

```
⚠️ [CreatorGate] 取不到 iCloud 用户标识：<系统错误描述>
⚠️ [CreatorGate] 判定结果 = unresolved（模拟器 / 未登录 iCloud / 网络不通都会走到这里）
⚠️ [CreatorGate] 此时只有本机「创作者模式」开关能解界面闸门；真实写入仍需 CloudKit 角色授权
```

在 Xcode 里过滤日志的方式（任选）：

- 控制台搜索框直接输入 `CreatorGate`
- 只想要 key：搜 `本机 iCloud 用户标识`
- 命令行：`xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "CreatorGate"'`

拿到那串 `_xxxxxxxx` 后，把它追加到
`ItemManager/Services/NoticeCloudKitService.swift` 的 `adminIDs` 数组，
并**同时**在 CloudKit Console 给该账户授权写入角色（两件事都要做，缺一个都提交不上去）。

## 二、门控是三态，不是布尔

`NoticeCloudKitService.CreatorGate`：

| 状态 | 什么时候 | 上传入口 |
|---|---|---|
| `allowed` | 取到身份且在 `adminIDs` 里 | **显示** |
| `denied` | 取到身份但不在 `adminIDs` 里 | **不显示**。本机「创作者模式」开关也撬不开 |
| `unresolved` | 身份取不到（模拟器 / 未登录 iCloud / 网络失败） | 允许「创作者模式」开关解界面闸门 |

为什么不做成布尔：之前的判定只有 true/false，而 `CKContainer.userRecordID()` 在模拟器上
必然抛错 → 统一算 false → 内容维护者在模拟器上**永远看不到入口**。
但那其实是「身份取不到」，不等同于「不是运营」。三态把这两种情况分开：

- 使用者的要求（不在白名单就不显示）由 `denied` 满足，且优先级高于本机开关
- 内容维护者在模拟器上的可用性由 `unresolved` + 创作者模式保留

`MidsummerStore.canContribute` 是唯一的判定入口：

```swift
switch creatorGate {
case .allowed:    return true
case .denied:     return false                                  // 硬闸门
case .unresolved: return CreatorMode.isEnabledInDefaults()      // 仅模拟器/未登录时放行界面
}
```

界面上，`denied` 时页脚不再显示「我是内容维护者，开启创作者模式」按钮
（`midsummer-creator-denied-note`），因为那个按钮撬不开闸门，摆着只会让人以为开关坏了。

## 三、⚠️ 这只是界面闸门，不是安全边界

`adminIDs` 是**客户端**名单，改 App 就能绕过。真正的写入门槛在
CloudKit Console 的 Security Roles（见 `MIDSUMMER_TALE_CLOUDKIT_SETUP.md` §2）：
`_world` / `_icloud` 一律 **Read-only**，Create/Write 只给自定义角色。
非白名单账号即使绕过界面，也照样写不进去——只是会拿到一条明确的失败提示。

## 四、相关文件

| 文件 | 作用 |
|---|---|
| `Services/NoticeCloudKitService.swift` | `adminIDs` 白名单、`creatorGate()` 三态判定与日志 |
| `Services/CreatorMode.swift` | 本机「创作者模式」开关（只在 `unresolved` 时起作用） |
| `Services/Midsummer/MidsummerStore.swift` | `creatorGate` / `canContribute` |
| `ItemManagerApp.swift` | 启动时打一次 `CreatorGate` 日志 |
| `Views/Settings/Refactored/SystemSettingsView.swift` | 设置页文案，写清「白名单是硬闸门」 |
