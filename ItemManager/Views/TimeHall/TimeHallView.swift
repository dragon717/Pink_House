import SwiftUI

enum TimeHallMode: String, CaseIterable, Identifiable {
  case chronicle
  case styleSpray

  var id: String { rawValue }

  var title: String {
    switch self {
    case .chronicle: return "编年史".appLocalized
    case .styleSpray: return "图鉴".appLocalized
    }
  }
}

struct TimeHallView: View {
  @Environment(ThemeManager.self) private var themeManager
  @Environment(\.colorScheme) private var colorScheme
  @ObservedObject private var store = TimeHallCatalogStore.shared

  @State private var mode: TimeHallMode = .chronicle
  @State private var selectedYear: Int?
  @State private var selectedStyle: String?
  @State private var detailItem: TimeHallItemDTO?
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
          }
        }
      }
    }
    .sheet(item: $detailItem) { item in
      TimeHallItemDetailView(item: item)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(store.catalog?.title ?? "梦裙时光馆".appLocalized)
          .font(.system(.largeTitle, design: .serif).weight(.semibold))
          .foregroundStyle(palette.primaryText)
        Text(store.catalog?.subtitle ?? "")
          .font(.subheadline)
          .foregroundStyle(palette.secondaryText)
        if !store.items.isEmpty {
          Text(
            "\(store.timelineYears.count) 年 · \(store.archiveCatalogues.count) 份图录 · \(store.items.count) 件馆藏"
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
        if mode == .styleSpray {
          styleFilterMenu
        }
        treasureButton
      }

      HStack(spacing: 8) {
        if mode == .styleSpray {
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
        heroCard
        yearRail
        archiveCatalogueSection
        yearStoryCard
        catalogueSection
        if !itemsForActiveYear.isEmpty {
          itemGrid(title: "馆藏精选".appLocalized, items: itemsForActiveYear)
        }
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

  private var heroCard: some View {
    ZStack(alignment: .bottomLeading) {
      TimeHallBundleImage(fileName: store.catalog?.heroImage)
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipped()

      LinearGradient(
        colors: [.clear, .black.opacity(0.55)],
        startPoint: .center,
        endPoint: .bottom
      )

      VStack(alignment: .leading, spacing: 8) {
        Text(store.catalog?.heroCaption ?? "")
          .font(.system(.title3, design: .serif).weight(.semibold))
          .foregroundStyle(.white)
        Text(store.catalog?.heroBody ?? "")
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.9))
          .lineLimit(3)
      }
      .padding(18)
    }
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .unifiedShadow(.card)
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
      .accessibilityLabel("\(record.year) \(record.titleZH)，\(record.evidenceLevel.labelZH)")
    }
  }

  @ViewBuilder
  private var archiveCatalogueSection: some View {
    let catalogues = store.archiveCatalogues(for: activeYear)
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
        Text("重点商品样板")
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
                Text("样板 \(catalogue.itemIds.count) 件")
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

  private var styleSprayContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        searchField
        itemGrid(
          title: selectedStyle.map { "「\($0)」".appLocalized } ?? "全部风格".appLocalized,
          items: selectedStyle.map {
            store.items(withStyle: $0).filter { filteredItems.contains($0) }
          } ?? filteredItems
        )
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 120)
    }
    .scrollIndicators(.hidden)
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(palette.secondaryText)
      TextField("搜索裙装、小物、风格".appLocalized, text: $searchText)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func itemGrid(title: String, items: [TimeHallItemDTO]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(.title3, design: .serif).weight(.semibold))
        .foregroundStyle(palette.primaryText)

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
          ForEach(items) { item in
            TimeHallItemCard(item: item) {
              detailItem = item
            }
          }
        }
      }
    }
  }
}

struct TimeHallItemCard: View {
  let item: TimeHallItemDTO
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

        Text(item.nameZH)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.primaryText)
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(item.kind.labelZH)
          Text("·")
          Text(item.categoryZH)
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

struct TimeHallItemDetailView: View {
  let item: TimeHallItemDTO
  @ObservedObject private var store = TimeHallCatalogStore.shared
  @Environment(\.dismiss) private var dismiss
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
            Text(item.nameZH)
              .font(.system(.title2, design: .serif).weight(.semibold))
            Text(item.name)
              .font(.subheadline)
              .foregroundStyle(palette.secondaryText)
            Text(
              "\(item.brand) · \(item.year) · \(TimeHallSeason(rawValue: item.season)?.labelZH ?? item.season)"
            )
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.pink)
            HStack(spacing: 8) {
              Label(item.kind.labelZH, systemImage: item.kind.symbolName)
              Text(item.categoryZH)
              Spacer()
              Text("¥\(item.priceJPY.formatted())")
                .fontWeight(.semibold)
            }
            .font(.subheadline)

            Text("图录第 \(item.cataloguePage) 页")
              .font(.footnote)
              .foregroundStyle(palette.secondaryText)

            FlowLayout(spacing: 8) {
              ForEach(item.stylesZH, id: \.self) { tag in
                Text(tag)
                  .font(.caption)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 5)
                  .background(Color.pink.opacity(0.12), in: Capsule())
              }
            }

            Text(item.noteZH)
              .font(.body)
              .foregroundStyle(palette.primaryText)
              .padding(.top, 4)

            Text("图片来自图录第 \(item.cataloguePage) 页；同页展品会共享这张原图。")
              .font(.caption)
              .foregroundStyle(palette.secondaryText)

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
