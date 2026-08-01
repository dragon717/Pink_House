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
    case .styleSpray: return "图鉴".appLocalized
    case .story: return "专题".appLocalized
    case .coordinate: return "搭配".appLocalized
    }
  }
}

enum TimeHallIllustrationSection: String, CaseIterable, Identifiable {
  case catalogue
  case commerce

  var id: String { rawValue }

  var title: String {
    switch self {
    case .catalogue: return "目录馆藏".appLocalized
    case .commerce: return "官方商品".appLocalized
    }
  }
}

private struct TimeHallItemImageGroup: Identifiable {
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
  @ObservedObject private var store = TimeHallCatalogStore.shared

  @State private var mode: TimeHallMode = .chronicle
  @State private var illustrationSection: TimeHallIllustrationSection = .catalogue
  @State private var selectedYear: Int?
  @State private var selectedStyle: String?
  @State private var detailItem: TimeHallItemDTO?
  @State private var detailCommerceItem: TimeHallCommerceItemDTO?
  @State private var detailCoordinate: TimeHallCoordinateDTO?
  @State private var detailStory: TimeHallStoryDTO?
  @State private var commerceSource: TimeHallCommerceSource?
  @State private var showTreasuresOnly = false
  @State private var searchText = ""
  @State private var isTimelineAscending = false

  private var palette: MagicThemePalette {
    MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
  }

  private var activeYear: Int {
    selectedYear ?? orderedTimelineYears.first ?? 2024
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
    if let selectedStyle {
      list = list.filter {
        $0.stylesZH.contains(selectedStyle) || $0.styles.contains(selectedStyle)
      }
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
    ZStack {
      LiquidBackground(themeSkinWallpaperContext: .timeHall)

      VStack(spacing: 0) {
        header
        modePicker
          .padding(.horizontal, 20)
          .padding(.bottom, 10)

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
      }
    }
    .sheet(item: $detailItem) { item in
      TimeHallItemDetailView(item: item)
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

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text((store.catalog?.title ?? "梦裙时光馆").appLocalized)
          .font(.system(.largeTitle, design: .serif).weight(.semibold))
          .foregroundStyle(palette.primaryText)
        Text(store.catalog?.subtitle ?? "")
          .font(.subheadline)
          .foregroundStyle(palette.secondaryText)
        if !store.items.isEmpty || !store.commerceItems.isEmpty {
          Text(
            "\(store.catalog?.scope.labelZH ?? "1972–至今") · \(store.items.count) 件目录馆藏 · \(store.commerceItems.count) 件官方商品"
          )
          .font(.caption)
          .foregroundStyle(palette.secondaryText.opacity(0.85))
        }
      }
      Spacer(minLength: 8)
      headerActions
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 8)
  }

  /// Prefer the full label, then collapse to familiar symbols when the title area needs the width.
  /// This lets Dynamic Type and localized titles keep a single, tappable 44 pt control.
  @ViewBuilder
  private var headerActions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        if mode == .styleSpray && illustrationSection == .catalogue {
          styleFilterMenu
        }
        treasureButton
      }

      HStack(spacing: 8) {
        if mode == .styleSpray && illustrationSection == .catalogue {
          styleFilterMenuCompact
        }
        treasureButtonCompact
      }
    }
  }

  /// Apple HIG: bordered capsule with a stable, single-line label.
  private var treasureButton: some View {
    Button {
      showTreasuresOnly.toggle()
    } label: {
      Label("珍藏".appLocalized, systemImage: showTreasuresOnly ? "heart.fill" : "heart")
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
    .buttonStyle(.bordered)
    .controlSize(.regular)
    .buttonBorderShape(.capsule)
    .tint(showTreasuresOnly ? .pink : nil)
    .accessibilityLabel("珍藏".appLocalized)
    .accessibilityValue(showTreasuresOnly ? "已开启".appLocalized : "已关闭".appLocalized)
  }

  private var treasureButtonCompact: some View {
    Button {
      showTreasuresOnly.toggle()
    } label: {
      Image(systemName: showTreasuresOnly ? "heart.fill" : "heart")
    }
    .buttonStyle(.bordered)
    .controlSize(.regular)
    .buttonBorderShape(.circle)
    .tint(showTreasuresOnly ? .pink : nil)
    .frame(width: 44, height: 44)
    .accessibilityLabel("珍藏".appLocalized)
    .accessibilityValue(showTreasuresOnly ? "已开启".appLocalized : "已关闭".appLocalized)
  }

  /// Apple HIG: `Menu` for filter choices; idle title「筛选」, selected title = tag only (stable min width).
  private var styleFilterMenu: some View {
    Menu {
      styleFilterMenuContent
    } label: {
      // Idle: 筛选 + icon. Selected: tag name only (HIG Menu trigger stays bordered/.regular).
      Group {
        if let selectedStyle {
          Text(selectedStyle)
            .lineLimit(1)
        } else {
          Label("筛选".appLocalized, systemImage: "line.3.horizontal.decrease")
            .labelStyle(.titleAndIcon)
        }
      }
      .frame(minWidth: 72, alignment: .center)
    }
    .buttonStyle(.bordered)
    .controlSize(.regular)
    .buttonBorderShape(.capsule)
    .tint(selectedStyle != nil ? .pink : nil)
    .accessibilityLabel("筛选".appLocalized)
    .accessibilityValue(selectedStyle ?? "全部风格".appLocalized)
  }

  @ViewBuilder
  private var styleFilterMenuContent: some View {
    Button {
      selectedStyle = nil
    } label: {
      if selectedStyle == nil {
        Label("全部风格".appLocalized, systemImage: "checkmark")
      } else {
        Text("全部风格".appLocalized)
      }
    }
    Divider()
    ForEach(store.styleBubbles()) { bubble in
      Button {
        selectedStyle = bubble.label
      } label: {
        if selectedStyle == bubble.label {
          Label(bubble.label, systemImage: "checkmark")
        } else {
          Text(bubble.label)
        }
      }
    }
  }

  private var styleFilterMenuCompact: some View {
    Menu {
      styleFilterMenuContent
    } label: {
      Image(systemName: "line.3.horizontal.decrease")
    }
    .buttonStyle(.bordered)
    .controlSize(.regular)
    .buttonBorderShape(.circle)
    .tint(selectedStyle != nil ? .pink : nil)
    .frame(width: 44, height: 44)
    .accessibilityLabel("筛选".appLocalized)
    .accessibilityValue(selectedStyle ?? "全部风格".appLocalized)
  }

  private var modePicker: some View {
    HStack(spacing: 0) {
      ForEach(TimeHallMode.allCases) { item in
        Button {
          withAnimation(.snappy) { mode = item }
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
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        searchField
        yearRail
        catalogueSection
        if !itemsForActiveYear.isEmpty {
          itemGrid(title: "馆藏精选".appLocalized, items: itemsForActiveYear)
        }
        archiveCatalogueSection
        yearStoryCard
        historyEvidenceSection
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 120)
    }
    .scrollIndicators(.hidden)
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
      .accessibilityLabel("\(record.year) \(record.titleZH)")
    }
  }

  @ViewBuilder
  private var archiveCatalogueSection: some View {
    let catalogues = archiveCataloguesForActiveYear
    if !catalogues.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("馆藏图录")
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
                  Label("查看图录", systemImage: "arrow.up.right.square")
                    .font(.caption2)
                    .foregroundStyle(palette.secondaryText)
                }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(catalogue.title) 图录")
            }
          }
        }
      }
    }
  }

  private var catalogueSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      if !store.catalogues(for: activeYear).isEmpty {
        Text("完整目录".appLocalized)
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
            .accessibilityLabel("\(catalogue.titleZH) 图录封面")

            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("\(catalogue.year) · \(catalogue.seasonLabel) · \(catalogue.pageCount) 页")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(Color.pink)
                Spacer()
                Text("馆藏 \(catalogue.itemIds.count) 件")
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
                  Label("查看图录", systemImage: "arrow.up.right.square")
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
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        searchField
        illustrationSectionPicker
        switch illustrationSection {
        case .catalogue:
          itemGrid(
            title: selectedStyle.map { "「\($0)」目录馆藏".appLocalized }
              ?? "目录馆藏".appLocalized,
            items: selectedStyle.map {
              store.items(withStyle: $0).filter { filteredItems.contains($0) }
            } ?? filteredItems
          )
        case .commerce:
          commerceSnapshotCard
          commerceSourcePicker
          commerceItemGrid
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 120)
    }
    .scrollIndicators(.hidden)
  }

  private var illustrationSectionPicker: some View {
    HStack(spacing: 8) {
      ForEach(TimeHallIllustrationSection.allCases) { section in
        let selected = illustrationSection == section
        Button {
          withAnimation(.snappy) {
            illustrationSection = section
            if section == .commerce { selectedStyle = nil }
          }
        } label: {
          Text(section.title)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(selected ? .white : palette.primaryText)
            .background(selected ? Color.pink : Color.primary.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var storyContent: some View {
    ScrollView {
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
    .scrollIndicators(.hidden)
  }

  private var coordinateContent: some View {
    ScrollView {
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
    .scrollIndicators(.hidden)
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
      TextField("搜索裙装、专题、品番".appLocalized, text: $searchText)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func itemGrid(title: String, items: [TimeHallItemDTO]) -> some View {
    let groups = groupedItemsByImage(items)
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(title)
          .font(.system(.title3, design: .serif).weight(.semibold))
          .foregroundStyle(palette.primaryText)
        Spacer()
        if groups.count != items.count {
          Text("\(groups.count) 幅·\(items.count) 件")
            .font(.caption.monospacedDigit())
            .foregroundStyle(palette.secondaryText)
        }
      }

      if items.isEmpty {
        Text("暂无馆藏".appLocalized)
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
            TimeHallItemCard(item: group.primaryItem, groupedItemCount: group.items.count) {
              detailItem = group.primaryItem
            }
          }
        }
      }
    }
  }

  private func groupedItemsByImage(_ items: [TimeHallItemDTO]) -> [TimeHallItemImageGroup] {
    var order: [String] = []
    var values: [String: [TimeHallItemDTO]] = [:]
    for item in items {
      let key = item.coverImage ?? "item:\(item.id)"
      if values[key] == nil { order.append(key) }
      values[key, default: []].append(item)
    }
    return order.compactMap { key in
      guard let groupItems = values[key] else { return nil }
      return TimeHallItemImageGroup(id: key, items: groupItems)
    }
  }
}

struct TimeHallItemCard: View {
  let item: TimeHallItemDTO
  var groupedItemCount = 1
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
            fileName: item.coverImage,
            placeholderSystemImage: item.kind.symbolName
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

        Text(
          groupedItemCount > 1
            ? "图录第 \(item.cataloguePage) 页 · \(groupedItemCount) 件" : item.displayName
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.primaryText)
        .lineLimit(1)
        HStack(spacing: 5) {
          Text(item.kind.labelZH)
          Text("·")
          Text(item.displayCategory)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Color.pink)
        Text("\(item.brand) · \(item.year) · ¥\(item.priceJPY.formatted())")
          .font(.caption)
          .foregroundStyle(palette.secondaryText)
      }
    }
    .buttonStyle(.plain)
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
              "\(item.brand) · \(item.year) · \(TimeHallSeason(rawValue: item.season)?.labelZH ?? item.season)"
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

  var body: some View {
    Group {
      if let image = store.image(named: fileName) {
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
  }
}
