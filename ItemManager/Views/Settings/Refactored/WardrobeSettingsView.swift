import SwiftUI
import PhotosUI

struct WardrobeSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    
    // Privacy
    @AppStorage("privacyShowPrice") private var showPrice = true
    @AppStorage("privacyShowOriginalPrice") private var showOriginalPrice = true
    
    // Theme State
    @State private var selectedItem: PhotosPickerItem?
    @State private var cropRequest: CropRequest?
    @State private var isLoadingImage = false
    @State private var showingMissingOriginalAlert = false
    
    // Wardrobe Style
    @AppStorage("UserPreference_WardrobeNavigationStyle") private var wardrobeNavigationStyle: WardrobeNavigationStyle = .classic
    
    var body: some View {
        @Bindable var theme = themeManager
        
        AdaptiveSettingsView(title: "梦幻衣橱") {
            // MARK: - 界面样式
            AdaptiveSection(header: "界面样式") {
                Picker("选择样式", selection: $wardrobeNavigationStyle) {
                    ForEach(WardrobeNavigationStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 外观个性化
            appAppearanceSection(theme: theme)
            
            // MARK: - 隐私显示
            AdaptiveSection(header: "隐私显示", footer: "关闭后，衣柜列表将不再显示对应的价格信息。") {
                Toggle("在列表中显示入库价格", isOn: $showPrice)
                    .adaptiveRow()
                Toggle("在列表中显示原价", isOn: $showOriginalPrice)
                    .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 业务提醒
            AdaptiveSection(header: "业务提醒") {
                NavigationLink(destination: NotificationSettingsView()) {
                    Label("心愿尾款设置", systemImage: "bell.badge")
                }
                .adaptiveRow(showDivider: false)
            }
            
            // MARK: - 基础数据
            AdaptiveSection(header: "基础数据") {
                NavigationLink(destination: TagModelManagementView()) {
                    Label("标签管理", systemImage: "tag")
                }
                .adaptiveRow()
                
                NavigationLink(destination: BrandManagementView()) {
                    Label("品牌管理", systemImage: "crown")
                }
                .adaptiveRow()
                
                // 属性字段管理直接在这里展开
                NavigationLink(destination: FieldSortSettingsView()) {
                    Label("属性字段排序与显示", systemImage: "list.bullet.indent")
                }
                .adaptiveRow(showDivider: false)
            }
        }
        // Image Picker Logic
        .onChange(of: selectedItem) { _, newItem in
            handleImageSelection(newItem)
        }
        .fullScreenCover(item: $cropRequest) { request in
            handleCropRequest(request)
        }
        .alert("无法调整当前图片", isPresented: $showingMissingOriginalAlert) {
            Button("取消", role: .cancel) { }
        } message: {
            Text("请重新选择一张图片以进行裁剪和移动。")
        }
    }
    
    // MARK: - Subviews & Actions
    
    @ViewBuilder
    private func appAppearanceSection(theme: ThemeManager) -> some View {
        @Bindable var theme = theme
        AdaptiveSection(header: "应用外观") {
            Picker("背景类型", selection: $theme.backgroundStyle) {
                ForEach(BackgroundStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .adaptiveRow()
            
            if theme.backgroundStyle == .color {
                ColorPicker("背景颜色", selection: Binding(
                    get: { theme.backgroundColor },
                    set: { theme.backgroundColorHex = $0.toHex() }
                ))
                .adaptiveRow()
            } else {
                imageSelectionRow(theme: theme)
                    .adaptiveRow()
                
                VStack(alignment: .leading) {
                    Text("图片不透明度: \(Int(theme.backgroundOpacity * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $theme.backgroundOpacity, in: 0...1)
                }
                .adaptiveRow()
            }
            
            Toggle("启用高斯模糊", isOn: $theme.isBlurEnabled)
                .adaptiveRow(showDivider: false)
            
            // 跳转到魔法配色设置
            NavigationLink(destination: MagicColorSettingsView()) {
                Label("字体配色与卡片样式", systemImage: "paintpalette")
            }
            .adaptiveRow(showDivider: false)
        }
    }


    
    @ViewBuilder
    private func imageSelectionRow(theme: ThemeManager) -> some View {
        Button {
            if let original = theme.getOriginalImage() {
                self.cropRequest = CropRequest(image: original, isNewSelection: false)
            } else {
                if theme.backgroundImage != nil {
                    showingMissingOriginalAlert = true
                }
            }
        } label: {
            HStack {
                Text("当前图片")
                    .foregroundStyle(.primary)
                Spacer()
                if let image = theme.backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        )
                } else {
                    Text("未选择")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(theme.backgroundImage == nil || isLoadingImage)
        
        PhotosPicker(selection: $selectedItem, matching: .images) {
            HStack {
                if isLoadingImage {
                    ProgressView().padding(.trailing, 4)
                }
                Label(isLoadingImage ? "处理中..." : "选择新图片", systemImage: "photo")
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isLoadingImage)
    }
    
    private func handleImageSelection(_ newItem: PhotosPickerItem?) {
        guard let newItem = newItem else { return }
        isLoadingImage = true
        Task {
            if let data = try? await newItem.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let optimizedImage = await uiImage.preparingThumbnail(of: CGSize(width: 2000, height: 2000)) ?? uiImage
                await MainActor.run {
                    self.cropRequest = CropRequest(image: optimizedImage, isNewSelection: true)
                    self.selectedItem = nil
                    self.isLoadingImage = false
                }
            } else {
                await MainActor.run { self.isLoadingImage = false }
            }
        }
    }
    
    private func handleCropRequest(_ request: CropRequest) -> some View {
        ImageCropView(image: request.image) { croppedImage in
            if request.isNewSelection {
                themeManager.setBackgroundImage(croppedImage)
                themeManager.originalImage = request.image
                if let data = request.image.pngData(), let url = themeManager.getOriginalImageURL() {
                     try? data.write(to: url)
                }
            } else {
                themeManager.setBackgroundImage(croppedImage)
            }
            cropRequest = nil
        } onCancel: {
            cropRequest = nil
        }
    }
}

// 抽取出来的字段排序视图
struct FieldSortSettingsView: View {
    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    
    var body: some View {
        List {
            Section(header: Text("属性字段管理 (长按可排序)")) {
                ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                    let config = getFieldConfig(field)
                    HStack {
                        NavigationLink(destination: FieldManagementView(title: config.title, keyPath: config.keyPath, isCommaSeparated: config.isCommaSeparated)) {
                            Label(config.label, systemImage: config.systemImage)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            visibilityManager.toggleVisibility(field)
                        }) {
                            Image(systemName: visibilityManager.isVisible(field) ? "eye" : "eye.slash")
                                .foregroundColor(visibilityManager.isVisible(field) ? .blue : .gray)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .onMove { indices, newOffset in
                    visibilityManager.moveField(from: indices, to: newOffset)
                }
            }
        }
        .navigationTitle("属性字段管理")
        .toolbar {
            EditButton()
        }
        .scrollContentBackground(.hidden)
        .background(LiquidBackground())
    }
    
    private func getFieldConfig(_ field: ClothingField) -> (title: String, label: String, systemImage: String, keyPath: ReferenceWritableKeyPath<Clothing, String>, isCommaSeparated: Bool) {
        switch field {
        case .types:
            return ("类型管理", "类型 (Types)", "tshirt", \.types, true)
        case .colors:
            return ("颜色管理", "颜色 (Colors)", "paintpalette", \.colors, true)
        case .sizes:
            return ("尺码管理", "尺码 (Sizes)", "ruler", \.sizes, true)
        case .length:
            return ("衣长管理", "衣长 (Length)", "arrow.up.and.down", \.length, false)
        case .condition:
            return ("状况管理", "状况 (Condition)", "star", \.condition, false)
        case .accessories:
            return ("小物管理", "小物 (Accessories)", "bag", \.accessories, true)
        }
    }
}
