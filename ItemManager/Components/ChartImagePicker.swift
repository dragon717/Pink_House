//
//  ChartImagePicker.swift
//  ItemManager
//
//  可复用的表图选择器组件，用于尺码表和价格表
//

import SwiftUI
import PhotosUI

/// 表图选择器组件
/// 用于在编辑页选择尺码表或价格表图片
struct ChartImagePicker: View {
    @Binding var imagePath: String?
    let placeholder: String
    
    @Environment(\.modelContext) private var modelContext
    
    // 图片选择状态
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingPhotosPicker = false
    
    // 裁剪状态
    @State private var imageToCrop: UIImage?
    @State private var showingCropper = false
    
    var body: some View {
        Button(action: {
            showingPhotosPicker = true
        }) {
            if let path = imagePath,
               let image = ImageManager.shared.loadImage(fileName: path) {
                // 已选择图片，显示缩略图
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            } else {
                // 未选择图片，显示添加按钮
                VStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                    Text(placeholder)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .photosPicker(
            isPresented: $showingPhotosPicker,
            selection: $selectedItem,
            matching: .images
        )
        .onChange(of: selectedItem) { _, newItem in
            guard let item = newItem else { return }
            
            Task {
                do {
                    if let data = try await item.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            imageToCrop = uiImage
                            showingCropper = true
                            selectedItem = nil
                        }
                    }
                } catch {
                    print("加载图片失败: \(error)")
                }
            }
        }
        .fullScreenCover(isPresented: $showingCropper) {
            if let image = imageToCrop {
                ImageCropView(
                    image: image,
                    aspectRatio: 1.0,  // 1:1 比例
                    targetWidth: 512,  // 输出尺寸
                    overlayType: .rectangle,
                    onCrop: { croppedImage in
                        saveImage(croppedImage)
                        showingCropper = false
                        imageToCrop = nil
                    },
                    onCancel: {
                        showingCropper = false
                        imageToCrop = nil
                    }
                )
            }
        }
    }
    
    /// 保存裁剪后的图片
    private func saveImage(_ image: UIImage) {
        // 使用 PNG 格式保留透明度（如果需要）
        if let fileName = ImageManager.shared.saveImage(image, context: modelContext, format: .png) {
            imagePath = fileName
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var imagePath: String? = nil
        
        var body: some View {
            VStack(spacing: 20) {
                HStack {
                    Text("尺码")
                    Spacer()
                    ChartImagePicker(imagePath: $imagePath, placeholder: "添加表图")
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                
                if let path = imagePath {
                    Text("已保存: \(path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
