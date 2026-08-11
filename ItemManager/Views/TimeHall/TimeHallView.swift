import SwiftUI
import SwiftData

enum TimeHallMode: String, CaseIterable, Identifiable {
  case chronicle
  case styleSpray
  case story
  case coordinate

  var id: String { rawValue }

  var title: String {
    switch self {
    case .chronicle: return "编年史".appLocalized
    case .styleSpray: return "图鉴手册".appLocalized
    case .story: return "珍选".appLocalized
    case .coordinate: return "搭配".appLocalized
    }
  }
}

private enum TimeHallMerchant: String, CaseIterable, Identifiable {
  case pinkHouse
  case angelicPretty
  case babyStarsShineBright
  case julietteEtJustine
  case wunderweltFleur

  var id: String { rawValue }

  var name: String {
    switch self {
    case .pinkHouse: return "Pink House"
    case .angelicPretty: return "Angelic Pretty"
    case .babyStarsShineBright: return "BABY, THE STARS SHINE BRIGHT"
    case .julietteEtJustine: return "Juliette et Justine"
    case .wunderweltFleur: return "Wunderwelt FLEUR"
    }
  }

  var subtitle: String {
    switch self {
    case .pinkHouse: return "编年史杂志与官方商品档案".appLocalized
    case .angelicPretty: return "甜美洛丽塔的梦幻衣橱".appLocalized
    case .babyStarsShineBright: return "细腻优雅的永恒洛丽塔衣橱".appLocalized
    case .julietteEtJustine: return "与艺术同行的古典优雅".appLocalized
    case .wunderweltFleur: return "官方授权多品牌新商品平台".appLocalized
    }
  }

  var catalogResourceName: String? {
    switch self {
    case .pinkHouse: return nil
    case .angelicPretty: return "catalog-angelic-pretty"
    case .babyStarsShineBright: return "catalog-baby-stars-shine-bright"
    case .julietteEtJustine: return "catalog-juliette-et-justine"
    case .wunderweltFleur: return "catalog-wunderwelt-fleur"
    }
  }

  var coverImage: String? {
    switch self {
    case .pinkHouse: return nil
    case .angelicPretty: return "brand-angelic-pretty-hero.jpg"
    case .babyStarsShineBright: return "brand-baby-hero.png"
    case .julietteEtJustine: return "brand-juliette-hero.jpg"
    case .wunderweltFleur: return "brand-wunderwelt-fleur-hero.png"
    }
  }

  var officialURL: String {
    switch self {
    case .pinkHouse: return "https://pinkhouse-webshop.jp/"
    case .angelicPretty: return "https://angelicpretty.com/"
    case .babyStarsShineBright: return "https://store.babyssb.co.jp/en"
    case .julietteEtJustine: return "https://juliette-et-justine.com/zh-cn"
    case .wunderweltFleur: return "https://www.wunderwelt.jp/zh/pages/fleur"
    }
  }
}

private enum TimeHallScrollRange: Equatable {
  case top
  case middle
  case collapsed

  init(distance: CGFloat) {
    if distance <= 16 {
      self = .top
    } else if distance >= 88 {
      self = .collapsed
    } else {
      self = .middle
    }
  }
}

private enum TimeHallStoreTheme: String, CaseIterable, Identifiable {
  case kagoshima
  case omotesando
  case nagoya
  case angelicPrettyTokyo
  case angelicPrettyOsaka
  case angelicPrettyParis
  case babyHonten
  case babyOsaka
  case babyYokohama
  case julietteOnline
  case wunderweltOnline

  var id: String { rawValue }

  var title: String {
    switch self {
    case .omotesando: return "Timeless 表参道"
    case .nagoya: return "名古屋松坂屋"
    case .kagoshima: return "鹿儿岛山形屋"
    case .angelicPrettyTokyo: return "东京店"
    case .angelicPrettyOsaka: return "大阪店"
    case .angelicPrettyParis: return "巴黎店"
    case .babyHonten: return "原宿本店"
    case .babyOsaka: return "大阪店"
    case .babyYokohama: return "横滨店"
    case .julietteOnline: return "官方线上商店"
    case .wunderweltOnline: return "FLEUR 官方线上店"
    }
  }

  var location: String {
    switch self {
    case .omotesando: return "东京 · 神宫前"
    case .nagoya: return "名古屋 · 松坂屋本馆 5F"
    case .kagoshima: return "鹿儿岛 · 山形屋1号馆 4F"
    case .angelicPrettyTokyo: return "东京 · 官方店铺资料"
    case .angelicPrettyOsaka: return "大阪 · 西心斋桥"
    case .angelicPrettyParis: return "巴黎 · Rue Saint-Roch"
    case .babyHonten: return "东京 · 神宫前"
    case .babyOsaka: return "大阪 · 西心斋桥"
    case .babyYokohama: return "横滨 · VIVRE 3F"
    case .julietteOnline, .wunderweltOnline: return "线上专营 · 官网访问"
    }
  }

  var storeImageName: String? {
    switch self {
    case .omotesando: return "time_hall_store_omotesando"
    case .nagoya: return "time_hall_store_nagoya"
    case .kagoshima: return "time_hall_store_kagoshima"
    case .angelicPrettyTokyo: return "store-angelic-pretty-tokyo.png"
    case .angelicPrettyOsaka: return "store-angelic-pretty-osaka.png"
    case .angelicPrettyParis: return "store-angelic-pretty-paris.png"
    case .babyHonten: return "store-baby-honten.png"
    case .babyOsaka: return "store-baby-osaka.png"
    case .babyYokohama: return "store-baby-yokohama.png"
    case .julietteOnline, .wunderweltOnline: return nil
    }
  }

  var merchant: TimeHallMerchant {
    switch self {
    case .omotesando, .nagoya, .kagoshima: return .pinkHouse
    case .angelicPrettyTokyo, .angelicPrettyOsaka, .angelicPrettyParis: return .angelicPretty
    case .babyHonten, .babyOsaka, .babyYokohama: return .babyStarsShineBright
    case .julietteOnline: return .julietteEtJustine
    case .wunderweltOnline: return .wunderweltFleur
    }
  }

  var sourceURL: String {
    switch self {
    case .omotesando, .nagoya, .kagoshima: return "https://pinkhouse-webshop.jp/"
    case .angelicPrettyTokyo: return "https://angelicpretty.com/Page/shop_harajuku.aspx"
    case .angelicPrettyOsaka: return "https://angelicpretty.com/Page/shop_osaka.aspx"
    case .angelicPrettyParis: return "https://angelicpretty-paris.com/gb/page/7-the-angelic-pretty-paris-shop"
    case .babyHonten: return "https://www.babyssb.co.jp/locations/honten/"
    case .babyOsaka: return "https://www.babyssb.co.jp/locations/osaka/"
    case .babyYokohama: return "https://www.babyssb.co.jp/locations/yokohama_baby/"
    case .julietteOnline: return "https://juliette-et-justine.com/zh-cn"
    case .wunderweltOnline: return "https://www.wunderwelt.jp/zh/pages/fleur"
    }
  }

  static func themes(for merchant: TimeHallMerchant) -> [Self] {
    allCases.filter { $0.merchant == merchant }
  }

  var accent: Color {
    switch self {
    case .omotesando: return Color(red: 0.73, green: 0.24, blue: 0.32)
    case .nagoya: return Color(red: 0.52, green: 0.08, blue: 0.16)
    case .kagoshima: return Color(red: 0.44, green: 0.29, blue: 0.20)
    case .angelicPrettyTokyo, .angelicPrettyOsaka, .angelicPrettyParis:
      return Color(red: 0.88, green: 0.34, blue: 0.59)
    case .babyHonten, .babyOsaka, .babyYokohama:
      return Color(red: 0.62, green: 0.12, blue: 0.25)
    case .julietteOnline: return Color(red: 0.40, green: 0.28, blue: 0.22)
    case .wunderweltOnline: return Color(red: 0.30, green: 0.20, blue: 0.42)
    }
  }

  var colors: [Color] {
    switch self {
    case .omotesando:
      return [Color(red: 0.98, green: 0.91, blue: 0.82), Color(red: 0.80, green: 0.90, blue: 0.82)]
    case .nagoya:
      return [Color(red: 0.98, green: 0.86, blue: 0.88), Color(red: 0.73, green: 0.25, blue: 0.31)]
    case .kagoshima:
      return [Color(red: 0.93, green: 0.85, blue: 0.72), Color(red: 0.74, green: 0.87, blue: 0.82)]
    case .angelicPrettyTokyo, .angelicPrettyOsaka, .angelicPrettyParis:
      return [Color(red: 1.00, green: 0.90, blue: 0.95), Color(red: 0.95, green: 0.82, blue: 0.91)]
    case .babyHonten, .babyOsaka, .babyYokohama:
      return [Color(red: 0.99, green: 0.91, blue: 0.91), Color(red: 0.91, green: 0.79, blue: 0.78)]
    case .julietteOnline:
      return [Color(red: 0.94, green: 0.89, blue: 0.82), Color(red: 0.83, green: 0.76, blue: 0.66)]
    case .wunderweltOnline:
      return [Color(red: 0.91, green: 0.87, blue: 0.96), Color(red: 0.79, green: 0.73, blue: 0.88)]
    }
  }

}

private struct TimeHallMagazinePageGroup: Identifiable {
  let id: String
  let items: [TimeHallItemDTO]

  var primaryItem: TimeHallItemDTO { items[0] }
}

private enum TimeHallDisplayLanguage {
  static var usesChinese: Bool {
    LanguageManager.shared.localeIdentifier.hasPrefix("zh")
  }

  static func productName(
    chinese: String,
    official: String,
    categoryZH: String,
    identifier: String
  ) -> String {
    guard usesChinese else { return official }
    let hasJapaneseKana = chinese.range(of: #"[ぁ-ゖァ-ヺ]"#, options: .regularExpression) != nil
    return hasJapaneseKana ? "\(categoryZH) · \(identifier)" : chinese
  }

  static func archiveTitle(kind: String, date: String?, official: String) -> String {
    guard usesChinese else { return official }
    return [kind, date].compactMap { $0 }.joined(separator: " · ")
  }

  static func officialName(_ value: String) -> String {
    usesChinese ? "官方日文名：\(value)" : value
  }

  static func officialTitle(_ value: String) -> String {
    usesChinese ? "官方日文标题：\(value)" : value
  }
}

extension TimeHallItemDTO {
  fileprivate var displayName: String {
    TimeHallDisplayLanguage.productName(
      chinese: nameZH,
      official: name,
      categoryZH: categoryZH,
      identifier: productCode ?? "图录第 \(cataloguePage) 页"
    )
  }

  fileprivate var displayCategory: String {
    TimeHallDisplayLanguage.usesChinese ? categoryZH : category
  }
}

extension TimeHallCommerceItemDTO {
  fileprivate var displayName: String {
    TimeHallDisplayLanguage.productName(
      chinese: nameZH,
      official: name,
      categoryZH: categoryZH,
      identifier: productCode
    )
  }

  fileprivate var displayCategory: String {
    TimeHallDisplayLanguage.usesChinese ? categoryZH : category
  }

  fileprivate var displayStyles: [String] {
    TimeHallDisplayLanguage.usesChinese ? stylesZH : styles
  }
}

extension TimeHallCoordinateDTO {
  fileprivate var displayTitle: String {
    TimeHallDisplayLanguage.archiveTitle(
      kind: "官方搭配".appLocalized,
      date: publishedOn ?? "#\(officialID)",
      official: title
    )
  }
}

extension TimeHallStoryDTO {
  fileprivate var displayTitle: String {
    TimeHallDisplayLanguage.archiveTitle(
      kind: kind.labelZH,
      date: publishedOn,
      official: title
    )
  }
}

struct TimeHallView: View {
  @Environment(ThemeManager.self) private var themeManager
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.isRoutePageActive) private var isRoutePageActive
  @ObservedObject private var store = TimeHallCatalogStore.shared

  @State private var carouselMerchant: TimeHallMerchant = .pinkHouse
  @State private var storeTheme: TimeHallStoreTheme = .kagoshima
  @State private var activeMerchant: TimeHallMerchant?
  @State private var curatedCatalog: TimeHallCatalogDTO?
  @State private var mode: TimeHallMode = .chronicle
  @State private var selectedYear: Int?
  @State private var detailCommerceItem: TimeHallCommerceItemDTO?
  @State private var detailCoordinate: TimeHallCoordinateDTO?
  @State private var detailStory: TimeHallStoryDTO?
  @State private var commerceSource: TimeHallCommerceSource?
  @State private var showTreasuresOnly = false
  @State private var searchText = ""
  @State private var isTimelineAscending = false
  @State private var isHeaderCollapsed = false

  private var palette: MagicThemePalette {
    MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
  }

  private var activeYear: Int {
    selectedYear ?? orderedTimelineYears.first ?? 2024
  }

  private var magazinePageCount: Int {
    Set(store.items.compactMap(\.coverImage)).count
  }

  private var orderedTimelineYears: [Int] {
    store.years
      .filter(hasMeaningfulTimelineContent(for:))
      .sorted(by: isTimelineAscending ? (<) : (>))
  }

  private func hasMeaningfulTimelineContent(for year: Int) -> Bool {
    if !store.archiveCatalogues(for: year).isEmpty || !store.catalogues(for: year).isEmpty {
      return true
    }
    guard let record = store.yearRecord(for: year), record.kind != .archiveGap else {
      return false
    }
    return !record.titleZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !record.storyZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var filteredItems: [TimeHallItemDTO] {
    var list = store.items
    if showTreasuresOnly {
      list = list.filter { store.isTreasured($0.id) }
    }
    if !searchText.isEmpty {
      let q = searchText.lowercased()
      list = list.filter {
        $0.nameZH.lowercased().contains(q)
          || $0.name.lowercased().contains(q)
          || $0.stylesZH.joined().lowercased().contains(q)
          || $0.categoryZH.lowercased().contains(q)
      }
    }
    return list
  }

  private var filteredCommerceItems: [TimeHallCommerceItemDTO] {
    var list = store.commerceItems
    if let commerceSource {
      list = list.filter { $0.sourceKind == commerceSource }
    }
    if showTreasuresOnly {
      list = list.filter { store.isTreasured($0.id) }
    }
    if !searchText.isEmpty {
      let q = searchText.lowercased()
      list = list.filter {
        $0.nameZH.lowercased().contains(q)
          || $0.name.lowercased().contains(q)
          || $0.productCode.lowercased().contains(q)
          || $0.categoryZH.lowercased().contains(q)
          || $0.stylesZH.joined().lowercased().contains(q)
      }
    }
    return list
  }

  private var filteredCoordinates: [TimeHallCoordinateDTO] {
    guard !searchText.isEmpty else { return store.coordinates }
    let q = searchText.lowercased()
    return store.coordinates.filter {
      $0.title.lowercased().contains(q)
        || $0.coordinatePoint.lowercased().contains(q)
        || $0.productCodes.joined().lowercased().contains(q)
        || $0.unlinkedItemNames.joined().lowercased().contains(q)
    }
  }

  private var filteredStories: [TimeHallStoryDTO] {
    guard !searchText.isEmpty else { return store.stories }
    let q = searchText.lowercased()
    return store.stories.filter {
      $0.title.lowercased().contains(q)
        || $0.summary.lowercased().contains(q)
        || $0.content.lowercased().contains(q)
        || $0.productCodes.joined().lowercased().contains(q)
    }
  }

  var body: some View {
    Group {
      if activeMerchant == .pinkHouse {
        pinkHouseHall
      } else if let activeMerchant {
        curatedBrandHall(activeMerchant)
      } else {
        merchantSelection
      }
    }
    .onChange(of: isRoutePageActive) { _, isActive in
      guard isActive else { return }
      carouselMerchant = .pinkHouse
      activeMerchant = nil
      curatedCatalog = nil
      isHeaderCollapsed = false
    }
    .onChange(of: carouselMerchant) { _, merchant in
      storeTheme = TimeHallStoreTheme.themes(for: merchant).first ?? .omotesando
    }
    .toolbar(.hidden, for: .navigationBar)
  }

  private var pinkHouseHall: some View {
    ZStack {
      LiquidBackground(themeSkinWallpaperContext: .timeHall)

      VStack(spacing: 0) {
        header
        ZStack(alignment: .top) {
          archiveScrollView

          expandedArchiveHeader
            .frame(height: 88, alignment: .top)
            .opacity(isHeaderCollapsed ? 0 : 1)
            .scaleEffect(isHeaderCollapsed ? 0.98 : 1, anchor: .top)
            .allowsHitTesting(!isHeaderCollapsed)
            .accessibilityHidden(isHeaderCollapsed)
            .animation(.easeOut(duration: 0.16), value: isHeaderCollapsed)
        }
      }
    }
    .sheet(item: $detailCommerceItem) { item in
      TimeHallCommerceItemDetailView(item: item)
    }
    .sheet(item: $detailCoordinate) { coordinate in
      TimeHallCoordinateDetailView(coordinate: coordinate)
    }
    .sheet(item: $detailStory) { story in
      TimeHallStoryDetailView(story: story)
    }
  }

  private func curatedBrandHall(_ merchant: TimeHallMerchant) -> some View {
    ZStack {
      LiquidBackground(themeSkinWallpaperContext: .timeHall)

      VStack(spacing: 0) {
        curatedBrandHeader(merchant)
        ZStack(alignment: .top) {
          if let catalog = curatedCatalog {
            curatedArchiveScrollView(catalog)
            curatedExpandedArchiveHeader(catalog)
              .frame(height: 88, alignment: .top)
              .opacity(isHeaderCollapsed ? 0 : 1)
              .scaleEffect(isHeaderCollapsed ? 0.98 : 1, anchor: .top)
              .allowsHitTesting(!isHeaderCollapsed)
              .accessibilityHidden(isHeaderCollapsed)
              .animation(.easeOut(duration: 0.16), value: isHeaderCollapsed)
          } else {
            GlassCard(cornerRadius: 24, padding: 20) {
              ContentUnavailableView(
                "档案读取失败".appLocalized,
                systemImage: "doc.text.magnifyingglass",
                description: Text("请返回后重新进入该品牌档案".appLocalized)
              )
            }
            .padding(20)
          }
        }
      }
    }
  }

  private func curatedBrandHeader(_ merchant: TimeHallMerchant) -> some View {
    HStack(spacing: 8) {
      Button {
        carouselMerchant = merchant
        isHeaderCollapsed = false
        activeMerchant = nil
        curatedCatalog = nil
      } label: {
        Label("选择品牌".appLocalized, systemImage: "chevron.left")
          .font(.caption.weight(.semibold))
          .frame(height: 30)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .tint(Color.pink)

      Text(merchant.name)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.72)

      if isHeaderCollapsed {
        collapsedModeMenu
      }

      Spacer(minLength: 0)

      if let url = URL(string: merchant.officialURL) {
        Link(destination: url) {
          Image(systemName: "safari")
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.small)
        .accessibilityLabel("打开品牌官网".appLocalized)
      }
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 4)
  }

  @ViewBuilder
  private func curatedArchiveScrollView(_ catalog: TimeHallCatalogDTO) -> some View {
    if #available(iOS 18.0, *) {
      curatedArchiveScrollViewBody(catalog)
        .onScrollGeometryChange(for: TimeHallScrollRange.self) { geometry in
          TimeHallScrollRange(
            distance: geometry.contentOffset.y + geometry.contentInsets.top
          )
        } action: { _, range in
          handleScrollRange(range)
        }
    } else {
      curatedArchiveScrollViewBody(catalog)
    }
  }

  private func curatedArchiveScrollViewBody(_ catalog: TimeHallCatalogDTO) -> some View {
    ScrollView {
      if #unavailable(iOS 18.0) {
        scrollThresholdObserver
      }
      curatedBrandContent(catalog)
        .padding(.top, 88)
    }
    .scrollIndicators(.hidden)
  }

  private func curatedExpandedArchiveHeader(_ catalog: TimeHallCatalogDTO) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 3) {
        Text(catalog.subtitle)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.primaryText)
        Text(catalog.scope.labelZH)
          .font(.caption)
          .foregroundStyle(palette.secondaryText.opacity(0.85))
          .lineLimit(2)
      }
      .frame(height: 40, alignment: .top)
      .padding(.horizontal, 20)

      modePicker
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(height: 48, alignment: .top)
    }
  }

  private func curatedBrandContent(_ catalog: TimeHallCatalogDTO) -> some View {
    Group {
      switch mode {
      case .chronicle:
        curatedChronicle(catalog)
      case .styleSpray:
        curatedAtlas(catalog)
      case .story:
        curatedStories(catalog)
      case .coordinate:
        curatedCoordinates(catalog)
      }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 120)
    .containerRelativeFrame(.horizontal, alignment: .leading)
  }

  private func curatedChronicle(_ catalog: TimeHallCatalogDTO) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      curatedSectionTitle("品牌编年史", detail: catalog.scope.labelZH)
      ForEach(catalog.timelineYears.sorted { $0.year < $1.year }) { record in
        GlassCard(cornerRadius: 22, padding: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text(String(record.year))
              .font(.caption.monospacedDigit().weight(.bold))
              .foregroundStyle(Color.pink)
            Text(record.titleZH)
              .font(.headline)
              .foregroundStyle(palette.primaryText)
            Text(record.storyZH)
              .font(.subheadline)
              .foregroundStyle(palette.secondaryText)
              .fixedSize(horizontal: false, vertical: true)
            if let source = record.sourceURLs.first, let url = URL(string: source) {
              Link("查看官方资料".appLocalized, destination: url)
                .font(.caption.weight(.semibold))
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  private func curatedAtlas(_ catalog: TimeHallCatalogDTO) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      curatedSectionTitle("官网图鉴手册", detail: catalog.scope.labelZH)
      ForEach(catalog.catalogues.sorted { ($0.year, $0.season) < ($1.year, $1.season) }) { catalogue in
        let catalogueItems = catalogue.itemIds.compactMap { itemID in
          catalog.items.first { $0.id == itemID }
        }
        GlassCard(cornerRadius: 22, padding: 0) {
          VStack(alignment: .leading, spacing: 0) {
            TimeHallBundleImage(fileName: catalogue.coverImage, placeholderSystemImage: "book.closed.fill")
              .scaledToFill()
              .frame(maxWidth: .infinity)
              .frame(height: 180)
              .clipped()
            VStack(alignment: .leading, spacing: 8) {
              Text("\(String(catalogue.year)) · \(catalogue.seasonLabel)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.pink)
              Text(catalogue.titleZH)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(palette.primaryText)
              Text(catalogue.summaryZH)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
              Divider()
              if catalogueItems.isEmpty {
                Text("官网未公开可稳定逐项核对的商品清单，保留目录层级。".appLocalized)
                  .font(.caption)
                  .foregroundStyle(palette.secondaryText)
              } else {
                ForEach(catalogueItems) { item in
                  VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                      Text(item.nameZH)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                      Spacer(minLength: 8)
                      if item.priceJPY > 0 {
                        Text("¥\(item.priceJPY.formatted())")
                          .font(.caption.monospacedDigit().weight(.semibold))
                          .foregroundStyle(Color.pink)
                      }
                    }
                    Text("\(item.categoryZH) · \(item.noteZH)")
                      .font(.caption)
                      .foregroundStyle(palette.secondaryText)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
              }
              if let url = URL(string: catalogue.sourceURL) {
                Link("查看官网目录".appLocalized, destination: url)
                  .font(.caption.weight(.semibold))
              }
            }
            .padding(16)
          }
        }
      }
    }
  }

  private func curatedStories(_ catalog: TimeHallCatalogDTO) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      curatedSectionTitle("官方珍选", detail: "仅收录官网可验证的专题、新闻、专栏与 Lookbook")
      if catalog.stories.isEmpty {
        GlassCard(cornerRadius: 22, padding: 16) {
          ContentUnavailableView(
            "暂无官网珍选档案".appLocalized,
            systemImage: "sparkles.rectangle.stack",
            description: Text("官网未提供可核验的专题或精选内容，因此不自行创作。".appLocalized)
          )
        }
      } else {
        ForEach(catalog.stories) { story in
          GlassCard(cornerRadius: 24, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
              TimeHallBundleImage(
                fileName: story.coverImage,
                placeholderSystemImage: story.kind.symbolName
              )
              .scaledToFill()
              .frame(maxWidth: .infinity)
              .frame(height: 180)
              .clipped()

              VStack(alignment: .leading, spacing: 9) {
                Label(story.kind.labelZH, systemImage: story.kind.symbolName)
                  .font(.caption.weight(.bold))
                  .foregroundStyle(Color.pink)
                Text(story.title)
                  .font(.system(.title3, design: .serif).weight(.semibold))
                  .foregroundStyle(palette.primaryText)
                Text(story.summary)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(palette.primaryText)
                Text(story.content)
                  .font(.body)
                  .foregroundStyle(palette.secondaryText)
                  .fixedSize(horizontal: false, vertical: true)
                if let url = URL(string: story.sourceURL) {
                  Link(destination: url) {
                    Label("查看官方来源".appLocalized, systemImage: "arrow.up.right.square")
                      .font(.caption.weight(.semibold))
                  }
                }
              }
              .padding(18)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func curatedCoordinates(_ catalog: TimeHallCatalogDTO) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      curatedSectionTitle("官方搭配", detail: "仅呈现官网已有 Lookbook、时装秀或搭配资料")
      if catalog.coordinates.isEmpty {
        GlassCard(cornerRadius: 22, padding: 16) {
          ContentUnavailableView(
            "暂无官网搭配档案".appLocalized,
            systemImage: "person.crop.rectangle.stack",
            description: Text("官网未提供可核验的专题搭配，因此不自行创作。".appLocalized)
          )
        }
      } else {
        ForEach(catalog.coordinates) { coordinate in
          GlassCard(cornerRadius: 22, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
              TimeHallBundleImage(fileName: coordinate.coverImage, placeholderSystemImage: "person.crop.rectangle.stack")
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipped()
              VStack(alignment: .leading, spacing: 8) {
                Text(coordinate.title)
                  .font(.headline)
                  .foregroundStyle(palette.primaryText)
                Text(coordinate.coordinatePoint)
                  .font(.subheadline)
                  .foregroundStyle(palette.secondaryText)
                if let url = URL(string: coordinate.sourceURL) {
                  Link("查看官方搭配".appLocalized, destination: url)
                    .font(.caption.weight(.semibold))
                }
              }
              .padding(16)
            }
          }
        }
      }
    }
  }

  private func curatedSectionTitle(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title.appLocalized)
        .font(.system(.title2, design: .serif).weight(.semibold))
        .foregroundStyle(palette.primaryText)
      Text(detail)
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private var archiveScrollView: some View {
    if #available(iOS 18.0, *) {
      archiveScrollViewBody
        .onScrollGeometryChange(for: TimeHallScrollRange.self) { geometry in
          TimeHallScrollRange(
            distance: geometry.contentOffset.y + geometry.contentInsets.top
          )
        } action: { _, range in
          handleScrollRange(range)
        }
    } else {
      archiveScrollViewBody
    }
  }

  private var archiveScrollViewBody: some View {
    ScrollView {
      if #unavailable(iOS 18.0) {
        scrollThresholdObserver
      }

      Group {
        switch mode {
        case .chronicle:
          chronicleContent
        case .styleSpray:
          styleSprayContent
        case .story:
          storyContent
        case .coordinate:
          coordinateContent
        }
      }
      .padding(.top, 88)
    }
    .scrollIndicators(.hidden)
  }

  private var merchantSelection: some View {
    GeometryReader { proxy in
      ZStack {
        LiquidBackground(themeSkinWallpaperContext: .timeHall)
        LinearGradient(colors: storeTheme.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
          .opacity(0.34)
          .ignoresSafeArea()

        Circle()
          .fill(storeTheme.accent.opacity(0.08))
          .frame(width: 360, height: 360)
          .blur(radius: 46)
          .offset(x: -180, y: -250)

        if proxy.size.width > proxy.size.height {
          merchantSelectionLandscape(size: proxy.size)
        } else {
          merchantSelectionPortrait
        }
      }
    }
  }

  private var merchantSelectionPortrait: some View {
    VStack(spacing: 16) {
      Spacer(minLength: 12)
      merchantSelectionIntroduction

      HStack(alignment: .center, spacing: 8) {
        merchantSelectionHeading
          .frame(maxWidth: .infinity)
        if TimeHallStoreTheme.themes(for: carouselMerchant).count > 1 {
          storeThemeMenu
        }
      }

      TabView(selection: $carouselMerchant) {
        ForEach(TimeHallMerchant.allCases) { merchant in
          merchantCard(merchant)
            .padding(.horizontal, 8)
            .tag(merchant)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(maxWidth: 620, maxHeight: 410)

      merchantPageIndicator
      merchantCarouselNavigation
      merchantSelectionFooter

      Spacer(minLength: 82)
    }
    .padding(.horizontal, 20)
  }

  private func merchantSelectionLandscape(size: CGSize) -> some View {
    VStack(spacing: 8) {
      merchantSelectionIntroductionCompact

      HStack(alignment: .center, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text("选择品牌".appLocalized)
            .font(.system(.headline, design: .serif).weight(.semibold))
            .foregroundStyle(palette.primaryText)
          Text("左右滑动，进入想翻阅的品牌档案".appLocalized)
            .font(.caption)
            .foregroundStyle(palette.secondaryText)
        }
        if TimeHallStoreTheme.themes(for: carouselMerchant).count > 1 {
          storeThemeMenu
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)

      HStack(spacing: 12) {
        Color.clear
          .frame(width: max(48, size.width * 0.08))

        TabView(selection: $carouselMerchant) {
          ForEach(TimeHallMerchant.allCases) { merchant in
            merchantVisual(merchant, imageWidthRatio: 0.96)
              .padding(.vertical, 8)
              .tag(merchant)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: size.width * 0.62)
        .frame(maxHeight: .infinity)

        VStack(spacing: 8) {
          Spacer(minLength: 0)
          merchantInfo(carouselMerchant, compact: true)
          merchantPageIndicator
          merchantCarouselNavigation
          merchantSelectionFooter
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 54)
    }
    .padding(.vertical, 8)
  }

  private var merchantSelectionIntroduction: some View {
    VStack(spacing: 6) {
      Text("梦裙时光馆".appLocalized)
        .font(.system(.largeTitle, design: .serif).weight(.semibold))
        .foregroundStyle(palette.primaryText)
      Text("在这里翻阅品牌的编年史、图鉴、珍选与搭配".appLocalized)
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.secondaryText)
    }
  }

  private var merchantSelectionIntroductionCompact: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("梦裙时光馆".appLocalized)
        .font(.system(.title, design: .serif).weight(.semibold))
        .foregroundStyle(palette.primaryText)
      Text("在这里翻阅品牌的编年史、图鉴、珍选与搭配".appLocalized)
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
  }

  private var merchantSelectionHeading: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("选择品牌".appLocalized)
        .font(.system(.title2, design: .serif).weight(.semibold))
        .foregroundStyle(palette.primaryText)
      Text("左右滑动，进入想翻阅的品牌档案".appLocalized)
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func merchantCard(_ merchant: TimeHallMerchant) -> some View {
    VStack(spacing: 18) {
      merchantVisual(merchant)
        .frame(height: 210)
      merchantInfo(merchant)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.snappy, value: storeTheme)
  }

  @ViewBuilder
  private func merchantVisual(_ merchant: TimeHallMerchant, imageWidthRatio: CGFloat = 0.82) -> some View {
    themedStorefront(theme: theme(for: merchant), imageWidthRatio: imageWidthRatio)
  }

  private func merchantInfo(_ merchant: TimeHallMerchant, compact: Bool = false) -> some View {
    let theme = theme(for: merchant)
    return VStack(spacing: compact ? 8 : 12) {
        VStack(spacing: 6) {
          Text(merchant.name)
            .font(.system(compact ? .title2 : .title, design: .serif).weight(.bold))
            .foregroundStyle(palette.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(.center)
          Text(theme.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.accent)
          Text(merchant.subtitle)
            .font(compact ? .caption : .subheadline)
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.secondaryText)
          if let url = URL(string: theme.sourceURL) {
            Link(destination: url) {
              Label(theme.merchant == .julietteEtJustine || theme.merchant == .wunderweltFleur ? "访问线上据点" : "查看门店资料", systemImage: "arrow.up.right.square")
                .font(.caption.weight(.semibold))
            }
          }
        }

        Button {
          isHeaderCollapsed = false
          mode = .chronicle
          curatedCatalog = merchant.catalogResourceName.flatMap(store.bundledCatalog(named:))
          activeMerchant = merchant
        } label: {
          Label("进入 \(merchant.name)", systemImage: "arrow.right.circle.fill")
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(theme.accent)
      }
      .padding(compact ? 8 : 12)
      .padding(.horizontal, compact ? 0 : 14)
  }

  private func themedStorefront(theme: TimeHallStoreTheme, imageWidthRatio: CGFloat) -> some View {
    GeometryReader { proxy in
      TimelineView(.animation(minimumInterval: 1 / 30)) { context in
        let wave = CGFloat(sin(context.date.timeIntervalSinceReferenceDate * 1.4))
        storefrontImage(theme)
          .scaledToFit()
          .frame(width: proxy.size.width * imageWidthRatio, height: proxy.size.height * 0.96)
          .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
          .offset(y: wave * 3)
          .shadow(color: .black.opacity(0.2), radius: 14, y: 9)
          .shadow(color: theme.accent.opacity(0.12), radius: 18, y: 6)
          .id(theme)
          .transition(.opacity.combined(with: .scale(scale: 0.94)))
      }
    }
    .accessibilityLabel("\(theme.title)门店主题")
  }

  @ViewBuilder
  private func storefrontImage(_ theme: TimeHallStoreTheme) -> some View {
    if let storeImageName = theme.storeImageName {
      if theme.merchant == .pinkHouse {
        Image(storeImageName).resizable()
      } else {
        TimeHallBundleImage(fileName: storeImageName, placeholderSystemImage: "storefront")
      }
    } else if let coverImage = theme.merchant.coverImage {
      TimeHallBundleImage(fileName: coverImage, placeholderSystemImage: "storefront")
    } else {
      TimeHallBundleImage(fileName: nil, placeholderSystemImage: "storefront")
    }
  }

  private func theme(for merchant: TimeHallMerchant) -> TimeHallStoreTheme {
    if merchant == carouselMerchant, storeTheme.merchant == merchant { return storeTheme }
    return TimeHallStoreTheme.themes(for: merchant).first ?? .omotesando
  }

  private var storeThemeMenu: some View {
    Menu {
      ForEach(TimeHallStoreTheme.themes(for: carouselMerchant)) { theme in
        Button {
          withAnimation(.snappy) { storeTheme = theme }
        } label: {
          Label(theme.title, systemImage: storeTheme == theme ? "checkmark.circle.fill" : "storefront")
        }
      }
    } label: {
      Image(systemName: "paintpalette.fill")
        .font(.caption.weight(.semibold))
        .frame(width: 32, height: 32)
    }
    .buttonStyle(.bordered)
    .buttonBorderShape(.circle)
    .controlSize(.small)
    .frame(width: 44, height: 44)
    .tint(storeTheme.accent)
    .accessibilityLabel("切换门店主题".appLocalized)
    .accessibilityValue(storeTheme.title)
  }

  private var merchantCarouselNavigation: some View {
    HStack(spacing: 10) {
      merchantNavigationButton(title: "上一家", systemImage: "chevron.left", offset: -1)
      merchantNavigationButton(title: "下一家", systemImage: "chevron.right", offset: 1)
    }
  }

  private var merchantPageIndicator: some View {
    HStack(spacing: 7) {
      ForEach(TimeHallMerchant.allCases) { merchant in
        Circle()
          .fill(merchant == carouselMerchant ? storeTheme.accent : palette.secondaryText.opacity(0.28))
          .frame(width: merchant == carouselMerchant ? 8 : 6, height: merchant == carouselMerchant ? 8 : 6)
      }
    }
    .frame(height: 8)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("第 \((TimeHallMerchant.allCases.firstIndex(of: carouselMerchant) ?? 0) + 1) 页，共 \(TimeHallMerchant.allCases.count) 页")
  }

  private var merchantSelectionFooter: some View {
    Text(storeTheme.location)
    .font(.caption.weight(.medium))
    .foregroundStyle(palette.secondaryText)
  }

  private func merchantNavigationButton(title: String, systemImage: String, offset: Int) -> some View {
    let merchants = TimeHallMerchant.allCases
    let index = merchants.firstIndex(of: carouselMerchant) ?? 0
    let targetIndex = index + offset
    let isEnabled = merchants.indices.contains(targetIndex)

    return Button {
      guard isEnabled else { return }
      withAnimation(.snappy) { carouselMerchant = merchants[targetIndex] }
    } label: {
      Label(title.appLocalized, systemImage: systemImage)
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 36)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .tint(isEnabled ? storeTheme.accent : .gray)
    .disabled(!isEnabled)
  }

  private var scrollThresholdObserver: some View {
    ScrollViewThresholdObserver { scrollDistance in
      handleScrollRange(TimeHallScrollRange(distance: scrollDistance))
    }
    .frame(width: 1, height: 1)
    .opacity(0)
    .accessibilityHidden(true)
  }

  private func handleScrollRange(_ range: TimeHallScrollRange) {
    let shouldCollapse: Bool?
    switch range {
    case .top: shouldCollapse = false
    case .middle: shouldCollapse = nil
    case .collapsed: shouldCollapse = true
    }
    guard let shouldCollapse, shouldCollapse != isHeaderCollapsed else { return }
    isHeaderCollapsed = shouldCollapse
  }

  private var header: some View {
    HStack(spacing: 8) {
      Button {
        carouselMerchant = .pinkHouse
        isHeaderCollapsed = false
        activeMerchant = nil
      } label: {
        Label("选择品牌".appLocalized, systemImage: "chevron.left")
          .font(.caption.weight(.semibold))
          .frame(height: 30)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
      .controlSize(.small)
      .tint(Color.pink)
      .accessibilityLabel("返回品牌选择，当前 Pink House")

      Text(TimeHallMerchant.pinkHouse.name)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.primaryText)
        .lineLimit(1)

      if isHeaderCollapsed {
        collapsedModeMenu
      }

      Spacer(minLength: 0)
      treasureButtonCompact
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 4)
  }

  private var expandedArchiveHeader: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 3) {
        Text(store.catalog?.subtitle ?? "PINK HOUSE · 1972–至今 · 真实目录与故事档案")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.primaryText)
        if !store.items.isEmpty || !store.commerceItems.isEmpty {
          Text(
            "\(store.catalog?.scope.labelZH ?? "1972–至今") · \(magazinePageCount) 幅编年史杂志内页 · \(store.commerceItems.count) 件官方商品"
          )
          .font(.caption)
          .foregroundStyle(palette.secondaryText.opacity(0.85))
        }
      }
      .frame(height: 40, alignment: .top)
      .padding(.horizontal, 20)

      modePicker
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(height: 48, alignment: .top)
    }
  }

  private var collapsedModeMenu: some View {
    Menu {
      ForEach(TimeHallMode.allCases) { item in
        Button {
          mode = item
        } label: {
          Label(item.title, systemImage: mode == item ? "checkmark.circle.fill" : "circle")
        }
      }
    } label: {
      HStack(spacing: 4) {
        Text(mode.title)
        Image(systemName: "chevron.down")
          .font(.caption2)
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(Color.pink)
      .padding(.horizontal, 9)
      .frame(height: 28)
      .background(Color.pink.opacity(0.12), in: Capsule())
    }
    .accessibilityLabel("切换品牌档案页签".appLocalized)
    .accessibilityValue(mode.title)
  }

  private var treasureButtonCompact: some View {
    Button {
      showTreasuresOnly.toggle()
    } label: {
      Image(systemName: showTreasuresOnly ? "heart.fill" : "heart")
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .buttonBorderShape(.circle)
    .tint(showTreasuresOnly ? .pink : nil)
    .frame(width: 32, height: 32)
    .accessibilityLabel("珍藏".appLocalized)
    .accessibilityValue(showTreasuresOnly ? "已开启".appLocalized : "已关闭".appLocalized)
  }

  private var modePicker: some View {
    HStack(spacing: 0) {
      ForEach(TimeHallMode.allCases) { item in
        Button {
          mode = item
        } label: {
          Text(item.title)
            .font(.subheadline.weight(mode == item ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(mode == item ? palette.primaryText : palette.secondaryText)
            .background {
              if mode == item {
                Capsule().fill(.ultraThinMaterial)
              }
            }
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(Capsule().fill(Color.primary.opacity(0.06)))
  }

  private var chronicleContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      searchField
      yearRail
      catalogueSection
      if !itemsForActiveYear.isEmpty {
        magazinePageGrid(title: "编年史杂志内页".appLocalized, items: itemsForActiveYear)
      }
      archiveCatalogueSection
      yearStoryCard
      historyEvidenceSection
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 120)
  }

  private var itemsForActiveYear: [TimeHallItemDTO] {
    let ids = Set(store.catalogues(for: activeYear).flatMap(\.itemIds))
    return filteredItems.filter { ids.contains($0.id) || $0.year == activeYear }
  }

  private var archiveCataloguesForActiveYear: [TimeHallArchiveCatalogueDTO] {
    let completeCatalogueURLs = Set(store.catalogues(for: activeYear).map(\.sourceURL))
    return store.archiveCatalogues(for: activeYear).filter {
      !completeCatalogueURLs.contains($0.sourceURL)
    }
  }

  private var yearRail: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("年份浏览")
          .font(.system(.headline, design: .serif).weight(.semibold))
          .foregroundStyle(palette.primaryText)
        Spacer()
        Menu {
          ForEach(orderedTimelineYears, id: \.self) { year in
            Button(String(year)) { selectedYear = year }
          }
        } label: {
          Label("选择年份", systemImage: "calendar")
            .font(.footnote.weight(.medium))
        }
        Menu {
          Button("升序") { isTimelineAscending = true }
          Button("倒序") { isTimelineAscending = false }
        } label: {
          Label(isTimelineAscending ? "升序" : "倒序", systemImage: "arrow.up.arrow.down")
            .font(.footnote.weight(.medium))
        }
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(orderedTimelineYears, id: \.self) { year in
            let record = store.yearRecord(for: year)
            let archiveCount = store.archiveCatalogues(for: year).count
            yearButton(
              year,
              subtitle: timelineSubtitle(record: record, archiveCount: archiveCount)
            )
          }
        }
      }
    }
  }

  private func timelineSubtitle(record: TimeHallYearRecordDTO?, archiveCount: Int) -> String {
    archiveCount > 0 ? "\(archiveCount) 份" : (record?.kind.labelZH ?? "")
  }

  private func yearButton(_ year: Int, subtitle: String) -> some View {
    let selected = year == activeYear
    return Button {
      withAnimation(.snappy) { selectedYear = year }
    } label: {
      VStack(spacing: 4) {
        Text(String(year))
          .font(.system(.headline, design: .serif))
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.caption2)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .foregroundStyle(selected ? .white : palette.primaryText)
      .background {
        Capsule()
          .fill(selected ? Color.pink.opacity(0.85) : Color.primary.opacity(0.06))
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var yearStoryCard: some View {
    if let record = store.yearRecord(for: activeYear),
      !record.titleZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !record.storyZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      GlassCard(cornerRadius: 24, padding: 18) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.kind.symbolName)
              .font(.title2.weight(.semibold))
              .foregroundStyle(record.kind == .archiveGap ? Color.orange : Color.pink)
              .frame(width: 46, height: 46)
              .background(
                (record.kind == .archiveGap ? Color.orange : Color.pink).opacity(0.12),
                in: Circle()
              )
            VStack(alignment: .leading, spacing: 4) {
              Text(String(record.year))
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(Color.pink)
              Text(record.titleZH)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(palette.primaryText)
            }
            Spacer()
          }

          Text(record.storyZH)
            .font(.body)
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

          if !record.sourceURLs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                ForEach(Array(record.sourceURLs.enumerated()), id: \.offset) { index, value in
                  if let url = URL(string: value) {
                    Link(destination: url) {
                      Label("相关资料 \(index + 1)", systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.pink.opacity(0.10), in: Capsule())
                    }
                  }
                }
              }
            }
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(String(record.year)) \(record.titleZH)")
    }
  }

  @ViewBuilder
  private var archiveCatalogueSection: some View {
    let catalogues = archiveCataloguesForActiveYear
    if !catalogues.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("官网杂志封面")
            .font(.system(.title3, design: .serif).weight(.semibold))
            .foregroundStyle(palette.primaryText)
          Spacer()
          Text("\(catalogues.count) 本")
            .font(.caption.monospacedDigit())
            .foregroundStyle(palette.secondaryText)
        }

        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
          spacing: 14
        ) {
          ForEach(catalogues) { catalogue in
            if let url = URL(string: catalogue.sourceURL) {
              Link(destination: url) {
                VStack(alignment: .leading, spacing: 8) {
                  TimeHallBundleImage(
                    fileName: catalogue.coverImage,
                    placeholderSystemImage: "book.closed.fill"
                  )
                  .scaledToFill()
                  .frame(maxWidth: .infinity)
                  .frame(height: 190)
                  .clipped()
                  .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                  Text(catalogue.seasonLabelZH)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.pink)
                  Text(catalogue.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(2)
                  Label("查看官网杂志", systemImage: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(catalogue.title) 杂志封面")
            }
          }
        }
      }
    }
  }

  private var catalogueSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !store.catalogues(for: activeYear).isEmpty {
        Text("完整杂志目录".appLocalized)
          .font(.system(.title3, design: .serif).weight(.semibold))
          .foregroundStyle(palette.primaryText)
      }
      ForEach(store.catalogues(for: activeYear)) { catalogue in
        GlassCard(cornerRadius: 22, padding: 16) {
          HStack(alignment: .top, spacing: 12) {
            TimeHallBundleImage(
              fileName: catalogue.coverImage, placeholderSystemImage: "book.closed.fill"
            )
            .scaledToFill()
            .frame(width: 92, height: 132)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("\(catalogue.titleZH) 杂志封面")

            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("\(String(catalogue.year)) · \(catalogue.seasonLabel) · \(catalogue.pageCount) 页")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(Color.pink)
                Spacer()
                Text("内页 \(Set(store.items(in: catalogue).compactMap(\.coverImage)).count) 幅")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(palette.secondaryText)
              }
              Text(catalogue.titleZH)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(palette.primaryText)
              Text(catalogue.summaryZH)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
              if let url = URL(string: catalogue.sourceURL) {
                Link(destination: url) {
                  Label("查看官网杂志", systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.medium))
                }
              }
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var historyEvidenceSection: some View {
    let entries = store.historyEntries(for: activeYear)
    if !entries.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("官方历史原文")
          .font(.system(.title3, design: .serif).weight(.semibold))
          .foregroundStyle(palette.primaryText)
        ForEach(entries) { entry in
          GlassCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
              if let coverImage = entry.coverImage {
                TimeHallBundleImage(
                  fileName: coverImage, placeholderSystemImage: "building.columns"
                )
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
              }
              Text(entry.title)
                .font(.headline)
                .foregroundStyle(palette.primaryText)
              Text(entry.content)
                .font(.body)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
              if let url = URL(string: entry.sourceURL) {
                Link("查看 Melrose 官方沿革", destination: url)
                  .font(.footnote.weight(.semibold))
              }
            }
          }
        }
      }
    }
  }

  private var styleSprayContent: some View {
    VStack(alignment: .leading, spacing: 18) {
      searchField
      commerceSnapshotCard
      commerceSourcePicker
      commerceItemGrid
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 120)
  }

  private var storyContent: some View {
    VStack(alignment: .leading, spacing: 18) {
        searchField
        GlassCard(cornerRadius: 22, padding: 16) {
          VStack(alignment: .leading, spacing: 7) {
            Label("官方 Feature 与制作工艺", systemImage: "sparkles.rectangle.stack")
              .font(.headline)
              .foregroundStyle(Color.pink)
            Text(
              "\(store.stories.filter { $0.kind == .feature }.count) 篇专题 · \(store.stories.filter { $0.kind == .craft }.count) 篇工艺档案"
            )
            .font(.system(.title3, design: .serif).weight(.semibold))
            .foregroundStyle(palette.primaryText)
          }
        }

        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
          spacing: 16
        ) {
          ForEach(filteredStories) { story in
            Button {
              detailStory = story
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                TimeHallBundleImage(
                  fileName: story.coverImage,
                  placeholderSystemImage: story.kind.symbolName
                )
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(story.kind.labelZH)
                  .font(.caption2.weight(.bold))
                  .foregroundStyle(story.kind == .craft ? Color.orange : Color.pink)
                Text(story.displayTitle)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(palette.primaryText)
                  .lineLimit(2)
                Text(story.publishedOn ?? "官方工艺档案")
                  .font(.caption2.monospacedDigit())
                  .foregroundStyle(palette.secondaryText)
              }
            }
            .buttonStyle(.plain)
          }
        }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 120)
  }

  private var coordinateContent: some View {
    VStack(alignment: .leading, spacing: 18) {
        searchField
        GlassCard(cornerRadius: 22, padding: 16) {
          VStack(alignment: .leading, spacing: 7) {
            Label("官方 Coordinate 搭配档案", systemImage: "person.crop.rectangle.stack")
              .font(.headline)
              .foregroundStyle(Color.pink)
            Text("\(store.coordinates.count) 套造型 · 按官网新着顺")
              .font(.system(.title3, design: .serif).weight(.semibold))
              .foregroundStyle(palette.primaryText)
          }
        }

        HStack {
          Text("全部搭配")
            .font(.system(.title3, design: .serif).weight(.semibold))
            .foregroundStyle(palette.primaryText)
          Spacer()
          Text("\(filteredCoordinates.count) 套")
            .font(.caption.monospacedDigit())
            .foregroundStyle(palette.secondaryText)
        }

        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
          spacing: 16
        ) {
          ForEach(filteredCoordinates) { coordinate in
            Button {
              detailCoordinate = coordinate
            } label: {
              VStack(alignment: .leading, spacing: 8) {
                TimeHallBundleImage(
                  fileName: coordinate.coverImage,
                  placeholderSystemImage: "person.crop.rectangle.stack"
                )
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(coordinate.displayTitle)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(palette.primaryText)
                  .lineLimit(2)
              }
            }
            .buttonStyle(.plain)
          }
        }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 120)
  }

  @ViewBuilder
  private var commerceSnapshotCard: some View {
    if let snapshot = store.commerceSnapshots.first {
      GlassCard(cornerRadius: 22, padding: 16) {
        VStack(alignment: .leading, spacing: 8) {
          Label("官方商品资料", systemImage: "bag.fill")
            .font(.headline)
            .foregroundStyle(Color.pink)
          Text("PINK HOUSE 当前商品与 OUTLET")
            .font(.system(.title3, design: .serif).weight(.semibold))
            .foregroundStyle(palette.primaryText)
          Text("当前商品 \(snapshot.currentItemIDs.count) 件 · OUTLET \(snapshot.outletItemIDs.count) 件")
            .font(.subheadline)
            .foregroundStyle(palette.secondaryText)
        }
      }
    }
  }

  private var commerceSourcePicker: some View {
    HStack(spacing: 8) {
      commerceSourceButton(nil, title: "全部")
      ForEach(TimeHallCommerceSource.allCases, id: \.rawValue) { source in
        commerceSourceButton(source, title: source.labelZH)
      }
    }
  }

  private func commerceSourceButton(_ source: TimeHallCommerceSource?, title: String) -> some View {
    let selected = commerceSource == source
    return Button {
      withAnimation(.snappy) { commerceSource = source }
    } label: {
      Text(title)
        .font(.subheadline.weight(selected ? .semibold : .regular))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .foregroundStyle(selected ? .white : palette.primaryText)
        .background(selected ? Color.pink : Color.primary.opacity(0.06), in: Capsule())
    }
    .buttonStyle(.plain)
  }

  private var commerceItemGrid: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(commerceSource?.labelZH ?? "在售与 OUTLET")
          .font(.system(.title3, design: .serif).weight(.semibold))
          .foregroundStyle(palette.primaryText)
        Spacer()
        Text("\(filteredCommerceItems.count) 件")
          .font(.caption.monospacedDigit())
          .foregroundStyle(palette.secondaryText)
      }
      if filteredCommerceItems.isEmpty {
        Text("暂无官方商品")
          .font(.subheadline)
          .foregroundStyle(palette.secondaryText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 40)
      } else {
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
          spacing: 14
        ) {
          ForEach(filteredCommerceItems) { item in
            TimeHallCommerceItemCard(item: item) {
              detailCommerceItem = item
            }
          }
        }
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(palette.secondaryText)
      TextField(
        mode == .chronicle ? "搜索编年史资料".appLocalized : "搜索商品、品番".appLocalized,
        text: $searchText
      )
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func magazinePageGrid(title: String, items: [TimeHallItemDTO]) -> some View {
    let groups = groupedItemsByImage(items)
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(title)
          .font(.system(.title3, design: .serif).weight(.semibold))
          .foregroundStyle(palette.primaryText)
        Spacer()
        Text("\(groups.count) 幅")
          .font(.caption.monospacedDigit())
          .foregroundStyle(palette.secondaryText)
      }

      if items.isEmpty {
        Text("暂无杂志内页".appLocalized)
          .font(.subheadline)
          .foregroundStyle(palette.secondaryText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 40)
      } else {
        LazyVGrid(
          columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
          spacing: 14
        ) {
          ForEach(groups) { group in
            TimeHallMagazinePageCard(group: group)
          }
        }
      }
    }
  }

  private func groupedItemsByImage(_ items: [TimeHallItemDTO]) -> [TimeHallMagazinePageGroup] {
    var order: [String] = []
    var values: [String: [TimeHallItemDTO]] = [:]
    for item in items {
      let key = item.coverImage ?? "item:\(item.id)"
      if values[key] == nil { order.append(key) }
      values[key, default: []].append(item)
    }
    return order.compactMap { key in
      guard let groupItems = values[key] else { return nil }
      return TimeHallMagazinePageGroup(id: key, items: groupItems)
    }
  }
}

private struct TimeHallMagazinePageCard: View {
  let group: TimeHallMagazinePageGroup
  @ObservedObject private var store = TimeHallCatalogStore.shared
  @Environment(ThemeManager.self) private var themeManager
  @Environment(\.colorScheme) private var colorScheme

  private var palette: MagicThemePalette {
    MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
  }

  private var item: TimeHallItemDTO { group.primaryItem }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .topTrailing) {
        TimeHallBundleImage(
          fileName: item.coverImage,
          placeholderSystemImage: "book.pages.fill"
        )
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

        Button {
          store.toggleTreasure(item.id)
        } label: {
          Image(systemName: store.isTreasured(item.id) ? "heart.fill" : "heart")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(store.isTreasured(item.id) ? Color.pink : .white)
            .padding(8)
            .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(8)
      }

      Text("\(String(item.year)) \(TimeHallSeason(rawValue: item.season)?.labelZH ?? item.season) · 第 \(item.cataloguePage) 页")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.primaryText)
        .lineLimit(1)
      Text("编年史官方杂志内页")
        .font(.caption2.weight(.medium))
        .foregroundStyle(Color.pink)
      Text("PINK HOUSE 官方目录")
        .font(.caption)
        .foregroundStyle(palette.secondaryText)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(String(item.year)) 年第 \(item.cataloguePage) 页编年史官方杂志内页")
  }
}

@MainActor
private enum TimeHallWardrobeDraftBuilder {
  static func makeDraft(
    for item: TimeHallItemDTO,
    store: TimeHallCatalogStore,
    modelContext: ModelContext
  ) -> ClothingEditDraft {
    let imageName = item.coverImage ?? item.gallery.first
    let noteLines = compactNoteLines(
      productCode: item.productCode,
      material: nil,
      countryOfOrigin: nil,
      salePriceJPY: nil,
      regularPriceJPY: nil,
      sourceURL: item.productPageURL ?? item.sourceURL
    )

    return draft(
      name: item.displayName,
      brand: item.brand,
      type: item.displayCategory,
      colors: "",
      sizes: "",
      originalPriceJPY: item.priceJPY,
      imageName: imageName,
      note: noteLines,
      store: store,
      modelContext: modelContext
    )
  }

  static func makeDraft(
    for item: TimeHallCommerceItemDTO,
    store: TimeHallCatalogStore,
    modelContext: ModelContext
  ) -> ClothingEditDraft {
    let noteLines = compactNoteLines(
      productCode: item.productCode,
      material: item.material,
      countryOfOrigin: item.countryOfOrigin,
      salePriceJPY: item.salePriceJPY,
      regularPriceJPY: item.regularPriceJPY,
      sourceURL: item.productPageURL
    )

    return draft(
      name: item.displayName,
      brand: item.brand,
      type: item.displayCategory,
      colors: item.colors.joined(separator: ", "),
      sizes: item.sizes.joined(separator: ", "),
      originalPriceJPY: item.regularPriceJPY,
      imageName: item.coverImage,
      note: noteLines,
      store: store,
      modelContext: modelContext
    )
  }

  private static func draft(
    name: String,
    brand: String,
    type: String,
    colors: String,
    sizes: String,
    originalPriceJPY: Int,
    imageName: String?,
    note: String,
    store: TimeHallCatalogStore,
    modelContext: ModelContext
  ) -> ClothingEditDraft {
    let now = Date()
    let imagePaths: [String]
    if let image = store.image(named: imageName),
      let fileName = ImageManager.shared.saveImage(image, context: modelContext)
    {
      imagePaths = [fileName]
    } else {
      imagePaths = []
    }

    return ClothingEditDraft(
      name: name,
      brandName: brand,
      types: type,
      colors: colors,
      sizes: sizes,
      length: "",
      condition: "全新",
      accessories: "",
      imagePaths: imagePaths,
      isShared: false,
      originalPrice: 0,
      originalPriceJPY: Double(originalPriceJPY),
      originalPriceCurrencyCode: ClothingPriceCurrency.jpy.rawValue,
      priceTotal: 0,
      deposit: 0,
      balance: 0,
      accessoriesPrice: 0,
      stock: 1,
      purchaseDate: now,
      depositDate: now,
      isDepositPlan: false,
      reservationKindRawValue: ClothingReservationKind.owned.rawValue,
      finalPaymentDate: now,
      finalPaymentEndDate: now,
      note: note,
      accessoryList: []
    )
  }

  private static func compactNoteLines(
    productCode: String?,
    material: String?,
    countryOfOrigin: String?,
    salePriceJPY: Int?,
    regularPriceJPY: Int?,
    sourceURL: String
  ) -> String {
    let usesChinese = TimeHallDisplayLanguage.usesChinese
    var lines: [String] = []
    if let productCode, !productCode.isEmpty {
      lines.append(usesChinese ? "品番：\(productCode)" : "Product code: \(productCode)")
    }
    if let material, !material.isEmpty {
      lines.append(usesChinese ? "材质：\(material)" : "Material: \(material)")
    }
    if let countryOfOrigin, !countryOfOrigin.isEmpty {
      lines.append(usesChinese ? "产地：\(countryOfOrigin)" : "Made in: \(countryOfOrigin)")
    }
    if let salePriceJPY, let regularPriceJPY {
      let price = "JP¥\(salePriceJPY.formatted()) / JP¥\(regularPriceJPY.formatted())"
      lines.append(usesChinese ? "OUTLET 价格 / 原价：\(price)" : "OUTLET / regular price: \(price)")
    }
    if !sourceURL.isEmpty {
      lines.append(usesChinese ? "官方来源：\(sourceURL)" : "Official source: \(sourceURL)")
    }
    return lines.joined(separator: "\n")
  }
}

private struct TimeHallAddToWardrobeButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("加入衣橱".appLocalized, systemImage: "plus.circle.fill")
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
    }
    .buttonStyle(.borderedProminent)
    .buttonBorderShape(.capsule)
    .tint(.pink)
  }
}

struct TimeHallItemDetailView: View {
  let item: TimeHallItemDTO
  @ObservedObject private var store = TimeHallCatalogStore.shared
  @ObservedObject private var tabNavigationManager = TabNavigationManager.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(ThemeManager.self) private var themeManager
  @Environment(\.colorScheme) private var colorScheme

  private var palette: MagicThemePalette {
    MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          TabView {
            if item.gallery.isEmpty {
              TimeHallBundleImage(
                fileName: item.coverImage,
                placeholderSystemImage: item.kind.symbolName
              )
              .scaledToFit()
              .frame(maxWidth: .infinity)
              .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
              .padding(.horizontal, 20)
            } else {
              ForEach(item.gallery, id: \.self) { name in
                TimeHallBundleImage(
                  fileName: name,
                  placeholderSystemImage: item.kind.symbolName
                )
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)
              }
            }
          }
          .tabViewStyle(.page(indexDisplayMode: .automatic))
          .frame(height: 420)

          VStack(alignment: .leading, spacing: 10) {
            Text(item.displayName)
              .font(.system(.title2, design: .serif).weight(.semibold))
            if item.displayName != item.name {
              Text(TimeHallDisplayLanguage.officialName(item.name))
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            }
            Text(
              "\(item.brand) · \(String(item.year)) · \(TimeHallSeason(rawValue: item.season)?.labelZH ?? item.season)"
            )
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.pink)
            HStack(spacing: 8) {
              Label(item.kind.labelZH, systemImage: item.kind.symbolName)
              Text(item.displayCategory)
              Spacer()
              Text("¥\(item.priceJPY.formatted())")
                .fontWeight(.semibold)
            }
            .font(.subheadline)

            Text(cataloguePageLabel)
              .font(.footnote)
              .foregroundStyle(palette.secondaryText)

            if let productCode = item.productCode, !productCode.isEmpty {
              Text("品番 \(productCode)")
                .font(.caption.monospaced())
                .foregroundStyle(palette.secondaryText)
            }

            FlowLayout(spacing: 8) {
              ForEach(
                TimeHallDisplayLanguage.usesChinese ? item.stylesZH : item.styles,
                id: \.self
              ) { tag in
                Text(tag)
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background(Color.pink.opacity(0.12), in: Capsule())
              }
            }

            TimeHallAddToWardrobeButton(action: addToWardrobe)

            if let imageURL = URL(string: item.imageSourceURL) {
              Link(destination: imageURL) {
                Label("查看图录原图", systemImage: "photo")
                  .font(.subheadline.weight(.semibold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 11)
              }
              .buttonStyle(.bordered)
              .buttonBorderShape(.capsule)
            }

            if let url = URL(string: item.sourceURL) {
              Link(destination: url) {
                Label("打开资料页", systemImage: "arrow.up.right.square")
                  .font(.subheadline.weight(.semibold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 11)
              }
              .buttonStyle(.bordered)
              .buttonBorderShape(.capsule)
            }

            if let value = item.productPageURL, let url = URL(string: value) {
              Link(destination: url) {
                Label("查看官方商品页", systemImage: "bag")
                  .font(.subheadline.weight(.semibold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 11)
              }
              .buttonStyle(.bordered)
              .buttonBorderShape(.capsule)
            }

          }
          .padding(.horizontal, 20)
          .padding(.bottom, 40)
        }
      }
      .background(
        LiquidBackground(themeSkinWallpaperContext: .timeHall, includeThemeSkinStickers: false)
      )
      .navigationTitle("馆藏详情".appLocalized)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭".appLocalized) { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            store.toggleTreasure(item.id)
          } label: {
            Image(systemName: store.isTreasured(item.id) ? "heart.fill" : "heart")
              .foregroundStyle(Color.pink)
          }
        }
      }
    }
  }

  private var cataloguePageLabel: String {
    let pages = item.cataloguePages ?? [item.cataloguePage]
    if pages.count == 1 {
      return "图录第 \(pages[0]) 页"
    }
    return "图录出现页：\(pages.map(String.init).joined(separator: "、"))"
  }

  private func addToWardrobe() {
    let draft = TimeHallWardrobeDraftBuilder.makeDraft(
      for: item,
      store: store,
      modelContext: modelContext
    )
    dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      tabNavigationManager.presentWardrobeCreation(with: draft)
    }
  }
}

struct TimeHallCommerceItemCard: View {
  let item: TimeHallCommerceItemDTO
  let onTap: () -> Void
  @ObservedObject private var store = TimeHallCatalogStore.shared
  @Environment(ThemeManager.self) private var themeManager
  @Environment(\.colorScheme) private var colorScheme

  private var palette: MagicThemePalette {
    MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
  }

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 8) {
        ZStack(alignment: .topTrailing) {
          TimeHallBundleImage(
            fileName: item.coverImage, placeholderSystemImage: item.kind.symbolName
          )
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .frame(height: 180)
          .clipped()
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

          Button {
            store.toggleTreasure(item.id)
          } label: {
            Image(systemName: store.isTreasured(item.id) ? "heart.fill" : "heart")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(store.isTreasured(item.id) ? Color.pink : .white)
              .padding(8)
              .background(.ultraThinMaterial, in: Circle())
          }
          .buttonStyle(.plain)
          .padding(8)
        }

        Text(item.sourceKind.labelZH)
          .font(.caption2.weight(.bold))
          .foregroundStyle(item.sourceKind == .outlet ? Color.orange : Color.pink)
        Text(item.displayName)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.primaryText)
          .lineLimit(2)
        Text("\(item.kind.labelZH) · \(item.displayCategory)")
          .font(.caption2)
          .foregroundStyle(palette.secondaryText)
        HStack(spacing: 6) {
          if let salePrice = item.salePriceJPY {
            Text("¥\(item.regularPriceJPY.formatted())")
              .strikethrough()
              .foregroundStyle(palette.secondaryText)
            Text("¥\(salePrice.formatted())")
              .foregroundStyle(Color.orange)
          } else {
            Text("¥\(item.regularPriceJPY.formatted())")
              .foregroundStyle(palette.primaryText)
          }
        }
        .font(.caption.weight(.semibold))
      }
    }
    .buttonStyle(.plain)
  }
}

struct TimeHallCommerceItemDetailView: View {
  let item: TimeHallCommerceItemDTO
  @ObservedObject private var store = TimeHallCatalogStore.shared
  @ObservedObject private var tabNavigationManager = TabNavigationManager.shared
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(ThemeManager.self) private var themeManager
  @Environment(\.colorScheme) private var colorScheme

  private var palette: MagicThemePalette {
    MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
  }

  private var bundledImages: [String] {
    [item.coverImage, item.detailImage].compactMap { $0 }.reduce(into: []) { result, name in
      if !result.contains(name) { result.append(name) }
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          TabView {
            ForEach(bundledImages, id: \.self) { fileName in
              TimeHallBundleImage(fileName: fileName, placeholderSystemImage: item.kind.symbolName)
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)
            }
          }
          .tabViewStyle(.page(indexDisplayMode: .automatic))
          .frame(height: 420)

          VStack(alignment: .leading, spacing: 12) {
            Text(item.sourceKind.labelZH)
              .font(.caption.weight(.bold))
              .foregroundStyle(item.sourceKind == .outlet ? Color.orange : Color.pink)
            Text(item.displayName)
              .font(.system(.title2, design: .serif).weight(.semibold))
              .foregroundStyle(palette.primaryText)
            if item.displayName != item.name {
              Text(TimeHallDisplayLanguage.officialName(item.name))
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
            }
            Text("品番 \(item.productCode)")
              .font(.caption.monospaced())
              .foregroundStyle(palette.secondaryText)
            HStack(spacing: 8) {
              Label(item.kind.labelZH, systemImage: item.kind.symbolName)
              Text(item.displayCategory)
              Spacer()
              commercePrice
            }
            .font(.subheadline)

            TimeHallAddToWardrobeButton(action: addToWardrobe)

            detailFacts

            if !item.stylesZH.isEmpty {
              FlowLayout(spacing: 8) {
                ForEach(item.displayStyles, id: \.self) { tag in
                  Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.pink.opacity(0.12), in: Capsule())
                }
              }
            }

            if !item.description.isEmpty {
              Text(
                TimeHallDisplayLanguage.usesChinese
                  ? "官方日文介绍".appLocalized : "官方介绍".appLocalized
              )
              .font(.headline)
              .foregroundStyle(palette.primaryText)
              .padding(.top, 4)
              Text(item.description)
                .font(.body)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let url = URL(string: item.productPageURL) {
              Link(destination: url) {
                Label("查看官方商品页", systemImage: "bag")
                  .font(.subheadline.weight(.semibold))
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 11)
              }
              .buttonStyle(.bordered)
              .buttonBorderShape(.capsule)
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 40)
        }
      }
      .background(
        LiquidBackground(themeSkinWallpaperContext: .timeHall, includeThemeSkinStickers: false)
      )
      .navigationTitle("商品详情".appLocalized)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭".appLocalized) { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            store.toggleTreasure(item.id)
          } label: {
            Image(systemName: store.isTreasured(item.id) ? "heart.fill" : "heart")
              .foregroundStyle(Color.pink)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var commercePrice: some View {
    if let salePrice = item.salePriceJPY {
      VStack(alignment: .trailing, spacing: 2) {
        Text("¥\(item.regularPriceJPY.formatted())").strikethrough()
          .foregroundStyle(palette.secondaryText)
        Text("¥\(salePrice.formatted())")
          .fontWeight(.semibold)
          .foregroundStyle(Color.orange)
      }
    } else {
      Text("¥\(item.regularPriceJPY.formatted())")
        .fontWeight(.semibold)
    }
  }

  private var detailFacts: some View {
    VStack(alignment: .leading, spacing: 7) {
      if !item.colors.isEmpty {
        Label("颜色：\(item.colors.joined(separator: "、"))", systemImage: "paintpalette")
      }
      if !item.sizes.isEmpty {
        Label("尺寸：\(item.sizes.joined(separator: "、"))", systemImage: "ruler")
      }
      if let material = item.material, !material.isEmpty {
        Label("材质：\(material)", systemImage: "square.grid.3x3")
      }
      if let country = item.countryOfOrigin, !country.isEmpty {
        Label("产地：\(country)", systemImage: "globe.asia.australia")
      }
    }
    .font(.footnote)
    .foregroundStyle(palette.secondaryText)
  }

  private func addToWardrobe() {
    let draft = TimeHallWardrobeDraftBuilder.makeDraft(
      for: item,
      store: store,
      modelContext: modelContext
    )
    dismiss()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      tabNavigationManager.presentWardrobeCreation(with: draft)
    }
  }
}

struct TimeHallCoordinateDetailView: View {
  let coordinate: TimeHallCoordinateDTO
  @ObservedObject private var store = TimeHallCatalogStore.shared
  @State private var detailCommerceItem: TimeHallCommerceItemDTO?
  @Environment(\.dismiss) private var dismiss
  @Environment(ThemeManager.self) private var themeManager
  @Environment(\.colorScheme) private var colorScheme

  private var palette: MagicThemePalette {
    MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
  }

  private var linkedItems: [TimeHallCommerceItemDTO] {
    let ids = Set(coordinate.linkedCommerceItemIDs)
    return store.commerceItems.filter { ids.contains($0.id) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          TimeHallBundleImage(
            fileName: coordinate.coverImage,
            placeholderSystemImage: "person.crop.rectangle.stack"
          )
          .scaledToFit()
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

          Text(coordinate.displayTitle)
            .font(.system(.title2, design: .serif).weight(.semibold))
            .foregroundStyle(palette.primaryText)
          if coordinate.displayTitle != coordinate.title {
            Text(TimeHallDisplayLanguage.officialTitle(coordinate.title))
              .font(.subheadline)
              .foregroundStyle(palette.secondaryText)
          }
          Text(coordinate.publishedOn ?? "日期未标注")
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(Color.pink)

          Text(
            TimeHallDisplayLanguage.usesChinese
              ? "官方日文搭配记录".appLocalized : "搭配说明".appLocalized
          )
          .font(.headline)
          .foregroundStyle(palette.primaryText)
          Text(coordinate.coordinatePoint)
            .font(.body)
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

          if !linkedItems.isEmpty {
            Text("已关联图鉴商品".appLocalized)
              .font(.headline)
              .foregroundStyle(palette.primaryText)
            ForEach(linkedItems) { item in
              TimeHallLinkedCommerceItemButton(
                item: item,
                primaryText: palette.primaryText,
                secondaryText: palette.secondaryText
              ) {
                detailCommerceItem = item
              }
            }
          }

          if !coordinate.unlinkedItemNames.isEmpty {
            Text("搭配单品".appLocalized)
              .font(.headline)
              .foregroundStyle(palette.primaryText)
            FlowLayout(spacing: 8) {
              ForEach(coordinate.unlinkedItemNames, id: \.self) { name in
                Text(name)
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background(Color.pink.opacity(0.12), in: Capsule())
              }
            }
          }

          if let url = URL(string: coordinate.sourceURL) {
            Link(destination: url) {
              Label("查看官方搭配页", systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.pink)
          }
        }
        .padding(20)
        .padding(.bottom, 30)
      }
      .background(
        LiquidBackground(themeSkinWallpaperContext: .timeHall, includeThemeSkinStickers: false)
      )
      .navigationTitle("搭配详情".appLocalized)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭".appLocalized) { dismiss() }
        }
      }
    }
    .sheet(item: $detailCommerceItem) { item in
      TimeHallCommerceItemDetailView(item: item)
    }
  }
}

struct TimeHallStoryDetailView: View {
  let story: TimeHallStoryDTO
  @ObservedObject private var store = TimeHallCatalogStore.shared
  @State private var detailCommerceItem: TimeHallCommerceItemDTO?
  @Environment(\.dismiss) private var dismiss
  @Environment(ThemeManager.self) private var themeManager
  @Environment(\.colorScheme) private var colorScheme

  private var palette: MagicThemePalette {
    MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
  }

  private var linkedItems: [TimeHallCommerceItemDTO] {
    let ids = Set(story.linkedCommerceItemIDs)
    return store.commerceItems.filter { ids.contains($0.id) }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          TimeHallBundleImage(
            fileName: story.coverImage, placeholderSystemImage: story.kind.symbolName
          )
          .scaledToFit()
          .frame(maxWidth: .infinity)
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

          Label(story.kind.labelZH, systemImage: story.kind.symbolName)
            .font(.caption.weight(.bold))
            .foregroundStyle(story.kind == .craft ? Color.orange : Color.pink)
          Text(story.displayTitle)
            .font(.system(.title2, design: .serif).weight(.semibold))
            .foregroundStyle(palette.primaryText)
          if story.displayTitle != story.title {
            Text(TimeHallDisplayLanguage.officialTitle(story.title))
              .font(.subheadline)
              .foregroundStyle(palette.secondaryText)
          }
          if let publishedOn = story.publishedOn {
            Text(publishedOn)
              .font(.caption.monospacedDigit())
              .foregroundStyle(palette.secondaryText)
          }

          if !TimeHallDisplayLanguage.usesChinese {
            Text(story.summary)
              .font(.headline)
              .foregroundStyle(palette.primaryText)
              .fixedSize(horizontal: false, vertical: true)
          }

          Text(
            TimeHallDisplayLanguage.usesChinese
              ? "官方日文原文".appLocalized : "官方正文".appLocalized
          )
          .font(.headline)
          .foregroundStyle(palette.primaryText)
          Text(story.content)
            .font(.body)
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)

          if !linkedItems.isEmpty {
            Text("已关联图鉴商品".appLocalized)
              .font(.headline)
              .foregroundStyle(palette.primaryText)
            ForEach(linkedItems) { item in
              TimeHallLinkedCommerceItemButton(
                item: item,
                primaryText: palette.primaryText,
                secondaryText: palette.secondaryText
              ) {
                detailCommerceItem = item
              }
            }
          }

          if let url = URL(string: story.sourceURL) {
            Link(destination: url) {
              Label("查看官方专题页", systemImage: "arrow.up.right.square")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.pink)
          }
        }
        .padding(20)
        .padding(.bottom, 30)
      }
      .background(
        LiquidBackground(themeSkinWallpaperContext: .timeHall, includeThemeSkinStickers: false)
      )
      .navigationTitle("专题详情".appLocalized)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("关闭".appLocalized) { dismiss() }
        }
      }
    }
    .sheet(item: $detailCommerceItem) { item in
      TimeHallCommerceItemDetailView(item: item)
    }
  }
}

private struct TimeHallLinkedCommerceItemButton: View {
  let item: TimeHallCommerceItemDTO
  let primaryText: Color
  let secondaryText: Color
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        TimeHallBundleImage(
          fileName: item.coverImage, placeholderSystemImage: item.kind.symbolName
        )
        .scaledToFill()
        .frame(width: 64, height: 80)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        VStack(alignment: .leading, spacing: 4) {
          Text(item.displayName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(primaryText)
            .lineLimit(2)
          Text("品番 \(item.productCode)")
            .font(.caption.monospaced())
            .foregroundStyle(secondaryText)
        }

        Spacer(minLength: 6)

        VStack(spacing: 4) {
          Image(systemName: "chevron.right")
          Text("查看大图".appLocalized)
            .font(.caption2)
            .lineLimit(1)
        }
        .foregroundStyle(Color.pink)
      }
      .padding(10)
      .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(item.displayName)，\("查看大图".appLocalized)")
  }
}

struct TimeHallBundleImage: View {
  let fileName: String?
  var placeholderSystemImage = "tshirt.fill"
  @ObservedObject private var store = TimeHallCatalogStore.shared
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
      } else {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(Color.pink.opacity(0.12))
          .overlay {
            Image(systemName: placeholderSystemImage)
              .foregroundStyle(Color.pink.opacity(0.5))
          }
        }
      }
    .task(id: fileName) {
      image = nil
      image = await store.loadImage(named: fileName)
    }
  }
}
