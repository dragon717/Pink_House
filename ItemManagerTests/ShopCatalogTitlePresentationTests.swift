//
//  ShopCatalogTitlePresentationTests.swift
//  ItemManagerTests
//
//  商品标题 / 颜色呈现口径契约（2026-09-23 用户反馈：
//  「我们内外的标题应当保持一致，仅在颜色上加以区分，因为其他方面完全相同。」）
//
//  现象：同一个商品
//    · 商品详情页标题 → 「红色大蝴蝶结背心裙」（整名，含颜色）
//    · 点菜式选购卡片 → 「大蝴蝶结背心裙 · 2 色」（款名 + 色数）
//  同款不同色只是颜色不同，两处标题不该长得不一样。
//
//  本套测试锁死口径（`ShopCatalogTitlePresentation.swift`）：
//    A. 标题文字**永远等于款式名**，与商品名里的颜色词无关 → 同款各颜色标题逐字相同。
//    B. 同款颜色数 > 1 才有「· N 色」标注；单色不得出现标注（也不得出现 0 色）。
//    C. 颜色**单独呈现**，取值唯一口径：显式规格色 → 名称颜色词 → nil。
//       名称里没有颜色词时**必须 nil**，不许拿整个款名当颜色（否则标题与颜色同时退化）。
//    D. 有意保留的例外：写进心愿尾款 / 衣橱的**记录名**带颜色（用 `product.name`），
//       所以「标题 ≠ 商品名」本身就是这条口径的可见证据。
//

import XCTest
@testable import ItemManager

final class ShopCatalogTitlePresentationTests: XCTestCase {

    private func product(id: String = "p1",
                         name: String,
                         category: String = "JSK",
                         seriesID: String = "s1",
                         designName: String? = nil,
                         archived: Bool = false) -> CatalogProduct {
        CatalogProduct(id: id, shopID: "shop1", seriesID: seriesID, name: name,
                       category: category, images: [],
                       archivedAt: archived ? Date(timeIntervalSince1970: 0) : nil,
                       designName: designName)
    }

    // MARK: A. 标题 = 款式名（本次反馈的核心）

    func testTitleTextStripsColorFromProductName() {
        let red = product(name: "红色大蝴蝶结背心裙")
        let pink = product(id: "p2", name: "粉色大蝴蝶结背心裙")

        let title = ShopCatalogTitleResolver.title(product: red, siblings: [pink])

        XCTAssertEqual(title.text, "大蝴蝶结背心裙",
                       "标题必须是款式名——颜色不参与标题文字")
        XCTAssertEqual(title.colorCount, 2)
        XCTAssertTrue(title.showsColorCount)
    }

    func testSameDesignDifferentColorsProduceIdenticalTitleText() {
        let red = product(name: "红色大蝴蝶结背心裙")
        let pink = product(id: "p2", name: "粉色大蝴蝶结背心裙")
        let black = product(id: "p3", name: "黑色大蝴蝶结背心裙")

        let redTitle = ShopCatalogTitleResolver.title(product: red, siblings: [pink, black])
        let pinkTitle = ShopCatalogTitleResolver.title(product: pink, siblings: [red, black])

        XCTAssertEqual(redTitle.text, pinkTitle.text,
                       "同款各颜色在详情页/点菜页看到的标题必须逐字相同——这正是「内外一致」")
        XCTAssertEqual(redTitle.colorCount, 3)
        XCTAssertEqual(pinkTitle.colorCount, 3)
    }

    func testExplicitDesignNameWinsOverDerivedName() {
        let p = product(name: "红色大蝴蝶结背心裙", designName: "大蝴蝶结背心裙（复刻）")

        let title = ShopCatalogTitleResolver.title(product: p, siblings: [])

        XCTAssertEqual(title.text, "大蝴蝶结背心裙（复刻）",
                       "显式款式名优先，派生只作兜底")
    }

    func testNameWithoutColorWordKeepsWholeNameAsTitle() {
        let p = product(name: "大蝴蝶结背心裙")

        let title = ShopCatalogTitleResolver.title(product: p, siblings: [])

        XCTAssertEqual(title.text, "大蝴蝶结背心裙", "剥离不出颜色词时款名回退原名")
        XCTAssertEqual(title.colorCount, 1)
    }

    // MARK: B. 「· N 色」标注只在同款多色时出现

    func testSingleColorHasNoCountAnnotation() {
        let title = ShopCatalogTitleResolver.title(product: product(name: "红色大蝴蝶结背心裙"),
                                                   siblings: [])

        XCTAssertEqual(title.colorCount, 1)
        XCTAssertFalse(title.showsColorCount)
        XCTAssertNil(title.colorCountText, "单色商品不得出现「· 1 色」这种噪声标注")
        XCTAssertFalse(title.isMultiColor)
    }

    func testColorCountAnnotationTextMatchesMenuCardStyle() {
        let title = ShopCatalogTitleResolver.title(products: [
            product(name: "红色大蝴蝶结背心裙"),
            product(id: "p2", name: "粉色大蝴蝶结背心裙"),
        ])

        XCTAssertEqual(title?.colorCountText, "· 2 色",
                       "标注文案与点菜页卡片完全一致（含前导分隔符）")
        XCTAssertTrue(title?.isMultiColor == true)
    }

    func testTitleFromGroupUsesFirstProductDesignNameAndGroupSize() {
        let group = [
            product(name: "红色大蝴蝶结背心裙"),
            product(id: "p2", name: "粉色大蝴蝶结背心裙"),
            product(id: "p3", name: "黑色大蝴蝶结背心裙"),
        ]

        let title = ShopCatalogTitleResolver.title(products: group)

        XCTAssertEqual(title?.text, "大蝴蝶结背心裙")
        XCTAssertEqual(title?.colorCount, 3)
    }

    func testEmptyGroupHasNoTitle() {
        XCTAssertNil(ShopCatalogTitleResolver.title(products: []),
                     "空集合不给标题，避免调用方拿到空字符串标题")
    }

    func testColorCountNeverDropsBelowOne() {
        let title = ShopCatalogProductTitle(text: "背心裙", colorCount: 0)

        XCTAssertEqual(title.colorCount, 1, "颜色数下限为 1（自己），不会出现 0 色")
        XCTAssertNil(title.colorCountText)
    }

    // MARK: C. 颜色单独呈现（唯一取值口径）

    func testExplicitVariantColorWinsOverNameDerivedColor() {
        let label = ShopCatalogColorPresentation.label(explicitColors: ["樱花粉"],
                                                       name: "红色大蝴蝶结背心裙")

        XCTAssertEqual(label, "樱花粉", "显式规格色是权威来源，优先于名称里的颜色词")
    }

    func testDerivedColorFromProductName() {
        let label = ShopCatalogColorPresentation.label(explicitColors: [],
                                                       name: "红色大蝴蝶结背心裙")

        XCTAssertEqual(label, "红色")
    }

    func testCompoundColorTakesLongestMatch() {
        let label = ShopCatalogColorPresentation.label(explicitColors: [],
                                                       name: "酒红色大蝴蝶结背心裙")

        XCTAssertEqual(label, "酒红色", "复合色词优先（「酒红色」不得被拆成「红色」）")
    }

    func testNoColorWordReturnsNilInsteadOfWholeName() {
        let label = ShopCatalogColorPresentation.label(explicitColors: [],
                                                       name: "大蝴蝶结背心裙")

        XCTAssertNil(label,
                     "名称里没有颜色词时必须 nil —— 拿整名当颜色会让标题和颜色同时变成款名")
    }

    func testBlankExplicitColorsAreIgnoredAndFallBackToName() {
        let label = ShopCatalogColorPresentation.label(explicitColors: ["", "   "],
                                                       name: "粉色大蝴蝶结背心裙")

        XCTAssertEqual(label, "粉色", "空白规格色不算数，继续往下取名称颜色词")
    }

    func testSelectionRecordColorIsNeverTheWholeName() {
        // 加购时写进心愿/衣橱记录的颜色必须是一个真颜色，不能是款名兜底
        let red = product(name: "红色大蝴蝶结背心裙")
        let label = ShopCatalogColorPresentation.label(explicitColors: [], name: red.name)

        XCTAssertEqual(label, "红色")
        XCTAssertNotEqual(label, red.name)
    }

    // MARK: D. 标题 ≠ 商品名（记录名保留颜色的可见证据）

    func testTitleDiffersFromProductNameForColoredProduct() {
        let p = product(name: "红色大蝴蝶结背心裙")

        let title = ShopCatalogTitleResolver.title(product: p, siblings: [])

        XCTAssertNotEqual(title.text, p.name,
                          "挑款用的标题（款式名）与写进心愿/衣橱的记录名（含颜色的整名）"
                          + "是两个口径：前者不带颜色，后者必须带颜色")
        XCTAssertTrue(p.name.contains("红色"), "记录名仍带颜色——这条是本口径有意保留的例外")
    }

    func testColorLabelIsNeverEqualToTitleForSameProduct() {
        let p = product(name: "黑色大蝴蝶结背心裙")

        let title = ShopCatalogTitleResolver.title(product: p, siblings: [])
        let color = ShopCatalogColorPresentation.label(explicitColors: [], name: p.name)

        XCTAssertNotEqual(color, title.text,
                          "颜色标注与标题不能是同一条文字（否则颜色等于没呈现）")
    }
}
