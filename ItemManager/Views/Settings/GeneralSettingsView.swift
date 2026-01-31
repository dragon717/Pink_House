import SwiftUI
import PhotosUI

struct GeneralSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var languageManager = LanguageManager.shared
    @State private var showingRestartAlert = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingCropper = false
    @State private var tempImage: UIImage?
    @State private var isNewSelection = false
    
    var body: some View {
        @Bindable var theme = themeManager
        
        Form {
            Section(header: Text("语言设置")) {
                Picker("界面语言", selection: $languageManager.currentLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: languageManager.currentLanguage) { _, _ in
                    showingRestartAlert = true
                }
                
                if showingRestartAlert {
                    Text("更改语言需要重启应用才能完全生效")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Section(header: Text("外观主题")) {
                Picker("背景类型", selection: $theme.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)
                
                if theme.backgroundStyle == .color {
                    ColorPicker("背景颜色", selection: Binding(
                        get: { theme.backgroundColor },
                        set: { theme.backgroundColorHex = $0.toHex() }
                    ))
                } else {
                    Button {
                        if let original = theme.getOriginalImage() {
                            self.tempImage = original
                            self.isNewSelection = false
                            self.showingCropper = true
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
                    }
                    .disabled(theme.backgroundImage == nil)
                    
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("选择新图片", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                await MainActor.run {
                                    self.tempImage = uiImage
                                    self.isNewSelection = true
                                    self.showingCropper = true
                                    self.selectedItem = nil
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("图片不透明度: \(Int(theme.backgroundOpacity * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $theme.backgroundOpacity, in: 0...1)
                    }
                }
                
                Toggle("启用高斯模糊", isOn: $theme.isBlurEnabled)
            }
            
            Section(header: Text("更多个性化 (开发中)")) {
                HStack {
                    Text("文字颜色")
                    Spacer()
                    Text("预留")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("选中色")
                    Spacer()
                    Text("预留")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("App图标")
                    Spacer()
                    Text("预留")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("通用设置")
        .alert("需要重启", isPresented: $showingRestartAlert) {
            Button("稍后") { }
        } message: {
            Text("语言更改将在下次启动应用时生效。")
        }
        .fullScreenCover(isPresented: $showingCropper) {
            if let image = tempImage {
                ImageCropView(image: image) { croppedImage in
                    // If isNewSelection is true, we update both original and display image.
                    // If false, we only update display image (cropped version), keeping original intact.
                    
                    if isNewSelection {
                        // For new selection, 'image' IS the original image
                        themeManager.setBackgroundImage(croppedImage, isOriginal: true)
                        // Wait, we need to save the ORIGINAL image, which is 'image' (tempImage), not 'croppedImage'.
                        // But setBackgroundImage(..., isOriginal: true) logic saves the PASSED image as original.
                        // This is wrong.
                        
                        // We need a way to save the ORIGINAL image separately.
                        // Let's manually save original if needed.
                        if let data = image.pngData(), let url = themeManager.getOriginalImageURL() {
                            try? data.write(to: url)
                        }
                        themeManager.setBackgroundImage(croppedImage)
                    } else {
                        themeManager.setBackgroundImage(croppedImage)
                    }
                    
                    showingCropper = false
                    tempImage = nil
                    isNewSelection = false
                } onCancel: {
                    showingCropper = false
                    tempImage = nil
                    isNewSelection = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
            .environment(ThemeManager.shared)
    }
}
