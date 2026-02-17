
import SwiftUI
import SwiftData
import PhotosUI

struct OOTDEditorView: View {
    @Bindable var outfit: Outfit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // States copied from OOTDView
    @State private var isListExpanded = false
    @State private var isProcessing = false
    @State private var processingMessage = ""
    @State private var showingActionSheet = false
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var shouldCutoutCameraImage = false
    @State private var isImagePickerPresented = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var showingLimitAlert = false
    @State private var showingSaveSuccessAlert = false
    @State private var showingSaveToClothingSheet = false
    @State private var showingRenameAlert = false
    @State private var newName = ""
    @State private var showingDeleteAlert = false
    @State private var showingMultiPhotoPicker = false
    @State private var showingShareSheet = false
    
    // 工具栏和贴纸库显示状态
    @State private var isToolbarVisible = true
    @State private var isStickerLibraryVisible = false
    
    var body: some View {
        GeometryReader { geometry in
            OOTDContentArea(
                currentOutfit: Binding(get: { outfit }, set: { _ in }), // OOTDContentArea expects optional binding
                isListExpanded: $isListExpanded,
                isProcessing: $isProcessing,
                processingMessage: processingMessage,
                isToolbarVisible: $isToolbarVisible,
                isStickerLibraryVisible: $isStickerLibraryVisible,
                geometry: geometry,
                onAddToOutfit: { cutout in
                    addToOutfit(cutout)
                },
                onAddPhoto: {
                    showingActionSheet = true
                },
                onBatchAdd: { cutouts in
                    // Logic from OOTDView
                    if outfit.items.count + cutouts.count > 20 {
                        showingLimitAlert = true
                        return false
                    }
                    for (index, cutout) in cutouts.enumerated() {
                        let item = OutfitItem(
                            cutout: cutout,
                            x: Double(index * 20),
                            y: Double(index * 20),
                            rotation: 0,
                            scale: 1.0,
                            zIndex: outfit.items.count
                        )
                        outfit.items.append(item)
                    }
                    saveSnapshot()
                    return true
                },
                onUpdate: {
                    saveSnapshot()
                }
            )
        }
        .navigationTitle(outfit.note.isEmpty ? "编辑书页" : outfit.note)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 左侧：显示/隐藏工具栏按钮
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isToolbarVisible.toggle()
                    }
                } label: {
                    Image(systemName: isToolbarVisible ? "sidebar.leading" : "sidebar.trailing")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            
            // 右侧：分享按钮和更多操作菜单
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // 分享按钮
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    
                    // 更多操作菜单
                    Menu {
                        Button {
                            showingSaveToClothingSheet = true
                        } label: {
                            Label("保存为裙子主图", systemImage: "photo.badge.arrow.down")
                        }
                        
                        Button {
                            newName = outfit.note
                            showingRenameAlert = true
                        } label: {
                            Label("重命名", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        // ... Pickers and Alerts ...
        .confirmationDialog("选择图片来源", isPresented: $showingActionSheet) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照并抠图") {
                    shouldCutoutCameraImage = true
                    showingCamera = true
                }
            }
            Button("从图库多选") {
                showingMultiPhotoPicker = true
            }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, newImage in
            if let image = newImage {
                processCameraImage(image, shouldCutout: shouldCutoutCameraImage)
            }
        }
        .sheet(isPresented: $showingMultiPhotoPicker) {
            MultiPhotoPickerView { cutouts in
                // 批量添加抠图到画布
                batchAddCutouts(cutouts)
            }
        }
        .sheet(isPresented: $showingSaveToClothingSheet) {
            ClothingPickerView { selectedClothing in
                // saveCanvasToClothing(clothing: selectedClothing)
                // Logic needs to be ported or accessed via static/shared helper
                // For now, let's just log or implement simple version
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareCardSheet(
                shareType: .outfit(outfit),
                onDismiss: { showingShareSheet = false }
            )
        }
        .alert("重命名", isPresented: $showingRenameAlert) {
            TextField("名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("确定") {
                outfit.note = newName
                try? modelContext.save()
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                outfit.isDeleted = true
                outfit.deletedAt = Date()
                try? modelContext.save()
                dismiss()
            }
        } message: {
            Text("确定要删除这张书页吗？")
        }
    }
    
    // MARK: - Helper Methods
    
    private func addToOutfit(_ cutout: CutoutItem) {
        let item = OutfitItem(
            cutout: cutout,
            x: 0,
            y: 0,
            rotation: 0,
            scale: 1.0,
            zIndex: outfit.items.count
        )
        outfit.items.append(item)
        saveSnapshot()
    }
    
    private func saveSnapshot() {
        Task { @MainActor in
            // Delay to ensure rendering is ready
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            let renderer = ImageRenderer(content: OOTDPreviewView(outfit: outfit))
            renderer.scale = 0.5 
            
            if let uiImage = renderer.uiImage,
               let path = ImageManager.shared.saveImage(uiImage, context: modelContext) {
                // Delete old snapshot if exists and different
                if let oldPath = outfit.snapshotPath, oldPath != path {
                    ImageManager.shared.deleteImage(fileName: oldPath, context: modelContext)
                }
                outfit.snapshotPath = path
                try? modelContext.save()
            }
        }
    }
    
    private func processPickedImage(_ item: PhotosPickerItem) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    Task {
                         if let cutout = try? await CutoutService.shared.processImage(image: image, category: "导入", clothing: nil, context: modelContext) {
                             await MainActor.run {
                                 addToOutfit(cutout)
                             }
                         }
                    }
                }
            }
        }
    }
    
    private func processCameraImage(_ image: UIImage, shouldCutout: Bool) {
        if shouldCutout {
            Task {
                if let cutout = try? await CutoutService.shared.processImage(image: image, category: "拍照", clothing: nil, context: modelContext) {
                     await MainActor.run {
                         addToOutfit(cutout)
                     }
                }
            }
        }
    }
    
    private func batchAddCutouts(_ cutouts: [CutoutItem]) {
        // 检查是否超过限制
        if outfit.items.count + cutouts.count > 20 {
            showingLimitAlert = true
            return
        }
        
        // 批量添加
        for (index, cutout) in cutouts.enumerated() {
            let item = OutfitItem(
                cutout: cutout,
                x: Double(index * 20),
                y: Double(index * 20),
                rotation: 0,
                scale: 1.0,
                zIndex: outfit.items.count
            )
            outfit.items.append(item)
        }
        
        saveSnapshot()
    }
}
