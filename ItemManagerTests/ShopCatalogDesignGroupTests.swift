//
//  ShopCatalogDesignGroupTests.swift
//  ItemManagerTests
//
//  「同款不同色」款式归组（2026-09-22 V1.4）：
//    1. 数据结构：CatalogProduct.designName 可选字段，旧 JSON 缺键自动 nil
//    2. 归组口径：显式款式名优先，缺省按名称剥离颜色词派生；designKey = 品类|款式
//    3. 发布自动归类：新建商品按 款式(显式)/名称 派生落 designName；
//       既有商品缺款式名时补价草稿也能回填
//

import XCTest
@testable import ItemManager

@MainActor
final class ShopCatalogDesignGroupTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
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

    private func publishNew(_ draft: CatalogProductDraft) throws -> String {
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        return try draftStore.publish(d, store: store)
    }

    // MARK: 1. 数据结构兼容

    func testDecodeWithoutDesignNameIsBackwardCompatible() throws {
        let json = """
        {"id":"p-old","shopID":"shop-1","seriesID":"s-1","name":"红色大蝴蝶结背心裙","category":"JSK"}
        """
        let product = try JSONDecoder().decode(CatalogProduct.self, from: Data(json.utf8))
        XCTAssertNil(product.designName, "旧 JSON 无 designName 键应自动置 nil")
    }

    func testDecodeAndEncodeWithDesignName() throws {
        let json = """
        {"id":"p-new","shopID":"shop-1","seriesID":"s-1","name":"红色大蝴蝶结背心裙","category":"JSK","designName":"大蝴蝶结背心裙"}
        """
        let product = try JSONDecoder().decode(CatalogProduct.self, from: Data(json.utf8))
        XCTAssertEqual(product.designName, "大蝴蝶结背心裙")
        // 回写再读回保持一致
        let data = try JSONEncoder().encode(product)
        let roundtrip = try JSONDecoder().decode(CatalogProduct.self, from: data)
        XCTAssertEqual(roundtrip.designName, "大蝴蝶结背心裙")
    }

    // MARK: 2. 归组口径

    func testDesignKeyGroupsSameDesignDifferentColors() {
        let red = CatalogProduct(id: "p1", shopID: "s", seriesID: "sr",
                                 name: "红色大蝴蝶结背心裙", category: "JSK")
        let pink = CatalogProduct(id: "p2", shopID: "s", seriesID: "sr",
                                  name: "粉色大蝴蝶结背心裙", category: "JSK")
        XCTAssertEqual(ShopCatalogSameDesignGrouper.designKey(of: red),
                       ShopCatalogSameDesignGrouper.designKey(of: pink),
                       "仅颜色词不同的商品应归入同一款式")
    }

    func testExplicitDesignNameWinsOverDerived() {
        let product = CatalogProduct(id: "p", shopID: "s", seriesID: "sr",
                                     name: "红色大蝴蝶结背心裙", category: "JSK",
                                     designName: "自定义款式")
        XCTAssertEqual(ShopCatalogSameDesignGrouper.designName(of: product), "自定义款式")
    }

    func testResolveDesignNamePriority() {
        // 显式优先
        XCTAssertEqual(ShopCatalogSameDesignGrouper.resolveDesignName(explicit: "手工填写", name: "红色夜莺"),
                       "手工填写")
        // 未填 → 名称派生
        XCTAssertEqual(ShopCatalogSameDesignGrouper.resolveDesignName(explicit: nil, name: "红色夜莺"),
                       "夜莺")
        // 无颜色词 → 整名兜底
        XCTAssertEqual(ShopCatalogSameDesignGrouper.resolveDesignName(explicit: "", name: "托胸贴布绣Jsk"),
                       "托胸贴布绣Jsk")
    }

    // MARK: 3. 发布自动归类

    func testPublishAssignsDerivedDesignName() throws {
        var draft = CatalogProductDraft()
        draft.name = "红色段段长Jsk"
        draft.newShopName = "款式归组店家"
        draft.newSeriesName = "款式归组系列"
        draft.price = 458
        _ = try publishNew(draft)

        let product = try XCTUnwrap(store.product(named: "红色段段长Jsk"))
        XCTAssertEqual(product.designName, "段段长Jsk",
                       "发布时未填款式应按名称剥离颜色词自动派生")
    }

    func testPublishExplicitDesignNameWins() throws {
        var draft = CatalogProductDraft()
        draft.name = "红色段段长Jsk"
        draft.designName = "段段长系列"
        draft.newShopName = "显式款式店家"
        draft.newSeriesName = "显式款式系列"
        draft.price = 458
        _ = try publishNew(draft)

        let product = try XCTUnwrap(store.product(named: "红色段段长Jsk"))
        XCTAssertEqual(product.designName, "段段长系列", "显式填写的款式名优先落库")
    }

    func testPublishBackfillsExistingProductDesignName() throws {
        // 先发布一个无款式字段的商品（模拟旧数据：名称含颜色词、designName 由派生写入）
        var first = CatalogProductDraft()
        first.name = "粉色大蝴蝶结背心裙"
        first.newShopName = "回填店家"
        first.newSeriesName = "回填系列"
        first.price = 318
        _ = try publishNew(first)
        let original = try XCTUnwrap(store.product(named: "粉色大蝴蝶结背心裙"))
        XCTAssertNotNil(original.designName)

        // 直接构造一个 designName = nil 的既有商品（覆盖层写回，模拟旧数据）
        var legacy = original
        legacy.designName = nil
        try ShopCatalogDraftStore.upsertEntity(legacy, keyPath: \.products)
        // upsertEntity 只刷新 ShopCatalogStore.shared；同步本地 store 视图
        store.reloadWithOverlay()

        // 补价草稿（无规格/图片）：显式款式名应回填到既有商品
        var supplement = CatalogProductDraft()
        supplement.name = "粉色大蝴蝶结背心裙"
        supplement.designName = "大蝴蝶结背心裙"
        supplement.shopID = legacy.shopID
        supplement.seriesID = legacy.seriesID
        supplement.price = 318
        _ = try publishNew(supplement)

        let updated = try XCTUnwrap(store.product(named: "粉色大蝴蝶结背心裙"))
        XCTAssertEqual(updated.designName, "大蝴蝶结背心裙",
                       "纯补价草稿也应回填既有商品缺失的款式名")
    }

    func testPublishedSameDesignColorsShareDesignKey() throws {
        // 两个颜色分别发布（同款不同色）→ 落库后 designKey 一致，列表归组展示的前提
        var red = CatalogProductDraft()
        red.name = "红色托胸贴布绣Jsk"
        red.newShopName = "归组店家2"
        red.newSeriesName = "归组系列2"
        red.price = 478
        _ = try publishNew(red)

        var pink = CatalogProductDraft()
        pink.name = "粉色托胸贴布绣Jsk"
        pink.shopID = store.product(named: "红色托胸贴布绣Jsk")?.shopID
        pink.seriesID = store.product(named: "红色托胸贴布绣Jsk")?.seriesID
        pink.price = 478
        _ = try publishNew(pink)

        let redProduct = try XCTUnwrap(store.product(named: "红色托胸贴布绣Jsk"))
        let pinkProduct = try XCTUnwrap(store.product(named: "粉色托胸贴布绣Jsk"))
        XCTAssertEqual(ShopCatalogSameDesignGrouper.designKey(of: redProduct),
                       ShopCatalogSameDesignGrouper.designKey(of: pinkProduct),
                       "同款不同色分别发布后应自动归入同一款式")
    }
}
