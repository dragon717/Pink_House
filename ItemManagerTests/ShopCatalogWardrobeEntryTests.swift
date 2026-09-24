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
        // 种子已连根清理（2026-09-24）：原种子夹具改由测试注入
        store = ShopCatalogSeedFixture.makeStore()
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
        // 现货阶段（2026-09-24 需求）：**只有全款**，但两个价格口径都要给
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .inStock, hasReservationPrice: true, hasStockPrice: true),
            [.fullPaid, .fullStockPaid],
            "现货阶段 = ① 按预约价全款加入 ② 按现货价全款加入，且不再出现定金+尾款"
        )
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .inStock, hasReservationPrice: false, hasStockPrice: true),
            [.fullStockPaid],
            "只有现货价档案时只给「按现货价全款」，不给点下去取不到数的选项"
        )
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .inStock, hasReservationPrice: true, hasStockPrice: false),
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
        XCTAssertTrue(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .inStock, hasReservationPrice: false, hasStockPrice: false).isEmpty
        )
    }

    /// 阶段 → 分支的完整矩阵（用户需求的四句话逐一钉住，防回归时被"顺手改回"）
    func testPhaseBranchMatrixMatchesRequirement() {
        // 1. 预约期间：定金+尾款加入 / 全款加入
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .reservationActive, hasReservationPrice: true, hasStockPrice: true),
            .depositPaid)
        // 2. 预约结束后仍想加入衣橱：同样两个选项（默认换成全款引导）
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .reservationEnded, hasReservationPrice: true, hasStockPrice: true),
            .fullPaid)
        // 3. 现货阶段：仅全款，两个价格口径（默认现货价）
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .inStock, hasReservationPrice: true, hasStockPrice: true),
            .fullStockPaid)
        // 三个「要弹选择弹窗」的阶段都不得塌缩成「静默默认直接加入」
        for phase in [ShopCatalogPurchasePhase.reservationActive, .reservationEnded, .inStock] {
            XCTAssertNotNil(
                ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                    phase: phase, hasReservationPrice: true, hasStockPrice: true),
                "\(phase) 必须弹选择弹窗，不能静默默认一种加入方式")
        }
    }

    /// 只有全款口径不生成尾款任务（需求原文「绝对不生成任何心愿尾款任务」）
    func testOnlyWishlistAndDepositCreateFinalPaymentTask() {
        XCTAssertTrue(ShopCatalogWardrobeEntryOption.wishlist.createsFinalPaymentTask)
        XCTAssertTrue(ShopCatalogWardrobeEntryOption.depositPaid.createsFinalPaymentTask)
        XCTAssertFalse(ShopCatalogWardrobeEntryOption.fullPaid.createsFinalPaymentTask)
        XCTAssertFalse(ShopCatalogWardrobeEntryOption.fullStockPaid.createsFinalPaymentTask)
        // 两个全款价格口径同属「全款一次记清」
        XCTAssertTrue(ShopCatalogWardrobeEntryOption.fullPaid.isFullPayment)
        XCTAssertTrue(ShopCatalogWardrobeEntryOption.fullStockPaid.isFullPayment)
        XCTAssertFalse(ShopCatalogWardrobeEntryOption.depositPaid.isFullPayment)
        XCTAssertFalse(ShopCatalogWardrobeEntryOption.wishlist.isFullPayment)
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

    // MARK: - 阶段化「加入衣橱」选择弹窗（2026-09-24 需求）

    /// 弹窗选项与默认选中规则：
    ///   · 预约中     → 两选项同屏，默认「加入心愿尾款（定金+尾款）」
    ///   · 预约已结束 → 两选项同屏，默认「预约价全款预约」
    ///   · 现货       → 两选项同屏（两个全款价格口径），默认「按现货价全款加入」
    ///   · 预约未开始 → 不弹选择（nil），走加入心愿（开售提醒）
    func testChoiceDefaultOptionPerPhase() {
        // 预约中：默认「加入心愿尾款（定金+尾款）」
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .reservationActive, hasReservationPrice: true, hasStockPrice: false),
            .depositPaid
        )
        // 预约已结束：默认「预约价全款预约」
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .reservationEnded, hasReservationPrice: true, hasStockPrice: false),
            .fullPaid
        )
        // 无预约价档案：两选项无从取数，回退原路径（不弹选择）
        XCTAssertNil(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .reservationActive, hasReservationPrice: false, hasStockPrice: false))
        XCTAssertNil(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .reservationEnded, hasReservationPrice: false, hasStockPrice: false))
        // 现货：弹选择，默认按现货价全款；没有现货价才退回按预约价全款
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .inStock, hasReservationPrice: true, hasStockPrice: true),
            .fullStockPaid
        )
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .inStock, hasReservationPrice: true, hasStockPrice: false),
            .fullPaid
        )
        XCTAssertNil(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .inStock, hasReservationPrice: false, hasStockPrice: false))
        // 预约未开始：不弹选择（加入心愿 = 开售提醒）
        XCTAssertNil(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .reservationUpcoming, hasReservationPrice: true, hasStockPrice: true))
    }

    // MARK: - 自定义分类词表（2026-09-24 需求：分类增删改）

    /// 候选口径：固定品类（除「其他」）→ 自定义（添加序）→ 「其他」兜底；去重
    func testCategoryCandidatesMergeAndDedupe() {
        let saved = ShopCatalogStore.customCategories
        defer { ShopCatalogStore.customCategories = saved }

        ShopCatalogStore.customCategories = ["斗篷", "JSK", "  ", "斗篷", "兔耳"]
        XCTAssertEqual(
            ShopCatalogStore.categoryCandidates,
            ["JSK", "OP", "SK", "Blouse", "KC", "小物", "鞋", "包", "斗篷", "兔耳", "其他"],
            "自定义追加在固定品类之后、其他之前；空串剔除；与固定品类重复的跳过"
        )
    }

    /// 写入时自动 trim + 丢空串（脏输入不进词表）
    func testCustomCategoriesSetterCleansInput() {
        let saved = ShopCatalogStore.customCategories
        defer { ShopCatalogStore.customCategories = saved }

        ShopCatalogStore.customCategories = ["  斗篷 ", "", "兔耳"]
        XCTAssertEqual(ShopCatalogStore.customCategories, ["斗篷", "兔耳"])
    }

    /// 选择弹窗选项标题按阶段取：预约语境用旧文案，现货阶段改用「按…全款加入」
    func testChoiceTitles() {
        for phase in [ShopCatalogPurchasePhase.reservationActive, .reservationEnded, .balancePending] {
            XCTAssertEqual(
                ShopCatalogWardrobeEntryPolicy.choiceTitle(for: .depositPaid, phase: phase),
                "加入心愿尾款（定金+尾款）")
            XCTAssertEqual(
                ShopCatalogWardrobeEntryPolicy.choiceTitle(for: .fullPaid, phase: phase),
                "预约价全款预约")
        }
        // 现货阶段：两个选项是**价格口径**，不能再写「预约」这个词
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.choiceTitle(for: .fullPaid, phase: .inStock),
            "按预约价全款加入")
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.choiceTitle(for: .fullStockPaid, phase: .inStock),
            "按现货价全款加入")
        // 说明文字必须点明「衣橱记为已全款 + 不生成尾款任务」
        for option in [ShopCatalogWardrobeEntryOption.fullPaid, .fullStockPaid] {
            let caption = ShopCatalogWardrobeEntryPolicy.choiceCaption(for: option)
            XCTAssertTrue(caption.contains("已全款"), "\(option) 说明缺「已全款」：\(caption)")
            XCTAssertTrue(caption.contains("不生成尾款任务"), "\(option) 说明缺「不生成尾款任务」：\(caption)")
        }
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

    // MARK: - 现货阶段：仅全款，两个价格口径（2026-09-24 需求 §3）

    /// 现货阶段两个全款口径的**唯一差别 = 入橱金额取自哪份档案**（预约价 vs 现货价），
    /// 两条都必须「已全款 + 不生成尾款任务」——所以不能只给一个全款按钮。
    func testStockPhaseTwoFullPaymentBasesDifferOnlyInAmount() throws {
        let spotStore = makeSpotPhaseStore()
        let context = modelContext()

        func draft(_ mode: ShopCatalogWardrobeDraftBuilder.PriceMode) throws -> ClothingEditDraft {
            try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
                selection: .init(productID: "prod-spot", priceMode: mode),
                store: spotStore, modelContext: context))
        }

        let byReservation = try draft(.fullReservation)
        let byStock = try draft(.fullStock)
        XCTAssertEqual(Decimal(byReservation.priceTotal), 318, "① 按预约价全款加入")
        XCTAssertEqual(Decimal(byStock.priceTotal), 428, "② 按现货价全款加入")
        XCTAssertNotEqual(Decimal(byReservation.priceTotal), Decimal(byStock.priceTotal))
        for entry in [byReservation, byStock] {
            XCTAssertTrue(entry.isDepositPlan, "全款口径复用同一套「已付清」存储口径")
            XCTAssertEqual(Decimal(entry.balance), 0, "全款口径都不留尾款")
        }
        XCTAssertTrue(byReservation.note.contains("按预约价"), byReservation.note)
        XCTAssertTrue(byStock.note.contains("按现货价"), byStock.note)

        // 该商品此刻的购买阶段：预约窗口全关、有现货价 → 现货阶段（详情页据此弹选择弹窗）
        XCTAssertEqual(
            ShopCatalogPurchasePhase.resolve(
                reservationStatuses: [], stockWindowOpen: false,
                hasStockPrice: true, hasReservationPrice: true),
            .inStock
        )
        // 现货阶段的候选 = 两个全款价格口径，且默认选中现货价那个
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.options(
                phase: .inStock, hasReservationPrice: true, hasStockPrice: true),
            [.fullPaid, .fullStockPaid]
        )
        XCTAssertEqual(
            ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
                phase: .inStock, hasReservationPrice: true, hasStockPrice: true),
            .fullStockPaid
        )
    }

    /// 按现货价全款落库：衣橱「已全款」、无尾款任务、依据的销售记录是**现货**那条
    func testStockPriceFullPaymentLandsAsFullPaidWithoutTask() throws {
        let context = modelContext()
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(
            productID: "prod-ag-xueguo-jsk", priceMode: .fullStock)
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: selection, store: store, modelContext: context))
        // 金额 = 后台现货价 568（种子 ev-ag-jsk-stock-2026），用户零输入
        XCTAssertEqual(Decimal(draft.priceTotal), 568)
        XCTAssertEqual(Decimal(draft.deposit), 568)
        XCTAssertEqual(Decimal(draft.balance), 0)
        XCTAssertTrue(draft.note.contains("按现货价"), "备注必须写明价格口径：\(draft.note)")

        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, selection: selection, store: store, modelContext: context)
        XCTAssertTrue(clothing.isFullPaymentReservation)
        XCTAssertFalse(clothing.isFinalPaymentPlan)
        XCTAssertEqual(clothing.reservationKind, .fullPaymentReservation)
        XCTAssertEqual(clothing.wardrobeStatusTagsForTesting, [.fullPaid])
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 0)
        XCTAssertEqual(clothing.totalBalance, 0)
        XCTAssertEqual(clothing.catalogSaleEventID, "ev-ag-jsk-stock-2026",
                       "现货价全款要挂到现货销售记录上，而不是预约记录")

        context.delete(clothing)
        try? context.save()
    }

    /// 现货价档案缺失时不得硬编一个数：拿不到价就返回 nil，由视图回退（不静默记 0 元）
    func testFullStockModeWithoutStockPriceReturnsNil() {
        let noStockStore = ShopCatalogStore(catalog: ShopCatalog(
            products: [
                CatalogProduct(id: "prod-no-stock", shopID: "s1", seriesID: "ser1",
                               name: "只有预约价 JSK", category: "JSK"),
            ],
            saleEvents: [
                CatalogSaleEvent(id: "ev-no-stock-resv", productID: "prod-no-stock",
                                 type: .reservation, price: 318, deposit: 91, balance: 227),
            ]
        ))
        XCTAssertNil(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: "prod-no-stock", priceMode: .fullStock),
            store: noStockStore, modelContext: modelContext()))
    }

    // MARK: - 需求：定金+尾款入心愿尾款列表 → 付完尾款自动进衣橱

    /// 定金 + 尾款加入 → 进心愿尾款列表；付完尾款 → 系统自动收尾并成为衣橱里的已拥有。
    /// 两步走的是同一套既有口径：列表筛选 = `isFinalPaymentPlan`，
    /// 收尾 = `WealthSavingLedger` 把它切成「非定金计划」→ `reservationKind == .owned`。
    func testDepositPlanEntersWishlistAndPayoffMovesToWardrobe() throws {
        let context = wealthModelContext()
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(
            productID: "prod-ag-xueguo-jsk", priceMode: .reservation(depositPaid: 128))
        let draft = try XCTUnwrap(ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: selection, store: store, modelContext: context))
        let clothing = try ShopCatalogWardrobeInserter.insert(
            draft: draft, selection: selection, store: store, modelContext: context)

        // 第一步：定金 + 尾款加入 → 心愿尾款列表（isFinalPaymentPlan = 该列表的筛选口径）
        XCTAssertTrue(clothing.isFinalPaymentPlan)
        XCTAssertEqual(clothing.reservationKind, .depositPlan)
        XCTAssertEqual(clothing.pendingFinalPaymentAmount, 300)
        XCTAssertTrue(WealthSavingLedger.shouldShowFinalPaymentPayoffAction(for: clothing),
                      "心愿尾款列表里必须能对它发起「付尾款」")

        // 第二步：付完尾款 → 自动离开心愿尾款、进入衣橱（已拥有）
        let result = try XCTUnwrap(WealthSavingLedger.recordFinalPayment(
            amount: clothing.pendingFinalPaymentAmount,
            for: clothing,
            context: context))
        XCTAssertTrue(result.paidOff)
        XCTAssertFalse(clothing.isFinalPaymentPlan, "付清后必须离开心愿尾款列表")
        XCTAssertFalse(clothing.isDepositPlan)
        XCTAssertEqual(clothing.reservationKind, .owned, "付清后自动成为衣橱里的已拥有")
        XCTAssertFalse(WealthSavingLedger.shouldShowFinalPaymentPayoffAction(for: clothing),
                       "付清后不再显示「付尾款」入口")
        // 口径说明：收尾只关掉「定金计划」这个事实，记录里的 `balance` 是**历史值**
        // （当初要补多少）不会被清零 → 判「付没付清」一律用 `isFinalPaymentPlan` /
        // `shouldShowFinalPaymentPayoffAction`，**不要**用 `pendingFinalPaymentAmount`
        // （它对已收尾的记录仍返回历史尾款，各页面也确实是先按 `isFinalPaymentPlan` 收窄再取数）。
        XCTAssertEqual(clothing.wardrobeValueAmount, 428, "成为衣橱资产后按完整裙装价计价")
        // 关联仍在：这条衣橱记录知道自己来自哪个商品、依据哪份销售记录
        XCTAssertEqual(clothing.catalogProductID, "prod-ag-xueguo-jsk")
        XCTAssertEqual(clothing.catalogSaleEventID, "ev-ag-jsk-resv-2026")
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

    /// 付尾款链路要用到 `WealthSavingEntry`（付清记录）与小物关系 → 用更完整的 schema 单独起容器，
    /// 不动上面那个（既有用例的 schema 保持不变，免得引入无关差异）。
    private func wealthModelContext() -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([Clothing.self, WealthSavingEntry.self, Brand.self, Tag.self, AccessoryItem.self])
        let container = try! ModelContainer(for: schema, configurations: config)
        retainedContainers.append(container)
        return ModelContext(container)
    }

    /// 现货阶段夹具：预约价 318（定金 91 + 尾款 227）与现货价 428 并存 ——
    /// 正好用来验证「两个全款口径金额不同、其余全同」。
    private func makeSpotPhaseStore() -> ShopCatalogStore {
        ShopCatalogStore(catalog: ShopCatalog(
            products: [
                CatalogProduct(id: "prod-spot", shopID: "shop-spot",
                               seriesID: "series-spot", name: "现货测试 JSK", category: "JSK"),
            ],
            saleEvents: [
                CatalogSaleEvent(id: "ev-spot-resv", productID: "prod-spot", type: .reservation,
                                 price: 318, deposit: 91, balance: 227),
                CatalogSaleEvent(id: "ev-spot-stock", productID: "prod-spot", type: .stock,
                                 price: 428),
            ]
        ))
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
