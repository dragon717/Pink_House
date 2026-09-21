# 并发访问与测试隔离

## MainActor 访问

工程开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，`AuthenticationManager` 显式 `@MainActor`。
非主线程读取必须包一层：

```swift
let userInfo = await MainActor.run { () -> (userId: String, nickname: String)? in
    let auth = AuthenticationManager.shared
    guard auth.isAuthenticated else { return nil }
    return (auth.userIdentifier, auth.customNickname)
}
```

`BackupService` 导出用户资料就是这么做的（约 738 行）。

**推论**：`nonisolated` 上下文里不能碰依赖 MainActor 状态的本地化入口
（如 `String.appLocalized` 背后的 `LanguageManager.shared`），否则报
`call to main actor-isolated ... in a synchronous nonisolated context`。
把"纯数据"和"本地化文案"切开，纯数据部分才能进 `nonisolated` 单测。

## 测试数据隔离硬规则（写单测必读）

**单测宿主就是主 App**（`bugod2.ItemManager`），测试进程里的 `FileManager.default`
指向的是**用户真实沙盒**。`tearDown` 里删 Application Support / Documents 下的文件 = 删用户数据。

因此：

- 任何会落盘的测试，**一律用注入目录**，不准指向真实路径。
- 不要在生产路径上 `removeItem`。
- 已有的防线测试：`ItemManagerTests/ShopCatalogStorageIsolationTests`（用
  `ShopCatalogStorage.useTemporaryForTesting()` / `restoreDefaultForTesting()` 的注入模式）。
  新写落盘测试时照这个模式做。

写这块测试前先自问：**这条路径会不会指向宿主 App 沙盒？** 会 → 换注入目录。

## 断言注意

- `image.size` 是「点」不是像素：快照断言用 pt 值（如 393），`scale = 2` 后像素才是 786。
- 头像文件写成功是 `try?`，失败静默；断言"头像已更新"时要连文件存在性一起断言，
  只断言 `customAvatarPath` 非空会放过写入失败的情况。
