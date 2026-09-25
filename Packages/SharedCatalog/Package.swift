// swift-tools-version: 6.0
//
//  SharedCatalog —— iOS App（ItemManager）与 Mac 运营工具（PinkHouseOps）共用的
//  商品目录领域层。
//
//  ## 边界（放进来之前先自问三件事）
//
//    · 只能 import Foundation / CryptoKit / ImageIO / CoreGraphics 这类
//      **两个平台都有**的框架；
//    · UIKit、PhotosUI、SwiftUI、SwiftData、CloudKit **一律不许进来** ——
//      UIKit 一进来 Mac target 直接编不过，这正是拆这个包的原因；
//    · 只放「领域事实」：模型、编解码、协议常量、图片规范化、发布门禁。
//      编排（Store/Service）与界面留在各自 App 里。
//
//  iOS 侧通过 `ItemManager/SharedCatalogBridge.swift` 的 `@_exported import`
//  一次性导出，避免给 99 个引用文件逐个加 import；Mac 侧同理
//  （`PinkHouseOps/SharedCatalogBridge.swift`）。
//
//  ## 为什么这个包自带测试目标
//
//  发布门禁、图片规范化、上传任务状态机这三块都是**纯逻辑**，不碰界面也不碰
//  网络。放在这里用 `swift test` 验证，代价是秒级、不需要模拟器，而且是
//  **两个平台同一份**验证 —— 比塞进 `ItemManagerTests`（要为一次断言等
//  五六分钟的模拟器启动）划算得多。
//  界面与落盘编排仍归各自 App，由 App 侧测试覆盖。

import PackageDescription

let package = Package(
    name: "SharedCatalog",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
    ],
    products: [
        .library(name: "SharedCatalog", targets: ["SharedCatalog"]),
    ],
    targets: [
        .target(
            name: "SharedCatalog",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "SharedCatalogTests",
            dependencies: ["SharedCatalog"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
