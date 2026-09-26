//
//  SharedCatalogBridge.swift
//  PinkHouseOps
//
//  一行 `@_exported import`，让本 target 的其它文件不必各自 `import SharedCatalog`。
//
//  ## 为什么需要它
//
//  工程开了 `-enable-upcoming-feature MemberImportVisibility`：**跨模块的成员必须
//  在使用的那个文件里显式 import 定义它的模块**，否则报
//  `cannot find type 'CatalogAsset' in scope`——看起来很像是「类型没定义」，
//  其实是 import 缺失（这个坑在 iOS 端也踩过）。
//
//  也可以用最直白的做法：在 10 个文件里各写一行 `import SharedCatalog`。
//  这里选桥接文件是因为 `PinkHouseOpsApp.swift` 之外还有后续要加的文件，
//  每加一个就忘一次 import 是必然事件。
//
//  ## 顺带说明它**不**解决什么
//
//  `@_exported` 只影响「本模块对外导出什么」，不会替你把 `Combine` 带进来。
//  `ObservableObject` / `@Published` 属于 Combine，用到的文件仍要自己
//  `import Combine`（同理由 MemberImportVisibility 强制）。
//
//  ## 为什么要导出两个模块
//
//  `PinkHouseOpsCore` 是 Mac 运营工具**可测的服务层**（受控发布桥接的调用端），
//  2026-09-27 从 App target 抽进本地包 `Packages/PinkHouseOps`。抽出去的原因不是
//  「架构更漂亮」，是**这里的逻辑之前无法被验证**：App 宿主式单测在本机跑不起来
//  （`xcodebuild test` 永久挂起，取证见 skill
//  `pink-house-xcodebuild-acceptance` 的 `references/mac-xctest-hang-forensics.md`），
//  而这层恰恰出过「`markCancelled()` 无人调用 → 取消那条错误分支走不到」的事故。
//  抽成纯逻辑包之后用 `swift test` 秒级覆盖。
//
//  注意模块名带 `Core` 后缀：App 的 target 已经叫 `PinkHouseOps`，
//  库若同名，这里 `import PinkHouseOps` 就变成「自己 import 自己」。

@_exported import SharedCatalog
@_exported import PinkHouseOpsCore
