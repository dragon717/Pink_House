//
//  ShopCatalogMediaReferenceTests.swift
//  SharedCatalogTests
//
//  「哪些字段承载图片引用」这份清单的**回归锁**。
//
//  ## 为什么值得单独一组测试
//
//  这份清单是三处共用的事实来源：共享包门禁 / iOS 改写端 / Python 发布端
//  （计划 §6 P4 明确禁止三方各定义一套）。它出错的**唯一表现**是
//  「发布后某些图没了」——数据完好、只有图片空白，线上看起来像 App 的 bug。
//  所以这组用例故意把清单**逐字写死**：新增字段时测试会红，
//  逼人同时想清楚「Python 那边改了吗、iOS 改写端要不要跟着改」。
//

import XCTest
@testable import SharedCatalog

final class ShopCatalogMediaReferenceTests: XCTestCase {

    // MARK: 清单本身

    /// 字段路径清单**逐字锁定**。
    ///
    /// 改这个数组之前，请先确认三件事：
    ///   1. `tools/time_hall/publication/build_release.py:collect_shop_catalog_media`
    ///      的 rewrite 覆盖面同步改了；
    ///   2. iOS `ShopCatalogOpsMediaStaging.rewrite` 能处理新字段；
    ///   3. 新字段确实需要门禁校验（而不是纯展示字段）。
    func testFieldPathListIsLocked() {
        XCTAssertEqual(
            ShopCatalogMediaReferences.fieldPaths(in: makeFullCatalog()),
            [
                "assets.originalURL",
                "assets.thumbnailURL",
                "assets.previewURL",
                "shops.logo",
                "shops.cover",
                "series.cover",
                "series.priceChart.sourceImage",
                "series.priceChart.sourceImages",
                "sizeCharts.sourceImage",
                "products.images",
                "variants.imageAssetID",
            ],
            "图片引用字段清单变了。三处（共享包 / iOS 改写端 / Python 发布端）必须同步。")
    }

    /// 发布端**只改写**「文件引用」字段；`CatalogAsset.id` 字段绝不能被改写，
    /// 否则资源 id 会被换成内容摘要，商品图直接丢。
    func testPublisherRewriteListExcludesAssetIDFields() {
        let catalog = makeFullCatalog()
        let fields = Set(ShopCatalogMediaReferences.publisherRewritten(in: catalog).map(\.field))

        XCTAssertEqual(fields, [
            "assets.originalURL",
            "assets.thumbnailURL",
            "assets.previewURL",
            "shops.logo",
            "shops.cover",
            "series.cover",
            "series.priceChart.sourceImage",
            "series.priceChart.sourceImages",
            "sizeCharts.sourceImage",
        ])
        XCTAssertFalse(fields.contains("products.images"), "商品图存的是 asset id，不是文件")
        XCTAssertFalse(fields.contains("variants.imageAssetID"), "规格图存的是 asset id，不是文件")
    }

    /// 只有 `CatalogAsset` 的三个 URL 字段「不可能合法地写着 asset id」。
    /// 其余字段都可能是 id，必须允许，否则裸名字会被误判成悬空引用。
    func testOnlyAssetURLFieldsDisallowAssetID() {
        let catalog = makeFullCatalog()
        for reference in ShopCatalogMediaReferences.all(in: catalog) {
            let isAssetURL = reference.field.hasPrefix("assets.")
            XCTAssertEqual(
                reference.allowsAssetID, !isAssetURL,
                "\(reference.field) 的 allowsAssetID 判定错了")
        }
    }

    // MARK: 顺序

    /// 组内顺序必须与 Python 的 `("originalURL", "thumbnailURL", "previewURL")` 一致：
    /// 改写端按首次出现顺序产出待上传清单，顺序一变运营看到的列表顺序也变。
    func testAssetFieldOrderMatchesPublisherScript() {
        let fields = ShopCatalogMediaReferences.all(in: makeFullCatalog())
            .filter { $0.field.hasPrefix("assets.") }
            .map(\.field)
        XCTAssertEqual(
            Array(fields.prefix(3)),
            ["assets.originalURL", "assets.thumbnailURL", "assets.previewURL"])
    }

    /// 价格表第 2 张图必须被遍历到 —— `sourceImages` 是最容易漏的字段，
    /// 漏了就是「价格表第二张图发布后消失」。
    func testSecondPriceChartImageIsTraversedWithIndexedOwner() {
        let owners = ShopCatalogMediaReferences.all(in: makeFullCatalog()).map(\.owner)
        XCTAssertTrue(owners.contains("系列「星月夜」/ 价格表原图 2"), "实际：\(owners)")
    }

    // MARK: 空值与单例

    /// 空串 / 全空白不算引用，必须跳过（否则门禁会为占位符报缺图）。
    func testBlankReferencesAreSkipped() {
        var catalog = makeFullCatalog()
        catalog.shops[0].logo = ""
        catalog.shops[0].cover = "   "
        let references = ShopCatalogMediaReferences.all(in: catalog)
        XCTAssertFalse(references.contains { $0.field == "shops.logo" })
        XCTAssertFalse(references.contains { $0.field == "shops.cover" })
    }

    /// 归属文案要能定位到「哪张图的哪个字段」，否则报错读给运营听也没用。
    func testOwnerLabelsCarryEntityAndField() {
        let byField = Dictionary(
            grouping: ShopCatalogMediaReferences.all(in: makeFullCatalog()), by: \.field)
        XCTAssertEqual(byField["assets.originalURL"]?.first?.owner, "图片资源 asset-1 / 原图")
        XCTAssertEqual(byField["shops.logo"]?.first?.owner, "店家「樱花小羊」/ 图标")
        XCTAssertEqual(byField["sizeCharts.sourceImage"]?.first?.owner, "尺码表 chart-1 / 原图")
        XCTAssertEqual(byField["products.images"]?.first?.owner, "商品「星月夜 JSK」/ 商品图")
        XCTAssertEqual(byField["variants.imageAssetID"]?.first?.owner, "规格 variant-1 / 规格图")
    }

    /// 商品归属要走 `productID`，尺码表要落到具体商品（发布端按商品定位资产）。
    func testProductAttributionIsCarriedThrough() {
        let references = ShopCatalogMediaReferences.all(in: makeFullCatalog())
        XCTAssertEqual(
            references.first { $0.field == "sizeCharts.sourceImage" }?.productID, "product-1")
        XCTAssertEqual(
            references.first { $0.field == "assets.originalURL" }?.productID, "",
            "图片资源本身不属于某个商品，productID 保持空串（与旧口径一致）")
    }

    // MARK: 本地文件名口径

    /// 与 Python `rewrite` 同判定：空名 / 含 `/` / `.` 开头一律视为「没有这个文件」。
    func testLocalFileNameRejectsIllegalNames() {
        XCTAssertEqual(ShopCatalogMediaReferences.localFileName(in: "local:a.jpg"), "a.jpg")
        XCTAssertEqual(ShopCatalogMediaReferences.localFileName(in: "local: a.jpg "), "a.jpg")
        XCTAssertNil(ShopCatalogMediaReferences.localFileName(in: nil))
        XCTAssertNil(ShopCatalogMediaReferences.localFileName(in: "local:"))
        XCTAssertNil(ShopCatalogMediaReferences.localFileName(in: "local:   "))
        XCTAssertNil(ShopCatalogMediaReferences.localFileName(in: "local:sub/a.jpg"))
        XCTAssertNil(ShopCatalogMediaReferences.localFileName(in: "local:.hidden"))
        XCTAssertNil(ShopCatalogMediaReferences.localFileName(in: "thmedia:\(String(repeating: "a", count: 64))"))
        XCTAssertNil(ShopCatalogMediaReferences.localFileName(in: "asset-1"))
    }

    // MARK: 夹具

    private func makeFullCatalog() -> ShopCatalog {
        var series = CatalogSeries(id: "series-1", shopID: "shop-1", name: "星月夜")
        series.cover = "local:series-cover.png"
        series.priceChart = CatalogPriceChart(
            id: "price-chart-1", seriesID: "series-1",
            unit: "CNY", columns: ["档位"], rows: [CatalogSizeRow(label: "定金", values: ["50"])],
            sourceImage: "local:price-1.png",
            sourceImages: ["local:price-1.png", "local:price-2.png"])

        let shop = CatalogShop(
            id: "shop-1", name: "樱花小羊",
            logo: "local:logo.png", cover: "local:shop-cover.png")
        let product = CatalogProduct(
            id: "product-1", shopID: "shop-1", seriesID: "series-1",
            name: "星月夜 JSK", category: "JSK", images: ["asset-1"])
        let variant = CatalogProductVariant(
            id: "variant-1", productID: "product-1",
            color: "粉色", size: "M", imageAssetID: "asset-2")
        let sizeChart = CatalogSizeChart(
            id: "chart-1", productID: "product-1",
            unit: "cm", columns: ["胸围"], rows: [CatalogSizeRow(label: "M", values: ["88"])],
            sourceImage: "local:size-1.png")
        let asset = CatalogAsset(
            id: "asset-1", type: .productImage,
            thumbnailURL: "local:asset-1-thumb.png", previewURL: "local:asset-1-preview.png",
            originalURL: "local:asset-1.png", width: 1200, height: 1600)

        return ShopCatalog(
            shops: [shop], series: [series], products: [product],
            variants: [variant], sizeCharts: [sizeChart], assets: [asset])
    }
}
