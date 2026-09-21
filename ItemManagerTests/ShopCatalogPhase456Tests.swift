//
//  ShopCatalogPhase456Tests.swift
//  ItemManagerTests
//
//  Phase 3-6 验收：
//    · Phase 4  草稿构建（现货 / 预约 / 心愿口径）与套装合并、多主衣物冲突（§12/§19-24）
//    · Phase 5  预约价格口径（总价/定金/待付尾款，§17）
//    · Phase 6  淘宝解析（§28）、发布校验与去重（§29）、覆盖层合并与发布链路（§31）
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ShopCatalogPhase456Tests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        // 存储重定向到临时目录：测试不得触碰用户真实沙盒（2026-09-21 事故防线）
        ShopCatalogStorage.useTemporaryForTesting()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        // 测试环境无 iCloud 白名单：注入创作者角色（§26 服务层校验的测试路径）
        CreatorAccess.setTestOverride(.creator)
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        // 临时目录整体清理 + 还原生产路径（不再直接删除真实覆盖层）
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    // MARK: Phase 4/5 草稿构建（§16/§17）

    func testStockDraftIsOwned() throws {
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", color: "夜空蓝", size: "M", priceMode: .stock),
            store: store, modelContext: modelContext()
        ))
        XCTAssertFalse(draft.isDepositPlan)
        XCTAssertEqual(draft.priceTotal, 568)
        XCTAssertEqual(draft.deposit, 0)
        XCTAssertEqual(draft.types, "JSK")
        XCTAssertEqual(draft.brandName, "Alice Girl")
        XCTAssertEqual(draft.colors, "夜空蓝")
        XCTAssertEqual(draft.sizes, "M")
    }

    func testReservationDraftIsDepositPlan() throws {
        // 预约 ¥428 = 定金 128 + 尾款 300（§17：待付尾款自动计算）
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .reservation(depositPaid: 128)),
            store: store, modelContext: modelContext()
        ))
        XCTAssertTrue(draft.isDepositPlan)
        XCTAssertEqual(draft.priceTotal, 428)
        XCTAssertEqual(draft.deposit, 128)
        XCTAssertEqual(draft.balance, 300)
        // 尾款时间 = 预约结束日（§17 尾款时间带入）
        XCTAssertEqual(
            Calendar.current.startOfDay(for: draft.finalPaymentDate),
            Calendar.current.startOfDay(for: try XCTUnwrap(store.saleEvent(id: "ev-ag-jsk-resv-2026")?.endAt))
        )
    }

    func testWishlistDraftRecordsFullBalance() throws {
        // 加入心愿：全部记为待付尾款（§16 心愿 = 我想拥有）。
        // 价格口径 = 当前可获得价：现货价优先（568），无现货回退预约价。
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .wishlist),
            store: store, modelContext: modelContext()
        ))
        XCTAssertTrue(draft.isDepositPlan)
        XCTAssertEqual(draft.deposit, 0)
        XCTAssertEqual(draft.balance, 568)
    }

    // MARK: Phase 4 套装合并（§12/§19-24）

    func testSetDraftMergesAccessories() throws {
        // 主衣物 JSK + 小物 KC / 袖套 / 包 → 一条记录（§12 示例；§23 拆条：小物挂第一条主衣物）
        let results = try ShopCatalogWardrobeDraftBuilder.makeSplitDrafts(
            selections: [
                .init(productID: "prod-ag-xueguo-jsk", priceMode: .stock),
                .init(productID: "prod-ag-xueguo-kc", priceMode: .stock),
                .init(productID: "prod-ag-xueguo-armwarmer", priceMode: .stock),
                .init(productID: "prod-ag-xueguo-bag", priceMode: .stock),
            ],
            accessoryProductIDs: [
                "prod-ag-xueguo-kc", "prod-ag-xueguo-armwarmer", "prod-ag-xueguo-bag",
            ],
            store: store, modelContext: modelContext()
        )
        // 只有一件主衣物 → 仅一条记录
        XCTAssertEqual(results.count, 1)
        let draft = results[0].draft
        // 主类型由主衣物决定（§20）
        XCTAssertEqual(draft.types, "JSK")
        // 小物写入现有「小物」栏（§21）
        XCTAssertEqual(draft.accessories, "雪国来信 KC、雪国来信 袖套、雪国来信 单肩包")
        // 价格合计（§12 支持整套总价）：JSK 568 + KC 128 + 袖套 88 + 包 238
        XCTAssertEqual(Decimal(draft.priceTotal), 1022)
        // 小物价明细合计（KC + 袖套 + 包）
        XCTAssertEqual(Decimal(draft.accessoriesPrice), 454)
        XCTAssertTrue(draft.name.contains("＋"), "套装名称应包含小物成员")
    }

    func testSplitDraftsCreateRecordPerPrimary() throws {
        // §23：多件主衣物各自成一条记录（JSK + OP → 2 条），不再视为冲突
        let results = try ShopCatalogWardrobeDraftBuilder.makeSplitDrafts(
            selections: [
                .init(productID: "prod-ag-xueguo-jsk", priceMode: .stock),
                .init(productID: "prod-unniq-yunduo-op", priceMode: .stock),
            ],
            accessoryProductIDs: [],
            store: store, modelContext: modelContext()
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].draft.types, "JSK")
        XCTAssertEqual(results[1].draft.types, "OP")
    }

    func testSetDraftRejectsPrimaryMarkedAsAccessory() throws {
        // 计划 §23：主衣物不能被勾为小物（服务层防呆，防静默丢弃）
        XCTAssertThrowsError(try ShopCatalogWardrobeDraftBuilder.makeSplitDrafts(
            selections: [
                .init(productID: "prod-ag-xueguo-jsk", priceMode: .stock),
                .init(productID: "prod-unniq-yunduo-op", priceMode: .stock),
            ],
            accessoryProductIDs: ["prod-unniq-yunduo-op"],
            store: store, modelContext: modelContext()
        )) { error in
            guard case ShopCatalogWardrobeError.primaryMarkedAsAccessory = error else {
                return XCTFail("应抛 primaryMarkedAsAccessory，实际：\(error)")
            }
        }
    }

    // MARK: Phase 4 落库（Catalog 引用字段回写）

    func testInsertWritesCatalogRefs() throws {
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", color: "夜空蓝", size: "M", priceMode: .stock),
            store: store, modelContext: context
        ))
        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft,
            selection: .init(productID: "prod-ag-xueguo-jsk", color: "夜空蓝", size: "M", priceMode: .stock),
            store: store, modelContext: context
        )
        XCTAssertEqual(clothing.catalogProductID, "prod-ag-xueguo-jsk")
        XCTAssertEqual(clothing.catalogVariantID, "var-jsk-blue-m")
        XCTAssertNil(clothing.catalogSaleEventID)
        // 清理，不污染模拟器数据
        context.delete(clothing)
        try? context.save()
    }

    // MARK: Phase 6 淘宝解析（§28）

    func testTaobaoShareTextParsing() {
        let text = """
        8.8 雪国来信JSK 夜空蓝
        【淘宝】https://item.taobao.com/item.htm?id=123456
        价格：428 定金：128 尾款：300
        复制这条信息，打开淘宝即可查看
        """
        let parsed = ShopCatalogTaobaoParser.parse(text)
        XCTAssertEqual(parsed.url, "https://item.taobao.com/item.htm?id=123456")
        XCTAssertEqual(parsed.title, "8.8 雪国来信JSK 夜空蓝")
        XCTAssertEqual(parsed.price, 428)
        XCTAssertEqual(parsed.deposit, 128)
        XCTAssertEqual(parsed.balance, 300)

        let draft = ShopCatalogTaobaoParser.makeDraft(from: parsed)
        XCTAssertEqual(draft.saleKind, .reservation)
        XCTAssertEqual(draft.name, "8.8 雪国来信JSK 夜空蓝")
        XCTAssertEqual(draft.price, 428)
    }

    // MARK: Phase 6 校验与去重（§29）

    func testValidationFailures() {
        var draft = CatalogProductDraft()
        draft.name = ""
        XCTAssertThrowsError(try ShopCatalogDraftValidator.validate(draft, catalog: store.catalog))

        draft.name = "测试商品"
        draft.price = 0
        XCTAssertThrowsError(try ShopCatalogDraftValidator.validate(draft, catalog: store.catalog))

        draft.price = 428
        draft.deposit = 100
        draft.balance = 300
        XCTAssertThrowsError(try ShopCatalogDraftValidator.validate(draft, catalog: store.catalog))

        draft.balance = 328
        draft.newShopName = "测试店家"
        draft.newSeriesName = "测试系列"
        XCTAssertNoThrow(try ShopCatalogDraftValidator.validate(draft, catalog: store.catalog))
    }

    func testDedupFinders() {
        var draft = CatalogProductDraft()
        draft.newShopName = "UNNIQ"        // 别名命中既有店家
        draft.newSeriesName = "雪国来信"    // 与 Alice Girl 既有系列同名（但店家不同 → 不算重复）
        draft.name = "雪国来信 JSK"         // 与既有商品同名

        let shop = ShopCatalogDraftValidator.findExistingShop(for: draft, catalog: store.catalog)
        XCTAssertEqual(shop?.id, "shop-unniq", "店家应按别名去重")

        let series = ShopCatalogDraftValidator.findExistingSeries(for: draft, shopID: shop?.id ?? "", catalog: store.catalog)
        XCTAssertNil(series, "同名系列在 UNNIQ 店下不存在，不应误判")

        let seriesInAG = ShopCatalogDraftValidator.findExistingSeries(
            for: draft, shopID: "shop-alice-girl", catalog: store.catalog)
        XCTAssertEqual(seriesInAG?.id, "series-ag-xueguo-2026", "同店家同名系列应去重")

        let product = ShopCatalogDraftValidator.findExistingProduct(
            for: draft, seriesID: "series-ag-xueguo-2026", catalog: store.catalog)
        XCTAssertEqual(product?.id, "prod-ag-xueguo-jsk", "同名商品应去重并走现货追加")
    }

    // MARK: Phase 6 发布链路（§31：草稿 → 覆盖层 → 用户可见）

    func testPublishWritesOverlayAndStoreMerges() throws {
        let draftStore = ShopCatalogDraftStore.shared
        var draft = CatalogProductDraft()
        draft.name = "测试发布款"
        draft.category = "OP"
        draft.saleKind = .stock
        draft.price = 356
        draft.newShopName = "测试新店家"
        draft.newSeriesName = "测试系列"
        draft.newSeriesYear = 2026

        // §31 状态机：仅 reviewed 可发布（draft → submitted → reviewed）。
        // advance 只更新 Store 内副本，调用方需回读最新状态再推进。
        try draftStore.advance(draft, to: .submitted)
        draft = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(draft, to: .reviewed)
        draft = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })

        let summary = try draftStore.publish(draft, store: store)
        XCTAssertTrue(summary.contains("测试发布款"))

        // 覆盖层落盘
        let overlay = try XCTUnwrap(ShopCatalogDraftStore.loadOverlay())
        XCTAssertEqual(overlay.shops.first?.name, "测试新店家")

        // 用户侧合并可见
        XCTAssertEqual(store.catalog?.products.contains { $0.name == "测试发布款" }, true)
        XCTAssertEqual(store.catalog?.shops.contains { $0.name == "测试新店家" }, true)

        // 再发一次同名现货 → 追加到既有商品而不是新建
        var draft2 = draft
        draft2.name = "测试发布款"
        draft2.shopID = overlay.shops.first?.id
        draft2.seriesID = overlay.series.first?.id
        let summary2 = try draftStore.publish(draft2, store: store)
        XCTAssertTrue(summary2.contains("追加"), "同名商品现货应走追加：\(summary2)")
        XCTAssertEqual(store.catalog?.products.filter { $0.name == "测试发布款" }.count, 1)
        XCTAssertEqual(store.catalog?.saleEvents.filter { $0.productID == store.catalog?.products.first { $0.name == "测试发布款" }?.id }.count, 2)
    }

    // MARK: helpers

    /// 容器必须随用例保活：`ModelContext` 不强持有容器，
    /// 容器若先释放，`save()` 会抛 `No eligible connection available`（NSException，
    /// `try?`/`catch` 均拦不住）。与 `ClothingTests` 的容器保活约定一致。
    private var retainedContainers: [ModelContainer] = []

    /// 每次新建内存容器（与 App 数据隔离）；schema 与 ClothingTests 相同
    private func modelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Clothing.self, Brand.self, Tag.self])
        let container = try! ModelContainer(for: schema, configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }
}
