import SwiftUI
import PhotosUI

struct WealthCustomizationView: View {
    @State private var viewModel = WealthAppearanceManager.shared
    
    // Define available denominations
    let rmbDenominations = [100, 50, 20, 10, 5, 1]
    let jpyDenominations = [10000, 5000, 1000]
    
    var body: some View {
        Form {
            Section {
                Toggle("显示容器背景", isOn: $viewModel.shouldShowWealthContainerBackground)
            } header: {
                Text("全局设置")
            } footer: {
                Text("开启后，在黄金和白银页面显示“财源广进”背景图。")
            }
            
            Section {
                ForEach(rmbDenominations, id: \.self) { value in
                    CustomizationRowView(currency: .rmb, denomination: value, viewModel: viewModel)
                }
            } header: {
                Text("人民币样式")
            } footer: {
                Text("自定义图片将应用到对应面额的纸币显示中。建议使用横向图片。")
            }
            
            Section {
                ForEach(jpyDenominations, id: \.self) { value in
                    CustomizationRowView(currency: .jpy, denomination: value, viewModel: viewModel)
                }
            } header: {
                Text("日元样式")
            } footer: {
                Text("自定义图片将应用到对应面额的纸币显示中。")
            }
        }
        .navigationTitle("来财个性化")
        .navigationBarTitleDisplayMode(.inline)
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
                                .fontWeight(.bold)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(radius: 1)
                }
            }
            .padding(.vertical, 8)
            
            // Actions
            HStack {
                if viewModel.getCustomImage(currency: currency, denominationValue: denomination) != nil {
                    Button(role: .destructive) {
                        viewModel.removeCustomImage(currency: currency, denominationValue: denomination)
                    } label: {
                        Text("恢复默认")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless) // Prevent tapping row from triggering other actions
                }
                
                Spacer()
                
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Text(viewModel.getCustomImage(currency: currency, denominationValue: denomination) == nil ? "选择图片" : "更换图片")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderless) // Prevent tapping row from triggering other actions
            }
        }
        .padding(.vertical, 4)
        .onChange(of: selectedItem) { _, newItem in
            if let newItem {
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
    
    // Helper to get default colors
    private func getDefaultColor(currency: CurrencyType, value: Int) -> Color {
        if currency == .rmb {
            switch value {
            case 100: return .red
            case 50: return .green
            case 20: return .orange // Brownish
            case 10: return .blue
            case 5: return .purple
            case 1: return .green.opacity(0.7) // Olive
            default: return .gray
            }
        } else {
            // JPY
            switch value {
            case 10000: return .brown
            case 5000: return .purple
            case 1000: return .blue
            default: return .gray
            }
        }
    }
}

#Preview {
    NavigationStack {
        WealthCustomizationView()
    }
}
