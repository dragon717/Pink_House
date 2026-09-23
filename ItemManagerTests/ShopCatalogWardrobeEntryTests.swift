//
//  ShopCatalogWardrobeEntryTests.swift
//  ItemManagerTests
//
//  需求 N 验收（2026-09-23「加购记账逻辑与衣橱卡片标题优化」）：
//    · §II  加购记账状态机：定金 → 衣橱「已付定」+ 心愿尾款任务；全款 → 衣橱「已全款」+ 无尾款任务
//    · §III 卡片标题 = `[系列名] + [款式名] + [颜色]` 及四档降级
//    · §III.3 状态标签 `全款` / `已付定` / `转单`
//    · §I   核心原则：金额全部自动读取后台档案，测试里不出现任何「用户输入金额」路径
//

import XCTest
import SwiftData
@testable import ItemManager

@MainActor
final class ShopCatalogWardrobeEntryTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        // 存储重定向到临时目录：测试不得触碰用户真实沙盒（2026-09-21 事故防线）
        ShopCatalogStorage.useTemporaryForTesting()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
    }

    override func tearDown() {
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    // MARK: - §II 场景二 分支 A：加入心愿尾款（定金 + 尾款）

    func testEndedReservationDepositBranchKeepsFinalPaymentTask() throws {
        // 后台数据：预约价 428 = 定金 128 + 尾款 300（种子 ev-ag-jsk-resv-2026）
        let archive = store.priceArchive(forProduct: "prod-ag-xueguo-jsk")
        // 金额一律「系统自动读取」：定金取自后台档案，而不是任何用户输入
        let backendDeposit = try XCTUnwrap(archive.currentDeposit)
        XCTAssertEqual(backendDeposit, 128)
        XCTAssertEqual(archive.currentReservationPrice, 428)

        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .reservation(depositPaid: backendDeposit)),
            store: store, modelContext: context
        ))
        XCTAssertTrue(draft.isDepositPlan)
        XCTAssertEqual(Decimal(draft.deposit), 128)
        XCTAssertEqual(Decimal(draft.balance), 300)
        XCTAssertEqual(Decimal(draft.priceTotal), 428)

        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, store: store, modelContext: context
        )
        // 衣橱记为「已付定」：仍在心愿尾款里等补款
        XCTAssertEqual(clothing.reservationKind, .depositPlan)
        XCTAssertTrue(clothing.isFinalPaymentPlan)
        XCTAssertFalse(clothing.isFullPaymentReservation)
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 300)
        XCTAssertEqual(clothing.wardrobeStatusTagsForTesting, [.depositPaid])

        context.delete(clothing)
        try? context.save()
    }

    // MARK: - §II 场景二 分支 B：加入衣橱（全款预约价）

    func testEndedReservationFullBranchHasNoFinalPaymentTask() throws {
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .fullReservation),
            store: store, modelContext: context
        ))
        // 金额 = 后台预约价（定金 + 尾款总和），无需用户填写
        XCTAssertEqual(Decimal(draft.priceTotal), 428)
        XCTAssertEqual(Decimal(draft.deposit), 428)
        XCTAssertEqual(Decimal(draft.balance), 0)
        XCTAssertTrue(draft.isDepositPlan)

        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, store: store, modelContext: context
        )
        // 衣橱记为「已全款」
        XCTAssertTrue(clothing.isFullPaymentReservation)
        XCTAssertFalse(clothing.isFinalPaymentPlan)
        XCTAssertEqual(clothing.reservationKind, .fullPaymentReservation)
        XCTAssertEqual(clothing.wardrobeStatusTagsForTesting, [.fullPaid])
        // 心愿尾款里**没有**该商品的待补记录（pendingFinalPaymentAmount == 0）
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 0)
        XCTAssertEqual(clothing.totalBalance, 0)

        context.delete(clothing)
        try? context.save()
    }

    /// 同款商品：定金分支会生成尾款任务，全款分支不会 —— 这是需求 §IV-1 的核心断言
    func testDepositBranchAndFullBranchDifferOnlyInFinalPaymentTask() throws {
        let context = modelContext()
        let depositDraft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .reservation(depositPaid: 128)),
            store: store, modelContext: context
        ))
        let fullDraft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .fullReservation),
            store: store, modelContext: context
        ))
        // 总价一致（都是后台预约价），差别只在「谁待付尾款」
        XCTAssertEqual(Decimal(depositDraft.priceTotal), Decimal(fullDraft.priceTotal))
        XCTAssertGreaterThan(Decimal(depositDraft.balance), 0)
        XCTAssertEqual(Decimal(fullDraft.balance), 0)
    }

    // MARK: - §II 场景一：现货全款（无尾款任务）

    func testStockBranchIsFullyPaidWithoutTask() throws {
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .stock),
            store: store, modelContext: context
        ))
        XCTAssertFalse(draft.isDepositPlan)
        XCTAssertEqual(Decimal(draft.priceTotal), 568)
        XCTAssertEqual(Decimal(draft.deposit), 0)
        XCTAssertEqual(Decimal(draft.balance), 0)

        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, store: store, modelContext: context
        )
        XCTAssertEqual(clothing.reservationKind, .owned)
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 0)
        // 普通已拥有记录不挂付款状态标签（避免给全部存量衣橱刷上「全款」）
        XCTAssertTrue(clothing.wardrobeStatusTagsForTesting.isEmpty)

        context.delete(clothing)
        try? context.save()
    }

    // MARK: - §III 衣橱记录名 = 系列名 + 款式名 + 颜色

    func testWardrobeRecordNameComposesSeriesDesignColor() throws {
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", color: "夜空蓝", priceMode: .stock),
            store: store, modelContext: context
        ))
        // 款式名「雪国来信 JSK」已含系列名「雪国来信」→ 不重复前置
        XCTAssertEqual(draft.name, "雪国来信 JSK 夜空蓝")
        XCTAssertEqual(draft.colors, "夜空蓝")
    }

    func testSameDesignDifferentColorsAreDistinguishable() throws {
        let context = modelContext()
        func name(_ color: String) throws -> String {
            try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
                selection: .init(productID: "prod-ag-xueguo-jsk", color: color, priceMode: .stock),
                store: store, modelContext: context
            )).name
        }
        let blue = try name("夜空蓝")
        let white = try name("初雪白")
        XCTAssertNotEqual(blue, white, "同名不同色必须能一眼区分")
        XCTAssertTrue(blue.hasSuffix("夜空蓝"))
        XCTAssertTrue(white.hasSuffix("初雪白"))
        XCTAssertTrue(blue.hasPrefix("雪国来信 JSK"))
    }

    /// 未点颜色时由系统从后台规格色里取默认值 —— 记录名仍然带颜色（不让用户动脑）
    func testRecordNameFillsColorFromBackendSpecColors() throws {
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .stock),
            store: store, modelContext: context
        ))
        XCTAssertEqual(store.colors(forProduct: "prod-ag-xueguo-jsk").first, "夜空蓝")
        XCTAssertEqual(draft.name, "雪国来信 JSK 夜空蓝")
    }

    /// 纯配饰（后台无规格色、商品名也没有颜色词）→ 降级为 `[系列名] + [款式名]`
    func testColorlessProductDegradesToSeriesAndDesign() throws {
        let context = modelContext()
        // prod-unniq-yunduo-op：变体色为空、商品名「云朵邮局 OP」不含颜色词
        XCTAssertTrue(store.colors(forProduct: "prod-unniq-yunduo-op").isEmpty)
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-unniq-yunduo-op", priceMode: .stock),
            store: store, modelContext: context
        ))
        XCTAssertEqual(draft.name, "云朵邮局 OP")
        XCTAssertEqual(draft.colors, "")
    }

    /// 套装合并名沿用主衣物记录名（不再从原始商品名拼装，否则会丢掉系列 / 颜色口径）
    func testSetDraftKeepsHeadRecordName() throws {
        let results = try ShopCatalogWardrobeDraftBuilder.makeSplitDrafts(
            selections: [
                .init(productID: "prod-ag-xueguo-jsk", color: "夜空蓝", priceMode: .stock),
                .init(productID: "prod-ag-xueguo-kc", priceMode: .stock),
            ],
            accessoryProductIDs: ["prod-ag-xueguo-kc"],
            store: store, modelContext: modelContext()
        )
        XCTAssertEqual(results.count, 1)
        let name = results[0].draft.name
        XCTAssertTrue(name.hasPrefix("雪国来信 JSK 夜空蓝"), "合并名应以主衣物记录名开头：\(name)")
        XCTAssertTrue(name.contains("＋"))
    }

    // MARK: - §III 纯逻辑：标题四档降级

    func testRecordNameFullComposition() {
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.recordName(
                seriesName: "天鹅之歌", designName: "段段方领JSK", color: "生成色"),
            "天鹅之歌 段段方领JSK 生成色"
        )
    }

    func testRecordNameWithoutSeries() {
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.recordName(
                seriesName: nil, designName: "段段方领JSK", color: "生成色"),
            "段段方领JSK 生成色"
        )
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.recordName(
                seriesName: "   ", designName: "段段方领JSK", color: "生成色"),
            "段段方领JSK 生成色"
        )
    }

    func testRecordNameWithoutColor() {
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.recordName(
                seriesName: "天鹅之歌", designName: "珍珠发箍", color: nil),
            "天鹅之歌 珍珠发箍"
        )
    }

    func testRecordNameWithoutSeriesAndColor() {
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.recordName(
                seriesName: nil, designName: "珍珠发箍", color: nil),
            "珍珠发箍"
        )
    }

    func testRecordNameDoesNotRepeatSeriesInsideDesign() {
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.recordName(
                seriesName: "雪国来信", designName: "雪国来信 JSK", color: "夜空蓝"),
            "雪国来信 JSK 夜空蓝"
        )
    }

    func testResolvedColorPrefersExplicitThenSpecThenNameWord() {
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.resolvedColor(explicit: "初雪白", specColors: ["夜空蓝"], productName: "雪国来信 JSK"),
            "初雪白"
        )
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.resolvedColor(explicit: nil, specColors: ["夜空蓝"], productName: "雪国来信 JSK"),
            "夜空蓝"
        )
        XCTAssertEqual(
            ShopCatalogWardrobeTitle.resolvedColor(explicit: nil, specColors: [], productName: "生成色一字领OP"),
            "生成色"
        )
        XCTAssertNil(
            ShopCatalogWardrobeTitle.resolvedColor(explicit: nil, specColors: [], productName: "珍珠发箍")
        )
    }

    // MARK: - §III.3 状态标签

    func testStatusChipsForPaymentStates() {
        XCTAssertEqual(
            ShopCatalogWardrobeStatusTag.chips(
                isSold: false, isFullPaymentReservation: true, isDepositPlan: true, isResaleTransfer: false),
            [.fullPaid]
        )
        XCTAssertEqual(
            ShopCatalogWardrobeStatusTag.chips(
                isSold: false, isFullPaymentReservation: false, isDepositPlan: true, isResaleTransfer: false),
            [.depositPaid]
        )
        XCTAssertEqual(
            ShopCatalogWardrobeStatusTag.chips(
                isSold: false, isFullPaymentReservation: false, isDepositPlan: false, isResaleTransfer: false),
            []
        )
        XCTAssertEqual(
            ShopCatalogWardrobeStatusTag.chips(
                isSold: true, isFullPaymentReservation: false, isDepositPlan: true, isResaleTransfer: false),
            [.sold]
        )
    }

    /// 转单与付款标签互相独立，可同时出现（例：闲鱼收来的转单 + 定金尾款）
    func testResaleTransferChipStandsAloneAndCombines() {
        XCTAssertEqual(
            ShopCatalogWardrobeStatusTag.chips(
                isSold: false, isFullPaymentReservation: false, isDepositPlan: false, isResaleTransfer: true),
            [.resaleTransfer]
        )
        XCTAssertEqual(
            ShopCatalogWardrobeStatusTag.chips(
                isSold: false, isFullPaymentReservation: false, isDepositPlan: true, isResaleTransfer: true),
            [.depositPaid, .resaleTransfer]
        )
        XCTAssertEqual(ShopCatalogWardrobeStatusTag.fullPaid.rawValue, "全款")
        XCTAssertEqual(ShopCatalogWardrobeStatusTag.depositPaid.rawValue, "已付定")
        XCTAssertEqual(ShopCatalogWardrobeStatusTag.resaleTransfer.rawValue, "转单")
    }

    /// 转单标记必须落库（经一键入库管线）
    func testResaleTransferPersistsThroughInsert() throws {
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .stock),
            store: store, modelContext: context
        )).with(isResaleTransfer: true)

        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, store: store, modelContext: context
        )
        XCTAssertTrue(clothing.isResaleTransfer)
        XCTAssertEqual(clothing.wardrobeStatusTagsForTesting, [.resaleTransfer])

        context.delete(clothing)
        try? context.save()
    }

    // MARK: - §II 按钮策略：按场景给出分支

    func testEntryOptionsPerPhase() {
        // 预约期内 / 预约期结束：两种口径都要给（系统自动分流）
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .reservationActive, hasReservationPrice: true, hasStockPrice: false),
            [.depositPaid, .fullPaid]
        )
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .reservationEnded, hasReservationPrice: true, hasStockPrice: false),
            [.depositPaid, .fullPaid]
        )
        // 现货在售：只有全款口径
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .inStock, hasReservationPrice: false, hasStockPrice: true),
            [.fullPaid]
        )
        // 预约未开始：还没有可记的成交价，只能先入心愿（开售提醒）
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .reservationUpcoming, hasReservationPrice: true, hasStockPrice: false),
            [.wishlist]
        )
        // 无价格档案：没有任何分支
        XCTAssertTrue(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .neutral, hasReservationPrice: false, hasStockPrice: false).isEmpty
        )
    }

    /// 只有全款口径不生成尾款任务（需求原文「绝对不生成任何心愿尾款任务」）
    func testOnlyWishlistAndDepositCreateFinalPaymentTask() {
        XCTAssertTrue(ShopCatalogWardrobeEntryOption.wishlist.createsFinalPaymentTask)
        XCTAssertTrue(ShopCatalogWardrobeEntryOption.depositPaid.createsFinalPaymentTask)
        XCTAssertFalse(ShopCatalogWardrobeEntryOption.fullPaid.createsFinalPaymentTask)
    }

    func testPhaseSpecificButtonTitles() {
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.buttonTitle(for: .depositPaid, phase: .reservationEnded),
            "加入心愿尾款"
        )
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.buttonTitle(for: .fullPaid, phase: .reservationEnded),
            "加入衣橱"
        )
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.buttonTitle(for: .depositPaid, phase: .reservationActive),
            "付定金加购"
        )
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.buttonTitle(for: .fullPaid, phase: .reservationActive),
            "全款加购"
        )
    }

    // MARK: - §II 待补尾款取数：读**后台录入的「尾款」**，不是「预约价 − 定金」现算

    /// 需求原文：「尾款金额自动读取后台录入的『尾款』数据」。
    /// 后台本来就存了独立的 `balance`（尾款）字段，所以不能再拿预约价减出来。
    func testPendingBalancePrefersBackendBalanceOverDerived() {
        XCTAssertEqual(
            ShopCatalogWardrobeAmount.pendingBalance(
                backendBalance: 300, reservationPrice: 430, depositPaid: 128),
            300,
            "后台录入尾款 300 必须优先于推导值 430 − 128 = 302"
        )
        // 后台没录尾款 → 退回推导（既有行为，不允许回归）
        XCTAssertEqual(
            ShopCatalogWardrobeAmount.pendingBalance(
                backendBalance: nil, reservationPrice: 428, depositPaid: 128),
            300
        )
        // 脏数据（负数）一律归零，不写进账
        XCTAssertEqual(
            ShopCatalogWardrobeAmount.pendingBalance(
                backendBalance: -5, reservationPrice: 100, depositPaid: 0),
            0
        )
    }

    func testBackendPriceInconsistencyDetection() {
        XCTAssertFalse(ShopCatalogWardrobeAmount.isBackendPriceInconsistent(
            deposit: 128, balance: 300, reservationPrice: 428))
        XCTAssertTrue(ShopCatalogWardrobeAmount.isBackendPriceInconsistent(
            deposit: 128, balance: 300, reservationPrice: 430))
        // 缺字段 → 不判定（旧数据可能只有预约价），避免误报
        XCTAssertFalse(ShopCatalogWardrobeAmount.isBackendPriceInconsistent(
            deposit: nil, balance: 300, reservationPrice: 430))
        XCTAssertFalse(ShopCatalogWardrobeAmount.isBackendPriceInconsistent(
            deposit: 128, balance: nil, reservationPrice: 430))
    }

    /// 端到端：后台三价不自洽（定金 128 + 尾款 300 ≠ 预约价 430）时，
    /// 衣橱待补尾款 = 录入的 300，且备注如实留痕、不写算不平的等式。
    func testInconsistentBackendPricesAreRecordedVerbatim() throws {
        let oddStore = ShopCatalogStore(catalog: ShopCatalog(
            products: [
                CatalogProduct(id: "p-odd", shopID: "s1", seriesID: "ser1",
                               name: "异常价测试 JSK", category: "JSK"),
            ],
            saleEvents: [
                CatalogSaleEvent(id: "ev-odd", productID: "p-odd", type: .reservation,
                                 price: 430, deposit: 128, balance: 300),
            ]
        ))
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "p-odd", priceMode: .reservation(depositPaid: 128)),
            store: oddStore, modelContext: context
        ))
        XCTAssertEqual(Decimal(draft.deposit), 128)
        XCTAssertEqual(Decimal(draft.balance), 300, "尾款必须取后台录入值，而不是 430 − 128")
        XCTAssertEqual(Decimal(draft.priceTotal), 430, "入橱金额仍以后台预约价为准")
        XCTAssertTrue(draft.note.contains("不自洽"), "不自洽必须留痕：\(draft.note)")
        XCTAssertTrue(draft.note.contains("以后台录入为准"), "要说明取了哪个数：\(draft.note)")

        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, store: oddStore, modelContext: context
        )
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 300)

        context.delete(clothing)
        try? context.save()
    }

    // MARK: - 图片物化（2026-09-24 根因修复回归）

    /// 加购草稿必须携带商品图：曾硬编码 `imagePaths: []`，
    /// 导致「时光馆加购 → 衣橱卡片无图可显示」（衣橱走 ImageManager 文件名体系）。
    func testMakeDraftMaterializesProductImagesIntoWardrobe() throws {
        let context = modelContext()
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-ag-xueguo-jsk", priceMode: .stock),
            store: store, modelContext: context
        ))
        // 种子商品挂 3 张 Bundle 画册图（asset-ag-jsk-1/2/3），必须全部物化成衣橱图片
        XCTAssertEqual(draft.imagePaths.count, 3, "商品图必须物化进草稿，而不是空数组")
        // 物化 = 真实写入 ImageManager 文件体系（衣橱卡片读取的就是它）
        let imagesDirectory = ImageManager.shared.imagesDirectory
        for fileName in draft.imagePaths {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: imagesDirectory.appendingPathComponent(fileName).path),
                "物化后的图片文件必须存在：\(fileName)")
        }

        // 落库后 Clothing.imagePaths 原样携带，卡片才能直接渲染
        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, store: store, modelContext: context
        )
        XCTAssertEqual(clothing.imagePaths, draft.imagePaths)

        // 清理：测试写入宿主沙盒 Images 目录的文件随手删掉，不污染真实数据
        for fileName in draft.imagePaths {
            try? FileManager.default.removeItem(
                at: imagesDirectory.appendingPathComponent(fileName))
        }
        context.delete(clothing)
        try? context.save()
    }

    // MARK: helpers

    /// 容器必须随用例保活：`ModelContext` 不强持有容器，
    /// 容器若先释放，`save()` 会抛 `No eligible connection available`（与 `ClothingTests` 一致）。
    private var retainedContainers: [ModelContainer] = []

    private func modelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Clothing.self, Brand.self, Tag.self])
        let container = try! ModelContainer(for: schema, configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }
}

// MARK: - 测试辅助

/// 衣橱状态标签口径的唯一来源是 `ShopCatalogWardrobeStatusTag.chips`；
/// `Clothing` 上没有该 computed，测试在这里用同一函数复算（避免两套口径）。
private extension Clothing {
    var wardrobeStatusTagsForTesting: [ShopCatalogWardrobeStatusTag] {
        ShopCatalogWardrobeStatusTag.chips(
            isSold: reservationKind == .sold,
            isFullPaymentReservation: isFullPaymentReservation,
            isDepositPlan: isDepositPlan,
            isResaleTransfer: isResaleTransfer
        )
    }
}
