//
//  ShopCatalogDraftStyleSyncTests.swift
//  ItemManagerTests
//
//  批次录入「同款不同色」一键同步契约（2026-09-23）。
//
//  用户需求原文：
//    「我录入了『天鹅之歌』系列的 3 个单品（生成色、粉紫色、蓝色一字领 OP），并试用了
//      『应用到整批 3 条单品』按钮，但发现它只能同步『店家』和『系列』，价格、尺码表、
//      面料、详情描述等关键信息均无法同步…… 期望：使我在录入并保存『生成色一字领 OP』后，
//      点击同步按钮即可自动将生成色的预约价、现货价、定金、尾款、尺码表、面料成分、
//      详情描述全部复制到粉紫色和蓝色单品上。」
//
//  锁死四组口径：
//    A. 款式组判定 = 系列 + 品类 + 款式名，且与批次页展示分组同源（未自报系列的草稿靠
//       整批归属的系列标签才能认出同款）。
//    B. 同步只搬**款式公共资料**（价格组 / 尺码表 / 面料 / 款式描述），
//       颜色私有字段（商品名 / 配色图 / 配色尺码）**永不复制**。
//    C. 价格必须**整组**搬 —— 只搬预约价而漏掉定金尾款会直接产出对账失败的草稿。
//    D. 发布时把草稿携带的面料 / 描述落到款式档案；**纯补价草稿不得清除既有档案**。
//

import XCTest
@testable import ItemManager

// MARK: - 纯逻辑：款式分组与同步产物

final class ShopCatalogDraftStyleSyncTests: XCTestCase {

    /// 一条草稿：显式款式名 + 颜色名（与录入端「商品名 = 颜色 + 款式名」一致）
    private func draft(_ color: String,
                       design: String? = "一字领OP",
                       category: String = "OP",
                       seriesID: String? = "series-swan",
                       newSeriesName: String = "",
                       batch: String? = "batch-1") -> CatalogProductDraft {
        var d = CatalogProductDraft()
        d.batchID = batch
        d.name = "\(color)\(design ?? "")"
        d.category = category
        d.designName = design
        d.seriesID = seriesID
        d.newSeriesName = newSeriesName
        return d
    }

    private func chart(_ id: String = "sizechart-draft-aaa111", image: String? = "local:chart.jpg")
        -> CatalogSizeChart {
        var c = CatalogSizeChart(id: id, productID: "prod-old")
        c.columns = ["尺码", "胸围", "衣长"]
        c.rows = [CatalogSizeRow(label: "M", values: ["84", "52"]),
                  CatalogSizeRow(label: "L", values: ["88", "54"])]
        c.sourceImage = image
        return c
    }

    private func asset(_ ref: String) -> CatalogAsset {
        CatalogAsset(id: "asset-\(ref)", type: .productImage,
                     thumbnailURL: nil, previewURL: nil, originalURL: ref,
                     width: nil, height: nil)
    }

    private func variant(_ color: String, _ size: String) -> CatalogProductVariant {
        CatalogProductVariant(id: "var-\(color)-\(size)", productID: "",
                              color: color, size: size, imageAssetID: nil)
    }

    // MARK: A. 款式组判定

    func testThreeColorsOfTheSameDesignFallIntoOneGroup() {
        let groups = ShopCatalogDraftStyleSync.groups([
            draft("生成色"), draft("粉紫色"), draft("蓝色"),
        ])
        XCTAssertEqual(groups.count, 1, "同款三色必须落在同一个款式组")
        XCTAssertEqual(groups.first?.colorCount, 3)
        XCTAssertEqual(groups.first?.designName, "一字领OP")
        XCTAssertTrue(groups.first?.isMultiColor == true)
    }

    func testDifferentDesignsAreNotMixed() {
        let groups = ShopCatalogDraftStyleSync.groups([
            draft("生成色"), draft("生成色", design: "高腰JSK"),
        ])
        XCTAssertEqual(groups.count, 2, "不同款式不得互相同步价格与尺码表")
    }

    func testSameNamedDesignInAnotherSeriesIsNotMixed() {
        let groups = ShopCatalogDraftStyleSync.groups([
            draft("生成色", seriesID: "series-swan"),
            draft("生成色", seriesID: "series-other"),
        ])
        XCTAssertEqual(groups.count, 2, "两个系列下的同名款不得串档")
    }

    func testSameNamedDesignInAnotherCategoryIsNotMixed() {
        let groups = ShopCatalogDraftStyleSync.groups([
            draft("生成色"), draft("生成色", category: "JSK"),
        ])
        XCTAssertEqual(groups.count, 2)
    }

    func testDesignNameIsDerivedWhenNotExplicitlyGiven() {
        // 与商品侧同源：剥离颜色词。「粉紫色」是复合色，长词优先，不会被拆成「粉」
        var a = draft("生成色", design: nil)
        a.designName = nil
        a.name = "生成色一字领OP"
        var b = draft("粉紫色", design: nil)
        b.designName = nil
        b.name = "粉紫色一字领OP"
        XCTAssertEqual(ShopCatalogDraftStyleSync.designName(of: a), "一字领OP")
        XCTAssertEqual(ShopCatalogDraftStyleSync.designName(of: b), "一字领OP",
                       "复合色必须整词剥离，否则粉色与生成色判成不同款")
        XCTAssertEqual(ShopCatalogDraftStyleSync.groups([a, b]).count, 1)
    }

    func testDraftsInheritingBatchSeriesStillRecogniseEachOtherAsOneDesign() {
        // 真实批次场景：整批归属定了系列，但草稿自己没自报（seriesID/newSeriesName 皆空），
        // 靠批次页选中的系列标签才能与「自报同名系列」的那条认成同款。
        // 少这一层，同款的颜色会被拆成两组，同步按钮「看得见点不到」。
        let selfReported = draft("生成色", seriesID: nil, newSeriesName: "天鹅之歌")
        let inherited = draft("粉紫色", seriesID: nil, newSeriesName: "")
        XCTAssertEqual(ShopCatalogDraftStyleSync.groups([selfReported, inherited]).count, 2,
                       "不给继承标签时确实认不出同款（口径说明用）")
        XCTAssertEqual(
            ShopCatalogDraftStyleSync.groups([selfReported, inherited],
                                             inheritedSeriesLabel: "天鹅之歌").count,
            1,
            "给了整批系列标签后必须归到同一款式组")
    }

    func testSiblingsExcludeSelfAndOtherStyles() {
        let source = draft("生成色")
        let others = [source, draft("粉紫色"), draft("蓝色"), draft("生成色", design: "高腰JSK")]
        let siblings = ShopCatalogDraftStyleSync.siblings(of: source, in: others)
        XCTAssertEqual(siblings.map(\.name), ["粉紫色一字领OP", "蓝色一字领OP"])
    }

    // MARK: B/C. 同步产物

    func testSyncPlanCopiesPriceGroupAsAWhole() throws {
        var source = draft("生成色")
        source.price = 498
        source.stockPrice = 698
        source.deposit = 100
        source.balance = 398
        source.currency = .cny
        source.startAt = Date(timeIntervalSince1970: 1_700_000_000)
        source.endAt = Date(timeIntervalSince1970: 1_700_600_000)
        source.saleKind = .reservation

        let target = draft("粉紫色")
        let plan = ShopCatalogDraftStyleSync.syncPlan(
            from: source, to: [target], fields: [.price])
        let updated = try XCTUnwrap(plan[target.id])

        XCTAssertEqual(updated.effectiveReservationPrice, 498)
        XCTAssertEqual(updated.effectiveStockPrice, 698)
        XCTAssertEqual(updated.deposit, 100)
        XCTAssertEqual(updated.balance, 398)
        XCTAssertEqual(updated.currency, .cny)
        XCTAssertEqual(updated.startAt, source.startAt)
        XCTAssertEqual(updated.endAt, source.endAt)
        XCTAssertNil(updated.depositBalanceIssue,
                     "价格整组搬完，目标不能留下定金尾款对不上的状态")
    }

    func testPriceOnlySyncDoesNotDragOtherFieldsAlong() throws {
        var source = draft("生成色")
        source.price = 498
        source.sizeChart = chart()
        source.fabric = "100% 聚酯纤维"
        source.styleDescription = "重工蕾丝一字领"

        let target = draft("粉紫色")
        let plan = ShopCatalogDraftStyleSync.syncPlan(
            from: source, to: [target], fields: [.price])
        let updated = try XCTUnwrap(plan[target.id])

        XCTAssertEqual(updated.price, 498)
        XCTAssertNil(updated.sizeChart, "没勾尺码表就不该动")
        XCTAssertNil(updated.fabric, "没勾面料就不该动")
        XCTAssertNil(updated.styleDescription, "没勾描述就不该动")
    }

    func testSizeChartIsCopiedWithFreshIdentityPerTarget() throws {
        var source = draft("生成色")
        source.sizeChart = chart()

        let a = draft("粉紫色")
        let b = draft("蓝色")
        let plan = ShopCatalogDraftStyleSync.syncPlan(
            from: source, to: [a, b], fields: [.sizeChart])
        let ua = try XCTUnwrap(plan[a.id])
        let ub = try XCTUnwrap(plan[b.id])

        XCTAssertEqual(ua.sizeChart?.columns, ["尺码", "胸围", "衣长"])
        XCTAssertEqual(ua.sizeChart?.rows.count, 2)
        XCTAssertEqual(ua.sizeChart?.sourceImage, "local:chart.jpg")
        XCTAssertNotEqual(ua.sizeChart?.id, source.sizeChart?.id,
                          "目标草稿必须持有自己的尺码表行，共用 id 会在发布时互相覆盖")
        XCTAssertNotEqual(ua.sizeChart?.id, ub.sizeChart?.id)
        XCTAssertEqual(ua.sizeChart?.id, "sizechart-draft-\(a.id.prefix(6))")
        XCTAssertEqual(ua.sizeChart?.productID, "", "草稿期不能带着别人的 productID")
    }

    func testSyncNeverTouchesColorPrivateFields() throws {
        var source = draft("生成色")
        source.price = 498
        source.sizeChart = chart()
        source.fabric = "提花布"
        source.styleDescription = "描述"
        source.images = [asset("gen.png")]

        var target = draft("粉紫色")
        target.images = [asset("pink.png")]
        target.variants = [variant("粉紫色", "M"), variant("粉紫色", "L")]
        target.rejectReason = "驳回：颜色写错了"
        target.publishedResult = CatalogDraftPublishResult(
            productID: "prod-x", saleEventIDs: [], publishedAt: Date(), operationKey: "k")
        let originalID = target.id
        let originalCreatedAt = target.createdAt

        let plan = ShopCatalogDraftStyleSync.syncPlan(
            from: source, to: [target],
            fields: ShopCatalogDraftStyleSync.defaultFields)
        let updated = try XCTUnwrap(plan[target.id])

        XCTAssertEqual(updated.name, "粉紫色一字领OP", "商品名含颜色，绝不能复制")
        XCTAssertEqual(updated.images.map(\.originalURL), ["pink.png"], "配色图是颜色私有的")
        XCTAssertEqual(updated.variants.map(\.color), ["粉紫色", "粉紫色"], "配色尺码不复制")
        XCTAssertEqual(updated.designName, "一字领OP")
        XCTAssertEqual(updated.category, "OP")
        XCTAssertEqual(updated.batchID, "batch-1")
        XCTAssertEqual(updated.id, originalID)
        XCTAssertEqual(updated.createdAt, originalCreatedAt)
        XCTAssertEqual(updated.status, .draft)
        XCTAssertEqual(updated.rejectReason, "驳回：颜色写错了", "驳回意见不能被同步抹掉")
        XCTAssertEqual(updated.publishedResult?.productID, "prod-x")
    }

    func testEmptySourceValueClearsTheTargetField() throws {
        // 「整快照覆盖」语义：源为空即清除，这样「再同步一次」能把改错的值纠正回去
        let source = draft("生成色")
        var target = draft("粉紫色")
        target.sizeChart = chart("sizechart-draft-old")
        target.fabric = "旧的错误面料"

        let plan = ShopCatalogDraftStyleSync.syncPlan(
            from: source, to: [target], fields: [.sizeChart, .fabric])
        let updated = try XCTUnwrap(plan[target.id])

        XCTAssertNil(updated.sizeChart)
        XCTAssertNil(updated.fabric)
    }

    func testSyncPlanSkipsTheSourceItself() {
        let source = draft("生成色")
        let plan = ShopCatalogDraftStyleSync.syncPlan(
            from: source, to: [source], fields: ShopCatalogDraftStyleSync.defaultFields)
        XCTAssertTrue(plan.isEmpty, "模板草稿原样不动")
    }

    func testEmptyFieldSelectionProducesNoPlan() {
        let source = draft("生成色")
        let plan = ShopCatalogDraftStyleSync.syncPlan(
            from: source, to: [draft("粉紫色")], fields: [])
        XCTAssertTrue(plan.isEmpty)
    }

    func testHasStyleContentRequiresAtLeastOneNonBlankValue() {
        var d = draft("生成色")
        XCTAssertFalse(ShopCatalogDraftStyleSync.hasStyleContent(d))
        d.fabric = "   "
        XCTAssertFalse(ShopCatalogDraftStyleSync.hasStyleContent(d), "空白串不算有内容")
        d.fabric = "提花布"
        XCTAssertTrue(ShopCatalogDraftStyleSync.hasStyleContent(d))
    }

    func testDescribeListsSelectedFieldsInFixedOrder() {
        XCTAssertEqual(ShopCatalogDraftStyleSync.describe([.styleDescription, .price]),
                       "价格、款式描述")
        XCTAssertEqual(ShopCatalogDraftStyleSync.describe([]), "（未选择任何字段）")
    }
}

// MARK: - 仓库层：syncStyleInfo 写盘与防线

@MainActor
final class ShopCatalogDraftStyleSyncStoreTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        // 存储重定向到临时目录：测试不得触碰用户真实沙盒（2026-09-21 事故防线）
        ShopCatalogStorage.useTemporaryForTesting()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        CreatorAccess.setTestOverride(.creator)
        // 跨套件累积 + 坏文件标志残留：setUp 必须重新载入（2026-09-23 补充）
        draftStore.loadDrafts()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    private var draftStore: ShopCatalogDraftStore { ShopCatalogDraftStore.shared }

    private func makeDraft(_ color: String,
                           design: String? = "一字领OP",
                           category: String = "OP",
                           price: Double = 0) -> CatalogProductDraft {
        var d = CatalogProductDraft()
        d.name = "\(color)\(design ?? "")"
        d.category = category
        d.designName = design
        d.price = price
        return d
    }

    /// 建批次 + 应用整批归属。
    /// ⚠️ `createBatch` 会用**批次会话**覆盖每条草稿的店家/系列字段，因此不能靠
    /// 在草稿上预设归属 —— 必须照真实流程走一次「应用到整批」。
    private func makeBatch(_ drafts: [CatalogProductDraft]) throws -> CatalogBatchEntrySession {
        let session = CatalogBatchEntrySession()
        try draftStore.createBatch(session, drafts: drafts)
        try draftStore.applyBatchAttribution(
            batchID: session.id,
            shopID: nil, newShopName: "同步测试店家", newShopAliases: "",
            seriesID: nil, newSeriesName: "天鹅之歌",
            newSeriesYear: 2026, newSeriesMonth: nil, newSeriesSeason: "冬")
        return session
    }

    private func fill(_ draft: CatalogProductDraft,
                      price: Double = 498, deposit: Double = 100, balance: Double = 398,
                      fabric: String? = "100% 聚酯纤维",
                      description: String? = "重工蕾丝一字领",
                      chart: Bool = true) throws -> CatalogProductDraft {
        var d = draft
        d.price = price
        d.deposit = deposit
        d.balance = balance
        d.fabric = fabric
        d.styleDescription = description
        if chart {
            var c = CatalogSizeChart(id: "sizechart-draft-\(draft.id.prefix(6))", productID: "")
            c.columns = ["尺码", "胸围", "衣长"]
            c.rows = [CatalogSizeRow(label: "M", values: ["84", "52"])]
            d.sizeChart = c
        }
        try draftStore.upsert(d)
        return try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
    }

    func testSyncWritesEverySiblingAndLeavesTheTemplateUntouched() throws {
        let session = try makeBatch([makeDraft("生成色"), makeDraft("粉紫色"), makeDraft("蓝色")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try fill(try XCTUnwrap(all.first { $0.name.contains("生成色") }))
        let targets = all.filter { $0.id != source.id }

        let count = try draftStore.syncStyleInfo(
            sourceDraftID: source.id,
            targetDraftIDs: targets.map(\.id),
            fields: ShopCatalogDraftStyleSync.defaultFields)
        XCTAssertEqual(count, 2, "同款另外两色都要被写到")

        for draft in draftStore.drafts
        where draft.batchID == session.id && draft.id != source.id {
            XCTAssertEqual(draft.effectiveReservationPrice, 498, "\(draft.name) 应拿到预约价")
            XCTAssertEqual(draft.deposit, 100)
            XCTAssertEqual(draft.balance, 398)
            XCTAssertEqual(draft.fabric, "100% 聚酯纤维")
            XCTAssertEqual(draft.styleDescription, "重工蕾丝一字领")
            XCTAssertEqual(draft.sizeChart?.columns, ["尺码", "胸围", "衣长"])
            XCTAssertEqual(draft.sizeChart?.id, "sizechart-draft-\(draft.id.prefix(6))",
                           "每条目标草稿持有自己的尺码表行")
            XCTAssertTrue(draft.name.contains("粉紫") || draft.name.contains("蓝色"),
                          "商品名（颜色）不得被模板覆盖")
        }

        let template = try XCTUnwrap(draftStore.drafts.first { $0.id == source.id })
        XCTAssertEqual(template.name, source.name)
    }

    func testSyncIsPersistedSoItSurvivesReload() throws {
        let session = try makeBatch([makeDraft("生成色"), makeDraft("粉紫色")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try fill(try XCTUnwrap(all.first { $0.name.contains("生成色") }))
        let target = try XCTUnwrap(all.first { $0.name.contains("粉紫") })

        _ = try draftStore.syncStyleInfo(sourceDraftID: source.id,
                                        targetDraftIDs: [target.id],
                                        fields: [.fabric, .styleDescription])

        draftStore.loadDrafts()   // 重新读盘
        let reloaded = try XCTUnwrap(draftStore.drafts.first { $0.id == target.id })
        XCTAssertEqual(reloaded.fabric, "100% 聚酯纤维", "同步必须落盘，不能只在内存里")
        XCTAssertEqual(reloaded.styleDescription, "重工蕾丝一字领")
    }

    func testPublishedTargetsAreSkippedInsteadOfOverwritten() throws {
        let session = try makeBatch([makeDraft("生成色"), makeDraft("粉紫色"), makeDraft("蓝色")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try fill(try XCTUnwrap(all.first { $0.name.contains("生成色") }))
        let published = try XCTUnwrap(all.first { $0.name.contains("粉紫") })
        let writable = try XCTUnwrap(all.first { $0.name.contains("蓝色") })

        // 发布只接受 reviewed 且要求价格有效，先给这条补一个合法价格
        var publishable = published
        publishable.price = 498
        publishable.deposit = 100
        publishable.balance = 398
        try draftStore.upsert(publishable)
        try draftStore.advance(publishable, to: .submitted)
        var p = try XCTUnwrap(draftStore.drafts.first { $0.id == published.id })
        try draftStore.advance(p, to: .reviewed)
        p = try XCTUnwrap(draftStore.drafts.first { $0.id == published.id })
        _ = try draftStore.publish(p, store: store)

        let count = try draftStore.syncStyleInfo(
            sourceDraftID: source.id,
            targetDraftIDs: [published.id, writable.id],
            fields: [.fabric])

        XCTAssertEqual(count, 1, "已发布的那条不回写（产物在覆盖层，改草稿不影响线上）")
        let stillPublished = try XCTUnwrap(draftStore.drafts.first { $0.id == published.id })
        XCTAssertNil(stillPublished.fabric, "已发布草稿不该被同步改写")
        let updated = try XCTUnwrap(draftStore.drafts.first { $0.id == writable.id })
        XCTAssertEqual(updated.fabric, "100% 聚酯纤维")
    }

    func testTargetsFromAnotherDesignAreRejectedByTheStore() throws {
        let session = try makeBatch([makeDraft("生成色"), makeDraft("别的款", design: "高腰JSK")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try fill(try XCTUnwrap(all.first { $0.name.contains("生成色") }))
        let other = try XCTUnwrap(all.first { $0.name.contains("别的款") })

        let count = try draftStore.syncStyleInfo(sourceDraftID: source.id,
                                                targetDraftIDs: [other.id],
                                                fields: ShopCatalogDraftStyleSync.defaultFields)
        XCTAssertEqual(count, 0, "防线在服务层：调用方传错 id 也不该串款")
        let untouched = try XCTUnwrap(draftStore.drafts.first { $0.id == other.id })
        XCTAssertNil(untouched.fabric)
    }

    func testMissingSourceDraftThrows() throws {
        XCTAssertThrowsError(
            try draftStore.syncStyleInfo(sourceDraftID: "draft-does-not-exist",
                                        targetDraftIDs: [],
                                        fields: [.price])
        ) { error in
            guard case ShopCatalogDraftStoreError.sourceDraftNotFound = error else {
                return XCTFail("应抛 sourceDraftNotFound，实际：\(error)")
            }
        }
    }

    func testEmptyFieldSelectionWritesNothing() throws {
        let session = try makeBatch([makeDraft("生成色"), makeDraft("粉紫色")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try fill(try XCTUnwrap(all.first { $0.name.contains("生成色") }))
        let target = try XCTUnwrap(all.first { $0.name.contains("粉紫") })

        let count = try draftStore.syncStyleInfo(sourceDraftID: source.id,
                                                targetDraftIDs: [target.id],
                                                fields: [])
        XCTAssertEqual(count, 0)
        let untouched = try XCTUnwrap(draftStore.drafts.first { $0.id == target.id })
        XCTAssertNil(untouched.fabric)
    }
}

// MARK: - 端到端：同步 → 发布 → 用户端读到同款公共资料

@MainActor
final class ShopCatalogDraftStyleSyncEndToEndTests: XCTestCase {

    private var store = ShopCatalogStore()

    override func setUp() {
        super.setUp()
        ShopCatalogStorage.useTemporaryForTesting()
        store = ShopCatalogStore()
        XCTAssertNotNil(store.loadFromBundleIfNeeded())
        CreatorAccess.setTestOverride(.creator)
        draftStore.loadDrafts()
    }

    override func tearDown() {
        CreatorAccess.setTestOverride(nil)
        ShopCatalogStorage.restoreDefaultForTesting()
        super.tearDown()
    }

    private var draftStore: ShopCatalogDraftStore { ShopCatalogDraftStore.shared }

    private func makeDraft(_ color: String) -> CatalogProductDraft {
        var d = CatalogProductDraft()
        d.name = "\(color)一字领OP"
        d.category = "OP"
        d.designName = "一字领OP"
        return d
    }

    /// 建批次 + 整批归属（店家 / 系列走真实流程：`createBatch` 会用会话值覆盖草稿字段）
    private func makeBatch(_ drafts: [CatalogProductDraft]) throws -> CatalogBatchEntrySession {
        let session = CatalogBatchEntrySession()
        try draftStore.createBatch(session, drafts: drafts)
        try draftStore.applyBatchAttribution(
            batchID: session.id,
            shopID: nil, newShopName: "同步测试店家", newShopAliases: "",
            seriesID: nil, newSeriesName: "天鹅之歌",
            newSeriesYear: 2026, newSeriesMonth: nil, newSeriesSeason: "冬")
        return session
    }

    /// 走到 reviewed 再发布（发布只接受 reviewed）
    private func publish(_ draftID: String) throws {
        try draftStore.advance(try XCTUnwrap(draftStore.drafts.first { $0.id == draftID }),
                              to: .submitted)
        try draftStore.advance(try XCTUnwrap(draftStore.drafts.first { $0.id == draftID }),
                              to: .reviewed)
        _ = try draftStore.publish(try XCTUnwrap(draftStore.drafts.first { $0.id == draftID }),
                                  store: store)
    }

    private func productID(_ name: String) throws -> String {
        try XCTUnwrap(store.catalog?.products.first { $0.name == name }?.id,
                      "发布后应能在目录里按名字找到「\(name)」")
    }

    /// 用户场景全流程：录生成色 → 同步到另两色 → 三条各自发布 →
    /// 三个颜色都读到同一份尺码表 / 面料（款式级），价格各自生效。
    func testSyncThenPublishMakesEveryColorShareTheStyleInfo() throws {
        let session = try makeBatch([makeDraft("生成色"), makeDraft("粉紫色"), makeDraft("蓝色")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try XCTUnwrap(all.first { $0.name.contains("生成色") })

        // ① 录生成色：价格 + 尺码表 + 面料 + 描述
        var filled = source
        filled.price = 498
        filled.deposit = 100
        filled.balance = 398
        filled.fabric = "100% 聚酯纤维"
        filled.styleDescription = "重工蕾丝一字领，后背绑带"
        var chart = CatalogSizeChart(id: "sizechart-draft-\(source.id.prefix(6))", productID: "")
        chart.columns = ["尺码", "胸围", "衣长"]
        chart.rows = [CatalogSizeRow(label: "M", values: ["84", "52"])]
        chart.sourceImage = "local:swan-chart.jpg"
        filled.sizeChart = chart
        try draftStore.upsert(filled)

        // ② 一键同步到另两色
        let targets = all.filter { $0.id != source.id }.map(\.id)
        let synced = try draftStore.syncStyleInfo(
            sourceDraftID: source.id,
            targetDraftIDs: targets,
            fields: ShopCatalogDraftStyleSync.defaultFields)
        XCTAssertEqual(synced, 2)

        // ③ 三条各自发布（每条仍是独立商品，颜色层只负责自己的图）
        for draft in all { try publish(draft.id) }

        let ids = try ["生成色一字领OP", "粉紫色一字领OP", "蓝色一字领OP"].map(productID)
        XCTAssertEqual(Set(ids).count, 3, "同款不同色仍是三个独立商品实体")

        store.reloadWithOverlay()

        // 每个颜色都读到同一份款式公共资料
        for id in ids {
            let product = try XCTUnwrap(store.catalog?.products.first { $0.id == id })
            XCTAssertEqual(store.sizeChart(forProduct: id)?.columns, ["尺码", "胸围", "衣长"],
                           "\(product.name) 应拿到款式共享的尺码表")
            XCTAssertEqual(store.fabric(forProduct: id), "100% 聚酯纤维",
                           "\(product.name) 应拿到款式面料")
            XCTAssertEqual(store.styleDescription(forProduct: id), "重工蕾丝一字领，后背绑带")
            XCTAssertEqual(store.priceArchive(forProduct: id).currentReservationPrice, Decimal(498),
                           "\(product.name) 应带预约价")
        }

        // 款式档案整款一份，不随颜色数量膨胀
        let first = try XCTUnwrap(store.catalog?.products.first { $0.id == ids[0] })
        let key = ShopCatalogStyleProfileSharing.styleKey(of: first)
        let profiles = (store.catalog?.styleProfiles ?? []).filter { $0.id == key }
        XCTAssertEqual(profiles.count, 1, "款式档案必须整款一份，而不是每个颜色各存一条")
    }

    /// 纯补价草稿发布后**不得**清掉既有款式档案
    /// （`writePlan` 的「空 = 清除」语义最容易在这里出静默事故）
    func testPriceOnlyPublishKeepsTheExistingStyleProfile() throws {
        let session = try makeBatch([makeDraft("生成色"), makeDraft("粉紫色")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let first = try XCTUnwrap(all.first { $0.name.contains("生成色") })
        let second = try XCTUnwrap(all.first { $0.name.contains("粉紫") })

        var withStyle = first
        withStyle.price = 498
        withStyle.deposit = 100
        withStyle.balance = 398
        withStyle.fabric = "100% 聚酯纤维"
        withStyle.styleDescription = "重工蕾丝一字领"
        try draftStore.upsert(withStyle)
        try publish(first.id)

        let product = try XCTUnwrap(store.catalog?.products.first { $0.name == "生成色一字领OP" })
        XCTAssertEqual(store.fabric(forProduct: product.id), "100% 聚酯纤维")

        // 第二条颜色：只补价格，完全不带面料 / 描述
        var priceOnly = second
        priceOnly.price = 498
        priceOnly.deposit = 100
        priceOnly.balance = 398
        try draftStore.upsert(priceOnly)
        try publish(second.id)

        store.reloadWithOverlay()
        XCTAssertEqual(store.fabric(forProduct: try productID("生成色一字领OP")), "100% 聚酯纤维",
                       "纯补价草稿发布后，既有面料必须还在")
        XCTAssertEqual(store.styleDescription(forProduct: try productID("生成色一字领OP")),
                       "重工蕾丝一字领")
    }
}
