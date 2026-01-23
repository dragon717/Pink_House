
import SwiftUI
import SwiftData
import PhotosUI

struct OOTDView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allClothing: [Clothing] // Fetch all clothing to scan
    @Query(sort: \Outfit.createdAt, order: .reverse) private var allOutfits: [Outfit]
    
    @State private var currentOutfit: Outfit?
    @State private var isImagePickerPresented = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var processingMessage = ""
    @State private var showingBatchConfirmation = false
    @State private var showingRenameAlert = false
    @State private var newName = ""
    @State private var showingDeleteCurrentAlert = false
    @State private var isListExpanded = false
    @State private var isSidebarVisible = false

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
                                    isImagePickerPresented = true
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
            // Filter skirts (simple string match for demo)
            let skirts = allClothing.filter { $0.types.contains("裙") || $0.name.contains("裙") || $0.types.contains("JSK") || $0.types.contains("OP") || $0.types.contains("SK") }
            
            for clothing in skirts {
                // Process first image of each clothing
                if let firstImagePath = clothing.imagePaths.first,
                   let image = ImageManager.shared.loadImage(fileName: firstImagePath) {
                    
                    do {
                        // Check if we already have a cutout for this clothing? 
                        // For now, just process.
                        _ = try await CutoutService.shared.processImage(image: image, category: "裙装", clothing: clothing, context: modelContext)
                        count += 1
                        await MainActor.run {
                            processingMessage = "已处理 \(count) 件..."
                        }
                    } catch {
                        // Ignore errors for individual items in batch
                        print("Failed to process \(clothing.name): \(error)")
                    }
                }
            }
            
            await MainActor.run {
                isProcessing = false
                processingMessage = ""
                // Optional: Show success toast
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
