//
//  BatchImportView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/31/26.
//

import SwiftUI
import PhotosUI
import SwiftData

struct BatchImageItem: Identifiable {
    let id = UUID()
    let sourceItem: PhotosPickerItem?
    var image: UIImage?
}

struct BatchImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var seriesName: String = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var displayedItems: [BatchImageItem] = []
    @State private var imageCache: [String: UIImage] = [:]
    @State private var isProcessing: Bool = false
    @State private var showingConfirmation: Bool = false
    @State private var unlockAlertItem: FeatureUnlockAlert?
    @State private var currentLoadTask: Task<Void, Never>?
    @State private var hasValidatedAccess = false
    @State private var hasPostedOpenNotification = false
    
    // Camera & ActionSheet States
    @State private var showingActionSheet = false
    @State private var showingCamera = false
    @State private var showingPhotosPicker = false
    @State private var cameraImage: UIImage?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基础信息")) {
                    TextField("系列名称", text: $seriesName)
                    Text("每张图片将作为一个独立的裙装条目。裙装名称将设置为系列名称。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section(header: Text("选择图片 (\(displayedItems.count) 张)")) {
                    Button {
                        showingActionSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("添加图片")
                        }
                    }
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
                    
                    if !displayedItems.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))]) {
                            ForEach(displayedItems) { item in
                                ZStack(alignment: .topTrailing) {
                                    if let image = item.image {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 80, height: 80)
                                            .overlay {
                                                Image(systemName: "exclamationmark.triangle")
                                                    .foregroundStyle(.yellow)
                                            }
                                    }
                                    
                                    Button {
                                        removeImage(item: item)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .red)
                                            .background(Circle().fill(.white))
                                    }
                                    .buttonStyle(.borderless) // Fix for Button in Form/List
                                    .offset(x: 5, y: -5)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if !displayedItems.isEmpty {
                            showingConfirmation = true
                        }
                    }
                    .disabled(displayedItems.isEmpty || isProcessing)
                }
            }
            .alert("确认导入", isPresented: $showingConfirmation) {
                Button("取消", role: .cancel) { }
                Button("确定") {
                    saveBatchItems()
                }
            } message: {
                Text("将创建 \(displayedItems.count) 个新条目，系列名称为“\(seriesName.isEmpty ? "(空)" : seriesName)”。\n确认后将立即保存。")
            }
            .disabled(isProcessing)
            .overlay {
                if isProcessing {
                    ZStack {
                        Color.black.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                            Text("正在处理图片...")
                                .foregroundStyle(.white)
                                .font(.headline)
                        }
                        .padding(30)
                        .background(Material.regularMaterial)
                        .cornerRadius(16)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker(image: $cameraImage)
                    .ignoresSafeArea()
            }
            .onChange(of: cameraImage) { _, newImage in
                if let image = newImage {
                    // Add camera image to displayedItems
                    let newItem = BatchImageItem(sourceItem: nil, image: image)
                    displayedItems.append(newItem)
                    cameraImage = nil
                }
            }
            .photosPicker(
                isPresented: $showingPhotosPicker,
                selection: $selectedItems,
                selectionBehavior: .ordered,
                matching: .images,
                preferredItemEncoding: .current,
                photoLibrary: .shared()
            )
            .onChange(of: selectedItems) { _, newItems in
                if !showingPhotosPicker {
                    loadImages(from: newItems)
                }
            }
            .onChange(of: showingPhotosPicker) { wasPresented, isPresented in
                guard wasPresented && !isPresented else { return }
                loadImages(from: selectedItems)
            }
            .onAppear {
                validateAccessOnAppear()
            }
        }
        .alert(item: $unlockAlertItem) { alert in
            if alert.canUnlock {
                return Alert(
                    title: Text("解锁 \(alert.feature.displayName)"),
                    message: Text("\(alert.condition.description)\n\n确定要解锁吗？"),
                    primaryButton: .default(Text("解锁")) {
                        unlockBatchImportAccess()
                    },
                    secondaryButton: .cancel(Text("取消")) {
                        dismiss()
                    }
                )
            } else {
                return Alert(
                    title: Text("尚未满足解锁条件"),
                    message: Text(alert.message ?? alert.condition.description),
                    dismissButton: .default(Text("知道了")) {
                        dismiss()
                    }
                )
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Downsample image from Data to a specific point size
    private func downsample(data: Data, to pointSize: CGSize, scale: CGFloat = UIScreen.main.scale) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }
        
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        return UIImage(cgImage: downsampledImage)
    }

    private func validateAccessOnAppear() {
        guard !hasValidatedAccess else { return }
        hasValidatedAccess = true

        if FeatureUnlockManager.shared.isUnlocked(.batchImport) {
            postOpenedNotificationIfNeeded()
            return
        }

        unlockAlertItem = FeatureUnlockManager.shared.makeAlertItem(for: .batchImport)
    }

    private func unlockBatchImportAccess() {
        let manager = FeatureUnlockManager.shared
        switch manager.unlock(.batchImport) {
        case .success, .alreadyUnlocked:
            postOpenedNotificationIfNeeded()
        case .conditionNotMet:
            unlockAlertItem = manager.makeAlertItem(for: .batchImport)
        case .insufficientResource(let type, let required, let current):
            let condition = manager.getCondition(for: .batchImport)
            unlockAlertItem = FeatureUnlockAlert(
                feature: .batchImport,
                condition: condition,
                canUnlock: false,
                message: "\(type)不足：当前 \(current)，需要 \(required)"
            )
        }
    }

    private func postOpenedNotificationIfNeeded() {
        guard !hasPostedOpenNotification else { return }
        hasPostedOpenNotification = true
        NotificationCenter.default.post(name: .batchImportViewOpened, object: nil)
    }

    private func loadImages(from items: [PhotosPickerItem]) {
        print("DEBUG: loadImages called with \(items.count) items")
        // Cancel previous task to prevent race conditions
        currentLoadTask?.cancel()
        
        // We must PRESERVE existing items that are not from PhotosPicker (e.g. Camera items)
        let cameraItems = displayedItems.filter { $0.sourceItem == nil }
        
        isProcessing = true
        
        currentLoadTask = Task {
            var newDisplayedItems: [BatchImageItem] = []
            
            // Add back camera items (optional: decide where to put them, at the end or beginning?
            // Current logic: append camera items at the end to keep them visible)
            // Or better: keep them if we want.
            // But usually PhotosPicker replaces the whole selection.
            // So if I pick new photos, the camera photos should stay? Yes.
            
            // Optimization: Create a pool of existing items (only those with sourceItem)
            var existingPool = displayedItems.filter { $0.sourceItem != nil }
            
            for item in items {
                if Task.isCancelled { return }
                
                // Find if we already have this item in our pool
                if let index = existingPool.firstIndex(where: { $0.sourceItem == item }) {
                    // Reuse existing item (already loaded image)
                    let reusedItem = existingPool[index]
                    newDisplayedItems.append(reusedItem)
                    existingPool.remove(at: index) // Consume it so we don't reuse it for another duplicate
                } else {
                    // New item, need to load
                    // Check cache first
                    if let id = item.itemIdentifier, let cached = imageCache[id] {
                        newDisplayedItems.append(BatchImageItem(sourceItem: item, image: cached))
                    } else {
                        // Need to load async
                        // We put a placeholder first
                        let newItem = BatchImageItem(sourceItem: item, image: nil)
                        newDisplayedItems.append(newItem)
                        
                        // We will load it below
                    }
                }
            }
            
            // Merge: PhotosPicker items + Camera items
            // Let's put camera items at the end for now, or keep them where they were?
            // It's hard to keep relative order if selectedItems changed completely.
            // Appending at the end is safest.
            newDisplayedItems.append(contentsOf: cameraItems)
            
            // Update UI with what we have (placeholders + reused + camera)
            if !Task.isCancelled {
                let initialItems = newDisplayedItems
                await MainActor.run {
                    self.displayedItems = initialItems
                }
                
                // Now load the missing images (only for those that have sourceItem and no image)
                for i in 0..<newDisplayedItems.count {
                    if Task.isCancelled { return }
                    
                    if newDisplayedItems[i].image == nil, let item = newDisplayedItems[i].sourceItem {
                        
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = downsample(data: data, to: CGSize(width: 200, height: 200)) {
                            
                            if Task.isCancelled { return }
                            
                            // Update the item in the local array
                            newDisplayedItems[i].image = image
                            
                            // Cache it
                            if let id = item.itemIdentifier {
                                await MainActor.run {
                                    imageCache[id] = image
                                }
                            }
                            
                            // Update UI incrementally
                            let updatedItem = newDisplayedItems[i]
                            let indexToUpdate = i
                            
                            await MainActor.run {
                                if indexToUpdate < self.displayedItems.count {
                                    self.displayedItems[indexToUpdate] = updatedItem
                                }
                            }
                        }
                    }
                }
            }
            
            if !Task.isCancelled {
                await MainActor.run {
                    self.isProcessing = false
                }
            }
        }
    }

    private nonisolated static func loadFullImage(from item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }

        return await Task.detached(priority: .userInitiated) {
            UIImage(data: data)
        }.value
    }
    
    private func removeImage(item: BatchImageItem) {
        print("DEBUG: Requesting removal of item: \(item.id)")
        
        // Find index of the item to remove
        guard let index = displayedItems.firstIndex(where: { $0.id == item.id }) else {
            print("WARNING: removeImage called for item not found in displayedItems. ID: \(item.id)")
            return
        }
        
        // Optimistically update UI
        displayedItems.remove(at: index)
        print("DEBUG: Removed from displayedItems. New count: \(displayedItems.count)")
        
        // Update source of truth
        // We need to remove the corresponding item from selectedItems.
        // Since we synced them, displayedItems[index] corresponds to selectedItems[index] 
        // IF selectedItems hasn't changed externally.
        // Let's verify.
        if index < selectedItems.count && selectedItems[index] == item.sourceItem {
            var newItems = selectedItems
            newItems.remove(at: index)
            print("DEBUG: Removed from selectedItems at index \(index). New count: \(newItems.count)")
            selectedItems = newItems // This triggers onChange -> loadImages
        } else {
            // Fallback: find by source item
            if let sourceIndex = selectedItems.firstIndex(where: { $0 == item.sourceItem }) {
                 var newItems = selectedItems
                 newItems.remove(at: sourceIndex)
                 print("DEBUG: Removed from selectedItems at sourceIndex \(sourceIndex). New count: \(newItems.count)")
                 selectedItems = newItems
            } else {
                print("ERROR: Could not find source item to remove in selectedItems")
            }
        }
    }
    
    private func saveBatchItems() {
        isProcessing = true
        
        // Move to background
        Task {
            // Need to access modelContext on main actor or pass it?
            // modelContext is not thread safe. 
            // We should use the context on the actor it belongs to (MainActor usually for view context).
            // But saving images (IO) should be background.
            
            // We can process images in background, get filenames, then insert on main.
            
            var savedImageCount = 0
            
            for item in displayedItems {
                if item.image == nil { continue } // Skip failed loads
                
                // If it's a camera image (sourceItem is nil), save directly
                if item.sourceItem == nil, let image = item.image {
                    if let fileName = await MainActor.run(body: {
                        ImageManager.shared.saveImage(image, context: modelContext, triggerImageSync: false)
                    }) {
                        savedImageCount += 1
                        let clothing = Clothing(
                            name: seriesName,
                            imagePaths: [fileName]
                        )
                        await MainActor.run {
                            modelContext.insert(clothing)
                        }
                    }
                    continue
                }
                
                // Load FULL image from sourceItem
                if let sourceItem = item.sourceItem,
                   let image = await Self.loadFullImage(from: sourceItem) {
                    
                    // Save image
                    if let fileName = await MainActor.run(body: {
                        ImageManager.shared.saveImage(image, context: modelContext, triggerImageSync: false)
                    }) {
                        savedImageCount += 1
                         // We can insert immediately
                        let clothing = Clothing(
                            name: seriesName,
                            imagePaths: [fileName]
                        )
                        await MainActor.run {
                            modelContext.insert(clothing)
                        }
                    }
                }
            }
            
            await MainActor.run {
                // 保存所有更改
                do {
                    try modelContext.save()
                    
                    // 更新衣物数量缓存，用于魔法任务进度实时显示
                    updateClothingCountCache()
                } catch {
                    print("BatchImportView: Failed to save context: \(error)")
                }
                
                isProcessing = false
                dismiss()
            }

            if savedImageCount > 0 {
                Task {
                    await ClothingImageSyncService.shared.syncPendingImages()
                }
            }
        }
    }
    
    /// 更新衣物数量缓存，用于魔法任务进度实时显示
    private func updateClothingCountCache() {
        FeatureUnlockManager.shared.refreshClothingCountCache(from: modelContext, reason: "batch-import")
    }
}
