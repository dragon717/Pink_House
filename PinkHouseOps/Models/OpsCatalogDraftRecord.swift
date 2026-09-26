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
//  ## 元数据字段为什么全部 Optional（迁移安全）
//
//  这个模型在磁盘上已经有一份存量库（`~/Library/Containers/bugod2.ItemManager.Ops/`）。
//  新增字段一律用 Optional：SwiftData 的轻量迁移对「新增可空列」是安全的，
//  而对「新增不可空列」需要默认值参与推断 —— 一旦推断失败，`ModelContainer`
//  初始化会抛错，App 直接 `fatalError` 打不开。草稿打不开比丢一个版本号严重得多。
//  取值时统一走下面的计算属性（`?? 0` 兜底），调用方不必到处判空。
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

    // MARK: 版本与校验绑定（方案 R01）

    /// 单调递增的编辑版本号。**每一次内容变更都必须 +1**，不允许「只改文案」。
    /// nil（存量草稿）= 0。
    var draftRevision: Int?
    /// 最后一次成功落盘时对应的 `draftRevision`。与 `draftRevision` 不等 = 有未保存修改。
    var savedRevision: Int?
    /// 最后一次校验对应的 `draftRevision`。与当前值不等 = 校验结果已过期（导出必须被拦）。
    var reviewedRevision: Int?

    // MARK: 损坏隔离（方案 R03）

    /// 内容解不开 → 进入只读隔离态。此时保存 / 导图 / 导入 / 导出一律拒绝，
    /// 原始字节原样保留，只能「另存为新草稿」后继续工作。
    var corruptionDetected: Bool?
    /// 首次发现损坏时的**原始字节备份**。即使后续有人手改了 `catalogJSON`，
    /// 这份备份也还在（运营可以把字节抠出来自己救）。
    var corruptedBackupJSON: Data?

    // MARK: 发布基线（方案 R07）

    /// 这份草稿是从哪个线上版本改出来的。nil = 未知（旧草稿 / 首次发布）。
    ///
    /// ⚠️ Mac 端**读不到线上基线**（不直连 CloudKit，见 `PinkHouseOpsApp` 文件头），
    /// 所以这个值只能由受控发布器在读取 / 回执时回填。在没回填之前，
    /// 这里只做留痕与展示，**不得据此声称「基线已核对」**。
    var baseReleaseSeq: Int?
    var baseRootIndexHash: String?

    // MARK: 基线快照（2026-09-27，方案 R07/R08）

    /// `ShopCatalogBaseline` 的 JSON（含环境与核对时刻）。
    /// **必须 Optional**（同 R01 字段的理由）：存量库加列不能要求默认值推断。
    var baselineJSON: Data?

    /// **上次确认发布出去的那一版目录快照**（`ShopCatalog` 的 JSON）。
    ///
    /// 它回答两个问题，缺了就只能猜：
    ///   1. 「这份包相对线上改了什么」—— 没有基线内容就只比得出「变了 / 没变」；
    ///   2. 严格发布策略（R08）的作用域 —— 作用域 = 这个快照与当前草稿的差分。
    ///
    /// ⚠️ 为什么作用域用**差分**而不是「让每个编辑命令自己上报动过谁」：
    /// 上报是**自觉**的，漏一处就让严格策略对那块内容整体失效，而且失效后
    /// 没有任何迹象（看起来一切正常）。差分是**推导**出来的，改不了漏。
    ///
    /// ⚠️ 没有这个快照（从未发布过）时，作用域按「整份目录」算 —— 这些内容
    /// 本来就是要首次发出去的，严格是对的。
    var baselineCatalogJSON: Data?

    // MARK: 最近成功发布（列表标签「已上线 / 线上待回读」的数据来源）

    /// 最近一次**回读确认**过的发布号。nil = 从未发布成功。
    var lastPublishedReleaseSeq: Int?
    var lastPublishedRootIndexHash: String?
    /// 那次发布对应的编辑版本号。与 `currentRevision` 不等 = 之后又改过。
    var lastPublishedRevision: Int?
    var lastPublishedAt: Date?

    // MARK: 工作台恢复

    /// 上次在商品编辑器里打开的商品（工作台「继续编辑」用）。
    var workingProductID: String?

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

    // MARK: 取值兜底（Optional → 具体值）

    var currentRevision: Int { draftRevision ?? 0 }
    var lastSavedRevision: Int { savedRevision ?? 0 }
    var isCorrupted: Bool { corruptionDetected ?? false }
    /// 有未落盘的修改
    var hasUnsavedChanges: Bool { currentRevision != lastSavedRevision }
    /// 校验结果是否对得上当前版本（false = 过期，导出必须被拦）
    var isReviewCurrent: Bool { reviewedRevision == currentRevision }

    /// 基线（解不开按「未知」处理，**绝不**兜成 releaseSeq 0 —— 那等于声称
    /// 「线上还没发过」，会让基线过期检测整体失效）。
    var baseline: ShopCatalogBaseline {
        get {
            guard let baselineJSON, !baselineJSON.isEmpty else {
                // 兼容旧字段：早期只有这两个裸列
                return ShopCatalogBaseline(releaseSeq: baseReleaseSeq, rootIndexHash: baseRootIndexHash)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return (try? decoder.decode(ShopCatalogBaseline.self, from: baselineJSON))
                ?? ShopCatalogBaseline(releaseSeq: baseReleaseSeq, rootIndexHash: baseRootIndexHash)
        }
        set {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            baselineJSON = try? encoder.encode(newValue)
            baseReleaseSeq = newValue.releaseSeq
            baseRootIndexHash = newValue.rootIndexHash
        }
    }

    /// 本地变更追踪（当前草稿内容相对基线快照的差分由 `OpsWorkspace.changeSet` 计算，
    /// 这里不再单独存一份「动过谁」—— 见 `baselineCatalogJSON` 的说明）。
    var baselineCatalog: ShopCatalog? {
        get {
            guard let baselineCatalogJSON, !baselineCatalogJSON.isEmpty else { return nil }
            return try? ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: baselineCatalogJSON)
        }
        set {
            guard let newValue else { baselineCatalogJSON = nil; return }
            baselineCatalogJSON = try? ShopCatalogJSONCoding.encoder().encode(newValue)
        }
    }

    /// 是否还有「本地已改但没发布」的内容（商品列表的「本地已改」标签用它）。
    var hasUnpublishedEdits: Bool { currentRevision != (lastPublishedRevision ?? 0) }

    /// 线上待回读：本地已经改过，但（当前版本）还没有一次回读确认的发布。
    var isAwaitingReadBack: Bool {
        guard let lastPublishedRevision else { return false }
        return currentRevision != lastPublishedRevision
    }

    /// 是否曾经发布成功过
    var hasEverPublished: Bool { (lastPublishedReleaseSeq ?? 0) > 0 }

    /// 记一次**已回读确认**的发布。
    ///
    /// 三件事必须一起做，缺一就会出现「界面说已上线、其实线上还是旧版」：
    ///   1. 写发布号与根清单摘要（回执里的，不是我们希望的）；
    ///   2. 写对应编辑版本（以后 `hasUnpublishedEdits` 才有意义）；
    ///   3. **用当前目录内容覆盖基线快照** —— 从这一刻起，「与线上比对了什么」
    ///      的参照物就是这一版。少了这步，下次发布会把上次的改动又算成新改动。
    func recordConfirmedPublish(
        releaseSeq: Int,
        rootIndexHash: String?,
        revision: Int,
        catalog: ShopCatalog,
        environment: String,
        at date: Date = Date()
    ) {
        lastPublishedReleaseSeq = releaseSeq
        lastPublishedRootIndexHash = rootIndexHash
        lastPublishedRevision = revision
        lastPublishedAt = date
        baselineCatalog = catalog
        baseline = ShopCatalogBaseline(
            releaseSeq: releaseSeq,
            rootIndexHash: rootIndexHash,
            environment: environment,
            observedAt: date)
    }
}
