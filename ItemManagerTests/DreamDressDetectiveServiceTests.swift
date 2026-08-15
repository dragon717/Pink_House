import XCTest
@testable import ItemManager

final class DreamDressDetectiveServiceTests: XCTestCase {
  func testInputRequiresAtLeastOneField() {
    XCTAssertThrowsError(
      try DreamDressDetectiveService.validate(
        DreamDressDetectiveInput(brandName: " ", productName: "", productURL: "")
      )
    ) { error in
      XCTAssertEqual(error as? DreamDressDetectiveError, .emptyInput)
    }

    XCTAssertNoThrow(
      try DreamDressDetectiveService.validate(
        DreamDressDetectiveInput(brandName: "Angelic Pretty", productName: "", productURL: "")
      )
    )
  }

  func testURLValidationRejectsNonHTTPSAndPrivateHosts() {
    let invalidURLs = [
      "http://example.com/item",
      "javascript:alert(1)",
      "https://localhost/item",
      "https://127.0.0.1/item",
      "https://192.168.1.10/item",
      "https://10.0.0.8/item",
      "https://8.8.8.8/item",
      "https://[::1]/item",
    ]

    for value in invalidURLs {
      XCTAssertFalse(
        DreamDressDetectiveService.isAllowedHTTPSURL(URL(string: value)!),
        value
      )
    }

    XCTAssertTrue(
      DreamDressDetectiveService.isAllowedHTTPSURL(
        URL(string: "https://example.com/item")!
      )
    )
  }

  func testJSONLDProductGroupGraphArrayAndOffer() {
    let html = """
    <script type="application/ld+json">
    [
      {
        "@context":"https://schema.org",
        "@type":"ProductGroup",
        "name":"梦境花园 JSK",
        "brand":{"@type":"Brand","name":"Dream Brand"},
        "hasVariant":[
          {"@type":"Product","name":"梦境花园 JSK 黑色","offers":{"price":"399","priceCurrency":"CNY"}}
        ]
      },
      {
        "@context":"https://schema.org",
        "@graph":[
          {"@type":"Product","name":"月光花园 OP","offers":[{"price":599,"priceCurrency":"CNY"}]}
        ]
      }
    ]
    </script>
    """

    let candidates = DreamDressHTMLParser.parse(
      html: html,
      baseURL: URL(string: "https://example.com/products/dress")!
    )

    XCTAssertEqual(candidates.count, 3)
    XCTAssertEqual(candidates[0].title, "梦境花园 JSK")
    XCTAssertEqual(candidates[0].brand, "Dream Brand")
    XCTAssertEqual(candidates[0].evidenceType, .jsonLD)
    XCTAssertEqual(candidates[1].price, "399 CNY")
    XCTAssertEqual(candidates[2].price, "599 CNY")
  }

  func testOpenGraphAndTitleFallback() {
    let html = """
    <html>
      <head>
        <title>页面标题</title>
        <meta property="og:title" content="梦境花园 OP">
        <meta property="og:site_name" content="Dream Brand">
        <meta property="product:price:amount" content="699">
        <meta property="product:price:currency" content="CNY">
        <link rel="canonical" href="/products/moon-op">
      </head>
    </html>
    """

    let candidates = DreamDressHTMLParser.parse(
      html: html,
      baseURL: URL(string: "https://example.com/share")!
    )

    XCTAssertEqual(candidates.count, 1)
    XCTAssertEqual(candidates[0].title, "梦境花园 OP")
    XCTAssertEqual(candidates[0].brand, "Dream Brand")
    XCTAssertEqual(candidates[0].price, "699 CNY")
    XCTAssertEqual(candidates[0].sourceURL.absoluteString, "https://example.com/products/moon-op")
    XCTAssertEqual(candidates[0].evidenceType, .openGraph)
  }

  func testProductImageAvailabilityAndUnavailableOverride() {
    let baseURL = URL(string: "https://example.com/products/dress")!
    let activeHTML = """
    <meta property="og:image" content="https://cdn.example.com/fallback.jpg">
    <script type="application/ld+json">
    {
      "@type":"Product",
      "name":"梦境花园 JSK",
      "image":{"@type":"ImageObject","contentUrl":"https://cdn.example.com/dress.jpg"},
      "offers":{"price":"399","priceCurrency":"CNY","availability":"https://schema.org/InStock"}
    }
    </script>
    """

    let active = DreamDressHTMLParser.parse(html: activeHTML, baseURL: baseURL).first
    XCTAssertEqual(active?.imageURL, URL(string: "https://cdn.example.com/dress.jpg"))
    XCTAssertEqual(active?.availability, .available)

    let delisted = DreamDressHTMLParser.parse(
      html: activeHTML + "<main>商品已下架</main>",
      baseURL: baseURL
    ).first
    XCTAssertEqual(delisted?.availability, .delisted)
    XCTAssertEqual(DreamDressHTMLParser.availability(in: "已下架"), .delisted)
    XCTAssertEqual(DreamDressHTMLParser.availability(in: "卖掉了"), .sold)
    XCTAssertEqual(DreamDressHTMLParser.availability(in: "在线"), .available)
    XCTAssertLessThan(DreamDressAvailability.available.sortPriority, DreamDressAvailability.unknown.sortPriority)
    XCTAssertLessThan(DreamDressAvailability.unknown.sortPriority, DreamDressAvailability.sold.sortPriority)
  }

  func testMetadataSourceURLFallsBackWhenUnsafe() {
    let html = """
    <html>
      <head>
        <meta property="og:title" content="梦境花园 OP">
        <meta property="og:url" content="http://localhost/private">
        <link rel="canonical" href="javascript:alert(1)">
      </head>
    </html>
    """
    let baseURL = URL(string: "https://example.com/share")!

    let candidate = DreamDressHTMLParser.parse(html: html, baseURL: baseURL).first

    XCTAssertEqual(candidate?.sourceURL, baseURL)
  }

  func testProductMatcherRejectsSameNameCommunitySite() {
    let input = DreamDressDetectiveInput(brandName: "仲夏物语", productName: "", productURL: "")
    let candidate = DreamDressCandidate(
      title: "仲夏物语-二次元大咖直播+粉丝社群平台",
      brand: "仲夏物语",
      price: nil,
      sourceURL: URL(string: "https://www.zhongxiawuyu.com/")!,
      evidenceType: .openGraph
    )

    XCTAssertFalse(
      DreamDressProductMatcher.accepts(candidate, input: input, pageEvidence: candidate.title)
    )
    XCTAssertFalse(DreamDressProductMatcher.acceptsAIItem(isLolitaRelated: false, category: "other"))

    let genericDress = DreamDressCandidate(
      title: "日常连衣裙",
      brand: "Generic Fashion",
      category: "连衣裙",
      price: nil,
      sourceURL: URL(string: "https://example.com/products/floral-midi-dress")!,
      evidenceType: .jsonLD
    )
    XCTAssertFalse(
      DreamDressProductMatcher.accepts(
        genericDress,
        input: DreamDressDetectiveInput(brandName: "", productName: "", productURL: genericDress.sourceURL.absoluteString),
        pageEvidence: "Generic everyday fashion"
      )
    )
  }

  func testProductMatcherAcceptsTimeHallDressSemantics() {
    let input = DreamDressDetectiveInput(brandName: "Angelic Pretty", productName: "", productURL: "")
    let candidate = DreamDressCandidate(
      title: "Happy Treat Party JSK",
      brand: "Angelic Pretty",
      category: "吊带裙",
      price: "33000 JPY",
      sourceURL: URL(string: "https://example.com/products/happy-treat-party-jsk")!,
      evidenceType: .jsonLD
    )

    XCTAssertTrue(
      DreamDressProductMatcher.accepts(candidate, input: input, pageEvidence: "Angelic Pretty \(candidate.title)")
    )
    XCTAssertTrue(DreamDressProductMatcher.acceptsAIItem(isLolitaRelated: true, category: "jsk"))
    XCTAssertTrue(DreamDressProductMatcher.acceptsAIItem(isLolitaRelated: true, category: "accessory"))
  }

  func testProductMatcherAcceptsLolitaAccessoriesOnlyWithPageEvidence() {
    let input = DreamDressDetectiveInput(brandName: "", productName: "", productURL: "https://example.com/socks")
    let candidate = DreamDressCandidate(
      title: "Lolita Over-knee Socks with Ribbon",
      brand: nil,
      category: "socks",
      price: nil,
      sourceURL: URL(string: input.productURL)!,
      evidenceType: .jsonLD
    )

    XCTAssertTrue(DreamDressProductMatcher.accepts(candidate, input: input, pageEvidence: candidate.title))
    XCTAssertFalse(DreamDressProductMatcher.accepts(candidate, input: input, pageEvidence: "Generic shopping community"))

    let hallucinatedBrand = DreamDressCandidate(
      title: "仲夏物语 Lolita JSK",
      brand: "仲夏物语",
      category: "jsk",
      price: nil,
      sourceURL: candidate.sourceURL,
      evidenceType: .aiStructured
    )
    XCTAssertFalse(
      DreamDressProductMatcher.accepts(
        hallucinatedBrand,
        input: DreamDressDetectiveInput(brandName: "仲夏物语", productName: "", productURL: ""),
        pageEvidence: "Generic Lolita JSK page"
      )
    )
  }

  func testWebSearchTreatsBrandAndProductAsAlternativeHints() {
    let input = DreamDressDetectiveInput(brandName: "仲夏物语", productName: "喵果", productURL: "")
    let brandHit = DreamDressCandidate(
      title: "仲夏物语卢瓦尔葡萄园翻领短袖op+无腰jsk",
      brand: nil,
      price: nil,
      sourceURL: URL(string: "https://www.goofish.com/item?id=1001")!,
      evidenceType: .webSearch
    )
    let productHit = DreamDressCandidate(
      title: "仲夏梦境 喵果森林原创 Lolita",
      brand: nil,
      price: nil,
      sourceURL: URL(string: "https://www.goofish.com/item?id=1002")!,
      evidenceType: .webSearch
    )
    let unrelated = DreamDressCandidate(
      title: "其他品牌原创 Lolita",
      brand: nil,
      price: nil,
      sourceURL: URL(string: "https://www.goofish.com/item?id=1003")!,
      evidenceType: .webSearch
    )

    XCTAssertTrue(DreamDressProductMatcher.accepts(brandHit, input: input, pageEvidence: brandHit.title))
    XCTAssertTrue(DreamDressProductMatcher.accepts(productHit, input: input, pageEvidence: productHit.title))
    XCTAssertFalse(DreamDressProductMatcher.accepts(unrelated, input: input, pageEvidence: unrelated.title))

    let shop = DreamDressCandidate(
      title: "仲夏物语 shop 日常连衣裙",
      brand: nil,
      price: nil,
      sourceURL: URL(string: "https://www.goofish.com/item?id=1004")!,
      evidenceType: .webSearch
    )
    XCTAssertFalse(DreamDressProductMatcher.accepts(shop, input: input, pageEvidence: shop.title))
  }

  func testWebSearchResponseKeepsOnlyCommercePlatforms() {
    let data = Data(#"{"content":[{"type":"web_search_tool_result","content":[{"type":"web_search_result","title":"仲夏物语 Lolita JSK","url":"https://www.xiaohongshu.com/discovery/item/68ac7320000000001b0322ed"},{"type":"web_search_result","title":"闲鱼商品","url":"https://www.goofish.com/item?id=996331710109"},{"type":"web_search_result","title":"空闲鱼商品","url":"https://www.goofish.com/item?id="},{"type":"web_search_result","title":"淘宝列表","url":"https://www.taobao.com/list/item/3"},{"type":"web_search_result","title":"错误政策页","url":"https://www.cinic.org.cn/whys/wcpolicy/1262276.html"},{"type":"web_search_result","title":"伪淘宝","url":"https://eviltaobao.com/item.htm?id=3"},{"type":"web_search_tool_result_error","error_code":"max_uses_exceeded"}]}]}"#.utf8)

    XCTAssertEqual(
      DreamDressDetectiveService.webSearchURLs(from: data),
      [
        URL(string: "https://www.xiaohongshu.com/discovery/item/68ac7320000000001b0322ed")!,
        URL(string: "https://www.goofish.com/item?id=996331710109")!
      ]
    )
  }

  func testGoofishRenderingUsesMobileDetailPage() {
    XCTAssertEqual(
      DreamDressDynamicPageLoader.renderURL(
        for: URL(string: "https://www.goofish.com/item?id=1036081371539&categoryId=0")!
      ).absoluteString,
      "https://h5.m.goofish.com/item?id=1036081371539"
    )
  }

}
