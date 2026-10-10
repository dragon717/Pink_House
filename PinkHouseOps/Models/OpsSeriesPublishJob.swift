//
//  OpsSeriesPublishJob.swift
//  PinkHouseOps
//
//  「系列发布」的**草稿箱记录**（SwiftData，本机）。
//
//  ## 它存的是什么
//
//  一次「发布整个系列」的**整份待发布内容**与它的**条目级状态**。
//  运营「写入草稿」或「发布整个系列」时，都会留下记录；**只有整个系列全部条目都发布成功**，
//  这条记录才被删除（需求 2026-10-07 §4）。失败或部分成功时它一直留着，
//  于是「哪些条目没发出去」永远查得到，而不是只留一句「发布失败」。
//
//  ## 为什么条目状态存成一份 JSON，而不是 SwiftData 关系
//
//  与 `OpsCatalogDraftRecord.catalogJSON` 同一个理由（那份文件写了三条）：
//  一次发布的条目状态是**一批**同构小结构，运营要的是「整批一起看」，
//  不是「按条件查单条」；拆成关系表等于把同一批事实再描述一遍，
//  两边分叉时界面显示的就不是真正发生过的事。
//
//  ## 为什么新字段一律 Optional
//
//  磁盘上已有存量库（容器 `~/Library/Containers/bugod2.ItemManager.Ops/`）。
//  SwiftData 轻量迁移对「新增可空列」是安全的；**新增模型类型**同样是加表，
//  不需要默认值推断 —— 但只要有一列写了非 Optional 且没有默认值，
//  `ModelContainer` 初始化就可能抛错、App 直接 fatalError 打不开。
//  打不开草稿库比丢一个状态严重得多，所以这里全部 Optional + 计算属性兜底。
//
//  ⚠️ SwiftData 的 CloudKit 自动同步**必须关掉**（同 `OpsCatalogDraftRecord`）：
//     这是本机发布台账，不该进任何人的私有库。
//

import Foundation
import SwiftData

// MARK: - 状态

/// 一次系列发布的终态/中间态。
enum OpsSeriesPublishStatus: String, Codable, CaseIterable, Sendable {
    /// 已存入发布草稿箱，等待运营发布
    case pending
    /// **发布中**：内容已完整落库，正在经受控发布器发布
    case publishing
    /// 全部条目发布成功（记录随即删除，所以一般看不到这个态）
    case published
    /// 部分成功：有条目没落成，整体**没有**发起发布
    case partialFailed
    /// 发布失败（校验 / 落盘 / 导出 / 桥接器拒绝 / 结果未确认）
    case failed

    var displayName: String {
        switch self {
        case .pending: return "待发布"
        case .publishing: return "发布中"
        case .published: return "已发布"
        case .partialFailed: return "部分失败"
        case .failed: return "发布失败"
        }
    }
}

/// 单个条目（系列内的一个类型/商品）的发布状态。
struct OpsSeriesPublishItem: Codable, Identifiable, Equatable {
    /// 条目 id（类型条目 id；已落库时为商品 id）
    var id: String
    /// 运营看的名字
    var name: String
    /// 这一步是否成功
    var ok: Bool
    /// 失败原因（成功时 nil）。**必须可定位**：是哪个条目、缺什么。
    var message: String?
}

// MARK: - 记录

@Model
final class OpsSeriesPublishJob {

    /// 一次发布任务的 id（也是重试时的定位键）
    @Attribute(.unique) var id: String
    /// 发布的**单位**：整个系列（不是单条商品）
    var seriesID: String
    var seriesName: String
    var shopID: String?
    var shopName: String?
    /// 归属的目录草稿；Optional 兼容旧草稿箱记录。
    var draftID: String?
    /// 每次重新提交都换一个标识，旧发布回执不能删掉新提交。
    var submissionID: String?

    /// `OpsSeriesPublishStatus.rawValue`
    var statusRaw: String
    /// `[OpsSeriesPublishItem]` 的 JSON
    var itemsJSON: Data?
    /// 本次发布对应的草稿 JSON 快照（`ShopCatalog`）。
    /// 留在草稿箱里 = 「内容不会丢」的凭据：即使窗口关了也能从它重来。
    var catalogSnapshotJSON: Data?

    /// 目标环境（development / production）
    var environment: String?
    /// 发布成功后的发布号
    var releaseSeq: Int?
    /// 失败原因（一条，可定位）
    var lastError: String?
    /// 本次运行的日志文件路径（排查入口）
    var logPath: String?

    var attemptCount: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        seriesID: String,
        seriesName: String,
        shopID: String? = nil,
        shopName: String? = nil,
        status: OpsSeriesPublishStatus = .pending,
        items: [OpsSeriesPublishItem] = [],
        catalogSnapshotJSON: Data? = nil,
        environment: String? = nil
    ) {
        self.id = id
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.shopID = shopID
        self.shopName = shopName
        self.draftID = nil
        self.submissionID = UUID().uuidString
        self.statusRaw = status.rawValue
        self.itemsJSON = try? JSONEncoder().encode(items)
        self.catalogSnapshotJSON = catalogSnapshotJSON
        self.environment = environment
        self.attemptCount = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: 取值兜底

    var status: OpsSeriesPublishStatus {
        get { OpsSeriesPublishStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var items: [OpsSeriesPublishItem] {
        get {
            guard let itemsJSON, !itemsJSON.isEmpty else { return [] }
            return (try? JSONDecoder().decode([OpsSeriesPublishItem].self, from: itemsJSON)) ?? []
        }
        set {
            itemsJSON = try? JSONEncoder().encode(newValue)
            updatedAt = Date()
        }
    }

    var attempts: Int { attemptCount ?? 0 }
    /// 失败条目（草稿箱页面逐条标红的就是它们）
    var failedItems: [OpsSeriesPublishItem] { items.filter { !$0.ok } }

    /// 标记一次尝试开始（内容已完整落库 → 发布中）
    func markPublishing() {
        status = .publishing
        attemptCount = attempts + 1
        updatedAt = Date()
    }

    /// 标记失败（保留草稿：记录**不删**，失败原因与日志路径写进来）
    func markFailed(_ status: OpsSeriesPublishStatus, error: String?, logPath: String?) {
        self.status = status
        self.lastError = error
        self.logPath = logPath
        self.updatedAt = Date()
    }
}
