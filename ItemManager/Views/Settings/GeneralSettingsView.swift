import SwiftUI
import PhotosUI

struct GeneralSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var audioManager = AudioManager.shared
    @State private var languageManager = LanguageManager.shared
    @State private var showingRestartAlert = false
    @State private var showingMissingOriginalAlert = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var cropRequest: CropRequest?
    @State private var isLoadingImage = false // Loading state
    
    @State private var showingVIPRedeemAlert = false
    @State private var vipCodeInput = ""
    @State private var showingRedeemResultAlert = false
    @State private var redeemResultMessage = ""
    
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
                            // Resize original if it's huge, just in case, though we resized it on save.
                            // But `getOriginalImage` reads from disk.
                            // We should probably optimize it here too if needed, but let's assume saved one is 2000x2000 max.
                            // Wait, if saved one IS the optimized one, we are good.
                            // BUT, previously we saved 'image' (tempImage) which WAS optimized.
                            // So original on disk should be optimized.
                            
                            self.cropRequest = CropRequest(image: original, isNewSelection: false)
                        } else {
                            // If no original image, fallback to current image if available
                            if theme.backgroundImage != nil {
                                // But warn user that this is a low-res/already cropped version
                                // Ideally we should just ask them to pick new one.
                                // But let's try to use current one but maybe it's too small.
                                // Actually, user feedback says "Black Screen" if we don't have image.
                                // If theme.getOriginalImage() returns nil, we check theme.backgroundImage.
                                // If theme.backgroundImage is also nil, button is disabled anyway.
                                // If theme.backgroundImage exists but original doesn't (legacy case),
                                // we should prompt user.
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
                        .contentShape(Rectangle()) // Make entire row tappable
                    }
                    .buttonStyle(.plain) // Remove default button highlighting that might look weird in list
                    .disabled(theme.backgroundImage == nil || isLoadingImage)
                    
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack {
                            if isLoadingImage {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Label(isLoadingImage ? "处理中..." : "选择新图片", systemImage: "photo")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isLoadingImage)
                    .onChange(of: selectedItem) { _, newItem in
                        guard let newItem = newItem else { return }
                        isLoadingImage = true
                        Task {
                            // Load image data in background
                            if let data = try? await newItem.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                
                                // Resize image if too large to improve performance and avoid crashes
                                let optimizedImage = await uiImage.preparingThumbnail(of: CGSize(width: 2000, height: 2000)) ?? uiImage
                                
                                await MainActor.run {
                                    self.cropRequest = CropRequest(image: optimizedImage, isNewSelection: true)
                                    self.selectedItem = nil
                                    self.isLoadingImage = false
                                }
                            } else {
                                await MainActor.run {
                                    self.isLoadingImage = false
                                    // Could show error alert here if needed
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
             
            Section(header: Text("个性化")) {
                // 萌宠音源设置
                HStack {
                    Image(systemName: "mic.and.signal.meter.fill")
                        .foregroundStyle(.purple)
                    Text("萌宠音源")
                    Spacer()
                    Picker("", selection: $audioManager.selectedVoiceType) {
                        ForEach(PetVoiceType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                
                NavigationLink(destination: PetCustomizationView()) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(.blue)
                        Text("萌宠气泡")
                        Spacer()
                        Text("大小与字体")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                
                NavigationLink(destination: WealthCustomizationView()) {
                    HStack {
                        Image(systemName: "banknote")
                            .foregroundStyle(.green)
                        Text("来财设置")
                        Spacer()
                        Text("自定义纸币样式")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                
                NavigationLink(destination: CelebrationSettingsView()) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.pink)
                        Text("彩蛋设置")
                        Spacer()
                        Text("付尾款特效")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                
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
        
            Section(header: Text("VIP")) {   
                Button {
                    vipCodeInput = ""
                    showingVIPRedeemAlert = true
                } label: {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                        Text("兑换码")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("通用设置")
        .alert("需要重启", isPresented: $showingRestartAlert) {
            Button("稍后") { }
        } message: {
            Text("语言更改将在下次启动应用时生效。")
        }
        .alert("VIP 兑换", isPresented: $showingVIPRedeemAlert) {
            TextField("请输入兑换码", text: $vipCodeInput)
            Button("取消", role: .cancel) { }
            Button("兑换") {
                redeemVIPCode()
            }
        } message: {
            Text("输入神秘代码获取奖励")
        }
        .alert("兑换结果", isPresented: $showingRedeemResultAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(redeemResultMessage)
        }
        .alert("无法调整当前图片", isPresented: $showingMissingOriginalAlert) {
            Button("选择新图片") {
                // Trigger photo picker somehow? 
                // We can't easily trigger PhotosPicker programmatically.
                // Just let user know.
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("请重新选择一张图片以进行裁剪和移动。")
        }
        .fullScreenCover(item: $cropRequest) { request in
            // Use 'request.image' here directly
            
            ImageCropView(image: request.image) { croppedImage in
                    // If isNewSelection is true, we update both original and display image.
                    // If false, we only update display image (cropped version), keeping original intact.
                    
                    if request.isNewSelection {
                        // For new selection, 'request.image' IS the original image
                        
                        // 1. Save cropped image as display background
                        themeManager.setBackgroundImage(croppedImage)
                        
                        // 2. Save full 'request.image' as original background and update cache
                        themeManager.originalImage = request.image
                        if let data = request.image.pngData(), let url = themeManager.getOriginalImageURL() {
                             try? data.write(to: url)
                        }
                    } else {
                        themeManager.setBackgroundImage(croppedImage)
                    }
                    
                    // Reset state
                    cropRequest = nil
                } onCancel: {
                    cropRequest = nil
                }
        }
    }
    
    private func redeemVIPCode() {
        let code = vipCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if code == "太子爷" {
            let key = "HasRedeemedVIP_Prince"
            if UserDefaults.standard.bool(forKey: key) {
                redeemResultMessage = "您已经领取过该奖励啦！"
                showingRedeemResultAlert = true
            } else {
                UserDefaults.standard.set(true, forKey: key)
                
                var status = PetViewModel.loadStatusFromDisk()
                status.meowCoin += 666
                status.fishCoin += 88888
                
                if let encoded = try? JSONEncoder().encode(status) {
                    UserDefaults.standard.set(encoded, forKey: "PetStatus_Data")
                    NotificationCenter.default.post(name: Notification.Name("PetStatusDidUpdateExternally"), object: nil)
                }
                
                redeemResultMessage = "兑换成功！\n获得 666 喵币\n88888 鱼币"
                showingRedeemResultAlert = true
            }
        } else {
            redeemResultMessage = "兑换码无效"
            showingRedeemResultAlert = true
        }
    }
}

extension UIImage: Identifiable {
    public var id: String {
        return UUID().uuidString
    }
}
