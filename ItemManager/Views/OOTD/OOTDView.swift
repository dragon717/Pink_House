
import SwiftUI
import SwiftData
import PhotosUI

struct OOTDView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Clothing> { $0.isDeleted == false }) private var allClothing: [Clothing] // Fetch all clothing to scan
    @Query(sort: \Outfit.createdAt, order: .reverse) private var allOutfits: [Outfit]
    
    @State private var currentOutfit: Outfit?
    @State private var isImagePickerPresented = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var processingMessage = ""
    @State private var showingBatchConfirmation = false
    @State private var showingRepairConfirmation = false
    @State private var showingRenameAlert = false
    @State private var newName = ""
    @State private var showingDeleteCurrentAlert = false
    @State private var isListExpanded = false
    @State private var isSidebarVisible = false
    @State private var showingActionSheet = false
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var shouldCutoutCameraImage = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Sidebar
                    OOTDSidebarView(
                        isVisible: $isSidebarVisible,
                        currentOutfit: $currentOutfit,
                        onAdd: {
                            createNewOutfit()
                        },
                        onDelete: { outfit in
                            deleteOutfit(outfit)
                        }
                    )
                    .zIndex(1)
                    
                    // Main Content
                    ZStack {
                        if let outfit = currentOutfit {
                            OOTDCanvasView(outfit: outfit)
                                .id(outfit.id) // Force refresh when switching outfits
                        } else {
                            ContentUnavailableView("开始新的穿搭", systemImage: "tshirt.fill")
                        }
                        
                        VStack {
                            Spacer()
                            OOTDCutoutListView(
                                isExpanded: $isListExpanded,
                                onSelect: { cutout in
                                    addToOutfit(cutout)
                                },
                                onAddPhoto: {
                                    showingActionSheet = true
                                }
                            )
                            .frame(height: isListExpanded ? geometry.size.height * 0.8 : 200)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isListExpanded)
                        }
                        
                        if isProcessing {
                            Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            VStack {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text(processingMessage)
                                    .foregroundColor(.white)
                                    .padding(.top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("OOTD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        withAnimation {
                            isSidebarVisible.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.left")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            createNewOutfit()
                        } label: {
                            Label("新建搭配", systemImage: "plus")
                        }
                        
                        Divider()
                        
                        if let current = currentOutfit {
                            Button {
                                newName = current.note
                                showingRenameAlert = true
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                            
                            Button {
                                copyCurrentOutfit()
                            } label: {
                                Label("复制搭配", systemImage: "doc.on.doc")
                            }
                            
                            Button(role: .destructive) {
                                showingDeleteCurrentAlert = true
                            } label: {
                                Label("删除搭配", systemImage: "trash")
                            }
                            
                            Divider()
                        }
                        
                        Button {
                            showingBatchConfirmation = true
                        } label: {
                            Label("批量处理小裙子", systemImage: "wand.and.stars")
                        }
                        
                        Button {
                            showingRepairConfirmation = true
                        } label: {
                            Label("修复丢失图片", systemImage: "hammer")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .confirmationDialog("选择图片来源", isPresented: $showingActionSheet) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("拍照并抠图") {
                        shouldCutoutCameraImage = true
                        showingCamera = true
                    }
                }
                
                Button("来自图库") {
                    isImagePickerPresented = true
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
            .alert("重命名搭配", isPresented: $showingRenameAlert) {
                TextField("名称", text: $newName)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    if let current = currentOutfit {
                        current.note = newName
                        try? modelContext.save()
                    }
                }
            }
            .alert("删除当前搭配", isPresented: $showingDeleteCurrentAlert) {
                Button("删除", role: .destructive) {
                    if let current = currentOutfit {
                        deleteOutfit(current)
                    }
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("确定要删除当前搭配吗？此操作无法撤销。")
            }
            .alert("批量处理", isPresented: $showingBatchConfirmation) {
                Button("开始扫描", role: .destructive) {
                    processWardrobeSkirts()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将扫描衣橱中所有裙装并尝试生成抠图。这可能需要一些时间。")
            }
            .alert("修复数据", isPresented: $showingRepairConfirmation) {
                Button("开始修复") {
                    repairMissingCutouts()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将扫描所有搭配中丢失图片的元素，并尝试从关联的小裙子重新生成抠图。")
            }
            .onAppear {
                if currentOutfit == nil {
                    if let first = allOutfits.first {
                        currentOutfit = first
                    } else {
                        createNewOutfit()
                    }
                }
            }
            .photosPicker(isPresented: $isImagePickerPresented, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, newItem in
                if let newItem {
                    processPickedImage(newItem)
                }
            }
            .onChange(of: currentOutfit) { _, _ in
                // Auto save when switching (although SwiftData autosaves, we might want to ensure snapshot)
                // Actually snapshot should be updated when content changes, not just switching
            }
        }
    }
    
    // ... createNewOutfit, addToOutfit, saveOutfit ...
    
    private func processWardrobeSkirts() {
        isProcessing = true
        processingMessage = "正在批量处理小裙子..."
        
        Task {
            var count = 0
            // Expanded filtering to include more categories
            // This now includes: Skirts, Dresses (JSK/OP), Tops, Bottoms, Shoes, Bags, Accessories
            // Basically everything that is not deleted.
            // If you want to exclude specific things, you can refine this.
            // For now, let's process ALL clothing items that have images.
            let itemsToProcess = allClothing.filter { clothing in
                !clothing.imagePaths.isEmpty
            }
            
            let total = itemsToProcess.count
            print("Batch processing started for \(total) items.")
            
            for (index, clothing) in itemsToProcess.enumerated() {
                // Update progress every few items to avoid UI spam
                if index % 5 == 0 {
                    await MainActor.run {
                        processingMessage = "正在处理 \(index + 1)/\(total)..."
                    }
                }
                
                // Process first image of each clothing
                if let firstImagePath = clothing.imagePaths.first,
                   let image = ImageManager.shared.loadImage(fileName: firstImagePath) {
                    
                    do {
                        // Check if we already have a cutout for this clothing? 
                        // The CutoutService handles deduplication via hash check, so it's safe to call repeatedly.
                        // However, we can optimize by checking linkedClothing relation first if needed, 
                        // but hash check is more robust against re-imports.
                        
                        // Use the clothing's type or name as category
                        // types is comma separated string e.g. "JSK,OP"
                        let category = clothing.types.split(separator: ",").first.map(String.init) ?? "未分类"
                        
                        _ = try await CutoutService.shared.processImage(image: image, category: category, clothing: clothing, context: modelContext)
                        count += 1
                    } catch {
                        // Ignore errors for individual items in batch (e.g. no subject found)
                        // print("Failed to process \(clothing.name): \(error)")
                    }
                }
            }
            
            await MainActor.run {
                isProcessing = false
                processingMessage = ""
                // Optional: Show success toast
                print("Batch processing finished. Processed \(count) items.")
            }
        }
    }

    private func createNewOutfit() {
        let newOutfit = Outfit(note: "搭配 \(Date().formatted(date: .numeric, time: .shortened))")
        modelContext.insert(newOutfit)
        try? modelContext.save() // Ensure ID is generated
        currentOutfit = newOutfit
        
        // Generate initial empty snapshot
        Task { @MainActor in
            saveSnapshot(for: newOutfit)
        }
    }
    
    private func deleteOutfit(_ outfit: Outfit) {
        // If deleting current, switch first
        if currentOutfit?.id == outfit.id {
            // Find next available
            if let index = allOutfits.firstIndex(where: { $0.id == outfit.id }) {
                // Prefer previous item if available (since list is reversed time, previous index is older)
                // Actually list is sorted by time desc.
                // If we are at index i, next one is i+1.
                let nextIndex = index + 1
                if nextIndex < allOutfits.count {
                    currentOutfit = allOutfits[nextIndex]
                } else if index > 0 {
                    currentOutfit = allOutfits[index - 1]
                } else {
                    currentOutfit = nil
                }
            }
        }
        
        // Clean up snapshot file
        if let path = outfit.snapshotPath {
             ImageManager.shared.deleteImage(fileName: path, context: modelContext)
        }
        
        modelContext.delete(outfit)
        try? modelContext.save()
        
        if currentOutfit == nil {
             createNewOutfit()
        }
    }
    
    private func copyCurrentOutfit() {
        guard let current = currentOutfit else { return }
        
        // Update snapshot for current before copying
        saveSnapshot(for: current)
        
        let newOutfit = Outfit(note: current.note + " 副本")
        modelContext.insert(newOutfit)
        
        // Copy items (Reference Principle: Point to same CutoutItem)
        for item in current.items {
            let newItem = OutfitItem(
                cutout: item.cutout, // Same reference
                x: item.x,
                y: item.y,
                rotation: item.rotation,
                scale: item.scale,
                zIndex: item.zIndex
            )
            newOutfit.items.append(newItem)
        }
        
        // Copy snapshot image file if exists
        if let snapPath = current.snapshotPath,
           let image = ImageManager.shared.loadImage(fileName: snapPath),
           let newPath = ImageManager.shared.saveImage(image, context: modelContext) {
            newOutfit.snapshotPath = newPath
        }
        
        try? modelContext.save()
        
        // Switch to new outfit
        currentOutfit = newOutfit
    }

    @MainActor
    private func saveSnapshot(for outfit: Outfit) {
        // Safety check: Ensure outfit is still valid and managed
        guard !outfit.isDeleted, outfit.modelContext != nil else {
            print("Snapshot skipped: Outfit is deleted or unmanaged")
            return
        }
        
        let renderer = ImageRenderer(content: OOTDPreviewView(outfit: outfit))
        renderer.scale = 2.0 
        
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
    
    private func addToOutfit(_ cutout: CutoutItem) {
        guard let outfit = currentOutfit else { return }
        
        // Default position center
        let item = OutfitItem(
            cutout: cutout,
            x: 0,
            y: 0,
            rotation: 0,
            scale: 1.0,
            zIndex: outfit.items.count
        )
        
        outfit.items.append(item)
        
        // Update snapshot
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // Wait for layout?
            saveSnapshot(for: outfit)
        }
    }
    
    private func saveOutfit() {
        // Implement snapshot taking and saving
        if let outfit = currentOutfit {
            saveSnapshot(for: outfit)
        }
        try? modelContext.save()
    }
    
    private func processCameraImage(_ image: UIImage, shouldCutout: Bool) {
        isProcessing = true
        processingMessage = "正在识别主体..."
        
        Task {
            do {
                // Since we only support "Camera with Cutout" now, shouldCutout is always true conceptually.
                // But the caller might still pass parameters.
                // However, we removed `processImageWithoutCutout`, so we MUST use `processImage` (which cuts out).
                
                let cutout = try await CutoutService.shared.processImage(image: image, category: "未分类", context: modelContext)
                
                await MainActor.run {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    addToOutfit(cutout)
                    isProcessing = false
                    cameraImage = nil
                }
            } catch {
                print("Error processing camera image: \(error)")
                await MainActor.run {
                    isProcessing = false
                    cameraImage = nil
                    // Show error alert if needed
                }
            }
        }
    }
    
    private func repairMissingCutouts() {
        isProcessing = true
        processingMessage = "正在扫描并修复数据..."
        
        Task {
            var repairedCount = 0
            var failCount = 0
            var skippedCount = 0
            
            // Fetch all cutouts
            let descriptor = FetchDescriptor<CutoutItem>()
            guard let allCutouts = try? modelContext.fetch(descriptor) else {
                await MainActor.run { isProcessing = false }
                return
            }
            
            let total = allCutouts.count
            print("Repair: Scanning \(total) cutouts...")
            
            for (index, cutout) in allCutouts.enumerated() {
                // Check if image is missing
                if ImageManager.shared.loadImage(fileName: cutout.imagePath) == nil {
                    // Try to recover from linked clothing
                    if let clothing = cutout.linkedClothing,
                       let firstPath = clothing.imagePaths.first,
                       let originalImage = ImageManager.shared.loadImage(fileName: firstPath) {
                        
                        await MainActor.run {
                            processingMessage = "修复中: \(cutout.category) (\(index + 1)/\(total))"
                        }
                        
                        do {
                            try await CutoutService.shared.reprocessItem(item: cutout, with: originalImage, context: modelContext)
                            repairedCount += 1
                        } catch {
                            print("Repair failed for \(cutout.id): \(error)")
                            failCount += 1
                        }
                    } else {
                        failCount += 1 // Cannot repair
                    }
                } else {
                    skippedCount += 1
                }
            }
            
            await MainActor.run {
                isProcessing = false
                processingMessage = ""
                // We could show a result alert here using another state, 
                // but for now printing is enough as the visual change will be immediate.
                print("Repair finished. Repaired: \(repairedCount), Failed: \(failCount), OK: \(skippedCount)")
                
                // Force UI refresh if needed (SwiftData should handle it)
                if let current = currentOutfit {
                    // Toggle current to force refresh?
                    // id(outfit.id) in view should handle it if items update.
                }
            }
        }
    }

    private func processPickedImage(_ item: PhotosPickerItem) {
        isProcessing = true
        processingMessage = "正在识别主体..."
        
        Task {
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    
                    // 1. Process
                    let cutout = try await CutoutService.shared.processImage(image: image, category: "未分类", context: modelContext)
                    
                    // 2. Feedback
                    await MainActor.run {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        
                        // Add to current outfit immediately
                        addToOutfit(cutout)
                        
                        isProcessing = false
                        selectedItem = nil
                    }
                }
            } catch {
                print("Error processing image: \(error)")
                await MainActor.run {
                    isProcessing = false
                    selectedItem = nil
                    // Show error alert
                }
            }
        }
    }
}
