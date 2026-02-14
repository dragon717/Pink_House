import SwiftUI
import PhotosUI

struct WealthCustomizationView: View {
    @State private var viewModel = WealthAppearanceManager.shared
    
    // Define available denominations
    let rmbDenominations = [100, 50, 20, 10, 5, 1]
    let jpyDenominations = [10000, 5000, 1000]
    
    var body: some View {
        AdaptiveSettingsView(title: "来财个性化") {
            AdaptiveSection(header: "全局设置", footer: "开启后，在黄金和白银页面显示背景图。") {
                Toggle("显示容器背景", isOn: $viewModel.shouldShowWealthContainerBackground)
                    .adaptiveRow(showDivider: viewModel.shouldShowWealthContainerBackground)
                
                if viewModel.shouldShowWealthContainerBackground {
                    ContainerBackgroundCustomizationRow(viewModel: viewModel)
                        .adaptiveRow(showDivider: false)
                }
            }
            
            AdaptiveSection(header: "人民币样式", footer: "自定义图片将应用到对应面额的纸币显示中。建议使用横向图片。") {
                ForEach(rmbDenominations, id: \.self) { value in
                    CustomizationRowView(currency: .rmb, denomination: value, viewModel: viewModel)
                        .adaptiveRow(showDivider: value != rmbDenominations.last)
                }
            }
            
            AdaptiveSection(header: "日元样式", footer: "自定义图片将应用到对应面额的纸币显示中。") {
                ForEach(jpyDenominations, id: \.self) { value in
                    CustomizationRowView(currency: .jpy, denomination: value, viewModel: viewModel)
                        .adaptiveRow(showDivider: value != jpyDenominations.last)
                }
            }
        }
    }
}

struct CustomizationRowView: View {
    let currency: CurrencyType
    let denomination: Int
    var viewModel: WealthAppearanceManager
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showingCropView = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("\(denomination) \(currency == .rmb ? "元" : "円")")
                    .font(.headline)
                Spacer()
            }
            
            // Preview
            ZStack {
                if let image = viewModel.getCustomImage(currency: currency, denominationValue: denomination) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 80)
                        .clipped()
                        .cornerRadius(4)
                        .shadow(radius: 2)
                } else {
                    // Default Preview Placeholder
                    let color = getDefaultColor(currency: currency, value: denomination)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 160, height: 80)
                        .overlay(
                            Text("\(denomination)")
                                .foregroundStyle(.white)
                                .font(.title)
                                .bold()
                        )
                        .shadow(radius: 2)
                }
                
                // Actions Overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        
                        if viewModel.getCustomImage(currency: currency, denominationValue: denomination) != nil {
                            Button {
                                viewModel.removeCustomImage(currency: currency, denominationValue: denomination)
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(.red)
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .frame(width: 160, height: 80)
        }
        .padding(.vertical, 8)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        self.selectedImage = image
                        self.showingCropView = true
                    }
                }
                selectedItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCropView) {
            if let image = selectedImage {
                ImageCropView(image: image, aspectRatio: 2.0) { croppedImage in
                    // Compress image
                    if let compressedData = croppedImage.jpegData(compressionQuality: 0.7),
                       let compressedImage = UIImage(data: compressedData) {
                        viewModel.setCustomImage(currency: currency, denominationValue: denomination, image: compressedImage)
                    }
                    showingCropView = false
                    selectedImage = nil
                } onCancel: {
                    showingCropView = false
                    selectedImage = nil
                }
                // .ignoresSafeArea() // Removed to allow safe area insets for buttons
            }
        }
    }
    
    private func getDefaultColor(currency: CurrencyType, value: Int) -> Color {
        // Simplified default colors matching WealthViewModel logic
        if currency == .rmb {
            switch value {
            case 100: return Color(red: 0.9, green: 0.3, blue: 0.3)
            case 50: return Color(red: 0.3, green: 0.7, blue: 0.5)
            case 20: return Color(red: 0.6, green: 0.4, blue: 0.2)
            case 10: return Color(red: 0.3, green: 0.5, blue: 0.8)
            case 5: return Color(red: 0.6, green: 0.3, blue: 0.7)
            case 1: return Color(red: 0.7, green: 0.7, blue: 0.3)
            default: return .gray
            }
        } else {
            switch value {
            case 10000: return Color(red: 0.5, green: 0.3, blue: 0.2)
            case 5000: return Color(red: 0.5, green: 0.2, blue: 0.6)
            case 1000: return Color(red: 0.2, green: 0.4, blue: 0.7)
            default: return .gray
            }
        }
    }
}

struct ContainerBackgroundCustomizationRow: View {
    var viewModel: WealthAppearanceManager
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var showingCropView = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("容器背景图")
                .font(.headline)
            
            ZStack {
                if let image = viewModel.containerBackgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    // Default preview
                    Image("WealthContainerBackground")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                
                // Actions Overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                        
                        if viewModel.containerBackgroundImage != nil {
                            Button {
                                viewModel.removeContainerBackgroundImage()
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(.red)
                                    .shadow(radius: 2)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        self.selectedImage = image
                        self.showingCropView = true
                    }
                }
                selectedItem = nil
            }
        }
        .fullScreenCover(isPresented: $showingCropView) {
            if let image = selectedImage {
                // User requested square crop for background
                ImageCropView(image: image, aspectRatio: 1.0) { croppedImage in
                    // Compress image
                    if let compressedData = croppedImage.jpegData(compressionQuality: 0.7),
                       let compressedImage = UIImage(data: compressedData) {
                        viewModel.setContainerBackgroundImage(compressedImage)
                    }
                    showingCropView = false
                    selectedImage = nil
                } onCancel: {
                    showingCropView = false
                    selectedImage = nil
                }
            }
        }
    }
}
