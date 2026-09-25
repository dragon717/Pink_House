//
//  ShopCatalogCloudSyncProtocol.swift
//  ItemManager
//
//  「店家上新 / 公共 Catalog」云同步 · 协议层（消费端）。
//
//  对应 Mac 发布端：tools/time_hall/publication/protocol.py（权威口径），
//  文档：docs/TIME_HALL_CLOUDKIT_CONSOLE_SETUP.md + publication/README.md。
//
//  ## 通道设计（docs/Pink_House_TimeHall_Static_CloudKit_Design.md §0）
//
//    生产通道：运营 Mac（server-to-server key）→ CloudKit 公共库
//    消费通道：本文件 + Reader/Cache/Service —— 设备**只读**拉取
//
//  ## 与 Mac 端共用的硬约定
//
//    · Record Type 只有三种：THRelease（发布头，固定记录名 th.release.catalog-v1，
//      全库唯一一条）/ THDataPack（不可变数据包）/ THMedia（不可变媒体）；
//    · 商店目录走**整包单分片**：entityType = `shop-catalog`、
//      brandID = `shaonv-xinyuan`（运营自有内容源，不与画册品牌共用 ——
//      根清单 brands 按 brandID 去重）、载荷键是 `shopCatalog`（画册分片是 `records`）；
//    · payloadHash = **压缩字节**的 SHA-256（不是解压后内容）；
//    · 读取顺序：发布头 → 根清单 → 按需取包；版本未变就不重复下载。
//
//  本文件全部是 nonisolated 纯逻辑（解码 / 校验 / 摘要），不碰网络与磁盘，可单测。
//

import Foundation
import CryptoKit

// MARK: - 协议常量（与 protocol.py 逐字对齐，禁止两端各改各的）

nonisolated enum ShopCatalogSyncProtocol {
    /// 协议结构版本（Mac 端 `PROTOCOL_SCHEMA_VERSION`）
    static let schemaVersion = 1
    /// 本读取器支持的协议版本（Mac 端 `READER_VERSION`）
    static let readerVersion = 1
    /// 发布头固定记录名（全库只有一条）
    static let releaseRecordName = "th.release.catalog-v1"
    /// 商店目录分片的实体类型
    static let shopCatalogEntityType = "shop-catalog"
    /// 商店目录的内容源 brandID（运营自有内容源）
    static let shopCatalogBrandID = "shaonv-xinyuan"
    /// 商店目录分片的 partitionID（brandID/entityType/scope）
    static var shopCatalogPartitionID: String { "\(shopCatalogBrandID)/\(shopCatalogEntityType)/all" }

    static func packRecordName(payloadHash: String) -> String { "th.pack.\(payloadHash)" }

    // MARK: 远端媒体（THMedia）

    /// 远端媒体引用前缀。发布端把运营上传图（`local:<文件名>`，只在原设备沙盒里有效）
    /// 上传成 THMedia 后，把包里的引用改写成 `thmedia:<contentHash>`。
    ///
    /// 为什么必须改写：不改写的话引用仍指向 `local:`，换台设备解析不到文件 →
    /// 商品图一律显示占位图（2026-09-25 实测：数据都拉到了，图全空）。
    static let mediaReferencePrefix = "thmedia:"

    /// 远端媒体记录名（THMedia，与 Mac 端 `th.media.{contentHash}` 一致）
    static func mediaRecordName(contentHash: String) -> String { "th.media.\(contentHash)" }

    static func mediaReference(contentHash: String) -> String {
        "\(mediaReferencePrefix)\(contentHash)"
    }

    /// `thmedia:<contentHash>` → 内容摘要；不是本前缀或摘要不合法时返回 nil
    static func mediaContentHash(in reference: String?) -> String? {
        guard let trimmed = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.hasPrefix(mediaReferencePrefix) else { return nil }
        let hash = String(trimmed.dropFirst(mediaReferencePrefix.count))
        return isPayloadHash(hash) ? hash : nil
    }

    /// 媒体键的**唯一解析口径**（公共数据库字段配置方案 §2.2）。
    ///
    /// canonical `mediaKey` 优先；它没有时回退 URL 字段里的 `thmedia:<hash>`
    /// （2026-09-25 那版发布端把摘要写在 URL 里，旧包必须继续能读）。
    /// 两个都没有 → nil，调用方按「不是远端媒体」走旧逻辑，绝不猜。
    ///
    /// ⚠️ 任何消费端读图的地方都必须走这里，禁止各处自己拆字符串 ——
    ///    拆法一旦分叉，就会出现「数据拉到了、图全空」且无从定位。
    static func resolvedMediaKey(
        _ mediaKey: String?, fallbackReferences: [String?] = []
    ) -> String? {
        if let key = mediaKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           isPayloadHash(key) {
            return key
        }
        for reference in fallbackReferences {
            if let hash = mediaContentHash(in: reference) { return hash }
        }
        return nil
    }

    /// 校验 64 位小写十六进制 SHA-256
    static func isPayloadHash(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.allSatisfy { character in
            guard character.isASCII else { return false }
            return ("a"..."f").contains(character) || ("0"..."9").contains(character)
        }
    }

    /// 压缩字节的 SHA-256（hex 小写）——与 Mac 端 `sha256_hex` 同一口径
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 发布头（THRelease）

/// 发布头：**唯一**的版本生效点。普通读取先只取元数据（不含资产），
/// 确认 `releaseSeq` 变化后才去取根清单 —— 版本未变零下载（§11.2）。
nonisolated struct ShopCatalogReleaseHeader: Equatable, Sendable {
    var releaseSeq: Int
    var schemaVersion: Int
    var revocationEpoch: Int
    var minimumReaderVersion: Int
    var previousReleaseSeq: Int
    var publishedAt: String?
    var rootIndexHash: String
}

// MARK: - 根清单（root-index.json）

nonisolated struct ShopCatalogRootIndex: Codable, Equatable, Sendable {
    nonisolated struct Partition: Codable, Equatable, Sendable {
        var partitionID: String
        var brandID: String
        var entityType: String
        var partitionRevision: Int
        var coverageStatus: String
        var checkedThrough: String?
        var packRecordName: String
        var payloadHash: String
        var recordCount: Int
        var dependencyPackRecordNames: [String]?

        /// 覆盖状态（§5.2）：empty 是有版本的有效结论，不是缺数据
        nonisolated enum Coverage {
            static let complete = "complete"
            static let empty = "empty"
            static let partial = "partial"
        }
    }

    var schemaVersion: Int
    var releaseSeq: Int
    var publishedAt: String?
    var revocationEpoch: Int
    var partitions: [Partition]
    /// 撤回清单（§14.1：撤回优先于一切展示来源）。
    /// 本期商店目录的撤回在发布侧体现为「更高 releaseSeq 的新快照」，
    /// 根清单撤回字段保留解码兼容，消费端先记录、不单独展示。
    var withdrawals: [Withdrawal]?

    nonisolated struct Withdrawal: Codable, Equatable, Sendable {
        var canonicalEntityID: String?
        var withdrawnAt: String?
    }

    /// 商店目录分片（整包单分片：最多一个；nil = 公共库还没有商店内容）
    var shopCatalogPartition: Partition? {
        partitions.first { $0.entityType == ShopCatalogSyncProtocol.shopCatalogEntityType }
    }
}

// MARK: - 分片负载（THDataPack.asset 解压后的 JSON）

/// 商店目录分片负载。与画册分片的差别：载荷键是 `shopCatalog`（不是 `records`），
/// 且一个分片承载**合并后的完整目录**（种子 + 覆盖层），引用全部包内可解析。
nonisolated struct ShopCatalogPackPayload: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var partitionID: String
    var brandID: String
    var entityType: String
    var partitionRevision: Int
    var coverageStatus: String
    var checkedThrough: String?
    var shopCatalog: ShopCatalog
}

// MARK: - 校验（三层，与 Mac 端 build/validate 同源）

nonisolated enum ShopCatalogSyncValidationError: LocalizedError, Equatable {
    /// 发布头结构 / 协议版本不受支持（需要更新 App 才能读）
    case unsupportedSchema(String)
    /// 根清单与发布头互相矛盾
    case rootIndexMismatch(String)
    /// 公共库还没有商店内容（正常空态，不算故障）
    case shopPartitionMissing
    /// 分片字节 / 契约与声明不符（拒绝安装，保留旧数据）
    case packMismatch(String)
    /// 分片内容结构不合法（重复 ID / 悬空引用 / 墓碑冲突 / 枚举非法）
    case structural([String])

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let detail):
            return "发布协议版本不受支持，需要更新 App 后才能获取商店上新：\(detail)"
        case .rootIndexMismatch(let detail):
            return "发布头与根清单不一致，已放弃本次更新：\(detail)"
        case .shopPartitionMissing:
            return "公共库中还没有发布商店内容"
        case .packMismatch(let detail):
            return "商店数据包与声明不符，已放弃安装：\(detail)"
        case .structural(let issues):
            return "商店数据包内容校验未通过（\(issues.count) 条）：\(issues.prefix(3).joined(separator: "；"))"
        }
    }
}

nonisolated enum ShopCatalogCloudSyncValidator {

    /// 三层校验 + 解码，全过才返回可安装的目录快照：
    ///   1. 发布头（协议版本 / 读取器版本）
    ///   2. 根清单（序号一致 / 商店分片存在 / 记录名与摘要自洽）
    ///   3. 分片（压缩字节摘要 → 契约 → 结构）
    ///
    /// 任何一层失败都抛错，调用方必须保留旧数据（§11.2 第 16 步）。
    static func validatedShopCatalog(
        header: ShopCatalogReleaseHeader,
        rootIndexData: Data,
        packCompressed: Data
    ) throws -> ShopCatalog {
        // ---- 第 1 层：发布头
        guard header.schemaVersion == ShopCatalogSyncProtocol.schemaVersion else {
            throw ShopCatalogSyncValidationError.unsupportedSchema(
                "schemaVersion \(header.schemaVersion) ≠ \(ShopCatalogSyncProtocol.schemaVersion)")
        }
        guard header.minimumReaderVersion <= ShopCatalogSyncProtocol.readerVersion else {
            throw ShopCatalogSyncValidationError.unsupportedSchema(
                "minimumReaderVersion \(header.minimumReaderVersion) > 本读取器 \(ShopCatalogSyncProtocol.readerVersion)")
        }

        // ---- 第 2 层：根清单
        let rootIndex: ShopCatalogRootIndex
        do {
            rootIndex = try ShopCatalogJSONCoding.decoder().decode(
                ShopCatalogRootIndex.self, from: rootIndexData)
        } catch {
            throw ShopCatalogSyncValidationError.rootIndexMismatch("根清单解码失败：\(error.localizedDescription)")
        }
        guard rootIndex.releaseSeq == header.releaseSeq else {
            throw ShopCatalogSyncValidationError.rootIndexMismatch(
                "releaseSeq \(rootIndex.releaseSeq) ≠ 发布头 \(header.releaseSeq)")
        }
        guard let partition = rootIndex.shopCatalogPartition else {
            throw ShopCatalogSyncValidationError.shopPartitionMissing
        }
        try checkPartitionContract(partition)

        // ---- 第 3 层：分片（先字节后结构）
        guard ShopCatalogSyncProtocol.sha256Hex(packCompressed) == partition.payloadHash else {
            throw ShopCatalogSyncValidationError.packMismatch("压缩字节 SHA-256 与 payloadHash 不一致")
        }
        let payload: ShopCatalogPackPayload
        do {
            let raw = try decompress(packCompressed)
            payload = try ShopCatalogJSONCoding.decoder().decode(
                ShopCatalogPackPayload.self, from: raw)
        } catch let error as ShopCatalogSyncValidationError {
            throw error
        } catch {
            throw ShopCatalogSyncValidationError.packMismatch("数据包解码失败：\(error.localizedDescription)")
        }
        try checkPayload(payload, matches: partition)
        try checkStructure(payload.shopCatalog, coverageStatus: partition.coverageStatus)

        // 版本未推进（与已安装一致）由调用方比对 installedRevision 决定，这里只管内容合法。
        return payload.shopCatalog
    }

    /// 分片描述契约（§6.7）：分片 ID 必须能由 brandID/entityType 推出，防运维手写漂移
    static func checkPartitionContract(_ partition: ShopCatalogRootIndex.Partition) throws {
        let knownCoverages: Set<String> = [
            ShopCatalogRootIndex.Partition.Coverage.complete,
            ShopCatalogRootIndex.Partition.Coverage.empty,
            ShopCatalogRootIndex.Partition.Coverage.partial,
        ]
        guard knownCoverages.contains(partition.coverageStatus) else {
            throw ShopCatalogSyncValidationError.rootIndexMismatch(
                "未知覆盖状态 \(partition.coverageStatus)")
        }
        let parts = partition.partitionID.split(separator: "/")
        guard parts.count >= 3, parts[0] == partition.brandID, parts[1] == partition.entityType else {
            throw ShopCatalogSyncValidationError.rootIndexMismatch(
                "分片 ID \(partition.partitionID) 与 brandID/entityType 不一致")
        }
        guard ShopCatalogSyncProtocol.isPayloadHash(partition.payloadHash) else {
            throw ShopCatalogSyncValidationError.rootIndexMismatch("payloadHash 不是 64 位小写 hex")
        }
        guard partition.packRecordName == ShopCatalogSyncProtocol.packRecordName(payloadHash: partition.payloadHash) else {
            throw ShopCatalogSyncValidationError.rootIndexMismatch("packRecordName 与 payloadHash 不一致")
        }
    }

    /// 负载与根清单描述互相印证（防「清单说 A、包里装 B」）
    static func checkPayload(
        _ payload: ShopCatalogPackPayload, matches partition: ShopCatalogRootIndex.Partition
    ) throws {
        guard payload.schemaVersion == ShopCatalogSyncProtocol.schemaVersion else {
            throw ShopCatalogSyncValidationError.packMismatch(
                "负载 schemaVersion \(payload.schemaVersion) 不受支持")
        }
        guard payload.partitionID == partition.partitionID,
              payload.brandID == partition.brandID,
              payload.entityType == partition.entityType,
              payload.partitionRevision == partition.partitionRevision else {
            throw ShopCatalogSyncValidationError.packMismatch("负载声明的分片与根清单描述不一致")
        }
    }

    /// 已通过三层校验并落盘的缓存包 → 目录快照（**冷启动恢复**路径）。
    ///
    /// 缓存包是「校验通过才写盘」的（`ShopCatalogCloudSyncService` 第 7 步），
    /// 所以恢复路径不重复做网络侧校验，只做「还解不开吗」的兜底：
    /// 解不开返回 nil，调用方按「没有本地内容」处理并重新下载。
    ///
    /// ⚠️ 远端层只进内存（`ShopCatalogStore.installRemoteCatalog`），进程重启即丢失。
    /// 没有这条恢复路径就会出现「控制状态说已安装、界面上一个店家都没有」
    /// ——2026-09-25 真机「看不到店家上线数据」的直接成因之一。
    static func catalog(fromVerifiedPack compressed: Data) -> ShopCatalog? {
        guard let raw = try? decompress(compressed),
              let payload = try? ShopCatalogJSONCoding.decoder().decode(
                  ShopCatalogPackPayload.self, from: raw) else { return nil }
        return payload.shopCatalog
    }

    // MARK: 结构校验（与 Mac 端 validate_shop_catalog 同一口径的客户端版）

    /// 结构校验。返回问题列表（空 = 通过）。
    /// 图片引用允许指向 Bundle 内置资源（`bundle:` 前缀），与 Mac 端一致**不**做资产引用校验。
    static func structuralIssues(
        _ catalog: ShopCatalog, coverageStatus: String
    ) -> [String] {
        var issues: [String] = []

        let entityCount = catalog.shops.count + catalog.series.count + catalog.products.count
            + catalog.variants.count + catalog.sizeCharts.count + catalog.saleEvents.count
            + catalog.assets.count + catalog.styleProfiles.count
        let coverage = ShopCatalogRootIndex.Partition.Coverage.self
        if coverageStatus == coverage.empty && entityCount > 0 {
            issues.append("覆盖状态为 empty 的分片不得携带条目")
        }
        if (coverageStatus == coverage.complete || coverageStatus == coverage.partial) && entityCount == 0 {
            issues.append("覆盖状态为 \(coverageStatus) 的分片不得为空")
        }

        // id 唯一（跨实体类型也不得撞车）
        var seen: [String: String] = [:]  // id → 实体类别
        func register(_ id: String, _ kind: String) {
            if id.isEmpty {
                issues.append("\(kind) 存在空 ID")
                return
            }
            if let previous = seen[id] {
                issues.append("ID \(id) 同时出现在 \(previous) 与 \(kind)")
            } else {
                seen[id] = kind
            }
        }
        catalog.shops.forEach { register($0.id, "店家") }
        catalog.series.forEach { register($0.id, "系列") }
        catalog.products.forEach { register($0.id, "商品") }
        catalog.variants.forEach { register($0.id, "规格") }
        catalog.sizeCharts.forEach { register($0.id, "尺码表") }
        catalog.saleEvents.forEach { register($0.id, "销售记录") }
        catalog.assets.forEach { register($0.id, "图片资源") }
        catalog.styleProfiles.forEach { register($0.id, "款式档案") }

        let shopIDs = Set(catalog.shops.map(\.id))
        let seriesIDs = Set(catalog.series.map(\.id))
        let productIDs = Set(catalog.products.map(\.id))

        if !shopIDs.isEmpty {
            for series in catalog.series where !shopIDs.contains(series.shopID) {
                issues.append("系列「\(series.name)」引用了不存在的店家 \(series.shopID)")
            }
            for product in catalog.products where !shopIDs.contains(product.shopID) {
                issues.append("商品「\(product.name)」引用了不存在的店家 \(product.shopID)")
            }
        }
        if !seriesIDs.isEmpty {
            for product in catalog.products where !seriesIDs.contains(product.seriesID) {
                issues.append("商品「\(product.name)」引用了不存在的系列 \(product.seriesID)")
            }
            for profile in catalog.styleProfiles where !seriesIDs.contains(profile.seriesID) {
                issues.append("款式档案「\(profile.designName)」引用了不存在的系列 \(profile.seriesID)")
            }
        }
        if !productIDs.isEmpty {
            for variant in catalog.variants where !productIDs.contains(variant.productID) {
                issues.append("规格 \(variant.id) 引用了不存在的商品 \(variant.productID)")
            }
            for event in catalog.saleEvents where !productIDs.contains(event.productID) {
                issues.append("销售记录 \(event.id) 引用了不存在的商品 \(event.productID)")
            }
            for chart in catalog.sizeCharts where !productIDs.contains(chart.productID) {
                issues.append("尺码表 \(chart.id) 引用了不存在的商品 \(chart.productID)")
            }
        }

        // 墓碑与现存实体不得同 id（既「在售」又「已删除」= 数据自相矛盾）
        let tombstones: [(alive: [String], removed: [String], label: String)] = [
            (catalog.shops.map(\.id), catalog.removedShopIDs, "店家"),
            (catalog.series.map(\.id), catalog.removedSeriesIDs, "系列"),
            (catalog.products.map(\.id), catalog.removedProductIDs, "商品"),
        ]
        for (alive, removed, label) in tombstones {
            for id in Set(alive).intersection(removed).sorted() {
                issues.append("已删除\(label) \(id) 仍出现在目录中")
            }
        }
        return issues
    }

    private static func checkStructure(
        _ catalog: ShopCatalog, coverageStatus: String
    ) throws {
        let issues = structuralIssues(catalog, coverageStatus: coverageStatus)
        guard issues.isEmpty else {
            throw ShopCatalogSyncValidationError.structural(issues)
        }
    }

    /// gzip 压缩（RFC 1952）—— 与 `decompress` 成对，**两侧必须同一口径**。
    ///
    /// iOS 运营端自己发布 `THDataPack` 时必须产出**与 Mac 端 `gzip.compress` 同格式**
    /// 的字节流，否则消费端 `decompress` 解不开（它对魔数 / 方法位是硬校验）。
    ///
    /// ⚠️ 不要被 `COMPRESSION_ZLIB` 这个名字骗了：它给的是**裸 deflate**
    ///    （RFC 1951，无 zlib 头），本文件 `decompress` 的注释早已写明这一点。
    ///    2026-09-26 实测复核（macOS 26）：
    ///
    ///        输入 0B   → 2B  `03 00`
    ///        输入 1B   → 3B  `73 04 00`
    ///        输入 512B → 20B 首字节 `0x7B`
    ///
    ///    首字节从不是 `0x78`（zlib 头）也不是 `0x1F`（gzip 头）；20 字节恰好等于
    ///    Python `zlib.compress(src, 9)` 去掉 2+4 封装后的 deflate 段长度。
    ///    **所以这里绝不能去剥「2 字节 zlib 头 + 4 字节 Adler32 尾」** ——
    ///    那会把 deflate 数据本身截断，产物必然解不开（已踩过一次）。
    ///
    /// mtime 固定写 0：构建时间不该进产物，否则「内容没变、字节变了」——
    /// 内容寻址的数据包会每次发布都多出一个新包。
    static func compress(_ data: Data) throws -> Data {
        let encoded: Data
        do {
            encoded = try (data as NSData).compressed(using: .zlib) as Data
        } catch {
            throw ShopCatalogSyncValidationError.packMismatch("压缩失败：\(error.localizedDescription)")
        }
        let deflated = normalizeToRawDeflate(encoded)

        var output = Data()
        output.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00])   // 魔数 + deflate + 无可选段
        output.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // mtime = 0（见上方说明）
        // XFL 是**提示位**不是校验位，解压端一律忽略：
        //   0x00 = 未声明 / 0x02 = 最大压缩 / 0x04 = 最快
        // 这里写 0x00 而不抄 Python 的 0x02 —— libcompression 用的是它自己的默认级别，
        // 我们并不知道是否等价于「最大压缩」，写 0x02 等于替它谎报。
        // OS=0xFF 是「未知」，与 Python gzip.compress 一致。
        output.append(contentsOf: [0x00, 0xFF])               // XFL + OS
        output.append(deflated)
        let crc = Self.crc32(data)
        for shift in stride(from: 0, to: 32, by: 8) {         // CRC32 小端
            output.append(UInt8(truncatingIfNeeded: crc >> UInt32(shift)))
        }
        let size = UInt32(truncatingIfNeeded: data.count)     // ISIZE 小端
        for shift in stride(from: 0, to: 32, by: 8) {
            output.append(UInt8(truncatingIfNeeded: size >> UInt32(shift)))
        }
        return output
    }

    /// 把 `compressed(using: .zlib)` 的产物归一成裸 deflate（RFC 1951）。
    ///
    /// 现状下这就是恒等变换（Apple 给的就是裸 deflate），保留是因为 Apple 从未把
    /// 这条行为写进文档，将来若改回真 zlib 封装，这里能兜住、不至于静默发出坏包。
    ///
    /// 判别为什么不会误伤裸 deflate：zlib 头的 CMF 低 4 位必须是 8 且 CINFO ≤ 7，
    /// 候选只有 `0x08`…`0x78`；而实测裸 deflate 首字节是 `0x73`/`0x03`，
    /// 若是 stored 块（BTYPE=00）则只能是 `0x00`/`0x01`（第 3–7 位必须全 0 作填充）。
    /// 两条集合不相交，所以不会把裸 deflate 当成 zlib 去剥。
    ///
    /// 阈值 8 的依据：zlib 封装最短 = 2 字节头 + 2 字节空 deflate 块
    /// （fixed-Huffman 的 end-of-block 共 10 bit）+ 4 字节 Adler32 = 8 字节。
    /// 短于 8 就不可能带封装 —— 这里**必须**用 8，早期版本拍脑袋写 6，
    /// 结果空数据（2 字节）和 1 字节输入（3 字节）被判成「长度异常」直接抛错。
    private static func normalizeToRawDeflate(_ encoded: Data) -> Data {
        /// zlib 封装的理论最短长度（见上）。低于它必然是裸 deflate。
        let shortestPossibleZlibStream = 8
        guard encoded.count >= shortestPossibleZlibStream else { return encoded }
        let prefix = [UInt8](encoded.prefix(2))
        let isZlibWrapped = prefix[0] & 0x0F == 0x08      // CM = deflate
            && prefix[0] >> 4 <= 0x07                      // CINFO ≤ 7（窗口 ≤ 32K）
            && (UInt16(prefix[0]) << 8 | UInt16(prefix[1])) % 31 == 0
        if isZlibWrapped {
            return encoded.subdata(in: 2..<(encoded.count - 4))
        }
        return encoded
    }

    /// CRC32（IEEE 802.3，gzip 尾校验用）。系统没把 zlib 的 crc32 暴露给 Swift，
    /// 这里自带一张表，行为与 Python `zlib.crc32` 一致。
    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1 != 0) ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    /// gzip 解压（RFC 1952）。
    ///
    /// 为什么手写头部解析而不是直接 `NSData.decompressed(using: .zlib)`：
    /// libcompression 的 `COMPRESSION_ZLIB` 是 **raw deflate**（RFC 1951，无 zlib 头），
    /// 而 Mac 端 `gzip.compress` 产物带 gzip 头与 CRC 尾 —— 直接喂会解压失败。
    /// 所以：剥掉 gzip 头（含 FEXTRA/FNAME/FCOMMENT/FHCRC 可选段）与 8 字节尾，
    /// 再把中间的 raw deflate 交给系统解压。
    private static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        // 显式标注参数类型：无标注时 $0 只有字符串插值一处使用，推断歧义
        // （编译器会把参数推成 any Any.Type，调用处全部报错）
        let fail: (String) -> ShopCatalogSyncValidationError = {
            ShopCatalogSyncValidationError.packMismatch("数据包不是合法 gzip：\($0)")
        }

        guard bytes.count > 18 else { throw fail("长度不足") }
        guard bytes[0] == 0x1F, bytes[1] == 0x8B else { throw fail("魔数不符") }
        guard bytes[2] == 0x08 else { throw fail("压缩方法不是 deflate") }
        let flags = bytes[3]
        guard flags & 0xE0 == 0 else { throw fail("保留了未定义的标志位，拒绝解析") }

        var offset = 10  // 固定头：魔数(2) + 方法(1) + 标志(1) + mtime(4) + XFL(1) + OS(1)
        if flags & 0x04 != 0 {  // FEXTRA
            guard offset + 2 <= bytes.count else { throw fail("FEXTRA 截断") }
            let extraLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + extraLength
        }
        if flags & 0x08 != 0 {  // FNAME（零结尾）
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {  // FCOMMENT（零结尾）
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }  // FHCRC
        guard offset + 8 <= bytes.count else { throw fail("头部越过尾部，结构不完整") }

        let deflated = Data(bytes[offset..<(bytes.count - 8)])  // 去掉 CRC32(4) + ISIZE(4)
        do {
            return try (NSData(data: deflated) as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw fail("deflate 解压失败：\(error.localizedDescription)")
        }
    }
}
