import SwiftUI
import PhotosUI

struct GeneralSettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var languageManager = LanguageManager.shared
    @State private var showingRestartAlert = false
    @State private var selectedItem: PhotosPickerItem?
    
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
                    HStack {
                        Text("当前图片")
                        Spacer()
                        if let image = theme.backgroundImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Text("未选择")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("选择新图片", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .onChange(of: selectedItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                theme.setBackgroundImage(uiImage)
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
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
            .environment(ThemeManager.shared)
    }
}
