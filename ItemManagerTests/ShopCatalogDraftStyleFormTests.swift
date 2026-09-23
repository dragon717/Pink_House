//
//  ShopCatalogDraftStyleFormTests.swift
//  ItemManagerTests
//
//  「款式（SPU）+ 多颜色（SKU）」一体化录表单纯逻辑与落盘契约（2026-09-23）。
//
//  用户需求原文：
//    「现在的表单结构不够合理，请实现在当前页面内添加多颜色 SKU 的功能。不需要让用户
//      通过『新建单品』来建颜色。把 designName（款式名）和多个 product（颜色）的录入
//      整合在同一个表单里，让公共资料实现跨颜色复用，图片单独上传。」
//    「请在颜色 SKU 添加区，将图片上传组件与颜色字段直接绑定。让用户点颜色的同时就能
//      直接传图，实现图片与 SKU 的强关联。不要单独弄一个图片上传区让用户去对应。」
//
//  锁死五组口径：
//    A. 草稿 → 颜色行：颜色名派生（显式规格色 → 名称颜色词 → 空）、商品名幂等重组。
//    B. 一件表单落盘：新增 / 更新 / 移除三种去向都要如实计数；一次 persist。
//    C. 款式名**一处决议** —— 新加的颜色必须继承同一个款名，否则会掉出同款组。
//    D. 图片与颜色强绑定：asset id 由草稿 id + 序号确定性生成，每个 variant 的
//       imageAssetID 指向本颜色主图（前端切色读的就是这条链）。
//    E. 同款家族口径唯一：表单展示范围与仓库落盘范围同源，否则会误删颜色草稿。
//

import XCTest
@testable import ItemManager

// MARK: - 纯逻辑：颜色行 / 商品名 / 款式层与颜色层应用

final class ShopCatalogStyleFormLogicTests: XCTestCase {

    private func draft(_ color: String,
                       design: String? = "一字领OP",
                       category: String = "OP",
                       seriesID: String? = "series-swan",
                       batch: String? = "batch-1") -> CatalogProductDraft {
        var d = CatalogProductDraft()
        d.batchID = batch
        d.name = "\(color)\(design ?? "")"
        d.category = category
        d.designName = design
        d.seriesID = seriesID
        return d
    }

    private func chart(_ id: String = "sizechart-draft-aaa111") -> CatalogSizeChart {
        var c = CatalogSizeChart(id: id, productID: "prod-old")
        c.columns = ["尺码", "胸围", "衣长"]
        c.rows = [CatalogSizeRow(label: "M", values: ["84", "52"])]
        return c
    }

    private func style(fabric: String = "100% 聚酯纤维",
                       designName: String = "",
                       styleNameFallback: String = "一字领OP") -> ShopCatalogDraftStyleForm.StyleInput {
        var s = ShopCatalogDraftStyleForm.StyleInput()
        s.designName = designName
        s.styleNameFallback = styleNameFallback
        s.category = "OP"
        s.fabric = fabric
        s.styleDescription = "重工蕾丝一字领"
        s.sizeChart = chart()
        s.reservationPrice = 498
        s.deposit = 100
        s.balance = 398
        s.currency = .cny
        s.shopID = nil
        s.newShopName = "天鹅店家"
        s.seriesID = "series-swan"
        return s
    }

    // MARK: A. 颜色名派生与商品名组合

    func testColorNameIsDerivedFromProductNameWhenNoVariant() {
        XCTAssertEqual(ShopCatalogDraftStyleForm.colorName(of: draft("生成色")), "生成色")
        XCTAssertEqual(ShopCatalogDraftStyleForm.colorName(of: draft("粉紫色")), "粉紫色",
                       "复合色必须整词识别，否则颜色名会被拆成「粉」")
    }

    func testColorNamePrefersExplicitVariantColor() {
        var d = draft("生成色")
        d.variants = [CatalogProductVariant(id: "v1", productID: "", color: "生成色-限定",
                                            size: "M", imageAssetID: nil)]
        XCTAssertEqual(ShopCatalogDraftStyleForm.colorName(of: d), "生成色-限定")
    }

    func testColorNameIsEmptyWhenNameCarriesNoColorWord() {
        var d = draft("大蝴蝶结背心裙", design: nil)
        d.designName = nil
        XCTAssertEqual(ShopCatalogDraftStyleForm.colorName(of: d), "",
                       "名称里没有颜色词时必须回空，不许把整名当颜色")
    }

    /// 幂等关键：存量草稿 name 本就是「颜色 + 款式」的形式，
    /// 派生款名再组合回去必须得到原值，否则打开一次表单就把名字改了。
    func testProductNameCompositionIsIdempotentForLegacyDrafts() {
        var legacy = draft("生成色", design: nil)
        legacy.designName = nil
        legacy.name = "生成色一字领OP"

        let color = ShopCatalogDraftStyleForm.colorName(of: legacy)
        let styleName = ShopCatalogDraftStyleForm.styleName(of: legacy)
        XCTAssertEqual(color, "生成色")
        XCTAssertEqual(styleName, "一字领OP")
        XCTAssertEqual(ShopCatalogDraftStyleForm.productName(colorName: color, styleName: styleName),
                       "生成色一字领OP")
    }

    func testNamePreviewExplainsEmptyState() {
        XCTAssertEqual(ShopCatalogDraftStyleForm.namePreview(colorName: "蓝色", styleName: "一字领OP"),
                       "蓝色一字领OP")
        XCTAssertEqual(ShopCatalogDraftStyleForm.namePreview(colorName: "", styleName: ""),
                       "（待填颜色名与款式名）")
    }

    // MARK: A2. 草稿 → 颜色行

    func testRowsPutTheSourceDraftFirst() {
        let first = draft("生成色")
        let second = draft("粉紫色")
        let third = draft("蓝色")
        let rows = ShopCatalogDraftStyleForm.rows(of: [first, second, third], sourceID: second.id)

        XCTAssertEqual(rows.map(\.draftID), [second.id, first.id, third.id],
                       "用户点进来的那一色要排第一，而不是列表里碰巧排第一的")
        XCTAssertTrue(rows.allSatisfy { !$0.isNew })
    }

    func testRowsCarryImagesSizesAndSettledFlag() {
        var d = draft("生成色")
        d.images = [CatalogAsset(id: "a1", type: .productImage, thumbnailURL: nil,
                                 previewURL: nil, originalURL: "local:gen.jpg",
                                 width: nil, height: nil)]
        d.variants = [CatalogProductVariant(id: "v1", productID: "", color: "生成色",
                                            size: "M", imageAssetID: "a1"),
                      CatalogProductVariant(id: "v2", productID: "", color: "生成色",
                                            size: "L", imageAssetID: "a1")]
        d.status = .published

        let row = ShopCatalogDraftStyleForm.rows(of: [d], sourceID: d.id)[0]
        XCTAssertEqual(row.imageRefs, ["local:gen.jpg"])
        XCTAssertEqual(row.sizes, ["M", "L"])
        XCTAssertTrue(row.isSettled, "已发布 = 只读行")
    }

    func testSizesAreDeduplicatedInVariantOrder() {
        var d = draft("生成色")
        d.variants = [CatalogProductVariant(id: "v1", productID: "", color: nil,
                                            size: "M", imageAssetID: nil),
                      CatalogProductVariant(id: "v2", productID: "", color: nil,
                                            size: "M", imageAssetID: nil),
                      CatalogProductVariant(id: "v3", productID: "", color: nil,
                                            size: "S", imageAssetID: nil)]
        XCTAssertEqual(ShopCatalogDraftStyleForm.sizes(of: d), ["M", "S"])
    }

    // MARK: E. 同款家族（唯一口径）

    func testSameStyleFamilyGroupsThreeColors() {
        let family = ShopCatalogDraftStyleForm.sameStyleFamily(
            of: draft("生成色"), in: [draft("生成色"), draft("粉紫色"), draft("蓝色")])
        XCTAssertEqual(family.count, 3)
    }

    func testSameStyleFamilySeparatesDifferentDesignsAndCategories() {
        let source = draft("生成色")
        let family = ShopCatalogDraftStyleForm.sameStyleFamily(
            of: source,
            in: [source,
                 draft("生成色", design: "高腰JSK"),
                 draft("生成色", category: "JSK")])
        XCTAssertEqual(family.count, 1)
    }

    func testSameStyleFamilyComparesSeriesTokenOnlyWhenBothDeclare() {
        // 一条自报系列、一条靠整批继承（系列字段全空）→ 仍算同款
        var inherited = draft("粉紫色")
        inherited.seriesID = nil
        inherited.newSeriesName = ""
        XCTAssertTrue(ShopCatalogDraftStyleForm.isSameStyle(draft("生成色"), inherited))

        // 两条都自报、但系列不同 → 不是同款
        XCTAssertFalse(ShopCatalogDraftStyleForm.isSameStyle(draft("生成色"),
                                                             draft("粉紫色", seriesID: "series-other")))
    }

    // MARK: F. 校验

    func testValidateRejectsEmptyColorList() {
        XCTAssertThrowsError(try ShopCatalogDraftStyleForm.validate(colors: [], styleName: "一字领OP"))
    }

    func testValidateRejectsBlankColorName() {
        let rows = [ShopCatalogDraftStyleForm.ColorRow(colorName: "生成色"),
                    ShopCatalogDraftStyleForm.ColorRow(colorName: "   ")]
        XCTAssertThrowsError(try ShopCatalogDraftStyleForm.validate(colors: rows,
                                                                   styleName: "一字领OP"))
    }

    func testValidateRejectsMultiColorWithoutStyleName() {
        let rows = [ShopCatalogDraftStyleForm.ColorRow(colorName: "生成色"),
                    ShopCatalogDraftStyleForm.ColorRow(colorName: "粉紫色")]
        XCTAssertThrowsError(try ShopCatalogDraftStyleForm.validate(colors: rows, styleName: ""),
                             "多颜色没有款名 = 同款会被拆成多款，公共资料复用失效")
    }

    func testValidateAllowsSingleColorWithoutStyleName() {
        let rows = [ShopCatalogDraftStyleForm.ColorRow(colorName: "生成色")]
        XCTAssertNoThrow(try ShopCatalogDraftStyleForm.validate(colors: rows, styleName: ""))
    }

    func testResolveStyleNamePrefersExplicitInput() {
        var source = draft("生成色", design: nil)
        source.designName = nil
        source.name = "生成色一字领OP"
        XCTAssertEqual(ShopCatalogDraftStyleForm.resolveStyleName(explicit: "圆领OP", source: source),
                       "圆领OP")
        XCTAssertEqual(ShopCatalogDraftStyleForm.resolveStyleName(explicit: "  ", source: source),
                       "一字领OP", "留空才回退派生")
    }

    // MARK: C/D. 款式层与颜色层应用

    func testApplyStyleWritesStyleLayerAndComposesProductName() {
        var target = draft("粉紫色", design: nil)
        target.designName = nil
        let updated = ShopCatalogDraftStyleForm.applyStyle(style(), to: target, colorName: "粉紫色")

        XCTAssertEqual(updated.name, "粉紫色一字领OP", "商品名 = 颜色名 + 款式名")
        XCTAssertEqual(updated.category, "OP")
        XCTAssertEqual(updated.price, 498)
        XCTAssertEqual(updated.stockPrice, nil)
        XCTAssertEqual(updated.deposit, 100)
        XCTAssertEqual(updated.balance, 398)
        XCTAssertEqual(updated.currency, .cny)
        XCTAssertEqual(updated.saleKind, .reservation,
                       "新口径统一按预约价 = price、现货价 = stockPrice")
        XCTAssertEqual(updated.fabric, "100% 聚酯纤维")
        XCTAssertEqual(updated.styleDescription, "重工蕾丝一字领")
    }

    func testApplyStyleDoesNotFabricateExplicitDesignName() {
        var target = draft("粉紫色", design: nil)
        target.designName = nil
        let updated = ShopCatalogDraftStyleForm.applyStyle(style(designName: ""),
                                                           to: target,
                                                           colorName: "粉紫色")
        XCTAssertNil(updated.designName, "用户没填款式名就不替他写一个显式款式名")
    }

    func testApplyStyleWritesExplicitDesignNameWhenGiven() {
        let updated = ShopCatalogDraftStyleForm.applyStyle(style(designName: "圆领OP"),
                                                           to: draft("生成色"),
                                                           colorName: "生成色")
        XCTAssertEqual(updated.designName, "圆领OP")
        XCTAssertEqual(updated.name, "生成色圆领OP")
    }

    /// 两条草稿共用同一个尺码表 id 会在发布时互相覆盖（发布按 id 落到覆盖层），
    /// 最后一个颜色赢家通吃 —— 所以必须逐条重编。
    func testApplyStyleReindexesChartIDPerDraft() {
        let a = draft("生成色")
        let b = draft("粉紫色")
        let chartA = ShopCatalogDraftStyleForm.applyStyle(style(), to: a, colorName: "生成色").sizeChart
        let chartB = ShopCatalogDraftStyleForm.applyStyle(style(), to: b, colorName: "粉紫色").sizeChart

        XCTAssertEqual(chartA?.id, "sizechart-draft-\(a.id.prefix(6))")
        XCTAssertEqual(chartB?.id, "sizechart-draft-\(b.id.prefix(6))")
        XCTAssertNotEqual(chartA?.id, chartB?.id)
        XCTAssertEqual(chartA?.productID, "", "草稿期不绑定 productID")
    }

    func testApplyStyleLeavesColorPrivateFieldsAlone() {
        var target = draft("粉紫色")
        target.images = [CatalogAsset(id: "keep", type: .productImage, thumbnailURL: nil,
                                      previewURL: nil, originalURL: "local:pink.jpg",
                                      width: nil, height: nil)]
        target.variants = [CatalogProductVariant(id: "v", productID: "", color: "粉紫色",
                                                 size: "M", imageAssetID: "keep")]
        target.status = .submitted
        target.rejectReason = "颜色写错了"

        let updated = ShopCatalogDraftStyleForm.applyStyle(style(), to: target, colorName: "生成色")
        XCTAssertEqual(updated.images.map(\.originalURL), ["local:pink.jpg"], "款式层不该动图片")
        XCTAssertEqual(updated.variants.map(\.color), ["粉紫色"])
        XCTAssertEqual(updated.status, .submitted)
        XCTAssertEqual(updated.rejectReason, "颜色写错了")
    }

    /// 图片与颜色强绑定的落点：每个 variant 的 imageAssetID 指向**本颜色**主图，
    /// 前端详情页切色时读的就是这条链。
    func testApplyColorBindsPrimaryImageToEveryVariant() {
        var row = ShopCatalogDraftStyleForm.ColorRow(colorName: "生成色")
        row.imageRefs = ["local:gen-1.jpg", "local:gen-2.jpg"]
        row.sizes = ["M"]
        let updated = ShopCatalogDraftStyleForm.applyColor(row, to: draft("生成色"),
                                                          orderedSizes: ["S", "M", "L"])

        XCTAssertEqual(updated.images.map(\.originalURL), ["local:gen-1.jpg", "local:gen-2.jpg"])
        let primary = updated.images.first?.id
        XCTAssertNotNil(primary)
        XCTAssertEqual(updated.variants.count, 1)
        XCTAssertEqual(updated.variants.first?.imageAssetID, primary,
                       "配色图必须绑定到该颜色的规格行")
        XCTAssertEqual(updated.variants.first?.color, "生成色")
        XCTAssertEqual(updated.variants.first?.size, "M")
    }

    func testApplyColorOrdersSizesByStyleChartAndKeepsUnknownOnes() {
        var row = ShopCatalogDraftStyleForm.ColorRow(colorName: "生成色")
        row.sizes = ["L", "XL", "S"]   // XL 不在款式尺码表里（历史数据）
        let updated = ShopCatalogDraftStyleForm.applyColor(row, to: draft("生成色"),
                                                          orderedSizes: ["S", "M", "L"])
        XCTAssertEqual(updated.variants.compactMap(\.size), ["S", "L", "XL"],
                       "按款式尺码表顺序输出，表外尺码追加在后而不是被丢掉")
    }

    func testApplyColorWithoutSizesProducesOneColorOnlyVariant() {
        var row = ShopCatalogDraftStyleForm.ColorRow(colorName: "生成色")
        row.sizes = []
        let updated = ShopCatalogDraftStyleForm.applyColor(row, to: draft("生成色"),
                                                          orderedSizes: [])
        XCTAssertEqual(updated.variants.count, 1)
        XCTAssertNil(updated.variants.first?.size)
        XCTAssertEqual(updated.variants.first?.color, "生成色")
    }

    func testApplyColorIsIdempotentForAssetIDs() {
        var row = ShopCatalogDraftStyleForm.ColorRow(colorName: "生成色")
        row.imageRefs = ["local:gen.jpg"]
        let once = ShopCatalogDraftStyleForm.applyColor(row, to: draft("生成色"), orderedSizes: [])
        let twice = ShopCatalogDraftStyleForm.applyColor(row, to: once, orderedSizes: [])
        XCTAssertEqual(once.images.map(\.id), twice.images.map(\.id))
        XCTAssertEqual(once.publishOperationKey, twice.publishOperationKey)
    }

    func testNewDraftInheritsBatchAndStatus() {
        let source = draft("生成色")
        var row = ShopCatalogDraftStyleForm.ColorRow(colorName: "蓝色")
        row.imageRefs = ["local:blue.jpg"]
        let fresh = ShopCatalogDraftStyleForm.makeNewDraft(colorRow: row,
                                                          style: style(),
                                                          basedOn: source,
                                                          orderedSizes: ["M"])
        XCTAssertEqual(fresh.batchID, source.batchID)
        XCTAssertEqual(fresh.status, .draft)
        XCTAssertEqual(fresh.name, "蓝色一字领OP")
        XCTAssertEqual(fresh.images.map(\.originalURL), ["local:blue.jpg"])
    }
}

// MARK: - 仓库层：applyStyleForm 一次落盘

@MainActor
final class ShopCatalogStyleFormStoreTests: XCTestCase {

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

    /// 源草稿：**不预设归属** —— `createBatch` 会用批次会话覆盖店家/系列字段，
    /// 归属必须照真实流程走一次「应用到整批」。
    private func makeSource(_ color: String = "生成色",
                            design: String? = "一字领OP") -> CatalogProductDraft {
        var d = CatalogProductDraft()
        d.name = "\(color)\(design ?? "")"
        d.category = "OP"
        d.designName = design
        return d
    }

    private func makeBatch(_ drafts: [CatalogProductDraft]) throws -> CatalogBatchEntrySession {
        let session = CatalogBatchEntrySession()
        try draftStore.createBatch(session, drafts: drafts)
        try draftStore.applyBatchAttribution(
            batchID: session.id,
            shopID: nil, newShopName: "表单测试店家", newShopAliases: "",
            seriesID: nil, newSeriesName: "天鹅之歌", newSeriesYear: 2026, newSeriesSeason: "冬")
        return session
    }

    private func style(from draft: CatalogProductDraft,
                       price: Double = 498,
                       fabric: String = "100% 聚酯纤维") -> ShopCatalogDraftStyleForm.StyleInput {
        var s = ShopCatalogDraftStyleForm.StyleInput()
        s.designName = draft.designName ?? ""
        s.category = draft.category
        s.fabric = fabric
        s.styleDescription = "重工蕾丝一字领"
        var c = CatalogSizeChart(id: "sizechart-form-\(draft.id.prefix(6))", productID: "")
        c.columns = ["尺码", "胸围", "衣长"]
        c.rows = [CatalogSizeRow(label: "M", values: ["84", "52"])]
        s.sizeChart = c
        s.reservationPrice = price
        s.deposit = 100
        s.balance = price - 100
        s.currency = .cny
        s.shopID = draft.shopID
        s.newShopName = draft.newShopName
        s.newShopAliases = draft.newShopAliases
        s.seriesID = draft.seriesID
        s.newSeriesName = draft.newSeriesName
        s.newSeriesYear = draft.newSeriesYear
        s.newSeriesSeason = draft.newSeriesSeason
        s.batchID = draft.batchID
        return s
    }

    private func colorRow(_ color: String, images: [String] = [], sizes: [String] = ["M"])
        -> ShopCatalogDraftStyleForm.ColorRow {
        var row = ShopCatalogDraftStyleForm.ColorRow(colorName: color)
        row.imageRefs = images
        row.sizes = sizes
        return row
    }

    private func current(_ id: String) throws -> CatalogProductDraft {
        try XCTUnwrap(draftStore.drafts.first { $0.id == id })
    }

    // MARK: 新增

    func testAddingColorsCreatesDraftsInOnePass() throws {
        let session = try makeBatch([makeSource()])
        let source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })

        // 表单：源草稿那一行 + 两个新颜色
        let rows = [
            ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)[0],
            colorRow("粉紫色", images: ["local:pink.jpg"]),
            colorRow("蓝色", images: ["local:blue.jpg"]),
        ]
        let result = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                                   style: style(from: source),
                                                   colors: rows)

        XCTAssertEqual(result.createdCount, 2)
        XCTAssertEqual(result.updatedCount, 1)
        XCTAssertEqual(result.removedCount, 0)

        let mine = draftStore.drafts.filter { $0.batchID == session.id }
        XCTAssertEqual(mine.count, 3, "一个表单里就录完了三个颜色，不需要「新建单品」三次")

        let names = Set(mine.map(\.name))
        XCTAssertEqual(names, ["生成色一字领OP", "粉紫色一字领OP", "蓝色一字领OP"])
        XCTAssertTrue(mine.allSatisfy { $0.fabric == "100% 聚酯纤维" },
                      "款式公共资料要落到每条颜色草稿")
        XCTAssertTrue(mine.allSatisfy { $0.price == 498 })
        XCTAssertEqual(Set(mine.compactMap { $0.sizeChart?.id }).count, 3,
                       "尺码表 id 逐条重编，避免发布时互相覆盖")
    }

    /// 关键回归：新加的颜色必须继承同一个款名。
    /// 若让它各自派生（新草稿 name 还空着），款名会是空串 → 商品名退化成只有颜色词 →
    /// 「在这个表单里加一个颜色」反而变成两个款式。
    func testNewColorsInheritTheSameStyleName() throws {
        let session = try makeBatch([makeSource()])
        let source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })

        var rows = ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)
        rows.append(colorRow("粉紫色"))
        _ = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                          style: style(from: source),
                                          colors: rows)

        let created = try XCTUnwrap(draftStore.drafts.first { $0.name.contains("粉紫") })
        XCTAssertEqual(created.name, "粉紫色一字领OP")

        let family = ShopCatalogDraftStyleForm.sameStyleFamily(
            of: try current(source.id), in: draftStore.drafts)
        XCTAssertEqual(family.count, 2, "新颜色必须与源草稿落在同一个同款家族里")
    }

    func testImagesStayBoundToTheirOwnColor() throws {
        let session = try makeBatch([makeSource()])
        let source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })

        var rows = ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)
        rows[0].imageRefs = ["local:gen.jpg"]
        rows.append(colorRow("粉紫色", images: ["local:pink.jpg"]))
        _ = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                          style: style(from: source),
                                          colors: rows)

        let gen = try current(source.id)
        let pink = try XCTUnwrap(draftStore.drafts.first { $0.name.contains("粉紫") })
        XCTAssertEqual(gen.images.map(\.originalURL), ["local:gen.jpg"])
        XCTAssertEqual(pink.images.map(\.originalURL), ["local:pink.jpg"],
                       "每个颜色只拿到自己的图 —— 这正是「图片与 SKU 强关联」")
        XCTAssertNotEqual(gen.variants.first?.imageAssetID, pink.variants.first?.imageAssetID)
    }

    // MARK: 移除

    func testRemovingAColorDeletesItsUnpublishedDraft() throws {
        let session = try makeBatch([makeSource(), makeSource("粉紫色")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try XCTUnwrap(all.first { $0.name.contains("生成色") })
        let doomed = try XCTUnwrap(all.first { $0.name.contains("粉紫") })

        let rows = [ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)[0]]
        let result = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                                   style: style(from: source),
                                                   colors: rows)

        XCTAssertEqual(result.removedCount, 1)
        XCTAssertNil(draftStore.drafts.first { $0.id == doomed.id },
                     "颜色行就是这份草稿本身，删掉它不该在草稿箱里留下孤儿")
    }

    func testRemovingAPublishedColorKeepsTheDraftAndCountsItSkipped() throws {
        let session = try makeBatch([makeSource(), makeSource("粉紫色")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try XCTUnwrap(all.first { $0.name.contains("生成色") })
        var published = try XCTUnwrap(all.first { $0.name.contains("粉紫") })

        // 发布只接受 reviewed 且要求价格合法
        published.price = 498
        published.deposit = 100
        published.balance = 398
        try draftStore.upsert(published)
        try draftStore.advance(published, to: .submitted)
        var p = try XCTUnwrap(draftStore.drafts.first { $0.id == published.id })
        try draftStore.advance(p, to: .reviewed)
        p = try XCTUnwrap(draftStore.drafts.first { $0.id == published.id })
        _ = try draftStore.publish(p, store: store)

        let rows = [ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)[0]]
        let result = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                                   style: style(from: source),
                                                   colors: rows)

        XCTAssertEqual(result.removedCount, 0, "已发布的是发布回执，不能连带删掉")
        XCTAssertEqual(result.skippedSettledCount, 1, "但要如实告知跳过了它")
        XCTAssertNotNil(draftStore.drafts.first { $0.id == published.id })
    }

    func testSettledColorRowIsSkippedInsteadOfOverwritten() throws {
        let session = try makeBatch([makeSource()])
        let source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })

        var published = source
        published.price = 498
        published.deposit = 100
        published.balance = 398
        try draftStore.upsert(published)
        try draftStore.advance(published, to: .submitted)
        var p = try XCTUnwrap(draftStore.drafts.first { $0.id == source.id })
        try draftStore.advance(p, to: .reviewed)
        p = try XCTUnwrap(draftStore.drafts.first { $0.id == source.id })
        _ = try draftStore.publish(p, store: store)

        let family = ShopCatalogDraftStyleForm.sameStyleFamily(of: try current(source.id),
                                                               in: draftStore.drafts)
        let rows = ShopCatalogDraftStyleForm.rows(of: family, sourceID: source.id)
        XCTAssertTrue(rows.first?.isSettled == true)

        var edited = rows
        edited[0].imageRefs = ["local:should-not-apply.jpg"]
        let result = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                                   style: style(from: source),
                                                   colors: edited)

        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.skippedSettledCount, 1)
        XCTAssertEqual(try current(source.id).images.map(\.originalURL), [],
                       "已发布草稿不该被这次编辑改写")
    }

    // MARK: 防线

    func testMissingSourceThrows() {
        XCTAssertThrowsError(
            try draftStore.applyStyleForm(sourceDraftID: "draft-does-not-exist",
                                          style: ShopCatalogDraftStyleForm.StyleInput(),
                                          colors: [colorRow("生成色")])
        ) { error in
            guard case ShopCatalogDraftStoreError.sourceDraftNotFound = error else {
                return XCTFail("应抛 sourceDraftNotFound，实际：\(error)")
            }
        }
    }

    func testMultiColorWithoutStyleNameIsRejected() throws {
        let session = try makeBatch([makeSource(design: nil)])
        var source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })
        source.name = ""
        source.designName = nil
        try draftStore.upsert(source)

        var input = style(from: try current(source.id))
        input.designName = ""
        XCTAssertThrowsError(
            try draftStore.applyStyleForm(
                sourceDraftID: source.id,
                style: input,
                colors: [colorRow("生成色"), colorRow("粉紫色")])
        ) { error in
            guard case ShopCatalogDraftStyleForm.FormError.missingStyleNameForMultiColor = error else {
                return XCTFail("多颜色缺款名应被拦下，实际：\(error)")
            }
        }
    }

    func testOtherDesignsAreNotTouched() throws {
        let session = try makeBatch([makeSource(), makeSource("生成色", design: "高腰JSK")])
        let all = draftStore.drafts.filter { $0.batchID == session.id }
        let source = try XCTUnwrap(all.first { $0.name.contains("一字领OP") })
        let other = try XCTUnwrap(all.first { $0.name.contains("高腰JSK") })
        let otherSnapshot = other

        var rows = ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)
        rows.append(colorRow("粉紫色"))
        _ = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                          style: style(from: source),
                                          colors: rows)

        XCTAssertEqual(try current(other.id), otherSnapshot,
                       "别款草稿一个字段都不该动")
    }

    func testFormIsPersistedSoItSurvivesReload() throws {
        let session = try makeBatch([makeSource()])
        let source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })
        var rows = ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)
        rows.append(colorRow("蓝色", images: ["local:blue.jpg"]))
        _ = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                          style: style(from: source),
                                          colors: rows)

        draftStore.loadDrafts()   // 重新读盘
        let reloaded = try XCTUnwrap(draftStore.drafts.first { $0.name.contains("蓝色") })
        XCTAssertEqual(reloaded.images.map(\.originalURL), ["local:blue.jpg"])
        XCTAssertEqual(reloaded.fabric, "100% 聚酯纤维")
        XCTAssertEqual(reloaded.variants.compactMap(\.size), ["M"])
    }

    func testSavingTwiceIsIdempotent() throws {
        let session = try makeBatch([makeSource()])
        let source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })

        var rows = ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)
        rows.append(colorRow("粉紫色", images: ["local:pink.jpg"]))
        let styleInput = style(from: source)

        _ = try draftStore.applyStyleForm(sourceDraftID: source.id, style: styleInput, colors: rows)
        let afterFirst = draftStore.drafts
            .filter { $0.batchID == session.id }
            .sorted { $0.name < $1.name }

        // 用户没改任何东西又点了一次「完成」
        let family = ShopCatalogDraftStyleForm.sameStyleFamily(of: try current(source.id),
                                                               in: draftStore.drafts)
        let rowsAgain = ShopCatalogDraftStyleForm.rows(of: family, sourceID: source.id)
        let result = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                                   style: styleInput,
                                                   colors: rowsAgain)

        XCTAssertEqual(result.createdCount, 0, "没有新颜色就不该再造草稿")
        let afterSecond = draftStore.drafts
            .filter { $0.batchID == session.id }
            .sorted { $0.name < $1.name }
        XCTAssertEqual(afterFirst.map(\.id), afterSecond.map(\.id))
        XCTAssertEqual(afterFirst.map(\.name), afterSecond.map(\.name))
        XCTAssertEqual(afterFirst.map { $0.publishOperationKey },
                       afterSecond.map { $0.publishOperationKey },
                       "重复保存不得改变发布指纹")
    }
}

// MARK: - 端到端：一个表单录完整款 → 三色各自发布

@MainActor
final class ShopCatalogStyleFormEndToEndTests: XCTestCase {

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

    private func makeBatch() throws -> CatalogBatchEntrySession {
        var d = CatalogProductDraft()
        d.name = ""
        d.category = "OP"
        d.designName = nil
        let session = CatalogBatchEntrySession()
        try draftStore.createBatch(session, drafts: [d])
        try draftStore.applyBatchAttribution(
            batchID: session.id,
            shopID: nil, newShopName: "表单测试店家", newShopAliases: "",
            seriesID: nil, newSeriesName: "天鹅之歌", newSeriesYear: 2026, newSeriesSeason: "冬")
        return session
    }

    private func publish(_ draftID: String) throws {
        try draftStore.advance(try XCTUnwrap(draftStore.drafts.first { $0.id == draftID }),
                              to: .submitted)
        try draftStore.advance(try XCTUnwrap(draftStore.drafts.first { $0.id == draftID }),
                              to: .reviewed)
        _ = try draftStore.publish(try XCTUnwrap(draftStore.drafts.first { $0.id == draftID }),
                                  store: store)
    }

    /// 用户场景全流程：一个表单里录完「一字领OP」的 生成色 / 粉紫色 / 蓝色 三色
    /// （每色各传自己的图 + 勾尺码），一次保存 → 三条各自发布 →
    /// 三个颜色都带自己的图、共用同一份尺码表与款式资料。
    func testOneFormThenPublishGivesEveryColorItsOwnImageAndSharedStyleInfo() throws {
        let session = try makeBatch()
        let source = try XCTUnwrap(draftStore.drafts.first { $0.batchID == session.id })

        var style = ShopCatalogDraftStyleForm.StyleInput()
        style.designName = "一字领OP"
        style.category = "OP"
        style.fabric = "100% 聚酯纤维"
        style.styleDescription = "重工蕾丝一字领，后背绑带"
        var chart = CatalogSizeChart(id: "sizechart-form-\(source.id.prefix(6))", productID: "")
        chart.columns = ["尺码", "胸围", "衣长"]
        chart.rows = [CatalogSizeRow(label: "M", values: ["84", "52"]),
                      CatalogSizeRow(label: "L", values: ["88", "54"])]
        chart.sourceImage = "local:swan-chart.jpg"
        style.sizeChart = chart
        style.reservationPrice = 498
        style.deposit = 100
        style.balance = 398
        style.currency = .cny
        style.newShopName = "表单测试店家"
        style.newSeriesName = "天鹅之歌"
        style.newSeriesYear = 2026
        style.newSeriesSeason = "冬"
        style.batchID = session.id

        func row(_ color: String, image: String) -> ShopCatalogDraftStyleForm.ColorRow {
            var r = ShopCatalogDraftStyleForm.ColorRow(colorName: color)
            r.imageRefs = [image]
            r.sizes = ["M", "L"]
            return r
        }

        var sourceRow = ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)[0]
        // 新草稿是空白的：颜色名由用户在颜色行里填（这里模拟用户输入）
        XCTAssertEqual(sourceRow.colorName, "", "空白新草稿还没有颜色名")
        sourceRow.colorName = "生成色"
        sourceRow.imageRefs = ["local:gen.jpg"]
        sourceRow.sizes = ["M", "L"]
        let rows = [
            sourceRow,
            row("粉紫色", image: "local:pink.jpg"),
            row("蓝色", image: "local:blue.jpg"),
        ]
        let result = try draftStore.applyStyleForm(sourceDraftID: source.id,
                                                   style: style,
                                                   colors: rows)
        XCTAssertEqual(result.writtenCount, 3)
        XCTAssertEqual(result.removedCount, 0)

        // 三条各自走完状态机发布
        let mine = draftStore.drafts.filter { $0.batchID == session.id }
        XCTAssertEqual(mine.count, 3)
        for draft in mine { try publish(draft.id) }

        store.reloadWithOverlay()
        let products = try ["生成色一字领OP", "粉紫色一字领OP", "蓝色一字领OP"].map { name in
            try XCTUnwrap(store.catalog?.products.first { $0.name == name },
                          "发布后应能按名字找到「\(name)」")
        }

        // ① 每个颜色各带自己的图（图片与 SKU 强关联的最终验收）
        let mainRefs = products.compactMap { product in
            product.images.first.flatMap { store.asset(id: $0)?.originalURL ?? $0 }
        }
        XCTAssertEqual(Set(mainRefs), ["local:gen.jpg", "local:pink.jpg", "local:blue.jpg"],
                       "三个颜色各有各的配色图，不能共用一张")

        // ② 款式公共资料：三色读到同一份面料 / 描述 / 尺码表
        let fabrics = Set(products.compactMap { store.fabric(forProduct: $0.id) })
        XCTAssertEqual(fabrics, ["100% 聚酯纤维"])
        let sizes = Set(products.map { store.sizeRun(forProduct: $0.id).joined(separator: ",") })
        XCTAssertEqual(sizes, ["M,L"], "尺码表是款式级：整款一份，三色读到同一张表")

        // ③ 价格各自生效（款式同价 → 三色都能读到同一笔预约价）
        for product in products {
            XCTAssertEqual(store.priceArchive(forProduct: product.id).currentReservationPrice,
                           Decimal(498))
        }
    }
}
