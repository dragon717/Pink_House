//
//  ShopCatalogPublicationGate.swift
//  SharedCatalog
//
//  发布前的图片引用门禁（计划 §6 P0：「禁止发布只含 `local:` 的新目录」）。
//
//  ## 为什么必须挡在发布前
//
//  `local:<文件名>` 只在**运营那台设备的沙盒**里有效（Application Support/ShopCatalog/images/）。
//  原样发布出去，其它设备解不出文件 → 商品图一律占位图，而且**数据是好的、图是空的**，
//  线上看起来像「App 的 bug」而不是「发布漏了图」（2026-09-25 实测踩到）。
//
//  发布端 `build_release.py` 对缺图是**硬报错**的；这个文件把同一套判定前移到
//  Mac 工具里，让运营在点「发布」之前就看到「哪几个引用解不出图」，
//  而不是等构建脚本抛异常。
//
//  ## 判定口径（与 `build_release.py:collect_shop_catalog_media` 对齐）
//
//  | 引用形态 | 判定 | 理由 |
//  |---|---|---|
//  | `thmedia:<hash>` | ✅ 已远端化 | 换设备可解 |
//  | `mediaKey` 字段（64 位 hex） | ✅ canonical 媒体键 | 公共数据库字段配置方案 §2.2 |
//  | `local:<名>` 且 staging 里有该文件 | ✅ 可上传 | 发布端会改写成 `thmedia:` |
//  | `local:<名>` 但 staging 里没有 | ⛔ **阻断** | 上传无从下手，发出去就是空图 |
//  | `bundle:` / 裸文件名 | ✅ App 内置资源 | 与 Mac 端一致，不做资产校验 |
//  | `http(s)://` | ⚠️ 放行但告警 | 不受我们控制，撤回/授权责任在运营 |
//  | 指向不存在的 `CatalogAsset.id` | ⚠️ 放行但告警 | 悬空 asset id，客户端会退化成占位图 |
//  | asset-id 字段里的裸名字 | ⚠️ 放行但告警 | 无法与内置资源文件名区分，但也无法证明它存在 |
//

import Foundation

// MARK: - 单个引用的判定

public nonisolated enum ShopCatalogReferenceResolution: Hashable, Sendable {
    /// 已经是 `thmedia:<contentHash>` —— 换设备可解
    case remoteMedia(mediaKey: String)
    /// `CatalogAsset.mediaKey` 字段里就是一个合法的 canonical 媒体键
    case canonicalMediaKey(String)
    /// `local:<文件名>`，且 staging 目录里有对应文件（发布端能上传）
    case stagedLocal(fileName: String)
    /// `local:<文件名>`，但 staging 目录里**没有**这个文件 —— 阻断发布
    case missingLocal(fileName: String)
    /// `bundle:` 或裸文件名：App 内置资源，两端一致不校验
    case bundled
    /// `http(s)://`：外部图片，能显示但不受控
    case remoteURL(String)
    /// 指向一个不存在的 `CatalogAsset.id`（悬空引用）
    case danglingAssetID(String)
    /// 无前缀、无斜杠的**裸名字**：按 App 内置资源放行，但无法证明它真的存在。
    ///
    /// 为什么单列一类而不是并进 `.bundled`：`product.images` 这类字段按定义存的是
    /// `CatalogAsset.id`，而历史数据里也可能直接写内置资源文件名。两者在字符串上
    /// 无法区分（都可能是 `cat_jsk_blue.png`），所以**不能阻断**（会误伤存量数据），
    /// 但也**不能静默当成功** —— 悬空的 asset id 在客户端就是一个占位图，
    /// 而「数据是好的、只有图是空的」正是这个仓库最难查的一类线上问题。
    /// 处置：放行 + 在界面上列出来，让人自己认一眼。
    case unverifiableBareName(String)

    /// 是否阻断发布
    public var blocksPublication: Bool {
        if case .missingLocal = self { return true }
        return false
    }

    /// 是否算「已解决」（阻断项与悬空/裸名字都不算）
    public var isResolved: Bool {
        switch self {
        case .remoteMedia, .canonicalMediaKey, .stagedLocal, .bundled:
            return true
        case .missingLocal, .remoteURL, .danglingAssetID, .unverifiableBareName:
            return false
        }
    }

    /// 需要人看一眼的（不阻断，但要在界面上列出来）
    public var isWarning: Bool {
        switch self {
        case .remoteURL, .danglingAssetID, .unverifiableBareName: return true
        case .remoteMedia, .canonicalMediaKey, .stagedLocal, .missingLocal, .bundled:
            return false
        }
    }
}

/// 一处图片引用 + 它属于谁（报错文案要说清「哪张图的哪个字段」）
public struct ShopCatalogMediaReferenceFinding: Hashable, Sendable {
    /// 人话描述的归属，如「图片资源 img-AB12 / 原图」「店家「樱花小羊」/ 封面」
    public let owner: String
    /// 引用原文（`local:xxx.jpg` / `thmedia:<hash>` / …）
    public let reference: String
    public let resolution: ShopCatalogReferenceResolution

    public init(owner: String, reference: String, resolution: ShopCatalogReferenceResolution) {
        self.owner = owner
        self.reference = reference
        self.resolution = resolution
    }
}

// MARK: - 审查结果

public nonisolated struct ShopCatalogPublicationReview: Sendable {
    /// 目录结构问题（来自 `ShopCatalogCloudSyncValidator.structuralIssues`，与消费端同口径）
    public var catalogIssues: [String] = []
    /// 图片引用阻断项（每条都能直接读给运营听）
    public var blockingIssues: [String] = []
    /// 放行但要提示的（远程图 / 悬空 asset id）
    public var warnings: [String] = []
    /// 全部引用判定（界面逐条列表用）
    public var findings: [ShopCatalogMediaReferenceFinding] = []
    /// staging 目录里**必须存在**的文件名（发布端会按这个清单找文件）
    public var requiredStagedFileNames: [String] = []
    /// 已经远端化的媒体键（可以跳过上传）
    public var remoteMediaKeys: [String] = []

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        catalogIssues: [String] = [],
        blockingIssues: [String] = [],
        warnings: [String] = [],
        findings: [ShopCatalogMediaReferenceFinding] = [],
        requiredStagedFileNames: [String] = [],
        remoteMediaKeys: [String] = []
    ) {
        self.catalogIssues = catalogIssues
        self.blockingIssues = blockingIssues
        self.warnings = warnings
        self.findings = findings
        self.requiredStagedFileNames = requiredStagedFileNames
        self.remoteMediaKeys = remoteMediaKeys
    }

    public var isBlocked: Bool { !catalogIssues.isEmpty || !blockingIssues.isEmpty }

    /// 一句话结论
    public var summary: String {
        if isBlocked {
            return "已挡住发布：\(catalogIssues.count + blockingIssues.count) 条问题需要处理"
        }
        if !warnings.isEmpty {
            return "可以发布，但有 \(warnings.count) 条提示"
        }
        return "可以发布"
    }
}

// MARK: - 门禁本体

public nonisolated enum ShopCatalogPublicationGate {

    /// 收集并判定目录里的全部图片引用。
    ///
    /// - Parameters:
    ///   - stagedFileNames: staging 目录里**现有**的文件名集合（只比文件名，不读内容；
    ///     内容核对由发布端按 SHA-256 做）。传空集 = 「本机没有可用图片」，
    ///     此时所有 `local:` 都会被判成缺图。
    ///   - coverageStatus: 目录覆盖状态，用于结构校验（整包发布固定 `complete`）。
    public static func review(
        _ catalog: ShopCatalog,
        stagedFileNames: Set<String>,
        coverageStatus: String = "complete"
    ) -> ShopCatalogPublicationReview {
        var review = ShopCatalogPublicationReview()
        review.catalogIssues = ShopCatalogCloudSyncValidator.structuralIssues(
            catalog, coverageStatus: coverageStatus)

        let assetIDs = Set(catalog.assets.map(\.id))
        review.findings = findings(in: catalog, assetIDs: assetIDs, stagedFileNames: stagedFileNames)

        var required: Set<String> = []
        var remoteKeys: Set<String> = []
        for finding in review.findings {
            switch finding.resolution {
            case .stagedLocal(let fileName):
                // 文件在 staging 里 → 发布端会把它上传成 THMedia 并改写引用。
                // 这是**正常中间态**（Mac 工具的全部意义就是走到这一步），不阻断。
                required.insert(fileName)
            case .missingLocal(let fileName):
                review.blockingIssues.append(
                    "\(finding.owner) 引用的图片「\(fileName)」在本机找不到文件，无法上传。"
                    + "请重新选择这张图，或把文件放回图片目录。")
            case .remoteMedia(let mediaKey):
                remoteKeys.insert(mediaKey)
            case .canonicalMediaKey(let mediaKey):
                remoteKeys.insert(mediaKey)
            case .remoteURL(let url):
                review.warnings.append(
                    "\(finding.owner) 用的是外部图片地址（\(url)），不受本次发布控制；"
                    + "撤回或换图请在源站处理。")
            case .danglingAssetID(let id):
                review.warnings.append(
                    "\(finding.owner) 指向了不存在的图片资源 \(id)，客户端会显示占位图。")
            case .unverifiableBareName(let name):
                review.warnings.append(
                    "\(finding.owner) 写的是一个裸名字「\(name)」，既不是图片资源 id 也不是 "
                    + "`bundle:` / `local:` / `thmedia:` 引用。按 App 内置资源放行，"
                    + "但本机无法确认它真的存在 —— 如果目录该有图，请回来确认。")
            case .bundled:
                break
            }
        }

        review.requiredStagedFileNames = required.sorted()
        review.remoteMediaKeys = remoteKeys.sorted()
        review.blockingIssues = deduplicated(review.blockingIssues)
        review.warnings = deduplicated(review.warnings)
        return review
    }

    /// 本机需要哪些图片文件（用于「导入整包」后核对素材是否齐）
    public static func requiredLocalFileNames(in catalog: ShopCatalog) -> [String] {
        let assetIDs = Set(catalog.assets.map(\.id))
        var names: Set<String> = []
        // staging 清单传空集：这里只关心「引用了哪些 local 文件名」，
        // 与文件在不在无关（所以两种 local 判定都要收）
        for finding in findings(in: catalog, assetIDs: assetIDs, stagedFileNames: []) {
            switch finding.resolution {
            case .stagedLocal(let fileName), .missingLocal(let fileName):
                names.insert(fileName)
            case .remoteMedia, .canonicalMediaKey, .bundled, .remoteURL,
                 .danglingAssetID, .unverifiableBareName:
                break
            }
        }
        return names.sorted()
    }

    /// **后置校验**：发布产物里不许再有任何 `local:` 引用。
    ///
    /// 与 `review` 的分工：`review` 是「发之前，图都准备好了吗」；
    /// 本方法是「发之后，产物真的远端化了吗」——两者都要有，
    /// 否则「上传步骤被跳过」这种 bug 会一路走到线上。
    public static func issuesInPublishedCatalog(_ catalog: ShopCatalog) -> [String] {
        let assetIDs = Set(catalog.assets.map(\.id))
        var issues: [String] = []
        // staging 清单传空集：发布产物里**任何** local 引用都是问题，
        // 不区分文件在不在（在也不该出现，因为已经被改写成 thmedia: 了）
        for finding in findings(in: catalog, assetIDs: assetIDs, stagedFileNames: []) {
            switch finding.resolution {
            case .missingLocal(let fileName), .stagedLocal(let fileName):
                issues.append(
                    "\(finding.owner) 的图片仍是本机引用「\(fileName)」，没有换成 thmedia:。")
            case .remoteMedia, .canonicalMediaKey, .bundled, .remoteURL,
                 .danglingAssetID, .unverifiableBareName:
                break
            }
        }
        return deduplicated(issues)
    }

    /// 目录里是否还残留任何 `local:` 引用（快速判定，不做归属分析）
    public static func containsLocalReferences(_ catalog: ShopCatalog) -> Bool {
        let assetIDs = Set(catalog.assets.map(\.id))
        return findings(in: catalog, assetIDs: assetIDs, stagedFileNames: []).contains { finding in
            switch finding.resolution {
            case .stagedLocal, .missingLocal: return true
            default: return false
            }
        }
    }

    // MARK: 引用遍历（字段清单唯一来源见 ShopCatalogMediaReferences）

    /// 走遍目录里所有可能承载图片引用的字段，逐条给出判定。
    ///
    /// 字段清单**不在这里**：它只有一处定义 —— `ShopCatalogMediaReferences.all(in:)`，
    /// 与 iOS 改写端 `ShopCatalogOpsMediaStaging.rewrite`、Python 发布端
    /// `build_release.collect_shop_catalog_media` 共用同一份。
    /// 这里只负责「按 `stagedFileNames` 判解不解得出图」。
    ///
    /// ⚠️ 新增图片字段时改 `ShopCatalogMediaReferences`，**不是**改这里；
    /// 漏一边就会出现「本地看着有图、发布后没图」。
    ///
    /// - Parameter stagedFileNames: staging 目录里现有的文件名集合。
    ///   `local:` 引用据此分成「文件在（可上传）」与「文件不在（阻断）」两种判定。
    public static func findings(
        in catalog: ShopCatalog,
        assetIDs: Set<String>,
        stagedFileNames: Set<String>
    ) -> [ShopCatalogMediaReferenceFinding] {
        ShopCatalogMediaReferences.all(in: catalog).map { reference in
            let trimmed = reference.reference.trimmingCharacters(in: .whitespacesAndNewlines)
            return ShopCatalogMediaReferenceFinding(
                owner: reference.owner,
                reference: trimmed,
                resolution: resolveReference(
                    trimmed,
                    assetIDs: assetIDs,
                    allowsAssetID: reference.allowsAssetID,
                    stagedFileNames: stagedFileNames))
        }
    }

    /// 单个引用的判定。`allowsAssetID = false` 用于「本来就是 URL」的字段
    /// （`CatalogAsset` 的三个 URL 字段），避免把一个恰好长得像 id 的字符串
    /// 误判成悬空引用。
    private static func resolveReference(
        _ reference: String,
        assetIDs: Set<String>,
        allowsAssetID: Bool,
        stagedFileNames: Set<String>
    ) -> ShopCatalogReferenceResolution {
        if let hash = ShopCatalogSyncProtocol.mediaContentHash(in: reference) {
            return .remoteMedia(mediaKey: hash)
        }
        if ShopCatalogSyncProtocol.isPayloadHash(reference) {
            return .canonicalMediaKey(reference)
        }
        if let fileName = ShopCatalogExportArchive.localFileName(in: reference) {
            // 文件在不在，决定它是「待上传的正常中间态」还是「阻断发布的缺图」
            return stagedFileNames.contains(fileName)
                ? .stagedLocal(fileName: fileName)
                : .missingLocal(fileName: fileName)
        }
        if reference.hasPrefix("bundle:") { return .bundled }
        if reference.hasPrefix("http://") || reference.hasPrefix("https://") {
            return .remoteURL(reference)
        }
        if allowsAssetID, assetIDs.contains(reference) { return .bundled }
        if allowsAssetID, reference.hasPrefix("asset:") {
            return .danglingAssetID(String(reference.dropFirst("asset:".count)))
        }
        // 裸文件名（无前缀、无斜杠）：在 asset-id 字段里**无法与内置资源文件名区分**，
        // 按 App 内置资源放行，但降级成「无法核对」让界面列出来（见 `.unverifiableBareName`）。
        // 非 asset-id 字段（如 CatalogAsset 的三个 URL）本就走 `.bundled`，
        // 与 `ShopCatalogImageResolver` 的兜底分支一致。
        if !reference.contains("/") {
            return allowsAssetID ? .unverifiableBareName(reference) : .bundled
        }
        return allowsAssetID ? .danglingAssetID(reference) : .bundled
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for value in values where seen.insert(value).inserted {
            output.append(value)
        }
        return output
    }
}
