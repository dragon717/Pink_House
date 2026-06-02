//
//  ChartImagePicker.swift
//  ItemManager
//
//  可复用的表图选择器组件，用于尺码表和价格表
//  支持高质量图片保存和异步加载
//

import SwiftUI
import PhotosUI

struct ChartImagePicker: View {
    @Binding var imagePath: String?
    let placeholder: String
    var editMode: Bool = false
    var deleteFileImmediately: Bool = true

    @Environment(\.modelContext) private var modelContext

    @State private var selectedItem: PhotosPickerItem?
    @State private var showingPhotosPicker = false
    @State private var imageToCrop: UIImage?
    @State private var showingCropper = false
    @State private var showingFullScreenViewer = false
    @State private var showingDeleteAlert = false
    @State private var loadedThumbnail: UIImage?

    private let thumbnailSize: CGFloat = 40

    var body: some View {
        Button(action: {
            if imagePath != nil {
                if editMode {
                    showingDeleteAlert = true
                } else {
                    showingFullScreenViewer = true
                }
            } else {
                showingPhotosPicker = true
            }
        }) {
            if imagePath != nil {
                ChartImageThumbnail(
                    imagePath: imagePath,
                    size: thumbnailSize,
                    loadedThumbnail: loadedThumbnail,
                    showExpandIcon: !editMode
                )
            } else {
                addButtonView
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
                if let data = try await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        imageToCrop = uiImage
                        showingCropper = true
                        selectedItem = nil
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCropper) {
            if let image = imageToCrop {
                ImageCropView(
                    image: image,
                    aspectRatio: nil,
                    targetWidth: 1920,
                    overlayType: .none,
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
        .sheet(isPresented: $showingFullScreenViewer) {
            if let path = imagePath {
                ChartImageViewer(imagePath: path) { [self] in
                    showingFullScreenViewer = false
                }
                .presentationBackground(.black)
                .ignoresSafeArea()
            }
        }
        .alert("修改表图".appLocalized, isPresented: $showingDeleteAlert) {
            Button("查看大图".appLocalized) {
                showingFullScreenViewer = true
            }
            Button("更换图片".appLocalized) {
                showingPhotosPicker = true
            }
            Button("删除图片".appLocalized, role: .destructive) {
                deleteImage()
            }
            Button("取消".appLocalized, role: .cancel) { }
        } message: {
            Text("选择操作".appLocalized)
        }
        .task {
            await loadThumbnail()
        }
    }

    private var addButtonView: some View {
        VStack(spacing: 1) {
            Image(systemName: "plus")
                .font(.system(size: 12))
            Text(placeholder.appLocalized)
                .font(.system(size: 8))
        }
        .foregroundStyle(.secondary)
        .frame(width: thumbnailSize, height: thumbnailSize)
        .background(Color(uiColor: .tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func saveImage(_ image: UIImage) {
        let previousPath = imagePath
        if let fileName = ImageManager.shared.saveChartImage(image, context: modelContext) {
            imagePath = fileName
            if deleteFileImmediately,
               let previousPath,
               !previousPath.isEmpty,
               previousPath != fileName {
                ImageManager.shared.deleteImage(fileName: previousPath, context: modelContext)
            }
            Task { await loadThumbnail() }
        }
    }

    private func deleteImage() {
        if let path = imagePath {
            if deleteFileImmediately {
                ImageManager.shared.deleteImage(fileName: path, context: modelContext)
            }
            imagePath = nil
            loadedThumbnail = nil
        }
    }

    private func loadThumbnail() async {
        guard let path = imagePath else { return }
        let thumbnail = await ImageManager.shared.loadImageAsync(fileName: path, targetSize: CGSize(width: thumbnailSize * 2, height: thumbnailSize * 2))
        await MainActor.run {
            loadedThumbnail = thumbnail
        }
    }
}

struct ChartImageThumbnail: View {
    let imagePath: String?
    let size: CGFloat
    let loadedThumbnail: UIImage?
    var showExpandIcon: Bool = true

    var body: some View {
        ZStack {
            if let thumbnail = loadedThumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let path = imagePath,
                      let image = ImageManager.shared.loadImage(fileName: path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Color(uiColor: .tertiarySystemFill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .overlay(
            Group {
                if showExpandIcon {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(4)
                }
            },
            alignment: .bottomTrailing
        )
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
