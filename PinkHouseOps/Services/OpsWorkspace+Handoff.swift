//
//  OpsWorkspace+Handoff.swift
//  PinkHouseOps
//
//  「iOS 导出整包」的接收端 —— Mac 端此前**没有任何入口**能吃到它。
//
//  ## 为什么必须有这一条路（2026-09-28 实测）
//
//  运营的实际链路是：
//
//      iOS「导出整包（含图片）」→ 一个 tar（shop-catalog.json + images/<原文件名>）
//                              → 交接给 Mac → Mac 解开 → 发布
//
//  这条链路在 iOS 侧是完整的（`ShopCatalogOpsView.exportWholeBundleForPublishing`，
//  tar 内条目名固定是 `images/<文件名>`，见 `ShopCatalogExportArchive.imageEntries`），
//  但 **Mac 侧的接收入口随 2026-09-27 的分区清理一起被删了** —— 服务层
//  `importCatalog(from:)` 还在，却没有任何视图调它。结果是：
//
//    · iOS 的内容进不了 Mac（用户报的「iOS 上传同步不到 Mac」）；
//    · Mac 草稿里那批 `local:img-XXXXXXXX.jpg` 永远缺文件，
//      于是 `makePublicationArchive` 缺图硬报错，Mac 也发不出去。
//
//  本文件只补「接收」这一半，不新增第二种包格式。
//
//  ## 一条不能破的口径：图片**按原文件名**进 staging
//
//  导入的目录 JSON 里引用的是 `local:img-XXXXXXXX.jpg`，而 Mac 自己
//  `ShopCatalogMediaStaging` 产出的文件名是 `<mediaKey>.<ext>`（64 位十六进制）。
//  两套命名并存是**设计如此**：
//
//    · 引用名是「交接方给的名字」，改不得 —— 一改，目录里的引用就全悬空；
//    · 门禁（`ShopCatalogPublicationGate`）判的是「引用的文件名在不在 staging 里」，
//      不是「staging 里有没有同名哈希文件」。
//
//  所以这里**原样拷贝，绝不重新哈希命名**。只有本机新导入的单图才走 staging 的哈希命名。
//

import Foundation

// MemberImportVisibility：用到哪些类型就在本文件里显式 import 哪些。
import SharedCatalog

// MARK: - 导入结果

/// 一次整包导入的结果。**缺失的图片必须逐条带出来** ——
/// 「导入成功但图不全」比「导入失败」难查得多（发布时才会炸，且炸在别人看不见的地方）。
struct OpsHandoffImportReport {
    let shops: Int
    let series: Int
    let products: Int
    let assets: Int
    /// 真的拷进 staging 的图片数
    let copiedImages: Int
    /// 引用到了但包里没有的文件名（前若干个会显示出来）
    let missingImageNames: [String]

    var summary: String {
        var parts = ["已导入 \(shops) 店家 / \(series) 系列 / \(products) 商品 / \(assets) 图片资源",
                     "拷入 \(copiedImages) 张图"]
        if !missingImageNames.isEmpty {
            parts.append("\(missingImageNames.count) 张在包里找不到")
        }
        return parts.joined(separator: "，")
    }

    /// 缺图的可见说明（为空表示一张不缺）。
    var missingText: String? {
        guard !missingImageNames.isEmpty else { return nil }
        let shown = missingImageNames.prefix(5).joined(separator: "、")
        let tail = missingImageNames.count > 5 ? " 等 \(missingImageNames.count) 个" : ""
        return "包里缺这些图：\(shown)\(tail)。缺图的目录发布时会被门禁拦下，"
            + "请在 iOS 端重新「导出整包（含图片）」。"
    }
}

// MARK: - 接收整包

extension OpsWorkspace {

    /// 导入一份 iOS 交接过来的整包。
    ///
    /// - Parameter url: 解开后的**目录**（内含 `shop-catalog.json` 与 `images/`），
    ///   或直接是那个 `shop-catalog.json`。两者都支持 —— 运营手上的东西形状不一，
    ///   但**绝不接受 tar**：解 tar 要自己写解析器，而 macOS 双击就能解开，
    ///   没必要在 App 里再养一套 USTAR 读取。
    /// - Returns: 导入结果；nil = 失败，原因在 `lastError` 里。
    @discardableResult
    func importHandoffPackage(from url: URL) -> OpsHandoffImportReport? {
        // 只读隔离态下导入 = 覆盖损坏记录 → 拒绝（R03）
        guard canMutate() else { return nil }

        // security-scoped：作用域用完必须还回去，否则系统会一直替我们持有权限。
        // 选目录时授权到目录，目录里的 `images/` 随之可访问。
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let layout = OpsHandoffLayout.resolve(url) else {
            lastError = "没找到 shop-catalog.json：请选择 iOS 整包解开后的目录"
                + "（里面有 shop-catalog.json 和 images/），或直接选那个 JSON。"
            return nil
        }

        // ---- 1) 先解码：解不开就一个字节都别拷（避免 staging 里留下一堆孤儿图）
        let decoded: ShopCatalog
        do {
            let data = try Data(contentsOf: layout.catalogURL)
            decoded = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: data)
        } catch {
            lastError = "导入失败（目录 JSON 解不开，已保留当前草稿）：\(error.localizedDescription)"
            return nil
        }

        // ---- 2) 图片按原文件名进 staging
        let names = OpsHandoffLayout.referencedLocalFileNames(in: decoded)
        let staging = stagingDirectory
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            lastError = "创建 staging 目录失败：\(error.localizedDescription)"
            return nil
        }

        var copied = 0
        var missing: [String] = []
        for name in names {
            guard let source = layout.imageURL(forNamed: name) else {
                missing.append(name)
                continue
            }
            let target = staging.appendingPathComponent(name)
            do {
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: source, to: target)
                copied += 1
            } catch {
                missing.append(name)
            }
        }

        // ---- 3) 内容替换走既有导入路径（同一套门禁、同一个 markDirty / 落盘口径）
        guard importCatalog(from: layout.catalogURL) else { return nil }

        let report = OpsHandoffImportReport(
            shops: decoded.shops.count,
            series: decoded.series.count,
            products: decoded.products.count,
            assets: decoded.assets.count,
            copiedImages: copied,
            missingImageNames: missing.sorted())
        statusMessage = report.summary
        if let missingText = report.missingText {
            lastError = missingText
        } else {
            lastError = nil
        }
        return report
    }
}

// MARK: - 包内布局

/// 整包的两种形状：目录 / 裸 JSON。
///
/// 单独抽出来是因为「去哪儿找 shop-catalog.json、去哪儿找 images/」
/// 这段判定纯逻辑、不碰状态，可以单独读、也便于将来加 tar 分支时只改这一处。
enum OpsHandoffLayout {
    case directory(catalogURL: URL, imagesDirectory: URL)
    case singleFile(catalogURL: URL)

    var catalogURL: URL {
        switch self {
        case .directory(let catalogURL, _): return catalogURL
        case .singleFile(let catalogURL): return catalogURL
        }
    }

    /// 按引用名找图。目录形态下 `images/` 与目录根都试 ——
    /// iOS 导出的是 `images/<名>`，但人工整理过的包常常把图摊在根目录。
    func imageURL(forNamed name: String) -> URL? {
        let fileManager = FileManager.default
        switch self {
        case .directory(_, let imagesDirectory):
            let inImages = imagesDirectory.appendingPathComponent(name)
            if let url = OpsHandoffLayout.readable(inImages, fileManager) { return url }
            let inRoot = catalogURL.deletingLastPathComponent().appendingPathComponent(name)
            return OpsHandoffLayout.readable(inRoot, fileManager)
        case .singleFile(let catalogURL):
            let sibling = catalogURL.deletingLastPathComponent().appendingPathComponent(name)
            return OpsHandoffLayout.readable(sibling, fileManager)
        }
    }

    /// ⚠️ **不能用 `fileExists` 判可读性**：沙盒里 `stat` 与 `open` 走两套判定，
    /// `fileExists` 会对没权限的路径返回 true。唯一判据是「真的读得开」。
    private static func readable(_ url: URL, _ fileManager: FileManager) -> URL? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        try? handle.close()
        return url
    }

    static func resolve(_ url: URL) -> OpsHandoffLayout? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            let catalog = url.appendingPathComponent("shop-catalog.json")
            guard readable(catalog, fileManager) != nil else { return nil }
            return .directory(
                catalogURL: catalog,
                imagesDirectory: url.appendingPathComponent("images", isDirectory: true))
        }
        guard url.pathExtension.lowercased() == "json",
              readable(url, fileManager) != nil else { return nil }
        return .singleFile(catalogURL: url)
    }

    /// 目录里所有 `local:` 引用指向的文件名（去重）。
    ///
    /// 引用字段清单只此一处（`ShopCatalogMediaReferences`），
    /// 不在这里另写一份 —— 少了字段就会漏拷图，而漏拷的表现是「发布时才报缺图」。
    static func referencedLocalFileNames(in catalog: ShopCatalog) -> [String] {
        var names = Set<String>()
        for reference in ShopCatalogMediaReferences.all(in: catalog) {
            if let name = ShopCatalogMediaReferences.localFileName(in: reference.reference) {
                names.insert(name)
            }
        }
        return names.sorted()
    }
}
