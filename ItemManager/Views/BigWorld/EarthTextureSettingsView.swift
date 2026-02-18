//
//  EarthTextureSettingsView.swift
//  ItemManager
//
//  地球纹理设置 - 管理真实地图和夜晚灯光纹理
//

import SwiftUI

struct EarthTextureSettingsView: View {
    @StateObject private var textureManager = EarthTextureManager.shared
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingImagePicker = false
    @State private var selectedTextureType: TextureType = .day
    
    var body: some View {
        NavigationStack {
            List {
                // 当前纹理状态
                Section("当前纹理") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("白天纹理")
                                .font(.subheadline)
                            Text(textureManager.dayTexture != nil ? "已加载" : "使用默认")
                                .font(.caption)
                                .foregroundStyle(textureManager.dayTexture != nil ? .green : .secondary)
                        }
                        
                        Spacer()
                        
                        if textureManager.dayTexture != nil {
                            Image(uiImage: textureManager.dayTexture!)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("夜晚灯光")
                                .font(.subheadline)
                            Text(textureManager.nightTexture != nil ? "已加载" : "使用默认")
                                .font(.caption)
                                .foregroundStyle(textureManager.nightTexture != nil ? .green : .secondary)
                        }
                        
                        Spacer()
                        
                        if textureManager.nightTexture != nil {
                            Image(uiImage: textureManager.nightTexture!)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                
                // 加载本地纹理
                Section("加载本地纹理") {
                    Button(action: {
                        selectedTextureType = .day
                        showingImagePicker = true
                    }) {
                        Label("加载白天纹理", systemImage: "sun.max")
                    }
                    
                    Button(action: {
                        selectedTextureType = .night
                        showingImagePicker = true
                    }) {
                        Label("加载夜晚灯光纹理", systemImage: "moon")
                    }
                }
                
                // 下载 NASA 纹理
                Section("下载 NASA 纹理") {
                    Button(action: {
                        Task {
                            await textureManager.downloadNASATextures()
                        }
                    }) {
                        HStack {
                            Label("下载 NASA 高清纹理", systemImage: "cloud.down")
                            
                            Spacer()
                            
                            if textureManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(textureManager.isLoading)
                    
                    if let error = textureManager.loadError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    Text("下载 NASA Blue Marble 白天纹理和 Black Marble 夜晚灯光纹理。文件较大，建议在 Wi-Fi 环境下下载。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // 纹理信息
                Section("纹理信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("支持的格式")
                            .font(.subheadline)
                        Text("• JPG, PNG, TIFF 等常见图片格式\n• 等距圆柱投影 (Equirectangular)\n• 建议分辨率: 2048x1024 或更高")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("数据来源")
                            .font(.subheadline)
                        Text("• NASA Blue Marble - 白天卫星影像\n• NASA Black Marble - 夜晚灯光数据\n• 自定义地图纹理")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // 重置按钮
                Section {
                    Button(action: {
                        textureManager.dayTexture = nil
                        textureManager.nightTexture = nil
                    }) {
                        Label("重置为默认纹理", systemImage: "arrow.counterclockwise")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("地球纹理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker { image in
                    if let image = image {
                        Task {
                            // 保存到临时文件
                            let tempDir = FileManager.default.temporaryDirectory
                            let tempURL = tempDir.appendingPathComponent("temp_texture_\(selectedTextureType).jpg")
                            
                            if let data = image.jpegData(compressionQuality: 0.9) {
                                try? data.write(to: tempURL)
                                await textureManager.loadTexture(from: tempURL, type: selectedTextureType)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 预览
#Preview {
    EarthTextureSettingsView()
        .environment(ThemeManager())
}
