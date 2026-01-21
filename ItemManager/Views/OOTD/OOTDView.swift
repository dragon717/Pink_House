
import SwiftUI
import SwiftData
import PhotosUI

struct OOTDView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allClothing: [Clothing] // Fetch all clothing to scan
    
    @State private var currentOutfit: Outfit?
    @State private var isImagePickerPresented = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var processingMessage = ""
    @State private var showingBatchConfirmation = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                if let outfit = currentOutfit {
                    OOTDCanvasView(outfit: outfit)
                } else {
                    ContentUnavailableView("开始新的穿搭", systemImage: "tshirt.fill")
                }
                
                VStack {
                    Spacer()
                    OOTDCutoutListView(
                        onSelect: { cutout in
                            addToOutfit(cutout)
                        },
                        onAddPhoto: {
                            isImagePickerPresented = true
                        }
                    )
                    .frame(height: 200) // Adjust height as needed
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
            .navigationTitle("OOTD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("保存搭配") {
                            saveOutfit()
                        }
                        Button("批量处理小裙子") {
                            showingBatchConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("新建") {
                        createNewOutfit()
                    }
                }
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
                    createNewOutfit()
                }
            }
            .photosPicker(isPresented: $isImagePickerPresented, selection: $selectedItem, matching: .images)
            .onChange(of: selectedItem) { _, newItem in
                if let newItem {
                    processPickedImage(newItem)
                }
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
                        _ = try await CutoutService.shared.processImage(image: image, category: "裙装", context: modelContext)
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
        let newOutfit = Outfit()
        modelContext.insert(newOutfit)
        currentOutfit = newOutfit
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
    }
    
    private func saveOutfit() {
        // Implement snapshot taking and saving
        // For now just save context
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
