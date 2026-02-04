
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
    @State private var showingLimitAlert = false
    @State private var isListExpanded = false
    @State private var isSidebarVisible = false
    @State private var showingActionSheet = false
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var shouldCutoutCameraImage = false
    
    // Batch Replace
    @State private var showingBatchReplaceSheet = false
    
    // Save to Clothing States
    @State private var showingSaveToClothingSheet = false
    @State private var showingSaveSuccessAlert = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Sidebar
                    OOTDSidebarView(
                        isVisible: $isSidebarVisible,
                        currentOutfit: $currentOutfit,
                        onAdd: { type in
                            createNewOutfit(canvasType: type)
                        },
                        onDelete: { outfit in
                            deleteOutfit(outfit)
                        }
                    )
                    .zIndex(1)
                    
                    // Main Content
                    OOTDContentArea(
                        currentOutfit: $currentOutfit,
                        isListExpanded: $isListExpanded,
                        isProcessing: $isProcessing,
                        processingMessage: processingMessage,
                        geometry: geometry,
                        onAddToOutfit: { cutout in
                            addToOutfit(cutout)
                        },
                        onAddPhoto: {
                            showingActionSheet = true
                        },
                        onBatchAdd: { cutouts in
                            // Optimized batch add
                            guard let outfit = currentOutfit else { return false }
                            
                            // Check limit
                            if outfit.items.count + cutouts.count > 20 {
                                showingLimitAlert = true
                                return false
                            }
                            
                            // Add items without triggering snapshot each time
                            for (index, cutout) in cutouts.enumerated() {
                                let item = OutfitItem(
                                    cutout: cutout,
                                    x: Double(index * 20), // Slight offset to see them
                                    y: Double(index * 20),
                                    rotation: 0,
                                    scale: 1.0,
                                    zIndex: outfit.items.count
                                )
                                outfit.items.append(item)
                            }
                            
                            // Save once at the end
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 100_000_000)
                                saveSnapshot(for: outfit)
                            }
                            
                            return true
                        }
                    )
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
                        Menu {
                            Button {
                                createNewOutfit(canvasType: "mannequin")
                            } label: {
                                Label("人台画布", systemImage: "tshirt")
                            }
                            
                            Button {
                                createNewOutfit(canvasType: "blank")
                            } label: {
                                Label("空白画布", systemImage: "square.dashed")
                            }
                        } label: {
                            Label("新建搭配", systemImage: "plus")
                        }
                        
                        Button {
                            showingSaveToClothingSheet = true
                        } label: {
                            Label("保存为裙子主图", systemImage: "photo.badge.arrow.down")
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
                            showingBatchReplaceSheet = true
                        } label: {
                            Label("一键替换裙子主图", systemImage: "arrow.triangle.2.circlepath")
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
            .modifier(OOTDAlertsModifier(
                showingRenameAlert: $showingRenameAlert,
                newName: $newName,
                onRename: {
                    if let current = currentOutfit {
                        current.note = newName
                        try? modelContext.save()
                    }
                },
                showingDeleteCurrentAlert: $showingDeleteCurrentAlert,
                onDeleteCurrent: {
                    if let current = currentOutfit {
                        deleteOutfit(current)
                    }
                },
                showingLimitAlert: $showingLimitAlert,
                showingBatchConfirmation: $showingBatchConfirmation,
                onBatchProcess: {
                    processWardrobeSkirts()
                },
                showingRepairConfirmation: $showingRepairConfirmation,
                onRepair: {
                    repairMissingCutouts()
                }
            ))
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
            .sheet(isPresented: $showingSaveToClothingSheet) {
                ClothingPickerView { selectedClothing in
                    saveCanvasToClothing(clothing: selectedClothing)
                }
            }
            .sheet(isPresented: $showingBatchReplaceSheet) {
                BatchReplaceCutoutView()
            }
            .alert("保存成功", isPresented: $showingSaveSuccessAlert) {
                Button("确定", role: .cancel) {}
            }
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
            // 获取已有抠图路径，防止重复抠已替换主图的图片
            let descriptor = FetchDescriptor<CutoutItem>()
            let existingCutouts = (try? modelContext.fetch(descriptor)) ?? []
            let existingPaths = Set(existingCutouts.map { $0.imagePath })

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
                   !existingPaths.contains(firstImagePath), // 检查主图是否已经是抠图
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

    private func createNewOutfit(canvasType: String = "mannequin") {
        let newOutfit = Outfit(note: "搭配 \(Date().formatted(date: .numeric, time: .shortened))", canvasType: canvasType)
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
        
        let newOutfit = Outfit(note: current.note + " 副本", canvasType: current.canvasType)
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
    private func saveCanvasToClothing(clothing: Clothing) {
        guard let outfit = currentOutfit else { return }
        
        // Render OOTD canvas to image
        let renderer = ImageRenderer(content: OOTDPreviewView(outfit: outfit))
        renderer.scale = 1.0 // High quality
        
        if let uiImage = renderer.uiImage,
           let newPath = ImageManager.shared.saveImage(uiImage, context: modelContext) {
            
            // Update Clothing: Insert new image at index 0
            clothing.imagePaths.insert(newPath, at: 0)
            
            // Save Context
            try? modelContext.save()
            
            // Show Success
            showingSaveSuccessAlert = true
            
            // Trigger feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }

    @MainActor
    private func saveSnapshot(for outfit: Outfit) {
        // Safety check: Ensure outfit is still valid and managed
        guard !outfit.isDeleted, outfit.modelContext != nil else {
            print("Snapshot skipped: Outfit is deleted or unmanaged")
            return
        }
        
        let renderer = ImageRenderer(content: OOTDPreviewView(outfit: outfit))
        // Since OOTDPreviewView uses fixed 1080x1440, we don't need to scale up too much.
        // Scale 1.0 = 1080x1440 output.
        // If we want a smaller snapshot for thumbnail, we can scale down.
        // For quality, let's keep 0.5 (540x720) or 1.0
        renderer.scale = 0.5 
        
        if let uiImage = renderer.uiImage,
           // Force a new filename UUID each time to avoid caching issues or overwrites
           // ImageManager handles content-hashing internally, but let's ensure the path updates.
           // Actually, ImageManager.saveImage returns existing path if hash matches.
           // If content changed, hash changes -> new path or existing path of same content.
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
        
        if outfit.items.count >= 20 {
            showingLimitAlert = true
            return
        }
        
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
        processingMessage = "正在深度修复数据..."
        
        Task {
            var relinkedCount = 0
            var regeneratedCount = 0
            var failCount = 0
            
            // 1. 获取所有 Outfit
            let outfitDescriptor = FetchDescriptor<Outfit>()
            guard let allOutfits = try? modelContext.fetch(outfitDescriptor) else {
                await MainActor.run { isProcessing = false }
                return
            }
            
            // 2. 获取所有 CutoutItem (作为缓存库)
            let cutoutDescriptor = FetchDescriptor<CutoutItem>()
            guard let allCutouts = try? modelContext.fetch(cutoutDescriptor) else {
                await MainActor.run { isProcessing = false }
                return
            }
            
            // 构建快速查找表
            // Hash -> [CutoutItem] (Valid ones)
            var validCutoutsByHash: [String: [CutoutItem]] = [:]
            // ClothingID -> [CutoutItem] (Valid ones)
            var validCutoutsByClothing: [UUID: [CutoutItem]] = [:]
            
            for cutout in allCutouts {
                if ImageManager.shared.loadImage(fileName: cutout.imagePath) != nil {
                    if !cutout.originalImageHash.isEmpty {
                        validCutoutsByHash[cutout.originalImageHash, default: []].append(cutout)
                    }
                    if let clothingID = cutout.linkedClothing?.id {
                        validCutoutsByClothing[clothingID, default: []].append(cutout)
                    }
                }
            }
            
            let totalOutfits = allOutfits.count
            print("Repair: Scanning \(totalOutfits) outfits with pool of \(allCutouts.count) cutouts...")
            
            for (index, outfit) in allOutfits.enumerated() {
                // Update UI every few outfits
                if index % 5 == 0 {
                    await MainActor.run {
                        processingMessage = "正在分析搭配: \(outfit.note.isEmpty ? "未命名" : outfit.note) (\(index + 1)/\(totalOutfits))"
                    }
                }
                
                for item in outfit.items {
                    // Check if cutout is missing or broken
                    var needsRepair = false
                    
                    if let cutout = item.cutout {
                        if ImageManager.shared.loadImage(fileName: cutout.imagePath) == nil {
                            needsRepair = true
                        }
                    } else {
                        // cutout is nil - hard to repair without extra info, skipping for now
                    }
                    
                    if needsRepair, let brokenCutout = item.cutout {
                        var fixed = false
                        
                        // Strategy 1: Relink by Hash
                        if !fixed, !brokenCutout.originalImageHash.isEmpty {
                            if let candidates = validCutoutsByHash[brokenCutout.originalImageHash],
                               let bestMatch = candidates.first {
                                item.cutout = bestMatch
                                relinkedCount += 1
                                fixed = true
                                print("Repaired by Hash: \(brokenCutout.id) -> \(bestMatch.id)")
                            }
                        }
                        
                        // Strategy 2: Relink by Clothing
                        if !fixed, let clothingID = brokenCutout.linkedClothing?.id {
                            if let candidates = validCutoutsByClothing[clothingID],
                               let bestMatch = candidates.first {
                                item.cutout = bestMatch
                                relinkedCount += 1
                                fixed = true
                                print("Repaired by Clothing: \(brokenCutout.id) -> \(bestMatch.id)")
                            }
                        }
                        
                        // Strategy 3: Regenerate (Original Logic)
                        if !fixed {
                            if let clothing = brokenCutout.linkedClothing,
                               let firstPath = clothing.imagePaths.first,
                               let originalImage = ImageManager.shared.loadImage(fileName: firstPath) {
                                
                                do {
                                    try await CutoutService.shared.reprocessItem(item: brokenCutout, with: originalImage, context: modelContext)
                                    regeneratedCount += 1
                                    fixed = true
                                } catch {
                                    print("Regeneration failed: \(error)")
                                }
                            }
                        }
                        
                        if !fixed {
                            failCount += 1
                        }
                    }
                }
            }
            
            try? modelContext.save()
            
            await MainActor.run {
                isProcessing = false
                processingMessage = ""
                print("Deep Repair Finished. Relinked: \(relinkedCount), Regenerated: \(regeneratedCount), Failed: \(failCount)")
                
                // Force UI refresh by toggling current outfit if set
                if let temp = currentOutfit {
                     currentOutfit = nil
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                         self.currentOutfit = temp
                     }
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

struct OOTDAlertsModifier: ViewModifier {
    @Binding var showingRenameAlert: Bool
    @Binding var newName: String
    let onRename: () -> Void
    
    @Binding var showingDeleteCurrentAlert: Bool
    let onDeleteCurrent: () -> Void
    
    @Binding var showingLimitAlert: Bool
    
    @Binding var showingBatchConfirmation: Bool
    let onBatchProcess: () -> Void
    
    @Binding var showingRepairConfirmation: Bool
    let onRepair: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("重命名搭配", isPresented: $showingRenameAlert) {
                TextField("名称", text: $newName)
                Button("取消", role: .cancel) { }
                Button("确定", action: onRename)
            }
            .alert("删除当前搭配", isPresented: $showingDeleteCurrentAlert) {
                Button("删除", role: .destructive, action: onDeleteCurrent)
                Button("取消", role: .cancel) { }
            } message: {
                Text("确定要删除当前搭配吗？此操作无法撤销。")
            }
            .alert("数量已达上限", isPresented: $showingLimitAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("每个搭配最多只能添加20个抠图。")
            }
            .alert("批量处理", isPresented: $showingBatchConfirmation) {
                Button("开始扫描", role: .destructive, action: onBatchProcess)
                Button("取消", role: .cancel) {}
            } message: {
                Text("将扫描衣橱中所有裙装并尝试生成抠图。这可能需要一些时间。")
            }
            .alert("修复数据", isPresented: $showingRepairConfirmation) {
                Button("开始深度修复", action: onRepair)
                Button("取消", role: .cancel) {}
            } message: {
                Text("将扫描所有搭配，尝试通过哈希匹配、关联服饰匹配等方式，找回丢失的图片引用。")
            }
    }
}

struct OOTDContentArea: View {
    @Binding var currentOutfit: Outfit?
    @Binding var isListExpanded: Bool
    @Binding var isProcessing: Bool
    let processingMessage: String
    let geometry: GeometryProxy
    
    // Actions
    let onAddToOutfit: (CutoutItem) -> Void
    let onAddPhoto: () -> Void
    let onBatchAdd: ([CutoutItem]) -> Bool
    
    var body: some View {
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
                    onSelect: onAddToOutfit,
                    onAddPhoto: onAddPhoto,
                    onBatchAdd: onBatchAdd
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
