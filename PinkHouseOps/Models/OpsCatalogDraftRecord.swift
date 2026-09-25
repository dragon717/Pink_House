//
//  OpsCatalogDraftRecord.swift
//  PinkHouseOps
//
//  Mac 本地草稿（SwiftData）。
//
//  ## 为什么整包存成一份 JSON Data，而不是把店家/系列/商品拆成 SwiftData 关系
//
//  1. 目录本身已经有一份**权威的 Codable 结构**（共享包里的 `ShopCatalog`），
//     发布端 `build_release.py` 读的就是它的 JSON 形态。拆成关系表就等于把
//     同一份事实再描述一遍 —— 两边一旦分叉，界面显示的和发布出去的就是两回事。
//  2. 运营的实际工作单元是「整包」：一次导入、一次编辑、一次导出。
//     关系表擅长的「按条件查单条」在这里用不上。
//  3. 草稿是**短期工作副本**，不是长期数据库。真正长期的是发布出去的公共库内容。
//
//  所以：SwiftData 只负责「草稿还在、退出后能恢复、对应哪个 staging 目录」，
//  目录内容以 JSON 原样存取，编解码统一走 `ShopCatalogJSONCoding`。
//
//  ⚠️ SwiftData 的 CloudKit 自动同步**必须关掉**：Apple 没有给 SwiftData
//     配置 public database 自动同步的选项（`ModelConfiguration.CloudKitDatabase`），
//     而且这是本机运营草稿，本来就不该同步到用户的私有库。
//

import Foundation
import SwiftData

@Model
final class OpsCatalogDraftRecord {
    /// 草稿标识。同时是 staging 子目录名，所以只用 ASCII（避免路径编码问题）。
    @Attribute(.unique) var id: String
    /// 运营看的标题，如「2026-09 上新」
    var title: String
    /// `ShopCatalog` 的 JSON 原文（`ShopCatalogJSONCoding.encoder` 产出）
    var catalogJSON: Data
    /// 覆盖状态：整包发布固定 `complete`，仅作留痕
    var coverageStatus: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        catalogJSON: Data,
        coverageStatus: String = "complete",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.catalogJSON = catalogJSON
        self.coverageStatus = coverageStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// staging 目录名：`Application Support/PinkHouseOps/staging/<id>/`
    var stagingFolderName: String { id }
}
