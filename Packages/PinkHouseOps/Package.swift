// swift-tools-version: 6.0
//
//  PinkHouseOps —— Mac 运营工具（`PinkHouseOps.app`）**可测的服务层**。
//
//  ## 为什么要有这个包
//
//  之前 `OpsPublisherBridge`（受控发布桥接的调用端：固定可执行 + 固定参数 + NDJSON 事件、
//  超时与取消的唯一入口）住在 App target 里，而 **App 宿主式单测在本机跑不起来**
//  （`xcodebuild test` 永久挂起，取证见 skill
//  `pink-house-xcodebuild-acceptance` 的 `references/mac-xctest-hang-forensics.md`）。
//  结果是：这层最容易写错的逻辑（曾经真的发生过「`markCancelled()` 无人调用」，
//  导致「取消」那条错误分支一辈子走不到）**没有任何能执行的回归锁**。
//
//  这个文件本身**不引用一行 App 代码** —— 只有 Foundation / Combine / SharedCatalog，
//  所以能编进纯逻辑目标、用 `swift test` 秒级验证，不碰界面也不需要模拟器。
//
//  ## 为什么模块叫 `PinkHouseOpsCore` 而不是 `PinkHouseOps`
//
//  App 的 target 已经叫 `PinkHouseOps`（模块名同名）。若这里的库也叫 `PinkHouseOps`，
//  App 侧 `import PinkHouseOps` 就成了「自己 import 自己」，模块名直接冲突。
//  所以目录叫 `Packages/PinkHouseOps`（标明归属哪个 App），**模块名带 `Core` 后缀**。
//
//  ## 边界
//
//  只放**与界面无关**的运营服务层；视图层与 SwiftData 编排仍留在 App 里。
//  `SharedCatalog` 仍是跨平台领域层（Foundation 级），本包依赖它、不反向被依赖。

import PackageDescription

let package = Package(
    name: "PinkHouseOps",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "PinkHouseOpsCore", targets: ["PinkHouseOpsCore"]),
    ],
    dependencies: [
        .package(path: "../SharedCatalog"),
    ],
    targets: [
        .target(
            name: "PinkHouseOpsCore",
            dependencies: [
                .product(name: "SharedCatalog", package: "SharedCatalog"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "PinkHouseOpsCoreTests",
            dependencies: [
                "PinkHouseOpsCore",
                // 用例里要拿到 `ShopCatalogPublishProtocol.schemaVersion`（协议版本断言）
                .product(name: "SharedCatalog", package: "SharedCatalog"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
