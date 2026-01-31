//
//  BatchImportView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/31/26.
//

import SwiftUI
import PhotosUI
import SwiftData

struct BatchImageItem: Identifiable {
    let id = UUID()
    let sourceItem: PhotosPickerItem
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
    @State private var currentLoadTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基础信息")) {
                    TextField("系列名称", text: $seriesName)
                    Text("每张图片将作为一个独立的裙子条目。裙子名称将设置为系列名称。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section(header: Text("选择图片 (\(displayedItems.count) 张)")) {
                    PhotosPicker(selection: $selectedItems, matching: .images, photoLibrary: .shared()) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("从相册选择")
                        }
                    }
                    .onChange(of: selectedItems) { _, newItems in
                        loadImages(from: newItems)
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

    private func loadImages(from items: [PhotosPickerItem]) {
        print("DEBUG: loadImages called with \(items.count) items")
        // Cancel previous task to prevent race conditions
        currentLoadTask?.cancel()
        
        guard !items.isEmpty else {
            print("DEBUG: items is empty, clearing displayedItems")
            displayedItems = []
            return
        }
        
        isProcessing = true
        
        currentLoadTask = Task {
            var newDisplayedItems: [BatchImageItem] = []
            
            // Try to reuse existing items to preserve UUIDs and reduce flickering
            // We map new items to displayed items
            // Since PhotosPickerItem is Equatable, we can find if we already have it
            
            // Note: PhotosPickerItem equality might not be enough if user picks same image twice?
            // Assuming unique selection or that we handle duplicates by order.
            // Let's try to match by index if item matches, otherwise search?
            // Simple approach: Iterate through new items. Check if we have a corresponding wrapper.
            
            // To handle reordering or removal correctly, we should be careful.
            // But here we are mostly concerned with "syncing".
            
            // Optimization: Create a pool of existing items
            var existingPool = displayedItems
            
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
            
            // Update UI with what we have (placeholders + reused)
            if !Task.isCancelled {
                let initialItems = newDisplayedItems
                await MainActor.run {
                    self.displayedItems = initialItems
                }
                
                // Now load the missing images
                for i in 0..<newDisplayedItems.count {
                    if Task.isCancelled { return }
                    
                    if newDisplayedItems[i].image == nil {
                        let item = newDisplayedItems[i].sourceItem
                        
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
                            
                            // Update UI incrementally? Or batch?
                            // Let's batch update at the end or periodically?
                            // For smoother UI, maybe update per item?
                            // Updating state inside loop triggers view update.
                            let updatedItem = newDisplayedItems[i]
                            let indexToUpdate = i
                            
                            await MainActor.run {
                                // Check bounds again just in case
                                if indexToUpdate < self.displayedItems.count {
                                    // We must ensure we are updating the SAME item by ID, 
                                    // but displayedItems might have changed if user deleted something?
                                    // But we are in a Task that gets cancelled on change.
                                    // So it should be safe.
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
            
            var createdItems: [(String, String)] = [] // (filename, name)
            
            for item in displayedItems {
                if item.image == nil { continue } // Skip failed loads
                
                // Load FULL image from sourceItem
                if let data = try? await item.sourceItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    
                    // Save image
                    if let fileName = await ImageManager.shared.saveImage(image, context: modelContext) {
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
                isProcessing = false
                dismiss()
            }
        }
    }
}
