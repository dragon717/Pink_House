import SwiftUI
import SwiftData
import UIKit

struct WardrobeStorageRoomView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorSchemeContrast) private var contrast
    @Query(sort: \Clothing.createdAt, order: .reverse) private var clothings: [Clothing]
    @Query(sort: \CutoutItem.timestamp, order: .reverse) private var cutouts: [CutoutItem]
    @AppStorage("privacyShowPrice") private var showPrice = true
    @State private var selectedDestination: WardrobeStorageDestination
    @State private var storageSettings = WardrobeStorageSettings.shared
    @State private var listMode = false
    @State private var searchText = ""
    @State private var shoeFilter: WardrobeShoeFilter = .all
    @State private var showingAdd = false
    @State private var showingCabinetEditor = false
    @State private var showingContents = false
    @State private var editingCabinet = false
    @State private var createAfterContents = false
    @State private var detailClothing: Clothing?
    @State private var cutoutRefresh = 0
    @State private var isPreparingImages = false
    @State private var imageFailureCount = 0
    @State private var preparationID = UUID()

    init(destination: WardrobeStorageDestination) {
        _selectedDestination = State(initialValue: destination)
    }

    private var customCabinet: WardrobeStorageCustomCabinet? {
        storageSettings.cabinets.first { $0.id == selectedDestination.customID }
    }
    private var destination: WardrobeStorageDestination {
        customCabinet.map(WardrobeStorageDestination.init(custom:)) ?? selectedDestination
    }
    private var category: WardrobeStorageCategory { destination.category }
    private var isShoeCabinet: Bool { destination.customID == nil && category == .shoes }


    private var palette: WardrobeStoragePalette {
        .themed(themeManager, scheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        let inventory = WardrobeStorageInventory.entries(clothings: clothings, cutouts: cutouts, customCabinets: storageSettings.cabinets)
        let collection = inventory.filter { $0.storageID == destination.id }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayed = collection.filter {
            (query.isEmpty || $0.searchTerms.localizedCaseInsensitiveContains(query)) &&
            (!isShoeCabinet || shoeFilter.matches($0.searchTerms))
        }
        let imageSources = preparationSources(inventory)
        let preparationKey = String(cutoutRefresh) + imageSources.map(\.key).joined(separator: "/")

        ZStack {
            LiquidBackground(themeSkinWallpaperContext: .wardrobe).ignoresSafeArea()
            HStack(alignment: .top, spacing: 8) {
                categoryRail
                VStack(spacing: 10) {
                    roomHeader(count: collection.reduce(0) { $0 + $1.quantity }, pendingCount: collection.filter { $0.statusLabel != nil }.count)
                    if listMode {
                        searchField
                    }
                    if isShoeCabinet {
                        if listMode {
                            shoeFilters
                        }
                    }
                    if !listMode && (!query.isEmpty || shoeFilter != .all) {
                        activeCabinetFilter
                    }
                    if imageFailureCount > 0 {
                        Text("有 %lld 张图片暂未抠出，可点右上角重试。".appLocalized(Int64(imageFailureCount)))
                            .font(.system(size: 11)).foregroundStyle(palette.secondary.color)
                            .padding(5).background(palette.label.color, in: RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GeometryReader { geometry in
                        let width = min(geometry.size.width, 520)
                        Group {
                            if displayed.isEmpty && (!query.isEmpty || shoeFilter != .all) {
                                emptySearch
                            } else if !listMode {
                                WardrobeStorageCabinet(category: category, entries: displayed, width: width, showPrice: showPrice, onSelect: select)
                                    .id(destination.id)
                            } else if displayed.isEmpty {
                                emptyCollection
                            } else {
                                WardrobeStorageGrid(entries: displayed, width: width, showPrice: showPrice, onSelect: select)
                                    .background { CardBackgroundView(cornerRadius: 20) }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .zIndex(listMode ? 0 : 1)
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: listMode)
                .padding(.trailing, 12)
            }
            .padding(.top, 8)
            .background { WardrobeStorageRearPlane() }
        }
        .navigationTitle("我的收纳柜".appLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette.label.color, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(palette.label.luminance < 0.18 ? .dark : .light, for: .navigationBar)
        .toolbar {
            if customCabinet != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("编辑柜子".appLocalized, systemImage: "pencil") { editingCabinet = true; showingCabinetEditor = true }
                        Button("管理收纳物品".appLocalized, systemImage: "checklist") { showingContents = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("管理柜子".appLocalized)
                }
            }
            if !imageSources.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    if isPreparingImages {
                        ProgressView().accessibilityLabel("正在处理柜内图片".appLocalized)
                    } else {
                        Button {
                            Task {
                                await WardrobeStorageCutoutCache.shared.clearFailures()
                                cutoutRefresh += 1
                            }
                        } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("重试抠图".appLocalized)
                    }
                }
            }
        }
        .environment(\.wardrobeStorageImageRefresh, cutoutRefresh)
        .task(id: preparationKey) {
            let jobID = UUID()
            preparationID = jobID
            isPreparingImages = !imageSources.isEmpty
            imageFailureCount = 0
            defer { if preparationID == jobID { isPreparingImages = false } }
            var failures = 0
            for source in imageSources {
                guard !Task.isCancelled else { return }
                let result = await WardrobeStorageImageResolver.resolve(source)
                guard !Task.isCancelled else { return }
                if result.canRetry { failures += 1 }
            }
            if preparationID == jobID { imageFailureCount = failures }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task {
                await WardrobeStorageCutoutCache.shared.clearFailures()
                cutoutRefresh += 1
            }
        }
        .navigationDestination(item: $detailClothing) { clothing in
            ClothingDetailView(clothing: clothing)
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                ClothingEditView(clothing: nil, initialTypes: category.initialTypes, onSaved: { clothing in
                    if let id = destination.customID, !WardrobeStorageCategory.hasMainGarmentType(clothing.types) {
                        do { try storageSettings.include(clothing.id, in: id) }
                        catch { ToastManager.shared.showError("物品已保存，收纳设置保存失败，请重新选择物品。".appLocalized) }
                    }
                })
            }
        }
        .sheet(isPresented: $showingCabinetEditor) {
            WardrobeStorageCabinetEditor(cabinet: editingCabinet ? customCabinet : nil) { selectedDestination = $0 }
        }
        .sheet(isPresented: $showingContents, onDismiss: {
            if createAfterContents { createAfterContents = false; showingAdd = true }
        }) {
            if let cabinet = customCabinet {
                WardrobeStorageContentsEditor(cabinet: cabinet) {
                    createAfterContents = true; showingContents = false
                }
            }
        }
        .floatingPetHidden(.presentationActive, isActive: true)
        .onChange(of: destination.id) { _, _ in
            searchText = ""
            shoeFilter = .all
        }
        .sensoryFeedback(.selection, trigger: category)
        .accessibilityIdentifier("storage.room")
        .wardrobeStorageAppearance()
    }

    private func preparationSources(_ inventory: [WardrobeStorageEntry]) -> [WardrobeStorageImageSource] {
        // Prioritize the open cabinet, then prepare every other category, including offscreen rows.
        let eligible = inventory.filter { $0.storageID != WardrobeStorageCategory.wardrobe.rawValue }
        let ordered = eligible.filter { $0.storageID == destination.id } + eligible.filter { $0.storageID != destination.id }
        var seen = Set<WardrobeStorageImageSource>()
        return ordered.map(\.imageSource).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private var categoryRail: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(storageSettings.destinations) { item in
                        Button {
                            if item.id == WardrobeStorageCategory.wardrobe.rawValue { dismiss() }
                            else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { selectedDestination = item } }
                        } label: {
                            VStack(spacing: 5) {
                                WardrobeStorageIcon(kind: item.icon, size: 37, selected: item.id == destination.id)
                                Text(item.title.appLocalized).font(.system(size: 10, weight: .medium)).lineLimit(2)
                                    .padding(3).background(palette.label.color, in: RoundedRectangle(cornerRadius: 5))
                            }
                            .frame(width: 48).frame(minHeight: 62)
                            .foregroundStyle(item.id == destination.id ? palette.accent.color : palette.secondary.color)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title.appLocalized)
                        .accessibilityAddTraits(item.id == destination.id ? .isSelected : [])
                        .accessibilityIdentifier("storage.rail.\(item.id)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            Button { editingCabinet = false; showingCabinetEditor = true } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                    .frame(width: 38, height: 38)
                    .foregroundStyle(palette.accent.color)
                    .background(palette.label.color, in: Circle())
                    .overlay { Circle().strokeBorder(palette.accent.color.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("添加柜子".appLocalized)
            .accessibilityIdentifier("storage.cabinet.add")
        }
        .frame(width: 54)
        .padding(.top, 8).padding(.bottom, 10).padding(.leading, 6)
    }

    private func roomHeader(count: Int, pendingCount: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(destination.title.appLocalized).font(.system(size: 23, weight: .semibold, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(count)" + category.unit.appLocalized + (pendingCount > 0 ? " · \(pendingCount)条状态记录" : ""))
                    .font(.system(size: 12)).foregroundStyle(palette.secondary.color)
            }
            Spacer(minLength: 0)
            Picker("展示方式".appLocalized, selection: $listMode) {
                Text("立体".appLocalized).tag(false)
                Text("列表".appLocalized).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 105)
            .accessibilityIdentifier("storage.mode")
            Button { if destination.customID != nil { showingContents = true } else { showingAdd = true } } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(palette.accent.color)
                    .background(palette.selected.color, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(destination.customID == nil ? "添加".appLocalized + destination.title.appLocalized : "收纳物品".appLocalized)
            .accessibilityIdentifier("storage.add")
        }
        .padding(8)
        .background(palette.label.color, in: RoundedRectangle(cornerRadius: 18))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary.color)
            TextField("", text: $searchText, prompt: Text("搜索收藏名称、品牌…".appLocalized).foregroundColor(palette.secondary.color))
                .font(.system(size: 13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("storage.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondary.color) }
                    .accessibilityLabel("清除搜索".appLocalized)
            }
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(palette.label.color, in: RoundedRectangle(cornerRadius: 14))
    }

    private var shoeFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(WardrobeShoeFilter.allCases) { filter in
                    Button {
                        shoeFilter = filter
                    } label: {
                        Text(filter.rawValue.appLocalized)
                            .font(.system(size: 12, weight: shoeFilter == filter ? .semibold : .regular))
                            .padding(.horizontal, 11).frame(height: 36)
                            .foregroundStyle(shoeFilter == filter ? palette.accent.color : palette.secondary.color)
                            .background(shoeFilter == filter ? palette.selected.color : palette.label.color, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(shoeFilter == filter ? .isSelected : [])
                    .accessibilityIdentifier("storage.filter.\(filter.nameForIdentifier)")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var activeCabinetFilter: some View {
        HStack {
            Button { listMode = true } label: {
                Label(searchText.isEmpty ? shoeFilter.rawValue.appLocalized : searchText, systemImage: "line.3.horizontal.decrease")
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("查看全部".appLocalized) { searchText = ""; shoeFilter = .all }
        }
        .font(.system(size: 12))
        .foregroundStyle(palette.secondary.color)
        .frame(minHeight: 32)
        .padding(6)
        .background(palette.label.color, in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptySearch: some View {
        ContentUnavailableView {
            Label("没有找到这件收藏".appLocalized, systemImage: "magnifyingglass")
        } description: {
            Text("换个关键词，或看看全部收藏。".appLocalized)
        } actions: {
            Button("清除筛选".appLocalized) { searchText = ""; shoeFilter = .all }
        }
        .background(palette.label.color, in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyCollection: some View {
        ContentUnavailableView {
            Label("留个位置，给下一次心动".appLocalized, systemImage: category.symbol)
        } description: {
            Text("添加的收藏会自动收进对应的柜子。".appLocalized)
        } actions: {
            Button("添加收藏".appLocalized) { if destination.customID != nil { showingContents = true } else { showingAdd = true } }
        }
        .background(palette.label.color, in: RoundedRectangle(cornerRadius: 20))
    }

    private func select(_ entry: WardrobeStorageEntry) { detailClothing = entry.clothing }

}

private extension WardrobeShoeFilter {
    var nameForIdentifier: String {
        switch self {
        case .all: return "all"
        case .sneakers: return "sneakers"
        case .whiteSneakers: return "white"
        case .boots: return "boots"
        case .maryJanes: return "maryjanes"
        case .heels: return "heels"
        }
    }
}
