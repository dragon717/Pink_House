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
    
    @AppStorage("isSpatialSceneEnabled") private var isSpatialSceneEnabled = false
    
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
            
            Picker("背景类型", selection: $theme.backgroundStyle) {
                    ForEach(BackgroundStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .padding(.vertical, 8)

            Section(header: Text("外观主题")) {    
                
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
            
            Picker("卡片样式", selection: $theme.cardStyle) {
                ForEach(CardStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)

            // 实时预览区域
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ZStack {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 80)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 80, height: 12)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.pink.opacity(0.3))
                                    .frame(width: 60, height: 12)
                            }
                        }
                        .padding(10)
                        .background(CardBackgroundView())
                        .frame(width: 140, height: 150)
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                    }
                    .padding()
                    .background(
                        ZStack {
                            if theme.backgroundStyle == .image, let image = theme.backgroundImage {
                                    Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                theme.backgroundColor
                            }
                        }
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    )
                    
                    Text("实时预览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)

            Section(header: Text("裙子卡片")) {
                if theme.cardStyle != .solid {
                    VStack(alignment: .leading) {
                        if theme.cardStyle == .transparent {
                            Text("卡片不透明度: \(Int(theme.transparentOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $theme.transparentOpacity, in: 0...1.0)
                        } else {
                            Text("卡片色调浓度: \(Int(theme.tintOpacity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $theme.tintOpacity, in: 0.1...0.8)
                        }
                    }
                    
                    if theme.cardStyle == .tinted {
                        ColorPicker("色调颜色", selection: Binding(
                            get: { theme.cardTintColor },
                            set: { theme.cardTintColorHex = $0.toHex() }
                        ))
                    }
                    
                    #if DEBUG
                    DisclosureGroup("开发者调试参数 (微调)") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("当前模式: \(theme.cardStyle == .transparent ? "液态玻璃" : "亚克力云母")")
                                .font(.caption).bold()
                            
                            if theme.cardStyle == .transparent {
                                Group {
                                    Text("回退背景不透明度 (无模糊时)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        Text("浅色: \(theme.dbg_glass_fallback_light, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_glass_fallback_light, in: 0...0.5)
                                    }
                                    HStack {
                                        Text("深色: \(theme.dbg_glass_fallback_dark, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_glass_fallback_dark, in: 0...0.5)
                                    }
                                    
                                    Divider()
                                    
                                    Text("边框渐变 (Light Mode)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        Text("起始: \(theme.dbg_glass_border_light_start, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_glass_border_light_start, in: 0...1)
                                    }
                                    HStack {
                                        Text("结束: \(theme.dbg_glass_border_light_end, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_glass_border_light_end, in: 0...1)
                                    }
                                    
                                    Text("边框渐变 (Dark Mode)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        Text("起始: \(theme.dbg_glass_border_dark_start, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_glass_border_dark_start, in: 0...1)
                                    }
                                    HStack {
                                        Text("结束: \(theme.dbg_glass_border_dark_end, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_glass_border_dark_end, in: 0...1)
                                    }
                                }
                            } else if theme.cardStyle == .tinted {
                                Group {
                                    Text("边框渐变 (Light Mode)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        Text("起始: \(theme.dbg_mica_border_light_start, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_mica_border_light_start, in: 0...1)
                                    }
                                    HStack {
                                        Text("结束: \(theme.dbg_mica_border_light_end, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_mica_border_light_end, in: 0...1)
                                    }
                                    
                                    Text("边框渐变 (Dark Mode)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    HStack {
                                        Text("起始: \(theme.dbg_mica_border_dark_start, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_mica_border_dark_start, in: 0...1)
                                    }
                                    HStack {
                                        Text("结束: \(theme.dbg_mica_border_dark_end, format: .number.precision(.fractionLength(2)))")
                                        Slider(value: $theme.dbg_mica_border_dark_end, in: 0...1)
                                    }
                                }
                            }
                        }
                        .font(.caption)
                        .padding(.vertical, 8)
                    }
                    #endif
                }
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


                NavigationLink(destination: CalendarSettingsView()) {
                    HStack {
                        Text("梦裙日历个性化")
                        Spacer()
                        Text(CalendarThemeManager.shared.currentTheme.displayName)
                            .foregroundStyle(.secondary)
                    }
                }

                // 限制 iOS 26 生效
                if #available(iOS 26.0, *) {
                    Toggle(isOn: $isSpatialSceneEnabled) {
                        VStack(alignment: .leading) {
                            Text("开启3d景深空间场景")
                            Text("iOS 26 专属特性")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("仅支持 iOS 26 及以上版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
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
                
                // Use PetDataManager to update currency
                _ = PetDataManager.shared.updateCurrency(type: .meowCoin, delta: 666)
                _ = PetDataManager.shared.updateCurrency(type: .fishCoin, delta: 88888)
                
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
