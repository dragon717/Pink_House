//
//  ShopCatalogProductRenameTests.swift
//  ItemManagerTests
//
//  「改名」口径契约（2026-09-24 需求：修改名称后，相关信息未发生任何变化）。
//
//  用户三张截图（一步步可复现）：
//    ① 商品管理页长按「背心裙 [黄色]」→「编辑基础（名称/分类）」；
//    ② 「编辑商品」弹窗把名称改成「黄色蜜糖邦尼背心裙」→ 保存；
//    ③ **点菜式选购页的标题依然是「背心裙」** —— 看起来改名没生效。
//
//  根因（两处叠加）：展示侧所有标题只认 `designName`；写入侧只写 `name`，
//  而发布路径把 `designName` 写成了非空的显式值 → `name` 被永久遮蔽。
//
//  本套件锁死修复后的七条口径：
//    A. 款式名 = 名称剥离颜色词（名称字段仍是完整 SKU 名）。
//    B. 改名**扇出整款**：同款所有颜色一起改（含归档），否则一款拆成两款。
//    C. 兄弟颜色的名字定向替换，颜色词与其位置原样保留。
//    D. 品类也是款式级：随款式一起改（款式键含品类）。
//    E. 名称**没被改动**时沿用现有款式名，不重新派生（保护人工指定的存量款式名）。
//    F. 款式档案按新款式键**改键**（不是丢下变孤儿），目标键已有档案时无损合并。
//    G. 各界面标题（`ShopCatalogTitleResolver`）与归组键（`designKey`）改名后立刻跟上。
//

import XCTest
import SwiftData
@testable import ItemManager

// MARK: - 纯逻辑：改名计划

final class ShopCatalogProductRenameTests: XCTestCase {

    private func product(_ id: String,
                         name: String,
                         category: String = "JSK",
                         series: String = "s1",
                         designName: String? = nil,
                         archived: Bool = false) -> CatalogProduct {
        CatalogProduct(id: id, shopID: "shop1", seriesID: series, name: name,
                       category: category, images: [],
                       archivedAt: archived ? Date(timeIntervalSince1970: 0) : nil,
                       designName: designName)
    }

    /// 用户截图里那一款：背心裙 · 2 色（黄色 / 粉色）
    private var yellow: CatalogProduct { product("p-yellow", name: "黄色背心裙", designName: "背心裙") }
    private var pink: CatalogProduct { product("p-pink", name: "粉色背心裙", designName: "背心裙") }

    private func profile(_ id: String,
                         series: String = "s1",
                         category: String = "JSK",
                         design: String = "背心裙",
                         fabric: String? = nil,
                         description: String? = nil) -> CatalogStyleProfile {
        var p = CatalogStyleProfile(id: id, seriesID: series, category: category, designName: design)
        p.fabric = fabric
        p.styleDescription = description
        return p
    }

    // MARK: A. 款式名派生

    func testRenameDerivesDesignNameByStrippingTheColorWord() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, pink])

        XCTAssertEqual(plan.designNameBefore, "背心裙")
        XCTAssertEqual(plan.designNameAfter, "蜜糖邦尼背心裙",
                       "款式名 = 名称剥离颜色词 —— 这正是各界面标题将要显示的文字")
        XCTAssertEqual(plan.products.first?.name, "黄色蜜糖邦尼背心裙",
                       "名称字段保持用户输入的完整 SKU 名（含颜色词）")
    }

    func testRenameWithoutColorWordKeepsTheWholeNameAsDesignName() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow])

        XCTAssertEqual(plan.designNameAfter, "蜜糖邦尼背心裙",
                       "名称里没有颜色词时，款式名就是整名（baseName 原样回退）")
    }

    // MARK: B. 扇出整款

    func testRenameFansOutToEveryColorOfTheSameDesign() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, pink])

        XCTAssertEqual(plan.products.count, 2, "本人 + 同款其余颜色，一个都不能漏")
        XCTAssertEqual(plan.siblingCount, 1)
        XCTAssertEqual(plan.products.first?.id, yellow.id, "第 1 个恒为被编辑的那一个")

        let names = Dictionary(uniqueKeysWithValues: plan.products.map { ($0.id, $0.name) })
        XCTAssertEqual(names[pink.id], "粉色蜜糖邦尼背心裙", "兄弟颜色跟着改名，颜色词保留")
        XCTAssertTrue(plan.products.allSatisfy { $0.designName == "蜜糖邦尼背心裙" },
                      "整款同一个款式名 —— 否则 designKey 不同，一款会被拆成两款")
    }

    func testArchivedSiblingIsRenamedToo() {
        let archivedPink = product("p-pink", name: "粉色背心裙", designName: "背心裙", archived: true)
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, archivedPink])

        XCTAssertEqual(plan.siblingCount, 1,
                       "归档颜色若留在旧款名上，等它被复活时就会把一款拆成两款")
        XCTAssertEqual(plan.products.first(where: { $0.id == archivedPink.id })?.designName,
                       "蜜糖邦尼背心裙")
    }

    func testOtherDesignsAndOtherSeriesAreNotTouched() {
        let anotherDesign = product("p-other", name: "粉色片裁JSK", designName: "片裁JSK")
        let sameNameOtherSeries = product("p-cross", name: "粉色背心裙", series: "s2",
                                         designName: "背心裙")
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, pink, anotherDesign, sameNameOtherSeries])

        XCTAssertEqual(Set(plan.products.map(\.id)), [yellow.id, pink.id],
                       "只改同系列同款 —— 别的款式、别的系列下的同名款都不许被波及")
    }

    // MARK: C. 兄弟颜色的名字

    func testSiblingColorWordAndItsPositionSurvive() {
        // 颜色词在款名之后的历史写法
        let suffixStyle = product("p-suffix", name: "背心裙粉色", designName: "背心裙")
        XCTAssertEqual(ShopCatalogProductRename.renamedName(oldName: "背心裙粉色",
                                                           designBefore: "背心裙",
                                                           designAfter: "蜜糖邦尼背心裙"),
                       "蜜糖邦尼背心裙粉色",
                       "定向替换不得把颜色词的位置搬走")

        // 颜色词在前（录入端口径）
        XCTAssertEqual(ShopCatalogProductRename.renamedName(oldName: "粉色背心裙",
                                                           designBefore: "背心裙",
                                                           designAfter: "蜜糖邦尼背心裙"),
                       "粉色蜜糖邦尼背心裙")

        // 旧名里找不到旧款名（历史脏数据）：用颜色词兜住「这一条是哪个颜色」
        XCTAssertEqual(ShopCatalogProductRename.renamedName(oldName: "粉色",
                                                           designBefore: "背心裙",
                                                           designAfter: "蜜糖邦尼背心裙"),
                       "粉色蜜糖邦尼背心裙")
    }

    func testRenamedSiblingKeepsItsColorLabel() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, pink, product("p-suffix", name: "背心裙薄荷色", designName: "背心裙")])

        for renamed in plan.products {
            let before = [yellow, pink, product("p-suffix", name: "背心裙薄荷色", designName: "背心裙")]
                .first { $0.id == renamed.id }
            XCTAssertEqual(ShopCatalogColorPresentation.derivedLabel(forName: renamed.name),
                           ShopCatalogColorPresentation.derivedLabel(forName: before?.name ?? ""),
                           "改名不得把颜色标签弄丢或换成别的颜色：\(renamed.name)")
        }
    }

    // MARK: D. 品类也是款式级

    func testRenameCarriesTheCategoryToTheWholeDesign() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "OP",
            among: [yellow, pink])

        XCTAssertEqual(plan.categoryAfter, "OP")
        XCTAssertTrue(plan.products.allSatisfy { $0.category == "OP" },
                      "designKey 含品类 —— 只改一个颜色的品类同样会拆组")
    }

    // MARK: E. 名称没改就不碰款式名

    func testUntouchedNameKeepsTheExplicitDesignName() {
        // 存量里真实存在「款式名 ≠ 名称剥离颜色词」的人工命名
        let legacy = product("p-legacy", name: "粉色款", designName: "花花款")
        let plan = ShopCatalogProductRename.plan(
            product: legacy,
            newName: "粉色款",              // 名称没动
            newCategory: "OP",              // 只改品类
            among: [legacy])

        XCTAssertEqual(plan.designNameAfter, "花花款",
                       "名称没被改动时不得重新派生款式名 —— 那会把人工命名无声改掉")
        XCTAssertFalse(plan.changesDesignName)
        XCTAssertTrue(plan.changesCategory)
    }

    // MARK: F. 款式档案改键

    func testStyleProfileIsRekeyedInsteadOfOrphaned() {
        let old = profile(ShopCatalogStyleProfileSharing.styleKey(seriesID: "s1", category: "JSK",
                                                                 designName: "背心裙"),
                          fabric: "雪花提花布 + 蕾丝拼接",
                          description: "高腰 A 字")
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, pink],
            profiles: [old])

        XCTAssertEqual(plan.styleProfile.removals, [old.id], "旧款式键的档案行必须清掉")
        let migrated = try? XCTUnwrap(plan.styleProfile.upserts.first)
        XCTAssertEqual(migrated?.id,
                       ShopCatalogStyleProfileSharing.styleKey(seriesID: "s1", category: "JSK",
                                                              designName: "蜜糖邦尼背心裙"),
                       "款式档案的 id 就是款式键 —— 改名等于换主键")
        XCTAssertEqual(migrated?.designName, "蜜糖邦尼背心裙")
        XCTAssertEqual(migrated?.fabric, "雪花提花布 + 蕾丝拼接", "面料必须跟着走，不许丢")
        XCTAssertEqual(migrated?.styleDescription, "高腰 A 字")
    }

    func testStyleProfileMergesLosslesslyWhenTargetKeyAlreadyExists() {
        let oldKey = ShopCatalogStyleProfileSharing.styleKey(seriesID: "s1", category: "JSK",
                                                            designName: "背心裙")
        let newKey = ShopCatalogStyleProfileSharing.styleKey(seriesID: "s1", category: "JSK",
                                                            designName: "蜜糖邦尼背心裙")
        let source = profile(oldKey, fabric: "雪花提花布", description: nil)
        // 目标键上已有档案：改名后两者是同一款，不许留下两条同键行
        let target = profile(newKey, design: "蜜糖邦尼背心裙",
                            description: "已有的款式描述")

        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow],
            profiles: [source, target])

        XCTAssertEqual(plan.styleProfile.upserts.count, 1, "同键只允许一条，否则读取侧变成随机胜负")
        XCTAssertEqual(plan.styleProfile.upserts.first?.id, newKey)
        XCTAssertEqual(plan.styleProfile.upserts.first?.fabric, "雪花提花布", "目标缺失的字段要补上")
        XCTAssertEqual(plan.styleProfile.upserts.first?.styleDescription, "已有的款式描述",
                       "目标已有的值优先，不被覆盖")
        XCTAssertEqual(plan.styleProfile.removals, [oldKey], "只删旧键")
    }

    func testEmptyStyleProfileIsRemovedWithoutWritingAShell() {
        let oldKey = ShopCatalogStyleProfileSharing.styleKey(seriesID: "s1", category: "JSK",
                                                            designName: "背心裙")
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow],
            profiles: [profile(oldKey)])            // 面料与描述都空

        XCTAssertEqual(plan.styleProfile.removals, [oldKey])
        XCTAssertTrue(plan.styleProfile.upserts.isEmpty, "空档案只删不写，不留空壳行")
    }

    func testNoProfileMigrationWhenNothingChanged() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色背心裙",                   // 名称原样
            newCategory: "JSK",
            among: [yellow, pink],
            profiles: [profile(ShopCatalogStyleProfileSharing.styleKey(seriesID: "s1",
                                                                      category: "JSK",
                                                                      designName: "背心裙"),
                               fabric: "雪花提花布")])

        XCTAssertTrue(plan.isNoop)
        XCTAssertTrue(plan.styleProfile.removals.isEmpty)
        XCTAssertTrue(plan.styleProfile.upserts.isEmpty, "没改就不该动款式档案（避免无谓改键）")
    }

    // MARK: G. 标题与归组立刻跟上（用户看到的就是这两条）

    func testTitlesFollowTheRenamedDesign() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, pink])

        let renamedYellow = plan.products.first { $0.id == yellow.id }!
        let renamedPink = plan.products.first { $0.id == pink.id }!
        let titled = ShopCatalogTitleResolver.title(product: renamedYellow, siblings: [renamedPink])

        XCTAssertEqual(titled.text, "蜜糖邦尼背心裙",
                       "这就是点菜页 / 详情页 / 商品管理行会显示的文字")
        XCTAssertEqual(titled.colorCount, 2)
        XCTAssertNotEqual(titled.text, ShopCatalogTitleResolver.title(product: yellow, siblings: [pink]).text,
                          "改名前后标题必须不同 —— 旧行为下两者**完全相同**，正是用户报的 bug")
    }

    func testDesignKeyStaysOneGroupAfterRename() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, pink])

        let keys = Set(plan.products.map { ShopCatalogSameDesignGrouper.designKey(of: $0) })
        XCTAssertEqual(keys, ["JSK|蜜糖邦尼背心裙"], "整款必须落在同一个款式键上，不许拆组")
    }

    // MARK: 弹窗预览文案

    func testPreviewShowsDesignNameChangeAndAffectedColors() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "黄色蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow, pink])

        let text = ShopCatalogProductRename.previewText(plan, typedName: "黄色蜜糖邦尼背心裙")
        XCTAssertEqual(text?.contains("背心裙 → 蜜糖邦尼背心裙"), true,
                       "改名前必须让用户看见款式名会变成什么")
        XCTAssertEqual(text?.contains("1 个颜色"), true, "影响范围也要说清楚")
        XCTAssertEqual(text?.contains("颜色标签：黄色"), true, "标题不含颜色，颜色另立标签要讲明白")
    }

    func testPreviewWarnsWhenTheNewNameHasNoColorWord() {
        let plan = ShopCatalogProductRename.plan(
            product: yellow,
            newName: "蜜糖邦尼背心裙",
            newCategory: "JSK",
            among: [yellow])

        let text = ShopCatalogProductRename.previewText(plan, typedName: "蜜糖邦尼背心裙")
        XCTAssertEqual(text?.contains("没有颜色词"), true,
                       "新名没有颜色词会让颜色标签消失 —— 不许静默")
    }

    func testReferenceNoteIsSilentWhenNothingIsReferenced() {
        XCTAssertNil(ShopCatalogProductRename.referenceNote(referencedRecordCount: 0))
        XCTAssertEqual(ShopCatalogProductRename.referenceNote(referencedRecordCount: 2)?
            .contains("2 条记录"), true,
                       "衣橱 / 心愿记录不跟着改名，但必须如实告知条数")
    }
}

// MARK: - 端到端：真实 Store + 真实发布链路
//
//  纯逻辑测不到「接线」：`renameProduct` / `updatePublishedProduct` 是否真的整款扇出、
//  款式档案是否真的改键后仍读得到、尺码表共享是否没被改键弄断。

@MainActor
final class ShopCatalogProductRenameStoreTests: XCTestCase {

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

    /// 走完状态机并发布，返回新建商品的 id（`publish` 的返回值是给人看的摘要，不是 id）
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

    private func draft(name: String, withChart: Bool = false) -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.name = name
        draft.category = "JSK"
        draft.newShopName = "改名验证店家"
        draft.newSeriesName = "改名验证系列"
        draft.price = 399
        if withChart {
            var chart = CatalogSizeChart(id: "", productID: "")
            chart.columns = ["S", "M", "L"]
            chart.rows = [CatalogSizeRow(label: "胸围", values: ["80", "84", "88"])]
            draft.sizeChart = chart
        }
        return draft
    }

    /// 同款两色（黄色 / 粉色）：款式名由名字派生 = 「背心裙」
    private func publishPair(withChart: Bool = false) throws -> (yellow: String, pink: String) {
        let yellowID = try publishNew(draft(name: "黄色背心裙", withChart: withChart))
        let pinkID = try publishNew(draft(name: "粉色背心裙"))
        return (yellowID, pinkID)
    }

    private func designName(of productID: String) -> String? {
        store.catalog?.products.first { $0.id == productID }
            .map { ShopCatalogSameDesignGrouper.designName(of: $0) }
    }

    func testRenameFansOutToEveryColorAndKeepsIDs() throws {
        let ids = try publishPair()
        XCTAssertEqual(designName(of: ids.yellow), "背心裙")
        XCTAssertEqual(designName(of: ids.pink), "背心裙")

        let plan = try ShopCatalogDraftStore.renameProduct(productID: ids.yellow,
                                                           newName: "黄色蜜糖邦尼背心裙",
                                                           newCategory: "JSK")
        store.reloadWithOverlay()

        XCTAssertEqual(plan.designNameAfter, "蜜糖邦尼背心裙")
        XCTAssertEqual(designName(of: ids.yellow), "蜜糖邦尼背心裙",
                       "被编辑的那一个颜色，款式名必须真的落库")
        XCTAssertEqual(designName(of: ids.pink), "蜜糖邦尼背心裙",
                       "同款其余颜色也要跟着落库 —— 否则一款拆成两款")
        XCTAssertEqual(store.product(id: ids.yellow)?.name, "黄色蜜糖邦尼背心裙")
        XCTAssertEqual(store.product(id: ids.pink)?.name, "粉色蜜糖邦尼背心裙")
        XCTAssertNotNil(store.product(id: ids.yellow), "id 不变，用户引用不受影响")
    }

    func testTitleOnTheMenuPageChangesAfterRename() throws {
        let ids = try publishPair()
        let pinkBefore = try XCTUnwrap(store.product(id: ids.pink))
        XCTAssertEqual(ShopCatalogTitleResolver.title(product: pinkBefore, siblings: []).text, "背心裙")

        try ShopCatalogDraftStore.renameProduct(productID: ids.yellow,
                                               newName: "黄色蜜糖邦尼背心裙",
                                               newCategory: "JSK")
        store.reloadWithOverlay()

        // 点菜式选购页的卡片标题取「该款式第一个商品」的 designName
        let siblings = (store.catalog?.products ?? []).filter { $0.seriesID == pinkBefore.seriesID }
        let title = try XCTUnwrap(ShopCatalogTitleResolver.title(products: siblings))
        XCTAssertEqual(title.text, "蜜糖邦尼背心裙",
                       "点菜页卡片标题 = 款式名，改名后必须跟着变（用户截图里那一处）")
    }

    func testStyleProfileSurvivesRenameByRekeying() throws {
        let ids = try publishPair()
        try ShopCatalogDraftStore.updateStylePublicInfo(fabric: "雪花提花布",
                                                       styleDescription: "高腰 A 字",
                                                       sizeChart: nil,
                                                       forProductID: ids.yellow)
        store.reloadWithOverlay()
        XCTAssertEqual(store.fabric(forProduct: ids.pink), "雪花提花布", "同款两色共享一份")

        try ShopCatalogDraftStore.renameProduct(productID: ids.yellow,
                                               newName: "黄色蜜糖邦尼背心裙",
                                               newCategory: "JSK")
        store.reloadWithOverlay()

        XCTAssertEqual(store.fabric(forProduct: ids.yellow), "雪花提花布",
                       "改名后款式档案必须改键跟过来，不许变孤儿（表现为「改个名字面料就空白了」）")
        XCTAssertEqual(store.fabric(forProduct: ids.pink), "雪花提花布")
        XCTAssertEqual(store.styleDescription(forProduct: ids.pink), "高腰 A 字")
    }

    func testSizeChartSharingIsNotBrokenByRename() throws {
        let ids = try publishPair(withChart: true)
        XCTAssertEqual(store.sizeRun(forProduct: ids.pink), ["S", "M", "L"],
                       "同款共享：黄色填过，粉色也应看到")

        try ShopCatalogDraftStore.renameProduct(productID: ids.yellow,
                                               newName: "黄色蜜糖邦尼背心裙",
                                               newCategory: "JSK")
        store.reloadWithOverlay()

        XCTAssertEqual(store.sizeRun(forProduct: ids.yellow), ["S", "M", "L"],
                       "改名不得把尺码表的款式共享范围弄断")
        XCTAssertEqual(store.sizeRun(forProduct: ids.pink), store.sizeRun(forProduct: ids.yellow),
                       "两色外侧尺码必须依旧逐字一致")
    }

    func testDeepEditRenameAlsoFansOutToTheWholeStyle() throws {
        let ids = try publishPair()
        let yellow = try XCTUnwrap(store.product(id: ids.yellow))

        var updated = yellow
        updated.name = "黄色蜜糖邦尼背心裙"
        let plan = try ShopCatalogDraftStore.updatePublishedProduct(
            updated, assets: [], variants: [], sizeChart: nil)
        store.reloadWithOverlay()

        XCTAssertEqual(plan.designNameAfter, "蜜糖邦尼背心裙")
        XCTAssertEqual(designName(of: ids.pink), "蜜糖邦尼背心裙",
                       "深度编辑改名与「编辑基础」同名，也必须整款扇出（两条入口不许分叉）")
    }

    func testUntouchedNameDuringDeepEditKeepsDesignNameStable() throws {
        let ids = try publishPair()
        let pink = try XCTUnwrap(store.product(id: ids.pink))

        // 只改图片 → 名称原样：款式名不得被重新派生
        try ShopCatalogDraftStore.updatePublishedProduct(pink, assets: [], variants: [],
                                                        sizeChart: nil)
        store.reloadWithOverlay()

        XCTAssertEqual(designName(of: ids.pink), "背心裙", "不动名称就不动款式名")
        XCTAssertEqual(designName(of: ids.yellow), "背心裙")
    }
}
