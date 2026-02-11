import SwiftUI
import UniformTypeIdentifiers

struct PetCustomizationView: View {
    @AppStorage("petBubbleSize") private var bubbleSize: PetBubbleSize = .medium
    @AppStorage("petBubbleUseCustomFont") private var useCustomFont: Bool = true
    
    @ObservedObject private var fontManager = FontManager.shared
    @State private var isImporting = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        Form {
            Section(header: Text("气泡大小")) {
                Picker("字体大小", selection: $bubbleSize) {
                    ForEach(PetBubbleSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                
                // 预览
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Text("预览效果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        PetBubblePreview(text: "心情 +5", size: bubbleSize.fontSize, useCustomFont: useCustomFont)
                        
                        PetBubblePreview(text: "鱼币 +100", size: bubbleSize.fontSize, useCustomFont: useCustomFont, isCurrency: true)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
                .listRowInsets(EdgeInsets()) // 让背景充满
            }
            
            Section(header: Text("字体设置")) {
                Toggle("使用萌宠专属字体", isOn: $useCustomFont)
                
                if useCustomFont {
                    if fontManager.isUsingUserFont {
                        // 用户自定义字体状态
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("当前使用自定义字体")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(.blue)
                            }
                            
                            if let name = fontManager.registeredFontName {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Button(role: .destructive) {
                                fontManager.resetToDefaultFont()
                            } label: {
                                Label("恢复默认萌宠字体", systemImage: "arrow.counterclockwise")
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    } else {
                        // 默认字体状态
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("默认: 也字工厂小石头")
                                    .font(.body)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            
                            if let name = fontManager.registeredFontName {
                                Text("PostScript: \(name)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // 导入按钮
                    Button {
                        isImporting = true
                    } label: {
                        Label("选择本地字体文件...", systemImage: "doc.badge.plus")
                    }
                    
                    Text("支持格式: .ttf, .otf, .ttc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section(footer: Text("设置将立即应用到所有萌宠互动气泡中。")) {
                // 占位
            }
        }
        .scrollContentBackground(.hidden)
        .background {
            LiquidBackground()
        }
        .navigationTitle("萌宠个性化")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType.font],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let selectedURL = urls.first else { return }
                
                if fontManager.importUserFont(from: selectedURL) {
                    // Success handled by FontManager state update
                } else {
                    errorMessage = "无法加载选定的字体文件，请检查文件是否损坏或格式是否正确。"
                    showingError = true
                }
                
            case .failure(let error):
                errorMessage = "导入失败: \(error.localizedDescription)"
                showingError = true
            }
        }
        .alert("导入失败", isPresented: $showingError) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
}

// 预览组件
struct PetBubblePreview: View {
    let text: String
    let size: CGFloat
    let useCustomFont: Bool
    var isCurrency: Bool = false
    
    // 监听 FontManager 以便在字体切换时自动刷新
    @ObservedObject private var fontManager = FontManager.shared
    
    var font: Font {
        if useCustomFont, let fontName = fontManager.getCustomFontName() {
            return .custom(fontName, size: size)
        } else {
            return .system(size: size, weight: .black, design: .rounded)
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                // 主体 + 描边
                Text(text)
                    .font(font)
                    .foregroundStyle(
                        LinearGradient(
                            colors: isCurrency ? [.orange, .yellow] : [.pink, .pink.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black, radius: 0, x: 1, y: 1)
                    .shadow(color: .black, radius: 0, x: -1, y: -1)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
                
                // 高光
                Text(text)
                    .font(font)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.6), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        Text(text)
                            .font(font)
                    )
            }
        }
    }
}
