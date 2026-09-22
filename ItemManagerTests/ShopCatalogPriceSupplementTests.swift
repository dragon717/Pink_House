//
//  ShopCatalogPriceSupplementTests.swift
//  ItemManagerTests
//
//  补录上新 · 给已有商品补充价格（2026-09-22）：
//    1. 商品已存在于 Catalog（含已被收进衣橱 / 心愿尾款）不再是阻断条件，
//       预约价与现货价都必须能继续录入并提交（旧实现会对预约记录直接抛错）
//    2. 追加后的价格档案必须同时保留预约（含定金 / 尾款）与现货口径，
//       且后追加的记录胜出（startAt 缺失时按数组顺序兜底）
//    3. 补录不新建商品、不覆盖原有信息
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ShopCatalogPriceSupplementTests: XCTestCase {

    private var store = ShopCatalogStore()
    private var retainedContainers: [ModelContainer] = []

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

    private func modelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Clothing.self, Brand.self, Tag.self])
        let container = try! ModelContainer(for: schema, configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }

    /// 完整发布链路：draft → submitted → reviewed → publish（§31 状态机）
    private func publishNew(_ draft: CatalogProductDraft) throws -> String {
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        return try draftStore.publish(d, store: store)
    }

    // MARK: 1. 已存在商品 → 补录价格不被重复阻断

    func testExistingProductCanSupplementReservationPrice() throws {
        // 先以现货价发布
        var stockDraft = CatalogProductDraft()
        stockDraft.name = "补录价格款A"
        stockDraft.saleKind = .stock
        stockDraft.price = 328
        stockDraft.newShopName = "补录价格店家A"
        stockDraft.newSeriesName = "补录价格系列A"
        _ = try publishNew(stockDraft)
        let product = try XCTUnwrap(store.product(named: "补录价格款A"))

        // 同名同系列再补一条预约价 —— 旧实现这里会抛「已收录」错误
        var reservationDraft = CatalogProductDraft()
        reservationDraft.name = "补录价格款A"
        reservationDraft.saleKind = .reservation
        reservationDraft.price = 288
        reservationDraft.deposit = 100
        reservationDraft.balance = 188
        reservationDraft.newShopName = "补录价格店家A"
        reservationDraft.newSeriesName = "补录价格系列A"
        let summary = try publishNew(reservationDraft)
        XCTAssertTrue(summary.contains("预约"), "摘要应说明追加了预约价记录，实际：\(summary)")

        store.reloadWithOverlay()
        XCTAssertEqual(store.catalog?.products.filter { $0.id == product.id }.count, 1, "补录价格不新建商品")
        XCTAssertEqual(store.catalog?.products.first { $0.id == product.id }?.name, "补录价格款A", "原有商品信息不变")
        XCTAssertEqual(store.saleEvents(forProduct: product.id).count, 2, "两条销售记录并存")

        // 价格档案：预约（含定金/尾款）与现货并列可读 —— 商品页所需全部字段
        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertEqual(archive.currentStockPrice, 328)
        XCTAssertEqual(archive.historicalReservationPrice, 288)
        XCTAssertEqual(archive.reservation?.deposit, 100, "定金必须保留，供商品页展示")
        XCTAssertEqual(archive.reservation?.balance, 188, "尾款必须保留，供商品页展示")
        XCTAssertEqual(archive.stockOverReservationDelta, 40)
    }

    func testExistingProductWithReservationCanSupplementStockPrice() throws {
        var reservationDraft = CatalogProductDraft()
        reservationDraft.name = "补录价格款B"
        reservationDraft.saleKind = .reservation
        reservationDraft.price = 150
        reservationDraft.deposit = 50
        reservationDraft.balance = 100
        reservationDraft.newShopName = "补录价格店家B"
        reservationDraft.newSeriesName = "补录价格系列B"
        _ = try publishNew(reservationDraft)
        let product = try XCTUnwrap(store.product(named: "补录价格款B"))

        // 预约已存在的同名商品，追加现货价也不应被阻断
        var stockDraft = CatalogProductDraft()
        stockDraft.name = "补录价格款B"
        stockDraft.saleKind = .stock
        stockDraft.price = 168
        stockDraft.newShopName = "补录价格店家B"
        stockDraft.newSeriesName = "补录价格系列B"
        let summary = try publishNew(stockDraft)
        XCTAssertTrue(summary.contains("现货"), "摘要应说明追加了现货价记录，实际：\(summary)")

        store.reloadWithOverlay()
        XCTAssertEqual(store.catalog?.products.filter { $0.id == product.id }.count, 1)
        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertEqual(archive.historicalReservationPrice, 150, "原有预约价数据不丢")
        XCTAssertEqual(archive.reservation?.deposit, 50)
        XCTAssertEqual(archive.reservation?.balance, 100)
        XCTAssertEqual(archive.currentStockPrice, 168, "新补的现货价应生效")
        XCTAssertEqual(archive.stockOverReservationDelta, 18)
    }

    func testProductAlreadyInWardrobeDoesNotBlockPriceSupplement() throws {
        var draft = CatalogProductDraft()
        draft.name = "衣橱已收款C"
        draft.saleKind = .reservation
        draft.price = 200
        draft.deposit = 80
        draft.balance = 120
        draft.newShopName = "补录价格店家C"
        draft.newSeriesName = "补录价格系列C"
        _ = try publishNew(draft)
        let product = try XCTUnwrap(store.product(named: "衣橱已收款C"))

        // 用户已把它收进衣橱（Clothing.catalogProductID 引用）
        // 注：不调用 context.save()（内存容器 save 偶发 ObjC 异常），
        // 同 context 的 fetch 含 pending changes，足以断言引用关系存在。
        let context = modelContext()
        let clothing = Clothing(name: "衣橱已收款C", types: "OP", price: 200, stock: 1)
        clothing.catalogProductID = product.id
        clothing.isDepositPlan = true
        context.insert(clothing)
        XCTAssertTrue(try ShopCatalogReferenceGuard.referencedProductIDs([product.id], modelContext: context).contains(product.id))

        // 已在衣橱中的商品继续补现货价：不得因「重复」抛错
        var stockDraft = CatalogProductDraft()
        stockDraft.name = "衣橱已收款C"
        stockDraft.saleKind = .stock
        stockDraft.price = 258
        stockDraft.newShopName = "补录价格店家C"
        stockDraft.newSeriesName = "补录价格系列C"
        XCTAssertNoThrow(try publishNew(stockDraft), "已在衣橱的商品补录价格不应被阻断")

        store.reloadWithOverlay()
        XCTAssertEqual(store.catalog?.products.filter { $0.id == product.id }.count, 1, "不产生重复商品")
        XCTAssertEqual(clothing.catalogProductID, product.id, "衣橱引用不受影响")
        let archive = store.priceArchive(forProduct: product.id)
        XCTAssertEqual(archive.historicalReservationPrice, 200)
        XCTAssertEqual(archive.currentStockPrice, 258)
    }

    // MARK: 2. 价格档案口径：后追加记录胜出

    func testPriceArchivePrefersLaterAppendedRecordWhenStartAtMissing() {
        let old = catalogEvent("ev-old", .stock, 100, startAt: nil)
        let new = catalogEvent("ev-new", .stock, 128, startAt: nil)
        let archive = CatalogPriceArchive(events: [old, new])
        XCTAssertEqual(archive.currentStockPrice, 128, "无时间标记时，后追加的补录记录应胜出")
    }

    func testPriceArchiveStillPrefersLatestDate() {
        let day1 = Date(timeIntervalSince1970: 0)
        let day2 = day1.addingTimeInterval(86_400)
        let earlier = catalogEvent("ev-e", .reservation, 200, startAt: day1)
        let later = catalogEvent("ev-l", .reservation, 260, startAt: day2)
        // 故意把晚记录放在数组前面：口径必须按时间而不是数组顺序
        let archive = CatalogPriceArchive(events: [later, earlier])
        XCTAssertEqual(archive.historicalReservationPrice, 260)
    }

    func testReservationWithoutDepositBalanceStillArchived() {
        // 只有总价、没填定金尾款（允许缺省）：价格档案仍可读，不崩溃
        let event = catalogEvent("ev-total-only", .reservation, 199, startAt: nil)
        let archive = CatalogPriceArchive(events: [event])
        XCTAssertEqual(archive.historicalReservationPrice, 199)
        XCTAssertNil(archive.reservation?.deposit, "缺失定金为 nil → 页面走「暂无」兜底")
        XCTAssertNil(archive.reservation?.balance, "缺失尾款为 nil → 页面走「暂无」兜底")
    }

    // MARK: 辅助

    private func catalogEvent(_ id: String, _ type: CatalogSaleEventType,
                             _ price: Decimal, startAt: Date?) -> CatalogSaleEvent {
        CatalogSaleEvent(id: id, productID: "p", type: type, price: price,
                         deposit: nil, balance: nil, startAt: startAt, endAt: nil)
    }
}
