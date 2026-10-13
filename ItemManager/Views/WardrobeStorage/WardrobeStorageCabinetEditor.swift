import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct WardrobeStorageCabinetEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.wardrobeStoragePalette) private var palette
    @State private var settings = WardrobeStorageSettings.shared
    @State private var name: String
    @State private var icon: WardrobeStorageIconKind
    @State private var useCustomIcon: Bool
    @State private var customIconData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cropRequest: CropRequest?
    @State private var isLoadingPhoto = false
    @State private var error: String?
    let cabinet: WardrobeStorageCustomCabinet?
    let onSave: (WardrobeStorageDestination) -> Void

    init(cabinet: WardrobeStorageCustomCabinet? = nil, onSave: @escaping (WardrobeStorageDestination) -> Void) {
        self.cabinet = cabinet; self.onSave = onSave
        _name = State(initialValue: cabinet?.name ?? "")
        _icon = State(initialValue: cabinet?.icon ?? .accessories)
        _useCustomIcon = State(initialValue: cabinet?.iconImageFile != nil)
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
                            Button { icon = option; useCustomIcon = false; error = nil } label: {
                                VStack(spacing: 6) {
                                    WardrobeStorageIcon(kind: option, size: 50, selected: !useCustomIcon && icon == option)
                                    Text(option.title.appLocalized).font(.caption).foregroundStyle(palette.primary.color)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title.appLocalized)
                            .accessibilityAddTraits(!useCustomIcon && icon == option ? .isSelected : [])
                            .accessibilityIdentifier("storage.custom.icon.\(option.rawValue)")
                        }
                    }
                    .padding(.vertical, 8)
                    .disabled(isLoadingPhoto)
                } header: {
                    Text("内置图标".appLocalized).foregroundStyle(palette.secondary.color)
                        .padding(4).background(palette.label.color, in: RoundedRectangle(cornerRadius: 5))
                }
                .listRowBackground(palette.label.color)
                Section {
                    HStack(spacing: 14) {
                        Button { useCustomIcon = true; error = nil } label: {
                            if hasCustomImage {
                                WardrobeStorageIcon(kind: icon, size: 60, selected: useCustomIcon,
                                                    imageFile: cabinet?.iconImageFile, imageData: customIconData)
                            } else {
                                Image(systemName: "photo.badge.plus").font(.system(size: 24))
                                    .foregroundStyle(palette.accent.color)
                                    .frame(width: 60, height: 60)
                                    .background(palette.selected.color, in: Circle())
                                    .overlay { Circle().strokeBorder(palette.border.color, lineWidth: 1) }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasCustomImage || isLoadingPhoto)
                        .accessibilityLabel("使用自定义图标".appLocalized)
                        .accessibilityAddTraits(useCustomIcon ? .isSelected : [])
                        .accessibilityIdentifier("storage.custom.photo.use")
                        VStack(alignment: .leading, spacing: 8) {
                            Text("选择喜欢的图片作为图标".appLocalized)
                                .font(.caption).foregroundStyle(palette.secondary.color)
                            PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                                Label((hasCustomImage ? "更换图片" : "从照片选择").appLocalized, systemImage: "photo")
                                    .foregroundStyle(palette.accent.color)
                            }
                            .disabled(isLoadingPhoto)
                            .accessibilityIdentifier("storage.custom.photo.select")
                        }
                        Spacer(minLength: 0)
                        if isLoadingPhoto { ProgressView().tint(palette.accent.color) }
                        else if useCustomIcon {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent.color)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("自定义图标".appLocalized).foregroundStyle(palette.secondary.color)
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
                            let update: WardrobeStorageIconUpdate = useCustomIcon
                                ? customIconData.map(WardrobeStorageIconUpdate.replace) ?? .keep : .useBuiltIn
                            let destination = try settings.saveCabinet(id: cabinet?.id, name: name, icon: icon, iconUpdate: update)
                            onSave(destination)
                            dismiss()
                        } catch { self.error = error.localizedDescription.appLocalized }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingPhoto || cropRequest != nil)
                    .accessibilityIdentifier("storage.custom.save")
                }
            }
        }
        .tint(palette.accent.color)
        .task(id: selectedPhoto) {
            guard let item = selectedPhoto else { isLoadingPhoto = false; return }
            isLoadingPhoto = true
            defer { if selectedPhoto == item { isLoadingPhoto = false } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw WardrobeStorageIconStore.ImageError.invalidImage
                }
                let decoded = await Task.detached(priority: .userInitiated) {
                    WardrobeStorageIconStore.cropImage(from: data)
                }.value
                guard !Task.isCancelled else { return }
                guard let decoded else { throw WardrobeStorageIconStore.ImageError.invalidImage }
                cropRequest = CropRequest(image: UIImage(cgImage: decoded), isNewSelection: true)
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription.appLocalized
                selectedPhoto = nil
            }
        }
        .sheet(item: $cropRequest, onDismiss: { selectedPhoto = nil }) { request in
            ImageCropView(image: request.image, aspectRatio: 1, targetWidth: 256, overlayType: .circle, contentMode: .fill,
                onCrop: { image in
                    if let data = image.pngData() {
                        customIconData = data; useCustomIcon = true; error = nil
                    } else { error = WardrobeStorageIconStore.ImageError.invalidImage.localizedDescription.appLocalized }
                    cropRequest = nil; selectedPhoto = nil
                }, onCancel: { cropRequest = nil; selectedPhoto = nil })
        }
    }

    private var hasCustomImage: Bool { customIconData != nil || cabinet?.iconImageFile != nil }
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
