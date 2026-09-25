//
//  SharedCatalogBridge.swift
//  ItemManager
//
//  把本地 Swift Package `SharedCatalog` 一次性导出给整个 App target。
//
//  ## 为什么要这个文件
//
//  ShopCatalog 领域层（模型 / JSON 编解码 / 云同步协议常量 / tar 归档）已迁到
//  `Packages/SharedCatalog`，好让 Mac 运营工具（PinkHouseOps）与 iOS App 共用同一份
//  口径。但迁走之后，**App 里引用这些类型的文件有 99 个**（Services / Views / Tests
//  全都有），逐个加 `import SharedCatalog` 既繁琐又容易漏。
//
//  `@_exported import` 让本模块的引用者「看到」被导出模块的公开符号，
//  等价于每个文件都写了一行 `import SharedCatalog`，但只需要在这里写一次。
//
//  ## 注意
//
//    · 这是 underscored 属性（编译器支持、Swift 官方未承诺 API 稳定性）。
//      之所以接受：本工程把它限制在**一个**文件里，将来若要换成显式 import，
//      grep 一下 `@_exported` 就能找到唯一落点。
//    · **不要再在别处加 `@_exported import`**，多一个就多一处隐式依赖，
//      排查「这个类型到底从哪来的」会重新变难。
//    · 共享层只放两个平台都有的东西（Foundation / CryptoKit / ImageIO）。
//      UIKit / PhotosUI / SwiftUI / SwiftData 一律留在各自 App 内，不要往上加。
//

@_exported import SharedCatalog
