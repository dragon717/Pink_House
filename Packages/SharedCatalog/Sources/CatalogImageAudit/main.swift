import Foundation
import SharedCatalog

// 只读全目录检查：与 App 共用引用解析、配色选图及 ImageIO 字节校验。
// 用法：swift run --package-path Packages/SharedCatalog CatalogImageAudit catalog.json media/ report.json
struct ImageResult: Codable {
    let mediaKey: String
    let byteCount: Int
    let width: Int?
    let height: Int?
    let issue: String?
}
struct AuditReport: Codable {
    let productCount: Int
    let assetCount: Int
    let referenceCount: Int
    let selectionCount: Int
    let sharedImageProductIDs: [String]
    let images: [ImageResult]
    let issues: [String]
}

do {
    guard CommandLine.arguments.count == 4 else {
        throw NSError(domain: "CatalogImageAudit", code: 2, userInfo: [NSLocalizedDescriptionKey:
            "用法：CatalogImageAudit <catalog.json> <media-directory> <report.json>"])
    }
    let catalogURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let output = URL(fileURLWithPath: CommandLine.arguments[3])
    let catalog = try ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: Data(contentsOf: catalogURL))
    let assets = Dictionary(catalog.assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let references = ShopCatalogMediaReferences.all(in: catalog)
    var keys = Set(catalog.assets.compactMap { ShopCatalogSyncProtocol.resolvedMediaKey($0.mediaKey) })
    var issues = [String]()
    for reference in references {
        let source = ShopCatalogImageSource.resolve(reference.reference, asset: { assets[$0] })
        keys.formUnion(source.mediaKeys)
        for value in source.references where !value.hasPrefix(ShopCatalogSyncProtocol.mediaReferencePrefix) {
            issues.append("\(reference.owner)：非受控云端图片引用 \(value)，需单独验证")
        }
        if source.mediaKeys.isEmpty && source.references.isEmpty {
            issues.append("\(reference.owner)：没有可解析的图片来源")
        }
    }
    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let byHash = Dictionary(grouping: files, by: { $0.deletingPathExtension().lastPathComponent })
    var images = [ImageResult]()
    for key in keys.sorted() {
        let result: ImageResult = autoreleasepool {
            guard let file = byHash[key]?.sorted(by: { $0.path < $1.path }).first,
                  let bytes = try? Data(contentsOf: file) else {
                return ImageResult(mediaKey: key, byteCount: 0, width: nil, height: nil, issue: "缺少图片文件")
            }
            let reason = ShopCatalogSyncProtocol.sha256Hex(bytes) == key
                ? ShopCatalogMediaStaging.rejectionReason(forStoredBytes: bytes) : "SHA-256 与引用不一致"
            let size = ShopCatalogMediaStaging.pixelSize(of: bytes)
            return ImageResult(mediaKey: key, byteCount: bytes.count, width: size?.width, height: size?.height, issue: reason)
        }
        images.append(result)
        if let issue = result.issue { issues.append("\(key)：\(issue)") }
    }
    let variants = Dictionary(grouping: catalog.variants, by: \.productID)
    var selectionCount = 0
    var sharedProducts = Set<String>()
    for product in catalog.products {
        let choices = variants[product.id] ?? []
        let colors = Set(choices.compactMap { CatalogVariantColorGrouping.normalizedColor($0.color) })
        let boundColors = Dictionary(grouping: choices.compactMap { variant -> (String, String)? in
            guard let color = CatalogVariantColorGrouping.normalizedColor(variant.color),
                  let image = variant.imageAssetID else { return nil }
            let source = ShopCatalogImageSource.resolve(image, asset: { assets[$0] })
            return (source.mediaKey ?? image, color)
        }, by: { $0.0 })
        if boundColors.values.contains(where: { Set($0.map { $0.1 }).count > 1 }) {
            sharedProducts.insert(product.id)
        }
        for color in [nil] + colors.sorted().map(Optional.some) {
            selectionCount += 1
            let selected = ShopCatalogProductImages.references(product: product, variants: choices,
                selectedColor: color, asset: { assets[$0] })
            if selected.isEmpty && (!product.images.isEmpty || choices.contains { $0.imageAssetID != nil }) {
                issues.append("商品 \(product.id)「\(product.name)」/ \(color ?? "未选配色")：选图结果为空")
            }
        }
    }
    let report = AuditReport(productCount: catalog.products.count, assetCount: catalog.assets.count,
        referenceCount: references.count, selectionCount: selectionCount,
        sharedImageProductIDs: sharedProducts.sorted(), images: images, issues: issues)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(report).write(to: output, options: .atomic)
    print("商品 \(report.productCount)，图片 \(images.count)，配色选图 \(selectionCount)，问题 \(issues.count)，报告：\(output.path)")
    exit(issues.isEmpty ? 0 : 1)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(2)
}
