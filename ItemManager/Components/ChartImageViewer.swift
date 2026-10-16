//
//  ChartImageViewer.swift
//  ItemManager
//
//  表图大图查看器
//

import SwiftUI

/// 路径与首帧图片一起驱动弹窗，避免弹窗先于图片内容出现。
struct ChartImagePreview: Identifiable {
    let imagePath: String
    let image: UIImage?

    var id: String { imagePath }
}

/// 单张表图大图查看器
struct ChartImageViewer: View {
    let preview: ChartImagePreview
    let onDismiss: () -> Void

    @State private var loadedImage: UIImage?
    @State private var loadFailed = false
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var showSaveAlert = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if let image = loadedImage ?? preview.image {
                ZoomableImageView(imagePath: preview.imagePath, preloadedImage: image)
            } else if loadFailed {
                Label("无法加载图片".appLocalized, systemImage: "photo")
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
            
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
                    .disabled(isSaving)
                }
                .padding()
                .padding(.top, 40)
                
                Spacer()
            }
        }
        .task(id: preview.imagePath) {
            loadedImage = nil
            loadFailed = false
            let image = await ImageManager.shared.loadImageAsync(fileName: preview.imagePath)
            guard !Task.isCancelled else { return }
            loadedImage = image
            loadFailed = image == nil
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
            if let image = await ImageManager.shared.loadImageAsync(fileName: preview.imagePath) {
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
    ChartImageViewer(preview: ChartImagePreview(imagePath: "", image: nil), onDismiss: {})
}
