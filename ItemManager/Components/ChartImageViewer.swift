//
//  ChartImageViewer.swift
//  ItemManager
//
//  表图大图查看器
//

import SwiftUI

/// 单张表图大图查看器
struct ChartImageViewer: View {
    let imagePath: String
    let onDismiss: () -> Void
    
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var showSaveAlert = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // 直接使用 ZoomableImageView，它会在 updateUIView 时加载图片
            ZoomableImageView(imagePath: imagePath)
            
            // 顶部控制栏
            VStack {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                    
                    Spacer()
                    
                    Button {
                        saveCurrentImage()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                .padding()
                .padding(.top, 40)
                
                Spacer()
            }
        }
        .alert("保存结果".appLocalized, isPresented: $showSaveAlert) {
            Button("确定".appLocalized, role: .cancel) { }
        } message: {
            Text(saveMessage ?? "")
        }
    }
    
    private func saveCurrentImage() {
        isSaving = true
        
        Task {
            if let image = await ImageManager.shared.loadImageAsync(fileName: imagePath) {
                let saver = ImageSaver()
                do {
                    try await saver.saveImage(image)
                    saveMessage = "图片已保存到相册".appLocalized
                } catch {
                    saveMessage = "保存失败: %@".appLocalized(error.localizedDescription)
                }
            } else {
                saveMessage = "无法加载图片".appLocalized
            }
            showSaveAlert = true
            isSaving = false
        }
    }
}

#Preview {
    ChartImageViewer(imagePath: "", onDismiss: {})
}
