//
//  BatchImportView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/31/26.
//

import SwiftUI
import PhotosUI
import SwiftData

struct BatchImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var seriesName: String = ""
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var isProcessing: Bool = false
    @State private var showingConfirmation: Bool = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("基础信息")) {
                    TextField("系列名称", text: $seriesName)
                    Text("每张图片将作为一个独立的裙子条目。裙子名称将设置为系列名称。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section(header: Text("选择图片 (\(selectedImages.count) 张)")) {
                    PhotosPicker(selection: $selectedItems, matching: .images, photoLibrary: .shared()) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("从相册选择")
                        }
                    }
                    .onChange(of: selectedItems) { _, newItems in
                        loadImages(from: newItems)
                    }
                    
                    if !selectedImages.isEmpty {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))]) {
                            ForEach(0..<selectedImages.count, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Button {
                                        removeImage(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .red)
                                            .background(Circle().fill(.white))
                                    }
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
                        if !selectedImages.isEmpty {
                            showingConfirmation = true
                        }
                    }
                    .disabled(selectedImages.isEmpty || isProcessing)
                }
            }
            .alert("确认导入", isPresented: $showingConfirmation) {
                Button("取消", role: .cancel) { }
                Button("确定") {
                    saveBatchItems()
                }
            } message: {
                Text("将创建 \(selectedImages.count) 个新条目，系列名称为“\(seriesName.isEmpty ? "(空)" : seriesName)”。\n确认后将立即保存。")
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
    
    private func loadImages(from items: [PhotosPickerItem]) {
        // Reset or append? PhotosPicker with selection binding reflects current selection.
        // So we should reload everything or handle diffs.
        // For simplicity, we just reload all.
        // But we need to be careful about performance if many items.
        // Actually, if we modify selectedItems (via remove), this triggers again.
        
        // Optimisation: check if count matches to avoid reload loop if just removing?
        // But removing updates selectedItems, which triggers onChange.
        // We can check if we are already processing.
        
        guard !items.isEmpty else {
            selectedImages = []
            return
        }
        
        // Only reload if the items actually changed in a way that requires reloading
        // (This is tricky with PhotosPickerItem equality, but let's just reload for now)
        
        isProcessing = true
        
        Task {
            var newImages: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    // Optional: Compress here for display? No, keep original for saving.
                    // But for display we might want thumbnails? 
                    // Let's just store the full UIImage for now, assuming user doesn't pick 1000s.
                    newImages.append(image)
                }
            }
            
            await MainActor.run {
                self.selectedImages = newImages
                self.isProcessing = false
            }
        }
    }
    
    private func removeImage(at index: Int) {
        guard index < selectedImages.count && index < selectedItems.count else { return }
        
        // This will trigger onChange, so we need to be careful.
        // Ideally we update both.
        var newItems = selectedItems
        newItems.remove(at: index)
        selectedItems = newItems // This triggers onChange -> loadImages
        
        // We could let loadImages handle the update of selectedImages,
        // but it might be slow to reload all. 
        // Ideally we should have a way to map items to images.
        // For now, let's rely on the reload.
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
            
            for image in selectedImages {
                // ImageManager.shared.saveImage is MainActor annotated in the file I read!
                // So I have to call it on MainActor.
                // If it's slow, it might block UI.
                // Let's check ImageManager again.
                // It says @MainActor class ImageManager.
                
                // If saveImage is on MainActor, we can't easily offload it without changing ImageManager.
                // But saveImage does `try data.write(to: fileURL)` which is blocking IO on Main thread if called from MainActor.
                // That's not ideal but let's follow existing pattern for now.
                
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
            
            await MainActor.run {
                isProcessing = false
                dismiss()
            }
        }
    }
}
