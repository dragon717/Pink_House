//
//  ShopCatalogSizeChartSharingTests.swift
//  ItemManagerTests
//
//  尺码表「款式共享」口径契约（2026-09-23，用户需求：
//  「只要我为其中任意一个颜色（比如红色）填写了尺码表，那么该同款的其它所有颜色
//   （比如粉色）都必须自动共享同一套尺码数据……前台商品页外侧显示的尺码信息也要同步」）。
//
//  锁死四组口径（`ShopCatalogSizeChartSharing`）：
//    A. 款式范围 = 同系列 + 同品类 + 同款式名；读含归档、写不含归档。
//    B. 读：款式范围内**最后一条有内容**的行 → 同款各颜色看到的内容逐字相同，
//       存量「只有红色填过」无需迁移即生效；空行不遮蔽真表。
//    C. 写：内容**扇出**到整款每个颜色一行（id 复用既有行，保证同 id 替换、不堆重复行）；
//       传 nil = 清空整款。
//    D. 尺码维度：项目里两种朝向都真实存在（种子 columns = S/M/L；手填/OCR 口径
//       rows.label = S/M/L），按「哪条轴像尺码用哪条」消歧 —— 旧实现写死行标签，
//       在种子数据上会把「胸围 / 腰围 / 裙长」当成尺码。
//

import XCTest
@testable import ItemManager

final class ShopCatalogSizeChartSharingTests: XCTestCase {

    // MARK: 构造夹具

    private func product(_ id: String,
                         name: String,
                         category: String = "JSK",
                         series: String = "s1",
                         archived: Bool = false) -> CatalogProduct {
        CatalogProduct(id: id, shopID: "shop1", seriesID: series, name: name,
                       category: category, images: [],
                       archivedAt: archived ? Date(timeIntervalSince1970: 0) : nil)
    }

    /// 大蝴蝶结背心裙：红色 / 粉色（同系列同品类 → 同款）
    private var red: CatalogProduct { product("p-red", name: "红色大蝴蝶结背心裙") }
    private var pink: CatalogProduct { product("p-pink", name: "粉色大蝴蝶结背心裙") }

    private func chart(_ productID: String,
                       id: String? = nil,
                       unit: String? = nil,
                       columns: [String] = ["S", "M", "L"],
                       rows: [CatalogSizeRow] = [CatalogSizeRow(label: "胸围", values: ["80", "84", "88"])],
                       sourceImage: String? = nil) -> CatalogSizeChart {
        var chart = CatalogSizeChart(id: id ?? "sizechart-\(productID)", productID: productID)
        chart.unit = unit
        chart.columns = columns
        chart.rows = rows
        chart.sourceImage = sourceImage
        return chart
    }

    /// 与 `ShopCatalogDraftStore.applySizeChart` 同一口径：整款删旧 + 扇出新行
    private func applying(_ plan: ShopCatalogSizeChartSharing.WritePlan,
                          to charts: [CatalogSizeChart]) -> [CatalogSizeChart] {
        var result = charts.filter { !plan.removals.contains($0.productID) }
        result.append(contentsOf: plan.upserts)
        return result
    }

    // MARK: A. 款式范围

    func testSameSeriesSameCategorySharesOneDesign() {
        let scope = ShopCatalogSizeChartSharing.designScope(of: red, among: [red, pink])

        XCTAssertEqual(scope.map(\.id), ["p-red", "p-pink"], "同款两色同属一个款式范围，自己在第 1 位")
    }

    func testDifferentSeriesIsNotShared() {
        let other = product("p-other", name: "粉色大蝴蝶结背心裙", series: "s2")

        let scope = ShopCatalogSizeChartSharing.designScope(of: red, among: [red, other])

        XCTAssertEqual(scope.map(\.id), ["p-red"], "不同系列（不同批次）不算同款")
    }

    func testDifferentCategoryIsNotShared() {
        let other = product("p-other", name: "粉色大蝴蝶结背心裙", category: "OP")

        let scope = ShopCatalogSizeChartSharing.designScope(of: red, among: [red, other])

        XCTAssertEqual(scope.map(\.id), ["p-red"], "不同品类不算同款")
    }

    func testArchivedColorIsOutOfWriteScopeButStillReadable() {
        let archivedPink = product("p-pink", name: "粉色大蝴蝶结背心裙", archived: true)

        XCTAssertEqual(ShopCatalogSizeChartSharing.designScope(of: red, among: [red, archivedPink]).map(\.id),
                       ["p-red"], "写范围不含归档颜色（不给已归档的颜色写尺码表行）")

        let charts = [chart("p-pink", columns: ["S", "M"])]
        let read = ShopCatalogSizeChartSharing.canonicalChart(for: red, among: [red, archivedPink],
                                                              charts: charts)
        XCTAssertEqual(read?.productID, "p-pink",
                       "读范围含归档颜色：归档某个颜色不该把整款的尺码表一起带走")
    }

    // MARK: B. 读：一侧填写，全款可见（本次需求主体）

    func testChartFilledOnOneColorIsVisibleOnEveryColor() {
        let charts = [chart("p-red", columns: ["S", "M", "L"], sourceImage: "asset-1")]

        let forRed = ShopCatalogSizeChartSharing.canonicalChart(for: red, among: [red, pink], charts: charts)
        let forPink = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink], charts: charts)

        XCTAssertEqual(forPink?.columns, ["S", "M", "L"], "粉色没有自己的表 → 自动共享红色的")
        XCTAssertEqual(forPink?.sourceImage, "asset-1", "原图也一起共享")
        XCTAssertEqual(forRed?.columns, forPink?.columns, "同款各颜色看到的必须是同一张表")
    }

    func testDivergentChartsResolveToTheLastWrittenOne() {
        // 历史数据可能给两个颜色各存了一份（后写胜出 = 覆盖层优先）
        let charts = [chart("p-red", id: "sizechart-red", columns: ["S", "M"]),
                      chart("p-pink", id: "sizechart-pink", columns: ["S", "M", "L"])]

        let forRed = ShopCatalogSizeChartSharing.canonicalChart(for: red, among: [red, pink], charts: charts)
        let forPink = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink], charts: charts)

        XCTAssertEqual(forRed?.columns, ["S", "M", "L"], "同一款式只认一份：最后写入的那一份")
        XCTAssertEqual(forPink?.id, forRed?.id, "两色解析到**同一行**，不会各看各的")
    }

    func testEmptyChartRowDoesNotShadowTheRealChart() {
        let charts = [chart("p-red", id: "sizechart-red", columns: ["S", "M"]),
                      chart("p-pink", id: "sizechart-pink", columns: [], rows: [], sourceImage: nil)]

        let resolved = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink], charts: charts)

        XCTAssertEqual(resolved?.id, "sizechart-red", "空行不算「有内容」，不能把真表遮住")
    }

    func testImageOnlyChartCountsAsMeaningful() {
        let charts = [chart("p-red", columns: [], rows: [], sourceImage: "local:chart.png")]

        let resolved = ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink], charts: charts)

        XCTAssertEqual(resolved?.sourceImage, "local:chart.png",
                       "只有原图也算有内容（模型契约：此时商品详情仅展示原图）")
    }

    func testNoChartAnywhereResolvesToNil() {
        XCTAssertNil(ShopCatalogSizeChartSharing.canonicalChart(for: pink, among: [red, pink], charts: []))
    }

    // MARK: C. 写：扇出到整款

    func testWritePlanFansOutToEveryColor() {
        let plan = ShopCatalogSizeChartSharing.writePlan(chart: chart("p-red"),
                                                        for: red, among: [red, pink], charts: [])

        XCTAssertEqual(plan.removals.sorted(), ["p-pink", "p-red"], "先清整款的旧行")
        XCTAssertEqual(plan.upserts.map(\.productID).sorted(), ["p-pink", "p-red"], "每个颜色一行")
        XCTAssertEqual(Set(plan.upserts.map(\.columns)), [["S", "M", "L"]], "内容逐字相同")
        XCTAssertEqual(Set(plan.upserts.map { $0.sourceImage }), [nil], "原图同样一致")
    }

    func testWritePlanReusesExistingRowIDsSoSeedRowsAreReplacedNotDuplicated() {
        // 红色是 Bundle 种子商品，尺码表 id 形如 sizechart-ag-jsk
        let existing = [chart("p-red", id: "sizechart-ag-jsk", columns: ["S"])]

        let plan = ShopCatalogSizeChartSharing.writePlan(chart: chart("p-red", columns: ["S", "M"]),
                                                        for: red, among: [red, pink], charts: existing)
        let redRow = plan.upserts.first { $0.productID == "p-red" }

        XCTAssertEqual(redRow?.id, "sizechart-ag-jsk",
                       "复用既有行 id：同 id 替换才能真正覆盖种子表，否则会多出一行且被种子行遮住")
        XCTAssertEqual(plan.upserts.first { $0.productID == "p-pink" }?.id, "sizechart-p-pink",
                       "粉色此前没有行 → 用确定性 id")
    }

    func testWritePlanIsIdempotent() {
        var charts = [chart("p-red", id: "sizechart-ag-jsk")]
        let scope = [red, pink]

        for _ in 0..<3 {
            let plan = ShopCatalogSizeChartSharing.writePlan(chart: chart("p-red", columns: ["S", "M", "L"]),
                                                            for: red, among: scope, charts: charts)
            charts = applying(plan, to: charts)
        }

        XCTAssertEqual(charts.count, 2, "重复保存不会堆出重复行")
        XCTAssertEqual(Set(charts.map(\.productID)), ["p-red", "p-pink"])
        XCTAssertEqual(Set(charts.map(\.columns)), [["S", "M", "L"]])
    }

    func testWritePlanWithNilClearsTheWholeDesign() {
        let existing = [chart("p-red", id: "sizechart-red"), chart("p-pink", id: "sizechart-pink")]

        let plan = ShopCatalogSizeChartSharing.writePlan(chart: nil, for: pink,
                                                        among: [red, pink], charts: existing)

        XCTAssertEqual(plan.removals.sorted(), ["p-pink", "p-red"], "清空作用于整款，不是只清当前颜色")
        XCTAssertTrue(plan.upserts.isEmpty)
        XCTAssertTrue(applying(plan, to: existing).isEmpty)
    }

    func testFanOutContentIsIdenticalAcrossColors() {
        let source = chart("p-red", unit: "cm", columns: ["S", "M"],
                           rows: [CatalogSizeRow(label: "胸围", values: ["80", nil])],
                           sourceImage: "local:chart.jpg")

        let plan = ShopCatalogSizeChartSharing.writePlan(chart: source, for: pink,
                                                        among: [red, pink], charts: [])

        // 除 id / productID（各自归位）外，其余字段必须逐字相同
        let contents = plan.upserts.map { row -> String in
            "\(row.unit ?? "-")|\(row.columns.joined(separator: ","))|"
                + "\(row.rows.map { "\($0.label):\($0.values.map { $0 ?? "—" }.joined(separator: ","))" }.joined(separator: ";"))|"
                + "\(row.sourceImage ?? "-")"
        }
        XCTAssertEqual(Set(contents).count, 1, "同款各颜色的尺码表内容完全一致")
    }

    // MARK: D. 尺码维度（朝向消歧）

    func testSizeLabelsPrefersTheSizeLikeAxisForSeedShape() {
        // 种子数据形状：columns = 尺码，rows.label = 部位
        let seed = chart("p-red", columns: ["S", "M", "L"],
                         rows: [CatalogSizeRow(label: "胸围", values: ["80", "84", "88"]),
                                CatalogSizeRow(label: "裙长", values: ["92", "94", "96"])])

        XCTAssertEqual(ShopCatalogSizeChartSharing.sizeLabels(of: seed), ["S", "M", "L"],
                       "旧实现取 rows.label 会显示成「胸围 / 裙长」")
    }

    func testSizeLabelsUsesRowLabelsForManualOrientation() {
        // 手填 / OCR 口径（角落标签「尺码」）：columns = 部位，rows.label = 尺码
        let manual = chart("p-red", columns: ["胸围", "衣长"],
                           rows: [CatalogSizeRow(label: "S", values: ["84", "52"]),
                                  CatalogSizeRow(label: "M", values: ["88", "56"])])

        XCTAssertEqual(ShopCatalogSizeChartSharing.sizeLabels(of: manual), ["S", "M"])
    }

    func testIsSizeTokenRecognisesCommonCodes() {
        for token in ["S", "M", "L", "XL", "XXL", "XS", "均码", "F", "90", "100"] {
            XCTAssertTrue(ShopCatalogSizeChartSharing.isSizeToken(token), "\(token) 应识别为尺码")
        }
        for token in ["胸围", "腰围", "裙长", "80-84", "肩宽", ""] {
            XCTAssertFalse(ShopCatalogSizeChartSharing.isSizeToken(token), "\(token) 不是尺码")
        }
    }

    func testSizeLabelsOfNilChartIsEmpty() {
        XCTAssertTrue(ShopCatalogSizeChartSharing.sizeLabels(of: nil).isEmpty)
    }

    // MARK: E. 前台尺码列（外侧展示）

    func testSizeRunPrefersSharedChart() {
        let charts = [chart("p-red", columns: ["S", "M", "L"])]
        let sizesByProduct = ["p-pink": ["均码"]]

        let run = ShopCatalogSizeChartSharing.sizeRun(for: pink, among: [red, pink], charts: charts,
                                                      sizesByProduct: { sizesByProduct })

        XCTAssertEqual(run, ["S", "M", "L"],
                       "同款共享尺码表优先于本商品自己的规格尺码 —— 否则两个颜色外侧尺码会不一致")
    }

    func testSizeRunFallsBackToOwnVariantsThenSiblings() {
        let runOwn = ShopCatalogSizeChartSharing.sizeRun(
            for: pink, among: [red, pink], charts: [],
            sizesByProduct: { ["p-pink": ["均码"], "p-red": ["S", "M"]] })
        XCTAssertEqual(runOwn, ["均码"], "没有尺码表时用本商品规格尺码")

        let runSibling = ShopCatalogSizeChartSharing.sizeRun(
            for: pink, among: [red, pink], charts: [],
            sizesByProduct: { ["p-red": ["S", "M"]] })
        XCTAssertEqual(runSibling, ["S", "M"], "本商品也没有规格尺码时取同款其它颜色的")
    }

    func testSizeRunIsEmptyWhenNothingIsAvailable() {
        let run = ShopCatalogSizeChartSharing.sizeRun(for: pink, among: [red, pink], charts: [],
                                                      sizesByProduct: { [:] })
        XCTAssertTrue(run.isEmpty)
    }

    func testSizeRunDoesNotEvaluateVariantSizesWhenChartHits() {
        var evaluated = false
        _ = ShopCatalogSizeChartSharing.sizeRun(for: pink, among: [red, pink],
                                               charts: [chart("p-red", columns: ["S"])],
                                               sizesByProduct: { evaluated = true; return [:] })
        XCTAssertFalse(evaluated, "命中尺码表时不应去算整份规格尺码（惰性求值）")
    }

    // MARK: F. 规格尺码索引

    func testVariantSizesByProductDeduplicatesAndKeepsOrder() {
        var catalog = ShopCatalog()
        catalog.variants = [
            CatalogProductVariant(id: "v1", productID: "p-red", color: "红色", size: "M"),
            CatalogProductVariant(id: "v2", productID: "p-red", color: "红色", size: "S"),
            CatalogProductVariant(id: "v3", productID: "p-red", color: "粉色", size: "M"),
            CatalogProductVariant(id: "v4", productID: "p-red", color: "粉色", size: "  "),
        ]

        XCTAssertEqual(ShopCatalogSizeChartSharing.variantSizesByProduct(catalog)["p-red"], ["M", "S"],
                       "按出现顺序去重，空白尺码不算")
    }
}

// MARK: - 端到端：真实 Store + 真实发布 / 深度编辑链路
//
//  纯逻辑测不到的是「接线」：Store 的读是否真的走了款式归并、发布与深度编辑是否真的扇出。
//  这里用真 store（临时存储目录）走一遍：红色带表发布 → 粉色不带表发布 → 粉色也必须看到表。

@MainActor
final class ShopCatalogSizeChartSharingEndToEndTests: XCTestCase {

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

    /// 走完状态机并发布，返回**新建商品的 id**。
    ///
    /// ⚠️ `publish` 的返回值是给人看的摘要（「已发布商品「红色共享款」（店家 · 系列）」），
    /// 不是 id —— 早期这里直接把摘要当 id 用，于是 `store.product(id:)` 全部落空，
    /// 端到端断言全部失去意义（断言里的 nil 是「查不到」而不是「没共享」）。
    /// 商品 id 一律从目录里按名字反查。
    private func publishNew(_ draft: CatalogProductDraft) throws -> String {
        let draftStore = ShopCatalogDraftStore.shared
        try draftStore.advance(draft, to: .submitted)
        var d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        try draftStore.advance(d, to: .reviewed)
        d = try XCTUnwrap(draftStore.drafts.first { $0.id == draft.id })
        _ = try draftStore.publish(d, store: store)
        return try XCTUnwrap(store.catalog?.products.first { $0.name == draft.name }?.id,
                             "发布后应能在目录里按名字找到商品「\(draft.name)」")
    }

    /// 该商品在目录里有多少条尺码表行（扇出不得堆重复行）
    private func chartRowCount(_ productID: String) -> Int {
        (store.catalog?.sizeCharts ?? []).filter { $0.productID == productID }.count
    }

    private func draft(name: String, withChart: Bool) -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.category = "JSK"
        draft.newShopName = "尺码共享店家"
        draft.newSeriesName = "尺码共享系列"
        draft.price = 500
        if withChart {
            var chart = CatalogSizeChart(id: "", productID: "")
            chart.columns = ["S", "M", "L"]
            chart.rows = [CatalogSizeRow(label: "胸围", values: ["80", "84", "88"])]
            chart.sourceImage = "local:shared-chart.jpg"
            draft.sizeChart = chart
        }
        return draft
    }

    /// 发布同款两色：红色带尺码表、粉色不带（模拟「只填了一个颜色」）
    private func publishSharedPair() throws -> (red: String, pink: String) {
        let redID = try publishNew(draft(name: "红色共享款", withChart: true))
        let pinkID = try publishNew(draft(name: "粉色共享款", withChart: false))
        return (redID, pinkID)
    }

    func testChartFilledOnOneColorIsVisibleOnEveryColor() throws {
        let ids = try publishSharedPair()

        let redChart = try XCTUnwrap(store.sizeChart(forProduct: ids.red))
        let pinkChart = try XCTUnwrap(store.sizeChart(forProduct: ids.pink),
                                      "粉色没填尺码表也必须能看到 —— 这就是本次需求")
        XCTAssertEqual(pinkChart.columns, redChart.columns)
        XCTAssertEqual(pinkChart.rows, redChart.rows)
        XCTAssertEqual(pinkChart.sourceImage, redChart.sourceImage, "原图一并共享")

        XCTAssertEqual(store.sizeRun(forProduct: ids.pink), ["S", "M", "L"],
                       "前台外侧尺码信息（详情页尺码行 / 点菜页 chips）必须同步")
        XCTAssertEqual(store.sizeRun(forProduct: ids.pink),
                       store.sizeRun(forProduct: ids.red),
                       "两色外侧尺码必须逐字一致")
    }

    func testDeepEditOnAnotherColorFansOutToTheWholeDesign() throws {
        let ids = try publishSharedPair()
        let pink = try XCTUnwrap(store.product(id: ids.pink))

        var chart = CatalogSizeChart(id: "", productID: "")
        chart.columns = ["S", "M", "XL"]
        chart.rows = [CatalogSizeRow(label: "胸围", values: ["80", "84", "92"])]
        try ShopCatalogDraftStore.updatePublishedProduct(pink, assets: [], variants: [],
                                                        sizeChart: chart)
        store.reloadWithOverlay()

        let redChart = try XCTUnwrap(store.sizeChart(forProduct: ids.red))
        XCTAssertEqual(redChart.columns, ["S", "M", "XL"],
                       "从粉色改尺码表 → 红色必须跟着变（整款一套，不是各存一份）")
        XCTAssertEqual(chartRowCount(ids.red), 1, "扇出不得留下重复行")
        XCTAssertEqual(chartRowCount(ids.pink), 1)
        XCTAssertEqual(store.sizeRun(forProduct: ids.red), store.sizeRun(forProduct: ids.pink))
    }

    func testClearingChartOnOneColorClearsTheWholeDesign() throws {
        let ids = try publishSharedPair()
        let red = try XCTUnwrap(store.product(id: ids.red))

        try ShopCatalogDraftStore.updatePublishedProduct(red, assets: [], variants: [],
                                                        sizeChart: nil)
        store.reloadWithOverlay()

        XCTAssertNil(store.sizeChart(forProduct: ids.red), "留空保存 = 清空整款尺码表")
        XCTAssertNil(store.sizeChart(forProduct: ids.pink), "同款另一色也一并清空")
        XCTAssertTrue(store.sizeRun(forProduct: ids.pink).isEmpty)
    }
}
