//
//  ShopCatalogOpsMediaStaging.swift
//  ItemManager
//
//  运营上传 · 图片暂存与目录改写（iOS 运营上传实施方案 §3.1 / §3.3）。
//
//  ## 职责
//
//    1. **扫描**：找出目录里所有 `local:<文件名>` 引用（只在运营这台设备的沙盒里有效）；
//    2. **暂存**：逐张读出字节 → 算 SHA-256（= `mediaKey`）→ 判 MIME → 记字节数；
//    3. **改写**：把这些引用换成 `thmedia:<hash>`，并把 canonical `CatalogAsset.mediaKey`
//       写进商品 JSON（公共数据库字段配置方案 §2.2）。
//
//  ## 三条硬约束
//
//    · 只处理 `local:`：`bundle:`（App 内置）与 `http(s)` 原样保留，**不**上传；
//    · 暂存阶段**不改目录**：`plan` 只读，`rewrite` 单独一步 —— 暂存失败时目录必须原封不动；
//    · **缺图硬报错**，与 Mac 端 `collect_shop_catalog_media` 同口径：静默跳过会让
//      「图没传」以「用户看到空白」的形式暴露，比直接失败难查得多。
//
//  纯逻辑（`nonisolated`，可单测）；文件读取走注入的闭包，测试不需要真沙盒。
//

import Foundation

// MARK: - 错误

nonisolated enum ShopCatalogOpsMediaStagingError: LocalizedError, Equatable {
    /// 引用的本地文件不存在（沙盒重置 / 导出时漏带图）
    case fileMissing(String)
    /// 文件读不出来
    case unreadable(String)
    /// MIME 不在准入白名单内（客户端解不了的类型不许进公共库）
    case unsupportedMimeType(reference: String, mimeType: String)
    /// 超出单张媒体字节上限
    case tooLarge(reference: String, byteCount: Int)

    var errorDescription: String? {
        switch self {
        case .fileMissing(let reference):
            return "图片 \(reference) 在本机找不到，无法上传（若换过设备或清过沙盒，请重新选图）"
        case .unreadable(let reference):
            return "图片 \(reference) 读取失败"
        case .unsupportedMimeType(let reference, let mimeType):
            return "图片 \(reference) 的类型 \(mimeType) 不在允许清单内"
        case .tooLarge(let reference, let byteCount):
            return "图片 \(reference) 超过单张上限（\(byteCount) > \(ShopCatalogUploadPolicy.maxMediaBytes) 字节）"
        }
    }
}

// MARK: - 暂存结果

/// 引用出现的**位置**：出问题时要能指出是哪一行，只说「有图没传」运营无从下手。
nonisolated struct ShopCatalogOpsMediaOwner: Equatable, Sendable {
    let productID: String
    let assetID: String
    let field: String
    let reference: String
}

/// 一张待上传媒体（同一内容摘要只出现一次，多处引用共享）
nonisolated struct ShopCatalogOpsStagedMedia: Equatable, Sendable {
    /// 图片字节 SHA-256，同时是 `THMedia` 记录名后缀
    let mediaKey: String
    /// 本地暂存文件路径
    let filePath: String
    let fileName: String
    let mimeType: String
    let byteCount: Int
    /// 引用它的所有位置
    let owners: [ShopCatalogOpsMediaOwner]
}

// MARK: - 暂存与改写

nonisolated enum ShopCatalogOpsMediaStaging {

    /// 引用前缀 `local:`（取自共享层，避免各处再写字面量）
    static let localReferencePrefix = ShopCatalogMediaReferences.localPrefix

    // MARK: 扫描 + 暂存

    /// 扫描目录里所有 `local:` 引用并算出 `mediaKey` / MIME / 字节数。
    ///
    /// - Parameters:
    ///   - catalog: 合并后的完整目录（种子 + 覆盖层）
    ///   - resolveFile: `local:<文件名>` → 本地文件 URL，**只在文件确实存在时才返回非 nil**。
    ///     默认走 `ShopCatalogImageStore`，并额外补一次存在性检查：
    ///     `ShopCatalogImageStore.url(for:)` 只拼路径、不查盘，直接用它会让「文件不存在」
    ///     掉进下面的 `unreadable` 分支 —— 而这两件事对运营的含义完全不同
    ///     （缺图 → 换过设备/清过沙盒，要重新选图；读不出来 → 文件在但读失败，要求重试）。
    ///   - readData: 读文件字节；默认 `Data(contentsOf:)`。返回 nil 表示**文件在但读失败**，
    ///     即 `unreadable` —— 因为不存在的情况已经被 `resolveFile` 拦掉了。
    /// - Returns: 按 `mediaKey` 去重后的待上传媒体
    /// - Throws: `ShopCatalogOpsMediaStagingError`（缺图 / 不可读 / 类型不许 / 超上限）
    static func plan(
        for catalog: ShopCatalog,
        resolveFile: (String) -> URL? = { reference in
            guard let url = ShopCatalogImageStore.url(for: reference) else { return nil }
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        },
        readData: (URL) -> Data? = { try? Data(contentsOf: $0) }
    ) throws -> [ShopCatalogOpsStagedMedia] {
        var byHash: [String: ShopCatalogOpsStagedMedia] = [:]
        var order: [String] = []

        for item in ownedReferences(in: catalog) {
            guard item.reference.hasPrefix(localReferencePrefix) else { continue }
            // 文件名口径走共享层：空名 / 含 `/` / `.` 开头一律按「没有这个文件」处理，
            // 与发布端 `collect_shop_catalog_media` 的 rewrite 同一判定。
            guard let fileName = ShopCatalogMediaReferences.localFileName(in: item.reference) else {
                throw ShopCatalogOpsMediaStagingError.fileMissing(item.reference)
            }
            guard let url = resolveFile(item.reference) else {
                throw ShopCatalogOpsMediaStagingError.fileMissing(item.reference)
            }
            guard let data = readData(url) else {
                throw ShopCatalogOpsMediaStagingError.unreadable(item.reference)
            }
            if data.count > ShopCatalogUploadPolicy.maxMediaBytes {
                throw ShopCatalogOpsMediaStagingError.tooLarge(
                    reference: item.reference, byteCount: data.count)
            }
            guard let mimeType = mimeType(for: data),
                  ShopCatalogUploadPolicy.isAllowedMimeType(mimeType) else {
                throw ShopCatalogOpsMediaStagingError.unsupportedMimeType(
                    reference: item.reference,
                    mimeType: mimeType(for: data) ?? ShopCatalogMediaStore.inferredFileExtension(data))
            }

            let digest = ShopCatalogSyncProtocol.sha256Hex(data)
            if var existing = byHash[digest] {
                existing = ShopCatalogOpsStagedMedia(
                    mediaKey: existing.mediaKey,
                    filePath: existing.filePath,
                    fileName: existing.fileName,
                    mimeType: existing.mimeType,
                    byteCount: existing.byteCount,
                    owners: existing.owners + [item])
                byHash[digest] = existing
            } else {
                byHash[digest] = ShopCatalogOpsStagedMedia(
                    mediaKey: digest,
                    filePath: url.path,
                    fileName: fileName,
                    mimeType: mimeType,
                    byteCount: data.count,
                    owners: [item])
                order.append(digest)
            }
        }
        return order.compactMap { byHash[$0] }
    }

    /// 按魔数判 MIME。复用 `ShopCatalogMediaStore.inferredFileExtension` 的判定口径，
    /// 保证「下载端认得的类型」与「上传端允许的类型」永远是同一套。
    static func mimeType(for data: Data) -> String? {
        switch ShopCatalogMediaStore.inferredFileExtension(data) {
        case "jpg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return nil
        }
    }

    // MARK: 改写

    /// 把 `local:` 引用改写成 `thmedia:<hash>`，并回填 `CatalogAsset.mediaKey`。
    ///
    /// - Parameter mediaKeys: `local:<文件名>` → 内容摘要（即 `plan` 的结果按引用反查）
    /// - Returns: 改写后的目录（入参不变）
    static func rewrite(
        _ catalog: ShopCatalog, mediaKeys: [String: String]
    ) -> ShopCatalog {
        guard !mediaKeys.isEmpty else { return catalog }
        var rewritten = catalog

        func resolve(_ reference: String?) -> String? {
            guard let reference, reference.hasPrefix(localReferencePrefix) else { return reference }
            guard let digest = mediaKeys[reference] else { return reference }
            return ShopCatalogSyncProtocol.mediaReference(contentHash: digest)
        }

        rewritten.assets = catalog.assets.map { asset in
            var item = asset
            item.originalURL = resolve(asset.originalURL) ?? asset.originalURL
            item.thumbnailURL = resolve(asset.thumbnailURL)
            item.previewURL = resolve(asset.previewURL)
            // canonical 媒体键取**原图**的摘要（方案 §2.2：第一版只加一个 mediaKey）
            for value in [item.originalURL, item.thumbnailURL, item.previewURL] {
                if let hash = ShopCatalogSyncProtocol.mediaContentHash(in: value) {
                    item.mediaKey = hash
                    break
                }
            }
            return item
        }

        rewritten.shops = catalog.shops.map { shop in
            var item = shop
            item.logo = resolve(shop.logo)
            item.cover = resolve(shop.cover)
            return item
        }

        rewritten.series = catalog.series.map { series in
            var item = series
            item.cover = resolve(series.cover)
            if var chart = series.priceChart {
                chart.sourceImage = resolve(chart.sourceImage)
                chart.sourceImages = chart.sourceImages?.map { resolve($0) ?? $0 }
                item.priceChart = chart
            }
            return item
        }

        rewritten.sizeCharts = catalog.sizeCharts.map { chart in
            var item = chart
            item.sourceImage = resolve(chart.sourceImage)
            return item
        }

        return rewritten
    }

    // MARK: 引用枚举（**字段清单唯一来源在共享包**）

    /// 目录里所有「发布端会改写」的图片引用。
    ///
    /// 字段清单**不在这里**：它只有一处定义 —— `ShopCatalogMediaReferences.all(in:)`
    /// （计划 §6 P4：「不要同时让 Python CLI、iOS App、Mac App 各自定义一套发布格式」）。
    /// 与 Mac 门禁 `ShopCatalogPublicationGate`、Python 发布端
    /// `build_release.collect_shop_catalog_media` 共用同一份。
    ///
    /// 只取 `isRewrittenByPublisher` 那一批：`products.images` /
    /// `variants.imageAssetID` 存的是 `CatalogAsset.id` 而不是文件，改写它们会把
    /// 资源 id 换成内容摘要，商品图直接丢。
    static func ownedReferences(in catalog: ShopCatalog) -> [ShopCatalogOpsMediaOwner] {
        ShopCatalogMediaReferences.publisherRewritten(in: catalog).map { reference in
            ShopCatalogOpsMediaOwner(
                productID: reference.productID,
                assetID: reference.entityID,
                field: reference.field,
                reference: reference.reference)
        }
    }

    /// `local:<文件名>` → 文件名（非本地引用 / 名字不合法返回 nil）。
    ///
    /// 委托给共享口径，避免这里再维护一套「什么算合法的本地文件名」：
    /// 发布端 Python 也会拒绝空名、含 `/`、以及 `.` 开头的名字。
    static func localFileName(in reference: String?) -> String? {
        ShopCatalogMediaReferences.localFileName(in: reference)
    }
}
