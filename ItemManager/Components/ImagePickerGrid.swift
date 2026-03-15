//
//  ImagePickerGrid.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI
import PhotosUI
import SwiftData
import UniformTypeIdentifiers

struct ImagePickerGrid: View {
    @Binding var imagePaths: [String]
    let maxCount: Int = 9
    
    private struct EditingSelection: Identifiable {
        let id = UUID()
        let index: Int
        let image: UIImage
    }
    
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingPermissionAlert = false
    @State private var editingSelection: EditingSelection?
    @State private var isProcessingImages = false
    @State private var draggingIndex: Int?
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingActionSheet = false
    @State private var showingPhotosPicker = false
    @State private var showingCropper = false
    @State private var imageToCrop: UIImage?
    @State private var shouldDismissSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择图片 (最多\(maxCount)张，第一张为主图)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Add Button
                    if imagePaths.count < maxCount {
                        Button {
                            showingActionSheet = true
                        } label: {
                            VStack {
                                if isProcessingImages {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus")
                                        .font(.title)
                                    Text("添加")
                                        .font(.caption)
                                }
                            }
                            .frame(width: 100, height: 100)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(12)
                            .foregroundStyle(.secondary)
                        }
                        .disabled(isProcessingImages)
                        .confirmationDialog("选择图片来源", isPresented: $showingActionSheet) {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button("拍照") {
                                    showingCamera = true
                                }
                            }
                            
                            Button("从相册选择") {
                                showingPhotosPicker = true
                            }
                            
                            Button("取消", role: .cancel) {}
                        }
                    }
                    
                    // Image List
                    ForEach(Array(imagePaths.enumerated()), id: \.offset) { index, path in
                        ZStack(alignment: .topTrailing) {
                            // Image Display
                            if let image = ImageManager.shared.loadImage(fileName: path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(index == 0 ? Color.accentColor : Color.clear, lineWidth: 3)
                                    )
                                    .overlay(alignment: .bottom) {
                                        if index == 0 {
                                            Text("主图")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.8))
                                                .clipShape(Capsule())
                                                .padding(.bottom, 4)
                                        }
                                    }
                                    .onTapGesture {
                                        editingSelection = EditingSelection(index: index, image: image)
                                    }
                            } else {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 100, height: 100)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                            
                            // Delete Button
                            Button(action: {
                                deleteImage(at: index)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .padding(4)
                        }
                        .draggable(path) {
                            if let image = ImageManager.shared.loadImage(fileName: path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            } else {
                                Text(path)
                            }
                        }
                        .dropDestination(for: String.self) { items, location in
                            draggingIndex = nil
                            return true
                        } isTargeted: { isTargeted in
                            if isTargeted, let fromIndex = draggingIndex, fromIndex != index {
                                withAnimation {
                                    let item = imagePaths.remove(at: fromIndex)
                                    imagePaths.insert(item, at: index)
                                    draggingIndex = index
                                }
                            }
                        }
                        .onDrag {
                            draggingIndex = index
                            return NSItemProvider(object: path as NSString)
                        }
                    }
                }
            }
        }
        .alert("需要相册权限", isPresented: $showingPermissionAlert) {
            Button("去设置", role: .cancel) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .destructive) {}
        } message: {
            Text("请在设置中允许访问相册以选择图片")
        }
        .sheet(item: $editingSelection) { selection in
            NavigationStack {
                VStack {
                    Image(uiImage: selection.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    
                    HStack(spacing: 10) {
                        let index = selection.index
                        if index < imagePaths.count {
                            if index > 0 {
                                Button(action: {
                                    moveImageToFront(from: index)
                                    editingSelection = nil
                                }) {
                                    Label("设为主图", systemImage: "star.fill")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.pink)
                            }
                            
                            Button(action: {
                                imageToCrop = selection.image
                                shouldDismissSheet = true
                                showingCropper = true
                            }) {
                                Label("编辑为主图", systemImage: "crop")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(role: .destructive, action: {
                                deleteImage(at: index)
                                editingSelection = nil
                            }) {
                                Label("删除", systemImage: "trash")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
                .navigationTitle("图片预览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            editingSelection = nil
                        }
                    }
                }
                .fullScreenCover(isPresented: $showingCropper) {
                    if let image = imageToCrop {
                        ImageCropView(image: image, aspectRatio: 1.0) { croppedImage in
                            saveImageAsMain(croppedImage)
                            showingCropper = false
                            // Do not dismiss editingSelection immediately to avoid conflict
                            imageToCrop = nil
                        } onCancel: {
                            showingCropper = false
                            shouldDismissSheet = false // Cancel dismiss if user cancelled crop
                            imageToCrop = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .onChange(of: showingCropper) { _, isShowing in
                if !isShowing && shouldDismissSheet {
                    // Wait for cover to dismiss before dismissing sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        editingSelection = nil
                        shouldDismissSheet = false
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, newImage in
            if let image = newImage {
                isProcessingImages = true
                Task {
                    let compressedImage = image.jpegData(compressionQuality: 0.7).flatMap { UIImage(data: $0) } ?? image
                    await MainActor.run {
                        saveImage(compressedImage)
                        cameraImage = nil
                        isProcessingImages = false
                    }
                }
            }
        }
        .alert("错误", isPresented: $showingErrorAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .photosPicker(isPresented: $showingPhotosPicker, selection: $selectedItems, maxSelectionCount: maxCount - imagePaths.count, matching: .images)
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            
            isProcessingImages = true
            Task {
                for item in newItems {
                    do {
                        if let data = try await item.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            // 压缩图片以节省空间
                            let compressedImage = uiImage.jpegData(compressionQuality: 0.7).flatMap { UIImage(data: $0) } ?? uiImage
                            await MainActor.run {
                                saveImage(compressedImage)
                            }
                        } else {
                            print("Failed to load image data or create UIImage")
                            await MainActor.run {
                                errorMessage = "无法加载图片数据"
                                showingErrorAlert = true
                            }
                        }
                    } catch {
                        print("Error loading image: \(error)")
                        await MainActor.run {
                            errorMessage = "加载图片出错：\(error.localizedDescription)"
                            showingErrorAlert = true
                        }
                    }
                }
                await MainActor.run {
                    selectedItems = []
                    isProcessingImages = false
                }
            }
        }
    }
    
    private func saveImage(_ image: UIImage) {
        print("ImagePickerGrid: Saving image, current imagePaths count: \(imagePaths.count)")
        if let fileName = ImageManager.shared.saveImage(image, context: modelContext) {
            // 使用 withAnimation 确保状态更新被 SwiftUI 捕获
            withAnimation {
                imagePaths.append(fileName)
            }
            print("ImagePickerGrid: Image saved, new imagePaths count: \(imagePaths.count), fileName: \(fileName)")
            // 强制触发一次状态更新，确保父视图同步
            DispatchQueue.main.async {
                print("ImagePickerGrid: Triggering state sync, imagePaths now has \(self.imagePaths.count) items")
            }
        } else {
            errorMessage = "保存图片失败"
            showingErrorAlert = true
            print("ImagePickerGrid: Failed to save image")
        }
    }

    private func saveImageAsMain(_ image: UIImage) {
        // Use PNG to preserve transparency for cropped images
        print("ImagePickerGrid: Saving image as main, current imagePaths count: \(imagePaths.count)")
        if let fileName = ImageManager.shared.saveImage(image, context: modelContext, format: .png) {
            imagePaths.insert(fileName, at: 0)
            print("ImagePickerGrid: Image saved as main, new imagePaths count: \(imagePaths.count), fileName: \(fileName)")
        } else {
            errorMessage = "保存图片失败"
            showingErrorAlert = true
            print("ImagePickerGrid: Failed to save image as main")
        }
    }
    
    private func deleteImage(at index: Int) {
        let fileName = imagePaths[index]
        
        // 逻辑修正：如果被删除的图片是某个抠图文件，且它是当前裙装“一键替换”的成果，
        // 则应该重置该裙装的 hasReplacedCutoutImage 状态。
        // 使用 CutoutService 集中处理逻辑
        CutoutService.shared.handleCutoutDeletion(imagePath: fileName, context: modelContext)
        
        ImageManager.shared.deleteImage(fileName: fileName, context: modelContext)
        imagePaths.remove(at: index)
    }
    
    private func moveImageToFront(from index: Int) {
        let item = imagePaths.remove(at: index)
        imagePaths.insert(item, at: 0)
    }
}


