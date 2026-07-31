import SwiftUI

enum TimeHallMode: String, CaseIterable, Identifiable {
    case chronicle
    case styleSpray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chronicle: return "编年史".appLocalized
        case .styleSpray: return "风格".appLocalized
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
    @State private var detailDress: TimeHallDressDTO?
    @State private var showTreasuresOnly = false
    @State private var searchText = ""

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var activeYear: Int {
        selectedYear ?? store.years.first ?? 2024
    }

    private var filteredDresses: [TimeHallDressDTO] {
        var list = store.dresses
        if showTreasuresOnly {
            list = list.filter { store.isTreasured($0.id) }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.nameZH.lowercased().contains(q)
                    || $0.name.lowercased().contains(q)
                    || $0.stylesZH.joined().lowercased().contains(q)
                    || $0.storeLimitZH.lowercased().contains(q)
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
        .sheet(item: $detailDress) { dress in
            TimeHallDressDetailView(dress: dress)
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
                if !store.dresses.isEmpty {
                    Text("\(store.dresses.count) 馆藏 · \(store.collections.count) 辑")
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
        .controlSize(.small)
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
        .controlSize(.small)
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
                collectionSection
                dressGrid(title: "馆藏精选".appLocalized, dresses: dressesForActiveYear)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }

    private var dressesForActiveYear: [TimeHallDressDTO] {
        let ids = Set(store.collections(for: activeYear).flatMap(\.dressIds))
        return filteredDresses.filter { ids.contains($0.id) || $0.year == activeYear }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            TimeHallBundleImage(fileName: store.catalog?.heroImage ?? "hero.jpg")
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
                Text("\(store.dresses.count) Dresses")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .unifiedShadow(.card)
    }

    private var yearRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.years, id: \.self) { year in
                    let selected = year == activeYear
                    Button {
                        withAnimation(.snappy) { selectedYear = year }
                    } label: {
                        VStack(spacing: 4) {
                            Text(String(year))
                                .font(.system(.headline, design: .serif))
                            Text(store.collections(for: year).map(\.seasonLabel).joined(separator: "·"))
                                .font(.caption2)
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
            }
        }
    }

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.collections(for: activeYear)) { collection in
                GlassCard(cornerRadius: 22, padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(collection.year) · \(collection.seasonLabel)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.pink)
                            Spacer()
                            Text("\(collection.dressIds.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(palette.secondaryText)
                        }
                        Text(collection.titleZH)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                        Text(collection.summaryZH)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var styleSprayContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                searchField
                dressGrid(
                    title: selectedStyle.map { "「\($0)」".appLocalized } ?? "全部风格".appLocalized,
                    dresses: selectedStyle.map { store.dresses(withStyle: $0).filter { filteredDresses.contains($0) } } ?? filteredDresses
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
            TextField("搜索裙装、风格、限定店".appLocalized, text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dressGrid(title: String, dresses: [TimeHallDressDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(palette.primaryText)

            if dresses.isEmpty {
                Text("暂无馆藏".appLocalized)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(dresses) { dress in
                        TimeHallDressCard(dress: dress) {
                            detailDress = dress
                        }
                    }
                }
            }
        }
    }
}

struct TimeHallDressCard: View {
    let dress: TimeHallDressDTO
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
                    TimeHallBundleImage(fileName: dress.coverImage)
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Button {
                        store.toggleTreasure(dress.id)
                    } label: {
                        Image(systemName: store.isTreasured(dress.id) ? "heart.fill" : "heart")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(store.isTreasured(dress.id) ? Color.pink : .white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }

                Text(dress.nameZH)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text("\(dress.brand) · \(dress.year)")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

struct TimeHallDressDetailView: View {
    let dress: TimeHallDressDTO
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
                        ForEach(dress.gallery, id: \.self) { name in
                            TimeHallBundleImage(fileName: name)
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .padding(.horizontal, 20)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .frame(height: 420)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(dress.nameZH)
                            .font(.system(.title2, design: .serif).weight(.semibold))
                        Text(dress.name)
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                        Text("\(dress.brand) · \(dress.year) · \(TimeHallSeason(rawValue: dress.season)?.labelZH ?? dress.season)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.pink)
                        Text(dress.storeLimitZH)
                            .font(.footnote)
                            .foregroundStyle(palette.secondaryText)

                        FlowLayout(spacing: 8) {
                            ForEach(dress.stylesZH, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.pink.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(dress.noteZH)
                            .font(.body)
                            .foregroundStyle(palette.primaryText)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(LiquidBackground(themeSkinWallpaperContext: .timeHall, includeThemeSkinStickers: false))
            .navigationTitle("馆藏详情".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭".appLocalized) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.toggleTreasure(dress.id)
                    } label: {
                        Image(systemName: store.isTreasured(dress.id) ? "heart.fill" : "heart")
                            .foregroundStyle(Color.pink)
                    }
                }
            }
        }
    }
}

struct TimeHallBundleImage: View {
    let fileName: String
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
                        Image(systemName: "tshirt.fill")
                            .foregroundStyle(Color.pink.opacity(0.5))
                    }
            }
        }
    }
}
