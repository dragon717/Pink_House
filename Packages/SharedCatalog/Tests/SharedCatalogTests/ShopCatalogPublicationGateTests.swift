//
//  ShopCatalogPublicationGateTests.swift
//
//  发布前的图片引用门禁 —— P0 的**核心交付**。
//
//  ## 这份测试要防的是什么
//
//  `local:<文件名>` 只在运营那台设备的沙盒里有效。原样发布出去，别的设备解不出
//  文件 → 商品图一律占位图，而**数据是好的、只有图是空的** ——
//  线上看起来像「App 的 bug」，实际是「发布漏了图」（2026-09-25 真实踩到）。
//
//  发布端 `build_release.py` 对缺图是硬报错的；门禁的意义是把同一套判定**前移**，
//  让运营在点发布之前就看到「哪个字段引用了哪个找不到的文件」。
//
//  所以这里逐条锁死判定表，并且**每个 case 都要有正面与负面两种输入**：
//  只测「能拦住缺图」不够 —— 把合法引用误判成缺图，会让运营在发布日当天卡住，
//  然后有人去把门禁注释掉。误报和漏报一样贵。
//
//  ## 夹具约定
//
//  `makeCatalog` 默认把 `CatalogAsset` 的三个 URL 字段设成**已远端化**
//  （`thmedia:<hash>`），这样默认情况下只有「被测的那个引用」会产生结论，
//  断言不会被夹具自身的引用噪声污染。需要本地图片时显式传 `assetURL:`。
//

import XCTest

@testable import SharedCatalog

final class ShopCatalogPublicationGateTests: XCTestCase {

    private let mediaHash = String(repeating: "a1b2c3d4", count: 8)   // 64 位 hex；⚠️ 不能叫 `hash`：XCTestCase 继承 NSObject，`hash` 是它的只读属性，会报 overriding property
    private let stagedFile = "img-0001.png"

    // MARK: 判定表逐条

    func testThmediaReferenceCountsAsRemoteMedia() {
        let catalog = makeCatalog(productImageReference: "thmedia:\(mediaHash)")
        let review = ShopCatalogPublicationGate.review(catalog, stagedFileNames: [])

        XCTAssertFalse(review.isBlocked, "已远端化的引用不该阻断发布")
        XCTAssertEqual(review.remoteMediaKeys, [mediaHash])
        XCTAssertTrue(review.requiredStagedFileNames.isEmpty, "远端图不需要本机文件")
        XCTAssertEqual(resolution(of: review, ownerSuffix: "商品图"), .remoteMedia(mediaKey: mediaHash))
    }

    func testBareMediaKeyCountsAsCanonicalMediaKey() {
        let catalog = makeCatalog(productImageReference: mediaHash)
        let review = ShopCatalogPublicationGate.review(catalog, stagedFileNames: [])

        XCTAssertFalse(review.isBlocked)
        XCTAssertEqual(review.remoteMediaKeys, [mediaHash])
        XCTAssertTrue(review.requiredStagedFileNames.isEmpty)
    }

    func testLocalReferenceWithStagedFileIsUploadableNotBlocked() {
        let catalog = makeCatalog(productImageReference: "local:\(stagedFile)")
        let review = ShopCatalogPublicationGate.review(
            catalog, stagedFileNames: [stagedFile, "别的不相关文件.png"])

        XCTAssertFalse(review.isBlocked, "「本机有待上传的图」是正常中间态，不是错误")
        XCTAssertEqual(review.requiredStagedFileNames, [stagedFile])
        XCTAssertFalse(review.findings.contains { $0.resolution.blocksPublication })
    }

    func testLocalReferenceWithoutStagedFileBlocksPublication() {
        let catalog = makeCatalog(productImageReference: "local:\(stagedFile)")
        let review = ShopCatalogPublicationGate.review(catalog, stagedFileNames: [])

        XCTAssertTrue(review.isBlocked)
        XCTAssertEqual(review.blockingIssues.count, 1)
        let issue = review.blockingIssues.first ?? ""
        XCTAssertTrue(issue.contains(stagedFile), "报错要说清是哪个文件：\(issue)")
        XCTAssertTrue(issue.contains("商品"), "报错要说清是哪个字段在引用：\(issue)")
        XCTAssertEqual(review.requiredStagedFileNames, [], "缺图的文件不该进「待上传清单」")
    }

    func testBundlePrefixIsTreatedAsBundledResource() {
        let catalog = makeCatalog(productImageReference: "bundle:cat_jsk_blue.png")
        let review = ShopCatalogPublicationGate.review(catalog, stagedFileNames: [])

        XCTAssertFalse(review.isBlocked)
        XCTAssertTrue(review.warnings.isEmpty, "显式 bundle: 前缀是明确声明，不必提示")
        XCTAssertEqual(resolution(of: review, ownerSuffix: "商品图"), .bundled)
    }

    func testRemoteURLPassesWithWarning() {
        let catalog = makeCatalog(productImageReference: "https://example.com/a.png")
        let review = ShopCatalogPublicationGate.review(catalog, stagedFileNames: [])

        XCTAssertFalse(review.isBlocked, "外链图不受本次发布控制，不该阻断")
        XCTAssertEqual(review.warnings.count, 1)
        XCTAssertTrue(review.warnings.first?.contains("example.com") == true)
    }

    func testDanglingAssetIDWarnsOnlyWhenTheIDIsNotKnown() {
        // 有效 asset id → 视为已解析，不该有提示
        let known = makeCatalog(productImageReference: "asset-1")
        XCTAssertTrue(ShopCatalogPublicationGate.review(known, stagedFileNames: []).warnings.isEmpty)

        // 不存在的 asset id（显式 asset: 前缀）→ 悬空，提示但不阻断
        let review = ShopCatalogPublicationGate.review(
            makeCatalog(productImageReference: "asset:ghost"), stagedFileNames: [])
        XCTAssertFalse(review.isBlocked)
        XCTAssertEqual(review.warnings.count, 1)
        XCTAssertTrue(review.warnings.first?.contains("ghost") == true)
    }

    func testBareNameInAssetIDFieldIsWarnedButNotBlocked() {
        // 历史数据里 `product.images` 也可能直接写内置资源文件名，两者在字符串上
        // 无法区分，所以**放行**；但不能静默 —— 悬空 asset id 在客户端就是一张占位图。
        let review = ShopCatalogPublicationGate.review(
            makeCatalog(productImageReference: "cat_jsk_blue.png"), stagedFileNames: [])

        XCTAssertFalse(review.isBlocked, "不能因为存量数据里有裸文件名就挡住发布")
        XCTAssertEqual(review.warnings.count, 1, "实际：\(review.warnings)")
        XCTAssertTrue(review.warnings.first?.contains("cat_jsk_blue.png") == true)
        let finding = review.findings.first { $0.reference == "cat_jsk_blue.png" }
        XCTAssertEqual(finding?.resolution, .unverifiableBareName("cat_jsk_blue.png"))
    }

    func testReferenceWithSlashButNoSchemeIsDanglingAssetID() {
        let review = ShopCatalogPublicationGate.review(
            makeCatalog(productImageReference: "some/nested/thing.png"), stagedFileNames: [])

        XCTAssertEqual(
            resolution(of: review, ownerSuffix: "商品图"),
            .danglingAssetID("some/nested/thing.png"))
        XCTAssertEqual(review.warnings.count, 1)
    }

    func testAssetURLFieldsDoNotTreatBareNamesAsAssetIDs() {
        // `CatalogAsset` 的三个 URL 本来就是 URL 语义（`allowsAssetID: false`），
        // 写内置资源文件名不该被误报成「悬空引用 / 裸名字」。
        let catalog = makeCatalog(
            productImageReference: "asset-1", assetURL: "builtin_placeholder.png")
        let review = ShopCatalogPublicationGate.review(catalog, stagedFileNames: [])

        XCTAssertTrue(review.warnings.isEmpty, "URL 字段的裸文件名不该进告警：\(review.warnings)")
        XCTAssertFalse(review.isBlocked)
    }

    // MARK: 遍历覆盖面（少一处就会「本地看着有图、发布后没图」）

    func testFindingsCoverEveryFieldThatCanCarryAnImage() {
        let review = ShopCatalogPublicationGate.review(
            makeFullCatalog(), stagedFileNames: [stagedFile])

        let owners = Set(review.findings.map(\.owner))
        for expected in [
            "图片资源 asset-1 / 原图",
            "图片资源 asset-1 / 预览图",
            "图片资源 asset-1 / 缩略图",
            "店家「樱花小羊」/ 图标",
            "店家「樱花小羊」/ 封面",
            "系列「星月夜」/ 封面",
            "系列「星月夜」/ 价格表原图",
            "系列「星月夜」/ 价格表原图 2",
            "尺码表 chart-1 / 原图",
            "商品「星月夜 JSK」/ 商品图",
            "规格 variant-1 / 规格图",
        ] {
            XCTAssertTrue(owners.contains(expected), "漏了字段：\(expected)\n实际：\(owners.sorted())")
        }
    }

    func testPriceChartSecondImageIsTraversedToo() {
        // `sourceImages` 是 2026-09-24 新增的多图列表，最容易漏 —— 漏了就会
        // 「价格表第二张图发布后消失」。
        let review = ShopCatalogPublicationGate.review(
            makeFullCatalog(), stagedFileNames: [stagedFile])
        XCTAssertTrue(review.findings.contains { $0.reference == "local:price-2.png" })
    }

    // MARK: 与「后置校验」的分工

    func testRequiredLocalFileNamesIsIndependentOfPresence() {
        let catalog = makeCatalog(productImageReference: "local:\(stagedFile)")

        XCTAssertEqual(
            ShopCatalogPublicationGate.requiredLocalFileNames(in: catalog), [stagedFile],
            "「本机需要哪些图」与「文件在不在」是两个问题，必须分开回答")

        // 缺图走的是**阻断**通道，不该混进「待上传清单」；
        // 但同一处引用无论文件在不在，都不能从「本机需要哪些图」里消失。
        let present = ShopCatalogPublicationGate.review(
            catalog, stagedFileNames: [stagedFile]).requiredStagedFileNames
        let absent = ShopCatalogPublicationGate.review(
            catalog, stagedFileNames: []).requiredStagedFileNames
        XCTAssertEqual(present, [stagedFile])
        XCTAssertEqual(absent, [])
        XCTAssertEqual(Set(present).union(Set(absent)),
                       Set(ShopCatalogPublicationGate.requiredLocalFileNames(in: catalog)))
    }

    func testContainsLocalReferencesDetectsLeftoverLocalRefs() {
        XCTAssertTrue(ShopCatalogPublicationGate.containsLocalReferences(
            makeCatalog(productImageReference: "local:\(stagedFile)")))
        XCTAssertFalse(ShopCatalogPublicationGate.containsLocalReferences(
            makeCatalog(productImageReference: "thmedia:\(mediaHash)")))
    }

    func testIssuesInPublishedCatalogFlagsArtifactsThatNeverGotRewritten() {
        // 发布产物里**任何** local 引用都是问题（即使文件在 staging 里也一样，
        // 因为它本该已经被改写成 thmedia: 了）。
        let issues = ShopCatalogPublicationGate.issuesInPublishedCatalog(
            makeCatalog(productImageReference: "local:\(stagedFile)"))
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].contains("thmedia:"))

        XCTAssertTrue(
            ShopCatalogPublicationGate.issuesInPublishedCatalog(
                makeCatalog(productImageReference: "thmedia:\(mediaHash)")).isEmpty)
    }

    // MARK: 结构问题（与消费端同一口径）

    func testEmptyCatalogIsBlockedBecauseCoverageSaysComplete() {
        let review = ShopCatalogPublicationGate.review(ShopCatalog(), stagedFileNames: [])
        XCTAssertTrue(review.isBlocked, "覆盖状态 complete 的分片不得为空")
        XCTAssertEqual(review.catalogIssues.count, 1)
        XCTAssertTrue(review.summary.contains("已挡住发布"))
    }

    func testDuplicateIDsAcrossEntityTypesAreStructuralIssues() {
        var catalog = makeCatalog(productImageReference: "asset-1")
        catalog.shops[0].id = "product-1"          // 与商品撞 id
        catalog.series[0].shopID = "product-1"
        catalog.products[0].shopID = "product-1"

        let review = ShopCatalogPublicationGate.review(catalog, stagedFileNames: [])
        XCTAssertTrue(review.isBlocked)
        XCTAssertTrue(review.catalogIssues.contains { $0.contains("同时出现") },
                      "实际：\(review.catalogIssues)")
    }

    func testIdenticalBlockingIssuesAreDeduplicated() {
        // 两个同名商品引用同一个缺失文件 → owner 文案相同 → 收敛成一条。
        // 不收敛的话界面上会出现一屏一模一样的报错，运营会以为「有 20 个问题」而不敢动。
        let product: (String) -> CatalogProduct = { id in
            CatalogProduct(
                id: id, shopID: "shop-1", seriesID: "series-1",
                name: "星月夜 JSK", category: "JSK", images: ["local:missing.png"])
        }
        let catalog = ShopCatalog(
            shops: [CatalogShop(id: "shop-1", name: "樱花小羊")],
            series: [CatalogSeries(id: "series-1", shopID: "shop-1", name: "星月夜")],
            products: [product("product-1"), product("product-2")])

        let review = ShopCatalogPublicationGate.review(catalog, stagedFileNames: [])
        XCTAssertEqual(review.blockingIssues.count, 1, "实际：\(review.blockingIssues)")
    }

    func testSummaryReportsCleanWhenNothingToSay() {
        let review = ShopCatalogPublicationGate.review(
            makeCatalog(productImageReference: "thmedia:\(mediaHash)"), stagedFileNames: [])
        XCTAssertEqual(review.summary, "可以发布")
        XCTAssertNil(review.findings.first { $0.resolution.isWarning })
    }

    // MARK: 夹具

    /// 取「归属描述以 `ownerSuffix` 结尾」的那条判定。
    /// owner 形如 `商品「星月夜 JSK」/ 商品图`、`图片资源 asset-1 / 原图`。
    private func resolution(
        of review: ShopCatalogPublicationReview, ownerSuffix: String
    ) -> ShopCatalogReferenceResolution? {
        review.findings.last { $0.owner.hasSuffix(ownerSuffix) }?.resolution
    }

    private func makeCatalog(
        productImageReference: String,
        assetURL: String? = nil
    ) -> ShopCatalog {
        let reference = assetURL ?? "thmedia:\(mediaHash)"
        let asset = CatalogAsset(
            id: "asset-1", type: .productImage,
            thumbnailURL: reference, previewURL: reference, originalURL: reference,
            width: 1200, height: 1600)
        return ShopCatalog(
            shops: [CatalogShop(id: "shop-1", name: "樱花小羊")],
            series: [CatalogSeries(id: "series-1", shopID: "shop-1", name: "星月夜")],
            products: [CatalogProduct(
                id: "product-1", shopID: "shop-1", seriesID: "series-1",
                name: "星月夜 JSK", category: "JSK", images: [productImageReference])],
            assets: [asset])
    }

    private func makeFullCatalog() -> ShopCatalog {
        let reference = "local:\(stagedFile)"
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
            thumbnailURL: reference, previewURL: reference, originalURL: reference,
            width: 1200, height: 1600)
        let asset2 = CatalogAsset(
            id: "asset-2", type: .productImage,
            thumbnailURL: "local:variant.png", previewURL: "local:variant.png",
            originalURL: "local:variant.png", width: 800, height: 800)
        return ShopCatalog(
            shops: [shop], series: [series], products: [product],
            variants: [variant], sizeCharts: [sizeChart], assets: [asset, asset2])
    }
}
