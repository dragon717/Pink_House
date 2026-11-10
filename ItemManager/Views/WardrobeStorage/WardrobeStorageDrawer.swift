import SwiftUI
import SwiftData

struct WardrobeStorageDrawer: View {
    var filterConfig = ClothingFilterService.FilterConfig()
    @AppStorage("UserPreference_SortOption") private var sortOption: SortOption = .createdAtDesc
    @AppStorage("UserPreference_PreferredBrandID") private var preferredBrandID = ""
    @Query(sort: \Clothing.createdAt, order: .reverse) private var clothings: [Clothing]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0
    @State private var storageSettings = WardrobeStorageSettings.shared
    @State private var showingCabinetEditor = false
    @State private var editingCabinet: WardrobeStorageCustomCabinet?
    @State private var pendingDestination: WardrobeStorageDestination?
    let onClose: () -> Void
    let onSelect: (WardrobeStorageDestination) -> Void

    private var visibleClothings: [Clothing] {
        let filtered = ClothingFilterService.filter(clothings, config: filterConfig)
        if sortOption == .brand {
            return ClothingFilterService.sortByBrand(filtered, preferredBrandID: preferredBrandID)
        }
        return filtered.sorted(using: sortOption.sortDescriptors)
    }

    private var palette: WardrobeStoragePalette {
        .themed(themeManager, scheme: colorScheme, contrast: contrast)
    }

    var body: some View {
        let inventory = WardrobeStorageInventory.entries(clothings: visibleClothings, customCabinets: storageSettings.cabinets)
        GeometryReader { geometry in
            let width = min(330, geometry.size.width * 0.80)
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.28)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .accessibilityLabel("关闭收纳柜".appLocalized)
                    .accessibilityAddTraits(.isButton)
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("我的收纳柜".appLocalized)
                                .font(.system(size: 23, weight: .semibold, design: .serif))
                            Text("把喜欢的，都好好收起来".appLocalized)
                                .font(.system(size: 12)).foregroundStyle(palette.secondary.color)
                        }
                        Spacer(minLength: 8)
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .medium))
                                .frame(width: 44, height: 44)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭收纳柜".appLocalized)
                        .accessibilityIdentifier("storage.close")
                    }
                    .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 18)
                    .background(palette.label.color)
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(storageSettings.destinations) { category in
                                let entries = inventory.filter { $0.storageID == category.id }
                                let count = entries.reduce(0) { $0 + $1.quantity }
                                let statusCount = entries.filter { $0.statusLabel != nil }.count
                                Button { onSelect(category) } label: {
                                    HStack(spacing: 16) {
                                        WardrobeStorageIcon(kind: category.icon, size: 45, imageFile: category.iconImageFile)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(category.title.appLocalized).font(.system(size: 17, weight: .medium))
                                            Text("\(count)" + category.category.unit.appLocalized + (statusCount > 0 ? " · \(statusCount)条状态记录" : ""))
                                                .font(.system(size: 12)).foregroundStyle(palette.secondary.color)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(palette.accent.color)
                                    }
                                    .padding(.horizontal, 18).padding(.vertical, 16)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(category.id == WardrobeStorageCategory.shoes.rawValue ? palette.selected.color : palette.label.color, in: RoundedRectangle(cornerRadius: 19))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 19)
                                            .strokeBorder(palette.accent.color.opacity(category.id == WardrobeStorageCategory.shoes.rawValue ? 0.24 : 0.10), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("storage.category.\(category.id)")
                                .contextMenu {
                                    if let cabinet = storageSettings.cabinets.first(where: { $0.id == category.customID }) {
                                        Button("编辑柜子".appLocalized, systemImage: "pencil") {
                                            editingCabinet = cabinet; showingCabinetEditor = true
                                        }
                                    }
                                }
                            }
                            Button { editingCabinet = nil; showingCabinetEditor = true } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "plus").font(.system(size: 20, weight: .medium)).frame(width: 45, height: 45)
                                    Text("添加柜子".appLocalized).font(.system(size: 16, weight: .medium))
                                    Spacer()
                                }
                                .foregroundStyle(palette.accent.color)
                                .padding(.horizontal, 18).padding(.vertical, 8)
                                .background(palette.label.color, in: RoundedRectangle(cornerRadius: 19))
                                .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(palette.accent.color.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("storage.cabinet.add")
                        }
                        .padding(.horizontal, 18).padding(.bottom, 20)
                    }
                    Text("收藏生活中的每一份美好".appLocalized)
                        .font(.system(size: 13, weight: .light, design: .serif))
                        .foregroundStyle(palette.secondary.color).padding(12)
                        .background(palette.label.color, in: RoundedRectangle(cornerRadius: 10)).padding(.bottom, 10)
                }
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background { CardBackgroundView(cornerRadius: 30) }
                .background { LiquidBackground(themeSkinWallpaperContext: .wardrobe) }
                .overlay(alignment: .leading) {
                    Rectangle().fill(palette.accent.color.opacity(0.15)).frame(width: 1)
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 26))
                .shadow(color: .black.opacity(0.18), radius: 18, x: -8)
                .offset(x: dragOffset)
                .simultaneousGesture(DragGesture(minimumDistance: 18)
                    .onChanged {
                        guard abs($0.translation.width) > abs($0.translation.height) * 1.3 else { return }
                        dragOffset = max(0, $0.translation.width)
                    }
                    .onEnded { value in
                        if abs(value.translation.width) > abs(value.translation.height) * 1.3 &&
                            (value.translation.width > width * 0.28 || value.predictedEndTranslation.width > width * 0.55) {
                            onClose()
                        } else {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { dragOffset = 0 }
                        }
                    })
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .wardrobeStorageAppearance()
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .accessibilityIdentifier("storage.drawer")
        .sheet(isPresented: $showingCabinetEditor, onDismiss: {
            if let destination = pendingDestination { pendingDestination = nil; onSelect(destination) }
        }) {
            WardrobeStorageCabinetEditor(cabinet: editingCabinet) { pendingDestination = $0 }
        }
    }
}
