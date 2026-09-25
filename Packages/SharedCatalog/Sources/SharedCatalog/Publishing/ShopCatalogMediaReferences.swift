//
//  ShopCatalogMediaReferences.swift
//  SharedCatalog
//
//  目录里「哪些字段承载图片引用」的**唯一一份 Swift 定义**
//  （计划 §6 P4：「不要同时让 Python CLI、iOS App、Mac App 各自定义一套发布格式」）。
//
//  ## 为什么必须收口到这里
//
//  发布路径要遍历同一批字段两次，而这两次分别落在两个地方：
//
//    · **校验**（Mac 侧 `ShopCatalogPublicationGate.review`）——
//      这批引用在本机解不解得出图；
//    · **改写**（iOS 侧 `ShopCatalogOpsMediaStaging.rewrite`，
//      Python 侧 `build_release.collect_shop_catalog_media`）——
//      把 `local:` 换成 `thmedia:`。
//
//  两边各抄一份字段清单时，新增一个图片字段**必然只改一边**。后果是
//  「改写了却没上传」或「上传了却没校验」，而这两种漏法表现完全一样：
//  **数据是好的、只有图是空的** —— 线上看起来像 App 的 bug，
//  2026-09-25 已经实测踩过一次。所以字段清单只能有一处。
//
//  ## 两类字段的判定口径必须分开
//
//  | 类别 | `isRewrittenByPublisher` | `allowsAssetID` |
//  |---|---|---|
//  | `assets.originalURL` / `thumbnailURL` / `previewURL` | ✅ | ❌ |
//  | `shops.logo` / `shops.cover` / `series.cover` / `series.priceChart.*` / `sizeCharts.sourceImage` | ✅ | ✅ |
//  | `products.images[]` / `variants.imageAssetID` | ❌ | ✅ |
//
//  · `isRewrittenByPublisher` = **存的是文件引用**（可能是 `local:`），发布端必须改写它。
//    把 `products.images` 也改写会把「资源 id」换成「内容摘要」，商品图直接丢；
//  · `allowsAssetID` = **这个字段可能合法地写着一个 `CatalogAsset.id`**。
//    为假时才有必要把裸名字判成「无法核对」（见
//    `ShopCatalogReferenceResolution.unverifiableBareName`）。
//    只有 `assets` 的三个字段本来就是 URL，不会放 id。
//
//  ⚠️ 跨语言的那一份在 `tools/time_hall/publication/build_release.py:
//     collect_shop_catalog_media`。改这里必须同步改那边；
//     `ShopCatalogMediaReferenceTests` 把字段清单钉死了，两边不一致会红。
//

import Foundation

// MARK: - 一处引用的位置与含义

/// 目录里某个字段承载的一处图片引用。
public nonisolated struct ShopCatalogMediaReference: Hashable, Sendable {

    /// 稳定字段路径，命名与发布端 Python **逐字对齐**（`assets.originalURL`、
    /// `shops.logo`、`series.priceChart.sourceImages`、`products.images`…）。
    ///
    /// **不要改这些字符串**：它们是人读日志、跨语言对照、以及
    /// `ShopCatalogMediaReferenceTests` 的锚点。同一字段出现多处（如
    /// `priceChart.sourceImages` 的第 2 张）时本字段相同，下标只出现在 `owner`。
    public let field: String

    /// 人话归属，直接用于界面与报错文案，如
    /// `图片资源 asset-1 / 原图`、`店家「樱花小羊」/ 封面`、`商品「星月夜 JSK」/ 商品图`。
    public let owner: String

    /// 所属实体 id（asset / shop / series / sizeChart / product / variant）。
    /// 「指向的 asset 存不存在」这类判定要靠它。
    public let entityID: String

    /// 商品归属 id；无商品概念时为空串（与旧实现保持一致，不要改成 nil）。
    public let productID: String

    /// 引用**原文**。
    ///
    /// 故意不在这一层做 trim：改写端必须拿到原字节才能原样回写；
    /// 判定是否需要 trim 由各自的调用方决定（门禁会 trim）。
    public let reference: String

    /// 发布端是否会把它的 `local:` 改写成 `thmedia:`。
    public let isRewrittenByPublisher: Bool

    /// 该字段是否可能合法地写着一个 `CatalogAsset.id`。
    public let allowsAssetID: Bool

    // 跨模块构造入口：`public` 结构体的合成逐成员 init 是 internal，外部模块必须显式声明。
    public init(
        field: String,
        owner: String,
        entityID: String,
        productID: String,
        reference: String,
        isRewrittenByPublisher: Bool,
        allowsAssetID: Bool
    ) {
        self.field = field
        self.owner = owner
        self.entityID = entityID
        self.productID = productID
        self.reference = reference
        self.isRewrittenByPublisher = isRewrittenByPublisher
        self.allowsAssetID = allowsAssetID
    }
}

// MARK: - 遍历

public nonisolated enum ShopCatalogMediaReferences {

    /// `local:<文件名>` 引用前缀。发布端 Python 的 `LOCAL_REFERENCE_PREFIX` 同值。
    public static let localPrefix = "local:"

    /// 走遍目录里所有承载图片引用的字段，顺序稳定。
    ///
    /// 顺序按「实体分组」排列（assets → shops → series → sizeCharts → products → variants），
    /// 组内按字段书写顺序。**顺序是有意义的**：改写端按首次出现顺序产出待上传清单，
    /// 顺序一变，运营看到的「待上传图片列表」顺序也会变。
    ///
    /// - Returns: 逐条引用；空串 / 全空白的值会被跳过（占位符不算引用）。
    public static func all(in catalog: ShopCatalog) -> [ShopCatalogMediaReference] {
        var results: [ShopCatalogMediaReference] = []

        func push(
            field: String,
            owner: String,
            entityID: String,
            productID: String = "",
            _ reference: String?,
            isRewrittenByPublisher: Bool,
            allowsAssetID: Bool
        ) {
            guard let reference, !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            results.append(ShopCatalogMediaReference(
                field: field,
                owner: owner,
                entityID: entityID,
                productID: productID,
                reference: reference,
                isRewrittenByPublisher: isRewrittenByPublisher,
                allowsAssetID: allowsAssetID))
        }

        // 1) 图片资源本体：三个 URL 字段。
        //
        // ⚠️ owner 文案必须**逐字**保持原样（含空格位置）：它直接显示在运营界面上，
        //    也是既有回归用例的匹配锚点。历史口径是「带 `「」` 的名字后面不加空格、
        //    纯 id 后面加空格」——不一致，但改文案等于改界面，不做顺手统一。
        for asset in catalog.assets {
            let prefix = "图片资源 \(asset.id)"
            let fields: [(String, String, String?)] = [
                ("assets.originalURL", "原图", asset.originalURL),
                ("assets.thumbnailURL", "缩略图", asset.thumbnailURL),
                ("assets.previewURL", "预览图", asset.previewURL),
            ]
            for (field, label, value) in fields {
                push(field: field, owner: "\(prefix) / \(label)", entityID: asset.id, value,
                     isRewrittenByPublisher: true, allowsAssetID: false)
            }
        }

        // 2) 店家图标 / 封面
        for shop in catalog.shops {
            let name = "店家「\(shop.name)」"
            push(field: "shops.logo", owner: "\(name)/ 图标", entityID: shop.id, shop.logo,
                 isRewrittenByPublisher: true, allowsAssetID: true)
            push(field: "shops.cover", owner: "\(name)/ 封面", entityID: shop.id, shop.cover,
                 isRewrittenByPublisher: true, allowsAssetID: true)
        }

        // 3) 系列封面 / 系列价格表原图
        for series in catalog.series {
            let name = "系列「\(series.name)」"
            push(field: "series.cover", owner: "\(name)/ 封面", entityID: series.id, series.cover,
                 isRewrittenByPublisher: true, allowsAssetID: true)
            if let chart = series.priceChart {
                push(field: "series.priceChart.sourceImage", owner: "\(name)/ 价格表原图",
                     entityID: series.id, chart.sourceImage,
                     isRewrittenByPublisher: true, allowsAssetID: true)
                for (index, one) in (chart.sourceImages ?? []).enumerated() {
                    push(field: "series.priceChart.sourceImages",
                         owner: "\(name)/ 价格表原图 \(index + 1)",
                         entityID: series.id, one,
                         isRewrittenByPublisher: true, allowsAssetID: true)
                }
            }
        }

        // 4) 尺码表原图
        for chart in catalog.sizeCharts {
            push(field: "sizeCharts.sourceImage", owner: "尺码表 \(chart.id) / 原图",
                 entityID: chart.id, productID: chart.productID, chart.sourceImage,
                 isRewrittenByPublisher: true, allowsAssetID: true)
        }

        // 5) 商品图：**存的是 `CatalogAsset.id`，不是文件**
        //    → 发布端不该改写它（改了就把 id 换成摘要），但要校验悬空 id。
        for product in catalog.products {
            for assetID in product.images {
                push(field: "products.images", owner: "商品「\(product.name)」/ 商品图",
                     entityID: product.id, productID: product.id, assetID,
                     isRewrittenByPublisher: false, allowsAssetID: true)
            }
        }

        // 6) 规格图绑定：同上，也是 `CatalogAsset.id`
        for variant in catalog.variants {
            push(field: "variants.imageAssetID", owner: "规格 \(variant.id) / 规格图",
                 entityID: variant.id, productID: variant.productID, variant.imageAssetID,
                 isRewrittenByPublisher: false, allowsAssetID: true)
        }

        return results
    }

    /// 发布端**会改写**的全部引用（`local:` → `thmedia:`）。
    ///
    /// 改写端只需要这一批：它对「文件引用」与「资源 id」的处置不同，
    /// 混在一起就会把 `products.images` 里的 id 也换掉。
    public static func publisherRewritten(in catalog: ShopCatalog) -> [ShopCatalogMediaReference] {
        all(in: catalog).filter(\.isRewrittenByPublisher)
    }

    /// 目录里所有引用涉及的**字段路径**（去重、稳定顺序）。
    /// 用于跨语言对照与回归锁：这里少一个字段就是一次「发布后没图」。
    public static func fieldPaths(in catalog: ShopCatalog) -> [String] {
        var seen: Set<String> = []
        return all(in: catalog).map(\.field).filter { seen.insert($0).inserted }
    }

    /// `local:<文件名>` → 文件名；非 `local:` 或文件名不合法时返回 nil。
    ///
    /// 与 `ShopCatalogExportArchive.localFileName(in:)` 同口径（那里是发布打包用的），
    /// 这里只是把它抬到引用层，免得调用方为了判断「是不是本地引用」再绕一层。
    public static func localFileName(in reference: String?) -> String? {
        guard let reference else { return nil }
        return ShopCatalogExportArchive.localFileName(in: reference)
    }
}
