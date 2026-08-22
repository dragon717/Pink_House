import XCTest
@testable import ItemManager

final class DreamDressDetectiveServiceTests: XCTestCase {

  @MainActor
  func testLivePinkHouseReturnsValidatedImages() async throws {
    guard ProcessInfo.processInfo.environment["RUN_DREAM_DRESS_LIVE"] == "1" else {
      throw XCTSkip("Set RUN_DREAM_DRESS_LIVE=1 for the opt-in network test.")
    }

    let result = try await DreamDressDetectiveService.shared.investigate(
      DreamDressDetectiveInput(brandName: "pink house", productName: "", productURL: ""),
      forceRefresh: true
    )

    XCTAssertGreaterThan(result.foundCount, 1)
    XCTAssertEqual(result.allCandidates.count, result.foundCount)
    XCTAssertGreaterThan(result.validCandidates.count, 1)
    XCTAssertTrue(result.validCandidates.allSatisfy { $0.imageURL != nil })
    XCTAssertFalse(result.isFromCache)

    let cached = try await DreamDressDetectiveService.shared.investigate(
      DreamDressDetectiveInput(brandName: "pink house", productName: "", productURL: "")
    )
    XCTAssertTrue(cached.isFromCache)
    XCTAssertEqual(cached.validCandidates, result.validCandidates)
  }

  func testYahooAuctionSearchPageExtractsDistinctProductsWithImages() {
    let html = #"""
    <a data-auction-id="x1240942804"
       data-auction-title="PINK HOUSE キャミソールワンピース"
       data-auction-img="https://auc-pctr.c.yimg.jp/example.jpg?pri=l&amp;w=300"
       data-auction-price="29000"></a>
    <a data-auction-id="x1240942804"
       data-auction-title="PINK HOUSE キャミソールワンピース"
       data-auction-img="https://auc-pctr.c.yimg.jp/example.jpg"
       data-auction-price="29000"></a>
    """#
    let candidates = DreamDressDetectiveService.yahooAuctionCandidates(
      from: html,
      input: DreamDressDetectiveInput(brandName: "pink house", productName: "", productURL: "")
    )

    XCTAssertEqual(candidates.count, 1)
    XCTAssertEqual(candidates[0].price, "¥29000")
    XCTAssertEqual(candidates[0].sourceURL.absoluteString, "https://auctions.yahoo.co.jp/jp/auction/x1240942804")
    XCTAssertEqual(candidates[0].imageURL?.query, "pri=l&w=300")
  }

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

  func testMatcherIgnoresSpacingCaseWidthAndPunctuation() {
    let candidate = DreamDressCandidate(
      title: "PINKHOUSE Floral JSK",
      brand: "PINKHOUSE",
      price: nil,
      sourceURL: URL(string: "https://www.goofish.com/item?id=1005")!,
      evidenceType: .webSearch
    )

    XCTAssertTrue(
      DreamDressProductMatcher.accepts(
        candidate,
        input: DreamDressDetectiveInput(brandName: "Ｐｉｎｋ House", productName: "", productURL: ""),
        pageEvidence: candidate.title
      )
    )
    XCTAssertEqual(
      DreamDressProductMatcher.normalizedSearchText("Pink-House"),
      DreamDressProductMatcher.normalizedSearchText("PINK HOUSE")
    )
  }

  func testSearchQueriesAddCompactCamelCaseAndMixedScriptVariants() {
    XCTAssertEqual(
      DreamDressDetectiveService.queryVariants(for: "Pink House"),
      ["Pink House", "PinkHouse", "ピンクハウス"]
    )
    XCTAssertEqual(
      DreamDressDetectiveService.queryVariants(for: "PinkHouse"),
      ["PinkHouse", "Pink House", "ピンクハウス"]
    )
    XCTAssertEqual(
      DreamDressDetectiveService.queryVariants(for: "拼客house"),
      ["拼客house", "拼客 house"]
    )
    XCTAssertEqual(
      DreamDressDetectiveService.searchQueries(
        for: DreamDressDetectiveInput(brandName: "仲夏物语", productName: "", productURL: "")
      ),
      [
        "仲夏物语 闲鱼 goofish 二手 在售 裙",
        "仲夏物语 淘宝 天猫 商品 价格 详情 裙",
        "仲夏物语 小红书 出物 穿搭 裙",
        "仲夏物语 抖音商城 今日头条 商品 价格 裙",
        "仲夏物语 裙 连衣裙 スカート ワンピース 二手 中古",
        "仲夏物语 Mercari メルカリ 中古 スカート ワンピース",
        "仲夏物语 Yahoo!オークション ヤフオク 中古 スカート ワンピース",
        "仲夏物语 楽天市場 公式 通販 スカート ワンピース"
      ]
    )
  }

  func testCacheFreshnessAndSearchTitlePriceExtraction() {
    let now = Date(timeIntervalSince1970: 10_000)
    XCTAssertTrue(
      DreamDressDetectiveService.isCacheFresh(
        lastCheckedAt: now.addingTimeInterval(-21_599),
        now: now
      )
    )
    XCTAssertFalse(
      DreamDressDetectiveService.isCacheFresh(
        lastCheckedAt: now.addingTimeInterval(-21_600),
        now: now
      )
    )
    XCTAssertEqual(DreamDressDetectiveService.price(in: "PINK HOUSE 半身裙 ￥12,800 在售"), "￥12,800")
    XCTAssertEqual(DreamDressDetectiveService.price(in: "闲鱼出物 899元"), "899元")

    let candidate = DreamDressCandidate(
      title: "PINK HOUSE 半身裙",
      brand: "PINK HOUSE",
      price: "￥12,800",
      imageURL: URL(string: "https://example.com/image.jpg"),
      sourceURL: URL(string: "https://example.com/item/1")!,
      evidenceType: .webSearch
    )
    XCTAssertNoThrow(try JSONEncoder().encode(candidate))
  }

  func testMatcherAcceptsPinkHouseJapaneseAlias() {
    let candidate = DreamDressCandidate(
      title: "ピンクハウス ロングスカート 中古",
      brand: "PINK HOUSE",
      price: nil,
      sourceURL: URL(string: "https://zenmarket.jp/cn/auction.aspx?itemCode=b1235204357")!,
      evidenceType: .webSearch
    )

    XCTAssertTrue(
      DreamDressProductMatcher.accepts(
        candidate,
        input: DreamDressDetectiveInput(brandName: "pink house", productName: "", productURL: ""),
        pageEvidence: candidate.title
      )
    )

    XCTAssertTrue(
      DreamDressProductMatcher.accepts(
        DreamDressCandidate(
          title: "PINK HOUSE 花卉圖案背帶裙/連身褲",
          brand: "PINK HOUSE",
          price: nil,
          sourceURL: URL(string: "https://zenmarket.jp/tw/auction.aspx?itemCode=c1084819827")!,
          evidenceType: .webSearch
        ),
        input: DreamDressDetectiveInput(brandName: "pink house", productName: "", productURL: ""),
        pageEvidence: "PINK HOUSE 花卉圖案背帶裙/連身褲"
      )
    )
  }

  func testWebSearchResponseKeepsOnlyCommercePlatforms() {
    let data = Data(#"{"content":[{"type":"web_search_tool_result","content":[{"type":"web_search_result","title":"仲夏物语 Lolita JSK","url":"https://www.xiaohongshu.com/discovery/item/68ac7320000000001b0322ed"},{"type":"web_search_result","title":"闲鱼商品","url":"https://www.goofish.com/item?id=996331710109"},{"type":"web_search_result","title":"抖音旧详情","url":"https://www.douyin.com/shipin/7294111986865621011"},{"type":"web_search_result","title":"空闲鱼商品","url":"https://www.goofish.com/item?id="},{"type":"web_search_result","title":"淘宝列表","url":"https://www.taobao.com/list/item/3"},{"type":"web_search_result","title":"错误政策页","url":"https://www.cinic.org.cn/whys/wcpolicy/1262276.html"},{"type":"web_search_result","title":"伪淘宝","url":"https://eviltaobao.com/item.htm?id=3"},{"type":"web_search_tool_result_error","error_code":"max_uses_exceeded"}]}]}"#.utf8)

    XCTAssertEqual(
      DreamDressDetectiveService.webSearchURLs(from: data),
      [
        URL(string: "https://www.xiaohongshu.com/discovery/item/68ac7320000000001b0322ed")!,
        URL(string: "https://www.goofish.com/item?id=996331710109")!,
        URL(string: "https://www.douyin.com/shipin/7294111986865621011")!
      ]
    )
  }

  func testWebSearchResponseAlsoKeepsTrustedProductCatalogs() {
    let data = Data(#"{"content":[{"type":"web_search_tool_result","content":[{"type":"web_search_result","title":"仲夏物语 天使花束 Lolita JSK","url":"https://wiki.smzdm.com/p/vmqnxdp/"},{"type":"web_search_result","title":"弥尔顿花园罩裙 | 仲夏物语 Lolita","url":"https://qiandao.com/spu?id=730921631832250082"},{"type":"web_search_result","title":"空图鉴","url":"https://qiandao.com/spu?id="},{"type":"web_search_result","title":"弥尔顿花园罩裙","url":"https://lolitalibrary.com/library/detail/14385"},{"type":"web_search_result","title":"新闻","url":"https://example.com/article"}]}]}"#.utf8)

    XCTAssertEqual(
      DreamDressDetectiveService.webSearchURLs(from: data).map(\.host),
      ["wiki.smzdm.com", "qiandao.com", "lolitalibrary.com"]
    )
  }

  func testWebSearchResponseKeepsVerifiedInternationalProductPages() {
    let data = Data(#"{"content":[{"type":"web_search_result","title":"ピンクハウス スカート","url":"https://zenmarket.jp/cn/auction.aspx?itemCode=b1235204357"},{"type":"web_search_result","title":"PINK HOUSE 牛仔连衣裙","url":"https://zenmarket.jp/cn/mercariproduct.aspx?itemCode=m37054488698"},{"type":"web_search_result","title":"PINK HOUSE スカート","url":"https://pinkhouse-webshop.jp/item/pinkhouse/1_1_A2163FSY107_1/02"},{"type":"web_search_result","title":"PINK HOUSE ワンピース","url":"https://jp.mercari.com/item/m64866844138"},{"type":"web_search_result","title":"PINK HOUSE skirt","url":"https://item.rakuten.co.jp/crown-store/132999-q/"},{"type":"web_search_result","title":"PINK HOUSE skirt","url":"https://auctions.yahoo.co.jp/jp/auction/b1237923495"},{"type":"web_search_result","title":"PINK HOUSE skirt","url":"https://paypayfleamarket.yahoo.co.jp/item/k1058397774"},{"type":"web_search_result","title":"PINK HOUSE 二手裙","url":"https://www.wunderwelt.jp/products/u30555"},{"type":"web_search_result","title":"品牌列表","url":"https://pinkhouse-webshop.jp/item?category_id=550"},{"type":"web_search_result","title":"搜索列表","url":"https://tw.bid.yahoo.com/search/auction/product?p=pink+house"}]}"#.utf8)

    XCTAssertEqual(
      DreamDressDetectiveService.webSearchURLs(from: data).map(\.host),
      ["auctions.yahoo.co.jp", "jp.mercari.com", "pinkhouse-webshop.jp", "jp.mercari.com", "item.rakuten.co.jp", "auctions.yahoo.co.jp", "paypayfleamarket.yahoo.co.jp", "www.wunderwelt.jp"]
    )
  }

  func testWebSearchCanonicalizesProxyPagesToOriginalProductPages() {
    let data = Data(#"{"content":[{"type":"web_search_result","title":"PINK HOUSE スカート","url":"https://www.j-subculture.com/zh-cn/shoppings/detail?shopping_url=https%3A%2F%2Fjp.mercari.com%2Fitem%2Fm41776143944%2F&shopping_type=1"},{"type":"web_search_result","title":"PINK HOUSE スカート","url":"https://www.letao.com.hk/jpshopping/item.php?itemcode=m50391818495&domain=mercari"}]}"#.utf8)

    XCTAssertEqual(
      DreamDressDetectiveService.webSearchURLs(from: data).map(\.absoluteString),
      ["https://jp.mercari.com/item/m41776143944/", "https://jp.mercari.com/item/m50391818495"]
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
