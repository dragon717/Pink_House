//
//  ShopCatalogDesignPaletteTests.swift
//  ItemManagerTests
//
//  「同款颜色集合」契约（2026-09-23 系统性修复）。
//
//  用户报的 Bug：
//    后台发布了「生成色 / 粉紫色 / 蓝色」三个同款单品（段段方领 JSK），
//    前端详情页**只有标题「段段方领 JSK · 3色」和顶部「生成色」标签，没有「配色」这一行**；
//    而同款另一条「段段长Jsk · 2色」却有「配色：红色 粉色」。
//
//  根因：同一件事有两个数据源 ——
//    · 标题的「· N 色」由**同款商品集合**推导（siblings.count + 1）；
//    · 「配色」行读 `store.colors(forProduct:)`，即**本商品自己的规格色**。
//    SPU/SKU 结构下每个颜色是独立商品 → 本商品只有自己那一色；
//    纯名称命名（没建规格行）时一条都没有 → 整行消失。
//
//  下面锁死：同款商品集合的判定口径、同款颜色集合的聚合与去重、以及
//  「颜色数 = 标题的 N」这个不变量。
//

import XCTest
@testable import ItemManager

// MARK: - 纯逻辑：同款商品集合与同款颜色集合

final class ShopCatalogDesignPaletteTests: XCTestCase {

    /// 逐个生成唯一 id：同款不同色会出现同名商品，id 不能靠名字拼
    private var sequence = 0

    private func product(_ name: String,
                         design: String? = "段段方领JSK",
                         category: String = "JSK",
                         seriesID: String = "series-swan",
                         archived: Bool = false) -> CatalogProduct {
        sequence += 1
        // memberwise 初始化必须按声明顺序：id/shopID/seriesID/name/category/designName…
        // （archivedAt 在 designName 之后，只能后置赋值）
        var p = CatalogProduct(id: "prod-\(sequence)",
                               shopID: "shop-1",
                               seriesID: seriesID,
                               name: name,
                               category: category,
                               designName: design)
        if archived { p.archivedAt = Date() }
        return p
    }

    /// 三色同款（每个商品自己的规格色只有自己那一色，正是 SPU/SKU 的真实形态）
    private func threeColorFamily() -> ([CatalogProduct], [String: [String]]) {
        let palette = ["生成色", "粉紫色", "蓝色"]
        let products = palette.map { product("\($0)段段方领JSK") }
        var explicit: [String: [String]] = [:]
        for (index, item) in products.enumerated() {
            explicit[item.id] = [palette[index]]
        }
        return (products, explicit)
    }

    // MARK: A. 同款商品集合

    func testSameDesignProductsExcludesSelfAndKeepsOrder() {
        let (products, _) = threeColorFamily()
        let siblings = ShopCatalogDesignPalette.sameDesignProducts(of: products[0], among: products)
        XCTAssertEqual(siblings.map(\.name), ["粉紫色段段方领JSK", "蓝色段段方领JSK"])
    }

    func testSiblingFromAnotherSeriesCategoryOrDesignIsExcluded() {
        let anchor = product("生成色段段方领JSK")
        let others = [
            product("生成色段段方领JSK", seriesID: "series-other"),
            product("生成色段段方领JSK", category: "OP"),
            product("生成色段段方领JSK", design: "段段长Jsk"),
        ]
        XCTAssertTrue(ShopCatalogDesignPalette.sameDesignProducts(of: anchor, among: others).isEmpty,
                      "跨系列 / 跨品类 / 不同款都不算同款颜色")
    }

    func testArchivedSiblingIsExcluded() {
        let anchor = product("生成色段段方领JSK")
        let archived = product("粉紫色段段方领JSK", archived: true)
        XCTAssertTrue(ShopCatalogDesignPalette.sameDesignProducts(of: anchor, among: [archived]).isEmpty)
    }

    // MARK: B. 同款颜色集合

    func testColorsAggregateAcrossTheWholeDesignWithSelfFirst() {
        let (products, explicit) = threeColorFamily()
        for (index, product) in products.enumerated() {
            let colors = ShopCatalogDesignPalette.colors(
                of: product, among: products, explicitColors: { explicit[$0.id] ?? [] })
            XCTAssertEqual(colors.count, 3, "每个颜色商品都应看到整款的 3 个颜色")
            XCTAssertEqual(colors.first, ["生成色", "粉紫色", "蓝色"][index],
                           "本商品的颜色排第一")
            XCTAssertEqual(Set(colors), ["生成色", "粉紫色", "蓝色"])
        }
    }

    /// 用户实际数据形态：没建规格行，颜色只写在商品名里 —— 也必须能列出配色行。
    func testColorsFallBackToTheColorWordInTheName() {
        let (products, _) = threeColorFamily()
        let colors = ShopCatalogDesignPalette.colors(
            of: products[0], among: products, explicitColors: { _ in [] })
        XCTAssertEqual(colors, ["生成色", "粉紫色", "蓝色"],
                       "没有规格色时要退回商品名里的颜色词，否则配色行整行消失")
    }

    func testLegacySingleProductWithSeveralVariantsKeepsItsOwnOrderFirst() {
        // 旧形态：一个商品自带两个规格色（图 3「段段长Jsk」就是这个形态）
        let single = product("段段长Jsk", design: "段段长Jsk")
        let colors = ShopCatalogDesignPalette.colors(
            of: single, among: [single], explicitColors: { _ in ["红色", "粉色"] })
        XCTAssertEqual(colors, ["红色", "粉色"])
    }

    func testDuplicateColorAcrossProductsIsListedOnce() {
        let a = product("生成色段段方领JSK")
        let b = product("生成色段段方领JSK", design: "段段方领JSK")
        let colors = ShopCatalogDesignPalette.colors(
            of: a, among: [a, b], explicitColors: { _ in ["生成色"] })
        XCTAssertEqual(colors, ["生成色"], "同名颜色只列一次")
    }

    func testProductWithoutAnyColorClueIsSkippedWithoutBreakingTheRest() {
        let anchor = product("生成色段段方领JSK")
        let colorless = product("大蝴蝶结背心裙", design: "段段方领JSK")
        let colors = ShopCatalogDesignPalette.colors(
            of: anchor, among: [anchor, colorless], explicitColors: { _ in [] })
        XCTAssertEqual(colors, ["生成色"],
                       "没有任何颜色线索的商品不贡献颜色，但不该影响其他颜色")
    }

    // MARK: C. 不变量：配色行条数必须等于标题的 N

    func testColorCountMatchesTheTitleAnnotation() {
        let (products, explicit) = threeColorFamily()
        let siblings = ShopCatalogDesignPalette.sameDesignProducts(of: products[0], among: products)
        let title = ShopCatalogTitleResolver.title(product: products[0], siblings: siblings)
        let colors = ShopCatalogDesignPalette.colors(
            of: products[0], among: products, explicitColors: { explicit[$0.id] ?? [] })
        XCTAssertEqual(colors.count, title.colorCount,
                       "标题写「· N 色」，配色行就必须有 N 个颜色 —— 这是本次 Bug 的核心不变量")
    }
}

// MARK: - 仓库层：store.designColors 是详情页「配色」行的数据源

@MainActor
final class ShopCatalogDesignColorsStoreTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        // 存储重定向到临时目录：测试不得触碰用户真实沙盒（2026-09-21 事故防线）
        ShopCatalogStorage.useTemporaryForTesting()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    /// 「发布出来的三个同款颜色商品」：用发布链路真实产出，不手搓目录。
    private func publishThreeColors() throws -> [CatalogProduct] {
        let draftStore = ShopCatalogDraftStore.shared
        draftStore.loadDrafts()

        var draft = CatalogProductDraft()
        draft.name = ""
        draft.category = "JSK"
        let session = CatalogBatchEntrySession()
        try draftStore.createBatch(session, drafts: [draft])
        try draftStore.applyBatchAttribution(
            batchID: session.id,
            shopID: nil, newShopName: "配色测试店家", newShopAliases: "",
            seriesID: nil, newSeriesName: "天鹅之歌",
            newSeriesYear: 2026, newSeriesMonth: nil, newSeriesSeason: "冬")

        let source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })

        var style = ShopCatalogDraftStyleForm.StyleInput()
        style.designName = "段段方领JSK"
        style.category = "JSK"
        style.reservationPrice = 539
        style.deposit = 100
        style.balance = 439
        style.currency = .cny
        style.newShopName = "配色测试店家"
        style.newSeriesName = "天鹅之歌"
        style.batchID = session.id

        // 三个颜色：**不需要**在颜色行里勾尺码，模拟「只填了颜色名 + 图」
        func row(_ color: String) -> ShopCatalogDraftStyleForm.ColorRow {
            var r = ShopCatalogDraftStyleForm.ColorRow(colorName: color)
            r.imageRefs = ["local:\(color).jpg"]
            r.sizes = []
            return r
        }
        var sourceRow = ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)[0]
        sourceRow.colorName = "生成色"
        sourceRow.imageRefs = ["local:gen.jpg"]

        _ = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                          style: style,
                                          colors: [sourceRow, row("粉紫色"), row("蓝色")])

        for draft in draftStore.drafts.filter({ $0.batchID == session.id }) {
            try draftStore.advance(draft, to: .submitted)
            try draftStore.advance(try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id }),
                                  to: .reviewed)
            _ = try draftStore.publish(try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id }),
                                      store: store)
        }
        store.reloadWithOverlay()

        let names = ["生成色段段方领JSK", "粉紫色段段方领JSK", "蓝色段段方领JSK"]
        return try names.map { name in
            try XCTUnwrap(store.catalog?.products.first { $0.name == name })
        }
    }

    func testDesignColorsListsWholePaletteForEveryColorProduct() throws {
        let products = try publishThreeColors()
        for product in products {
            XCTAssertEqual(store.designColors(forProduct: product.id).count, 3,
                           "「\(product.name)」的配色行必须列出整款 3 色")
            XCTAssertEqual(Set(store.designColors(forProduct: product.id)),
                           ["生成色", "粉紫色", "蓝色"])
        }
    }

    func testDesignColorsAgreeWithTheTitleColorCount() throws {
        let products = try publishThreeColors()
        let product = products[0]
        let siblings = ShopCatalogDesignPalette.sameDesignProducts(
            of: product, among: store.catalog?.products ?? [])
        let title = ShopCatalogTitleResolver.title(product: product, siblings: siblings)
        XCTAssertEqual(title.colorCount, 3)
        XCTAssertEqual(store.designColors(forProduct: product.id).count, title.colorCount,
                       "标题的「· N 色」与配色行条数必须一致 —— 这就是本次 Bug")
    }

    func testDesignColorsFallsBackToOwnVariantsForUnknownProduct() {
        XCTAssertEqual(store.designColors(forProduct: "prod-does-not-exist"), [],
                       "脏引用不崩、退回本商品规格色（空也照实返回）")
    }
}
