import SwiftUI
import SwiftData

struct WardrobeStorageCabinetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wardrobeStoragePalette) private var palette
    @State private var settings = WardrobeStorageSettings.shared
    @State private var name: String
    @State private var icon: WardrobeStorageIconKind
    @State private var error: String?
    let cabinet: WardrobeStorageCustomCabinet?
    let onSave: (WardrobeStorageDestination) -> Void

    init(cabinet: WardrobeStorageCustomCabinet? = nil, onSave: @escaping (WardrobeStorageDestination) -> Void) {
        self.cabinet = cabinet; self.onSave = onSave
        _name = State(initialValue: cabinet?.name ?? "")
        _icon = State(initialValue: cabinet?.icon ?? .accessories)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("", text: $name, prompt: Text("例如：礼帽柜、袜子柜".appLocalized).foregroundColor(palette.secondary.color))
                        .accessibilityIdentifier("storage.custom.name")
                        .submitLabel(.done)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                } header: {
                    Text("柜子名称".appLocalized).foregroundStyle(palette.secondary.color)
                        .padding(4).background(palette.label.color, in: RoundedRectangle(cornerRadius: 5))
                }
                .listRowBackground(palette.label.color)
                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(WardrobeStorageIconKind.allCases) { option in
                            Button { icon = option } label: {
                                VStack(spacing: 6) {
                                    WardrobeStorageIcon(kind: option, size: 50, selected: icon == option)
                                    Text(option.title.appLocalized).font(.caption).foregroundStyle(palette.primary.color)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title.appLocalized)
                            .accessibilityAddTraits(icon == option ? .isSelected : [])
                            .accessibilityIdentifier("storage.custom.icon.\(option.rawValue)")
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("选择图标".appLocalized).foregroundStyle(palette.secondary.color)
                        .padding(4).background(palette.label.color, in: RoundedRectangle(cornerRadius: 5))
                }
                .listRowBackground(palette.label.color)
            }
            .scrollContentBackground(.hidden)
            .background { LiquidBackground(themeSkinWallpaperContext: .wardrobe) }
            .navigationTitle((cabinet == nil ? "添加柜子" : "编辑柜子").appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.label.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(palette.label.luminance < 0.18 ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消".appLocalized) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存".appLocalized) {
                        do {
                            let destination = try settings.saveCabinet(id: cabinet?.id, name: name, icon: icon)
                            onSave(destination)
                            dismiss()
                        } catch { self.error = error.localizedDescription.appLocalized }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("storage.custom.save")
                }
            }
        }
        .tint(palette.accent.color)
    }
}

struct WardrobeStorageContentsEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wardrobeStoragePalette) private var palette
    @Query(sort: \Clothing.createdAt, order: .reverse) private var clothings: [Clothing]
    @State private var settings = WardrobeStorageSettings.shared
    @State private var selection: Set<UUID>
    @State private var search = ""
    @State private var error: String?
    @AppStorage("privacyShowPrice") private var showPrice = true
    let cabinet: WardrobeStorageCustomCabinet
    let onCreateNew: () -> Void

    init(cabinet: WardrobeStorageCustomCabinet, onCreateNew: @escaping () -> Void) {
        self.cabinet = cabinet; self.onCreateNew = onCreateNew
        _selection = State(initialValue: cabinet.clothingIDs)
    }

    var body: some View {
        let eligible = clothings.filter { !$0.isDeleted && $0.deletedAt == nil && !WardrobeStorageCategory.hasMainGarmentType($0.types) }
        let displayed = eligible.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        NavigationStack {
            List {
                Section {
                    Button(action: onCreateNew) { Label("新建物品".appLocalized, systemImage: "plus") }
                        .accessibilityIdentifier("storage.custom.new-item")
                }
                .listRowBackground(palette.label.color)
                Section {
                    if displayed.isEmpty {
                        Text(eligible.isEmpty ? "还没有可收纳的物品".appLocalized : "没有找到这件物品".appLocalized)
                            .foregroundStyle(palette.secondary.color)
                    }
                    ForEach(displayed) { clothing in
                        Button {
                            if selection.contains(clothing.id) { selection.remove(clothing.id) }
                            else { selection.insert(clothing.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(clothing.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(clothing.id) ? palette.accent.color : palette.secondary.color)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(clothing.name.isEmpty ? "未命名".appLocalized : clothing.name).foregroundStyle(palette.primary.color)
                                    if showPrice { Text(clothing.price, format: .currency(code: "CNY")).font(.caption).foregroundStyle(palette.secondary.color) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("选择收纳物品".appLocalized).foregroundStyle(palette.secondary.color)
                        .padding(4).background(palette.label.color, in: RoundedRectangle(cornerRadius: 5))
                }
                .listRowBackground(palette.label.color)
                if let error { Text(error).foregroundStyle(.red).listRowBackground(palette.label.color) }
            }
            .scrollContentBackground(.hidden)
            .background { LiquidBackground(themeSkinWallpaperContext: .wardrobe) }
            .searchable(text: $search, prompt: Text("搜索物品".appLocalized).foregroundColor(palette.secondary.color))
            .navigationTitle(cabinet.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.label.color, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(palette.label.luminance < 0.18 ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消".appLocalized) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成".appLocalized) {
                        do { try settings.setContents(selection, for: cabinet.id); dismiss() }
                        catch { self.error = error.localizedDescription.appLocalized }
                    }
                    .accessibilityIdentifier("storage.custom.contents.save")
                }
            }
        }
        .tint(palette.accent.color)
    }
}
