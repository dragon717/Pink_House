//
//  ShopCatalogStyleProfileSharingTests.swift
//  ItemManagerTests
//
//  款式（SPU）公共属性口径契约（2026-09-23 录入端重构）。
//
//  用户需求原文：
//    「尺码表、面料、款式描述，这些是款式（SPU）的公共属性，必须在录商品的第一步
//      就填好，只填一次。颜色图片、颜色库存，这些是颜色（SKU）的差异属性……
//      请按这个逻辑重构一下录入端的表单。」
//
//  锁死三组口径：
//    A. 款式键 = 系列 + 品类 + 款式名；跨系列的**同名款不得串档**（少比一个系列就会串）。
//    B. 读：款式档案整款共享；款式描述对旧数据回退商品自身 `description`。
//    C. 写：整款**一份**（id = 款式键），不做按颜色扇出；空值 = 清除而不是跳过。
//
//    D. **尺码表读取的优先级回归**（用户截图里的真实现象）：
//       粉色那条记录只带了原图、没有结构化行列，旧口径「取最后一条有内容的」会把它
//       当成胜出者 —— 于是**两个颜色都只剩「查看尺码表原图」**，看起来像粉色把
//       红色的表弄丢了。结构化内容必须优先，原图再单独兜底合并。
//

import XCTest
@testable import ItemManager

// MARK: - 纯逻辑：款式档案

final class ShopCatalogStyleProfileSharingTests: XCTestCase {

    private func product(_ id: String,
                         name: String,
                         category: String = "JSK",
                         series: String = "s1",
                         designName: String? = nil,
                         description: String? = nil) -> CatalogProduct {
        CatalogProduct(id: id, shopID: "shop1", seriesID: series, name: name,
                       category: category, images: [], description: description,
                       designName: designName)
    }

    private var red: CatalogProduct { product("p-red", name: "红色大蝴蝶结背心裙") }
    private var pink: CatalogProduct { product("p-pink", name: "粉色大蝴蝶结背心裙") }

    private func profile(_ id: String,
                         series: String = "s1",
                         category: String = "JSK",
                         design: String = "大蝴蝶结背心裙",
                         fabric: String? = nil,
                         description: String? = nil) -> CatalogStyleProfile {
        var p = CatalogStyleProfile(id: id, seriesID: series, category: category, designName: design)
        p.fabric = fabric
        p.styleDescription = description
        return p
    }

    // MARK: A. 款式键

    func testStyleKeyIsStableForEveryColorOfTheSameDesign() {
        XCTAssertEqual(ShopCatalogStyleProfileSharing.styleKey(of: red),
                       ShopCatalogStyleProfileSharing.styleKey(of: pink),
                       "同款不同色必须落到同一个款式键 —— 否则公共资料各存一份")
    }

    func testStyleKeyIncludesSeriesSoSameNamedDesignsDoNotCrossContaminate() {
        let otherSeries = product("p-other", name: "红色大蝴蝶结背心裙", series: "s2")
        XCTAssertNotEqual(ShopCatalogStyleProfileSharing.styleKey(of: red),
                          ShopCatalogStyleProfileSharing.styleKey(of: otherSeries),
                          "两个系列下的同名款不得共用面料 / 描述")
    }

    func testStyleKeyFollowsCategoryAndDesignName() {
        let otherCategory = product("p-op", name: "红色大蝴蝶结背心裙", category: "OP")
        XCTAssertNotEqual(ShopCatalogStyleProfileSharing.styleKey(of: red),
                          ShopCatalogStyleProfileSharing.styleKey(of: otherCategory))
    }

    func testExplicitDesignNameWinsForTheKey() {
        let explicit = product("p-e", name: "红色大蝴蝶结背心裙（复刻）",
                               designName: "大蝴蝶结背心裙")
        XCTAssertEqual(ShopCatalogStyleProfileSharing.styleKey(of: explicit),
                       ShopCatalogStyleProfileSharing.styleKey(of: red),
                       "显式款式名优先：复刻款与原型可选归入同款")
    }

    // MARK: 范围

    func testDesignScopeCoversEveryColorOfTheSameDesign() {
        let unrelated = product("p-hat", name: "蝴蝶结头饰", category: "小物")
        let scope = ShopCatalogStyleProfileSharing.designScope(of: red, among: [red, pink, unrelated])
        XCTAssertEqual(Set(scope.map(\.id)), ["p-red", "p-pink"])
    }

    // MARK: B. 读

    func testProfileIsSharedByEveryColor() {
        let profiles = [profile("s1|JSK|大蝴蝶结背心裙", fabric: "提花布")]
        XCTAssertEqual(ShopCatalogStyleProfileSharing.fabric(for: red, among: [red, pink],
                                                            profiles: profiles),
                       "提花布")
        XCTAssertEqual(ShopCatalogStyleProfileSharing.fabric(for: pink, among: [red, pink],
                                                            profiles: profiles),
                       "提花布",
                       "粉色没单独录过也必须读到款式面料")
    }

    func testStyleDescriptionFallsBackToProductDescriptionForLegacyData() {
        let legacy = product("p-legacy", name: "红色大蝴蝶结背心裙",
                             description: "旧数据：描述写在商品上")
        XCTAssertEqual(ShopCatalogStyleProfileSharing.styleDescription(for: legacy,
                                                                      among: [legacy],
                                                                      profiles: []),
                       "旧数据：描述写在商品上",
                       "档案缺失时回退商品自身 description —— 搬家不该让老数据消失")
    }

    func testProfileDescriptionTakesPrecedenceOverProductDescription() {
        let withBoth = product("p-both", name: "红色大蝴蝶结背心裙", description: "商品上的旧描述")
        let profiles = [profile("s1|JSK|大蝴蝶结背心裙", description: "款式档案里的新描述")]
        XCTAssertEqual(ShopCatalogStyleProfileSharing.styleDescription(for: withBoth, among: [withBoth],
                                                                      profiles: profiles),
                       "款式档案里的新描述")
    }

    func testFabricHasNoFallbackAndBlankIsTreatedAsMissing() {
        let p = product("p-blank", name: "红色大蝴蝶结背心裙")
        XCTAssertNil(ShopCatalogStyleProfileSharing.fabric(for: p, among: [p], profiles: []))
        let blank = [profile("s1|JSK|大蝴蝶结背心裙", fabric: "   ")]
        XCTAssertNil(ShopCatalogStyleProfileSharing.fabric(for: p, among: [p], profiles: blank),
                     "全空白等同于没录")
    }

    // MARK: C. 写

    func testWritePlanProducesExactlyOneProfileForTheWholeDesign() {
        let plan = ShopCatalogStyleProfileSharing.writePlan(
            fabric: "提花布", styleDescription: "含可拆蝴蝶结",
            for: pink, among: [red, pink], profiles: [])
        XCTAssertEqual(plan.upserts.count, 1, "款式档案整款一份 —— 不得按颜色扇出")
        XCTAssertEqual(plan.upserts.first?.id, ShopCatalogStyleProfileSharing.styleKey(of: red))
        XCTAssertEqual(plan.upserts.first?.fabric, "提花布")
        XCTAssertTrue(plan.removals.contains(ShopCatalogStyleProfileSharing.styleKey(of: pink)),
                      "旧档（同键）要一起清掉，避免键漂移留下孤儿")
    }

    func testWritePlanWithEmptyValuesClearsTheProfile() {
        let plan = ShopCatalogStyleProfileSharing.writePlan(
            fabric: nil, styleDescription: "", for: red, among: [red, pink], profiles: [])
        XCTAssertTrue(plan.upserts.isEmpty, "面料与描述都空 = 清除，不留空壳行")
        XCTAssertFalse(plan.removals.isEmpty)
    }

    func testWritePlanTrimsWhitespace() {
        let plan = ShopCatalogStyleProfileSharing.writePlan(
            fabric: "  提花布  ", styleDescription: "  ", for: red, among: [red], profiles: [])
        XCTAssertEqual(plan.upserts.first?.fabric, "提花布")
        XCTAssertNil(plan.upserts.first?.styleDescription)
    }
}

// MARK: - 纯逻辑：尺码表读取优先级（结构化优先 + 原图兜底）

final class ShopCatalogSizeChartPriorityTests: XCTestCase {

    private func product(_ id: String, name: String, series: String = "s1") -> CatalogProduct {
        CatalogProduct(id: id, shopID: "shop1", seriesID: series, name: name, category: "JSK")
    }

    private var red: CatalogProduct { product("p-red", name: "红色大蝴蝶结背心裙") }
    private var pink: CatalogProduct { product("p-pink", name: "粉色大蝴蝶结背心裙") }

    private func structured(_ productID: String, sourceImage: String? = nil) -> CatalogSizeChart {
        var chart = CatalogSizeChart(id: "sizechart-\(productID)", productID: productID)
        chart.columns = ["尺码", "前裙长", "推荐胸围"]
        chart.rows = [CatalogSizeRow(label: "S", values: ["80", "78-83"]),
                      CatalogSizeRow(label: "M", values: ["82", "84-89"])]
        chart.sourceImage = sourceImage
        return chart
    }

    private func imageOnly(_ productID: String, image: String) -> CatalogSizeChart {
        var chart = CatalogSizeChart(id: "sizechart-\(productID)", productID: productID)
        chart.sourceImage = image
        return chart
    }

    /// 用户截图里的现象：粉色只上传了原图（没填行列），位置在红色之后
    func testStructuredChartWinsOverLaterImageOnlyRecord() {
        let charts = [structured("p-red", sourceImage: "local:red.jpg"),
                      imageOnly("p-pink", image: "local:pink.jpg")]
        let forPink = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink],
                                                                 charts: charts)
        let forRed = ShopCatalogSizeChartSharing.canonicalChart(for: red, among: [red, pink],
                                                               charts: charts)
        XCTAssertEqual(forPink?.columns.count, 3, "粉色的「仅原图」记录不得遮蔽红色的完整表格")
        XCTAssertEqual(forRed?.rows.count, 2)
        XCTAssertEqual(forPink?.columns, forRed?.columns, "同款两色必须拿到同一张表")
        XCTAssertEqual(ShopCatalogSizeChartSharing.sizeLabels(of: forPink), ["S", "M"],
                       "尺码轴取行标签（手工表格朝向）")
    }

    func testContentSourceImageIsKept() {
        let charts = [structured("p-red", sourceImage: "local:red.jpg"),
                      imageOnly("p-pink", image: "local:pink.jpg")]
        let chart = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink],
                                                               charts: charts)
        XCTAssertEqual(chart?.sourceImage, "local:red.jpg", "内容来源自带原图时用它自己的")
    }

    func testImageFallsBackToAnotherColorWhenContentSourceHasNone() {
        let charts = [structured("p-red", sourceImage: nil),
                      imageOnly("p-pink", image: "local:pink.jpg")]
        let chart = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink],
                                                               charts: charts)
        XCTAssertEqual(chart?.columns.count, 3, "内容仍取结构化那条")
        XCTAssertEqual(chart?.sourceImage, "local:pink.jpg",
                       "内容来源没图 → 用款内最后一条带图的，别把图丢了")
    }

    func testImageOnlyIsUsedWhenNoStructuredChartExistsAnywhere() {
        let charts = [imageOnly("p-red", image: "local:red.jpg"),
                      imageOnly("p-pink", image: "local:pink.jpg")]
        let chart = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink],
                                                               charts: charts)
        XCTAssertEqual(chart?.sourceImage, "local:pink.jpg", "整款都没有表格时，仅原图仍然可用")
        XCTAssertTrue(chart?.hasStructuredContent == false)
    }

    func testEmptyRowsDoNotShadowRealChart() {
        var empty = CatalogSizeChart(id: "sizechart-p-pink", productID: "p-pink")
        empty.columns = []
        empty.rows = []
        let charts = [structured("p-red", sourceImage: "local:red.jpg"), empty]
        let chart = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink],
                                                               charts: charts)
        XCTAssertEqual(chart?.rows.count, 2, "空行不算「有内容」，不得遮蔽真表")
    }
}

// MARK: - 端到端：真实 Store + 款式公共属性写入

@MainActor
final class ShopCatalogStylePublicInfoEndToEndTests: XCTestCase {

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

    private func publishNew(_ draft: CatalogProductDraft) throws -> String {
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        _ = try draftStore.publish(d, store: store)
        return try XCTUnwrap(store.catalog?.products.first { $0.name == draft.name }?.id,
                             "发布后应能在目录里按名字找到商品")
    }

    /// 同款两色：与录入端「第 1 步建款式 → 第 2 步加两色」等价的产物
    private func publishPair() throws -> (red: String, pink: String) {
        func draft(_ name: String) -> CatalogProductDraft {
            var draft = CatalogProductDraft()
            draft.name = name
            draft.category = "JSK"
            draft.newShopName = "款式档案店家"
            draft.newSeriesName = "款式档案系列"
            draft.price = 318
            draft.deposit = 63
            draft.balance = 255
            return draft
        }
        let red = try publishNew(draft("红色大蝴蝶结背心裙"))
        let pink = try publishNew(draft("粉色大蝴蝶结背心裙"))
        return (red, pink)
    }

    /// 写款式公共属性并刷新本测试持有的 store。
    ///
    /// 写入口径与 `upsertEntity` / `updatePublishedProduct` 一致：静态写入接口只刷新
    /// `ShopCatalogStore.shared`，**调用方负责刷新自己持有的 store 实例**。
    /// 漏掉这一句会让断言读到写之前的快照 —— 表现成「写进去了但读不到」。
    private func writeStyle(fabric: String?,
                            styleDescription: String?,
                            chart: CatalogSizeChart?,
                            through productID: String) throws {
        _ = try ShopCatalogDraftStore.updateStylePublicInfo(fabric: fabric,
                                                           styleDescription: styleDescription,
                                                           sizeChart: chart,
                                                           forProductID: productID)
        store.reloadWithOverlay()
    }

    private func styleChart() -> CatalogSizeChart {
        var chart = CatalogSizeChart(id: "", productID: "")
        chart.columns = ["尺码", "前裙长", "推荐胸围", "推荐腰围"]
        chart.rows = [CatalogSizeRow(label: "S", values: ["80", "78-83", "60-66"]),
                      CatalogSizeRow(label: "M", values: ["82", "84-89", "66-72"])]
        chart.sourceImage = "local:style-chart.jpg"
        return chart
    }

    /// 录入端第 1 步：公共属性**只写一次**，整款同步
    func testStylePublicInfoIsWrittenOnceAndSharedByEveryColor() throws {
        let ids = try publishPair()

        try writeStyle(fabric: "雪花提花布 + 蕾丝拼接",
                       styleDescription: "含可拆大蝴蝶结",
                       chart: styleChart(),
                       through: ids.red)

        XCTAssertEqual(store.catalog?.styleProfiles.count, 1,
                       "款式档案整款一份 —— 不是每个颜色一份")
        XCTAssertEqual(store.fabric(forProduct: ids.red), "雪花提花布 + 蕾丝拼接")
        XCTAssertEqual(store.fabric(forProduct: ids.pink), "雪花提花布 + 蕾丝拼接",
                       "粉色没填也必须读到款式面料")
        XCTAssertEqual(store.styleDescription(forProduct: ids.pink), "含可拆大蝴蝶结")
        XCTAssertEqual(store.sizeRun(forProduct: ids.pink), ["S", "M"],
                       "尺码表同属款式公共属性：两色尺码必须一致")
        XCTAssertEqual(store.sizeRun(forProduct: ids.red), store.sizeRun(forProduct: ids.pink))
    }

    /// 从一个颜色写入，用另一个颜色读 —— 款式键归一化必须真的落到同一份
    func testWritingThroughAnyColorLandsOnTheSameStyleProfile() throws {
        let ids = try publishPair()
        try writeStyle(fabric: "雪纺", styleDescription: nil, chart: nil, through: ids.pink)
        XCTAssertEqual(store.catalog?.styleProfiles.count, 1)
        XCTAssertEqual(store.fabric(forProduct: ids.red), "雪纺",
                       "从粉色写、红色也要读到（款式级，不是颜色级）")
    }

    /// 再次保存 = 整快照覆盖（与价格修正的「留空 = 清除」一致）
    func testSavingEmptySnapshotClearsTheStylePublicInfo() throws {
        let ids = try publishPair()
        try writeStyle(fabric: "雪纺", styleDescription: "描述", chart: styleChart(),
                       through: ids.red)
        try writeStyle(fabric: "", styleDescription: "", chart: nil, through: ids.red)

        XCTAssertNil(store.fabric(forProduct: ids.red), "留空 = 清除该公共属性")
        XCTAssertNil(store.fabric(forProduct: ids.pink))
        XCTAssertNil(store.sizeChart(forProduct: ids.pink), "尺码表一并清空且作用于整款")
        XCTAssertTrue(store.catalog?.styleProfiles.isEmpty ?? false, "不留空壳档案")
    }

    /// 「以后上新颜色不必重复填尺码表」：新颜色不带任何款式资料也能拿到
    func testNewColorAddedLaterInheritsStyleChartWithoutRefilling() throws {
        let ids = try publishPair()
        try writeStyle(fabric: nil, styleDescription: nil, chart: styleChart(),
                       through: ids.red)

        var later = CatalogProductDraft()
        later.name = "米白色大蝴蝶结背心裙"
        later.category = "JSK"
        // 与录入端表单一致：款式名显式落库。若只靠「剥离颜色词」派生，
        // 「米白色」这种复合色会被拆成「米」，款式键就对不上款式了。
        later.designName = "大蝴蝶结背心裙"
        later.newShopName = "款式档案店家"
        later.newSeriesName = "款式档案系列"
        later.price = 318
        let beige = try publishNew(later)

        XCTAssertEqual(store.sizeRun(forProduct: beige), ["S", "M"],
                       "后加的颜色不填尺码表也必须继承款式的")
        XCTAssertNotNil(store.sizeChart(forProduct: beige))
    }
}
