
import SwiftUI
import SwiftData

struct BatchReplaceCutoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // View State
    @State private var items: [ReplaceableItem] = []
    @State private var isLoading = true
    @State private var showingConfirmation = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("正在扫描可替换项...".appLocalized)
                } else if items.isEmpty {
                    ContentUnavailableView(
                        "没有可替换的项".appLocalized,
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("请先执行“批量处理小裙装”以生成抠图，或者所有裙装都已经包含抠图图片。".appLocalized)
                    )
                } else {
                    List {
                        Section {
                            HStack {
                                Text("全选".appLocalized)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { items.allSatisfy { $0.isSelected } },
                                    set: { newValue in
                                        for index in items.indices {
                                            items[index].isSelected = newValue
                                        }
                                    }
                                ))
                            }
                        }
                        
                        ForEach($items) { $item in
                            ReplaceItemRow(item: $item)
                                .onTapGesture {
                                    item.isSelected.toggle()
                                }
                        }
                    }
                }
                
                // Bottom Action Bar
                if !items.isEmpty {
                    VStack {
                        Divider()
                        HStack {
                            VStack(alignment: .leading) {
                                Text("已选择 %d 项".appLocalized(items.filter { $0.isSelected }.count))
                                    .font(.headline)
                                Text("将选中的抠图设为首图".appLocalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                showingConfirmation = true
                            }) {
                                Text("确认替换".appLocalized)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(items.filter { $0.isSelected }.isEmpty ? Color.gray : Color.accentColor)
                                    .cornerRadius(12)
                            }
                            .disabled(items.filter { $0.isSelected }.isEmpty)
                        }
                        .padding()
                    }
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .navigationTitle("替换主图".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消".appLocalized) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                prepareData()
            }
            .alert("确认替换".appLocalized, isPresented: $showingConfirmation) {
                Button("取消".appLocalized, role: .cancel) { }
                Button("执行".appLocalized, action: performReplacement)
            } message: {
                Text("将把选中的 %d 个抠图设置为对应裙装的第一张图片（主图）。原图将后移。".appLocalized(items.filter { $0.isSelected }.count))
            }
        }
    }
    
    private func prepareData() {
        Task { @MainActor in
            // Build a map of clothing -> cutout
            // We want the cutout that is linked to the clothing
            
            var candidates: [ReplaceableItem] = []
            let allCutouts = (try? modelContext.fetch(FetchDescriptor<CutoutItem>())) ?? []
            let clothingDescriptor = FetchDescriptor<Clothing>(
                predicate: #Predicate { $0.deletedAt == nil }
            )
            let allClothing = (try? modelContext.fetch(clothingDescriptor)) ?? []
            
            // Create a lookup for cutouts by linkedClothing
            let clothingMap = Dictionary(grouping: allCutouts.filter { $0.linkedClothingID != nil }) { $0.linkedClothingID! }
            
            // 获取所有 CutoutItem 的 imagePath，用于去重检查
            let allCutoutPaths = Set(allCutouts.map { $0.imagePath })
            
            var processedCount = 0
            
            for clothing in allClothing {
                
                // 保护机制：若裙装图片里已经有抠图图片（无论在哪个位置），则不应该出现在一键替换列表里
                // 这避免了重复添加或打乱用户已有的排序
                let hasAnyCutout = clothing.imagePaths.contains { path in
                    allCutoutPaths.contains(path)
                }
                
                if hasAnyCutout {
                    continue
                }
                
                // Find associated cutouts
                if let cutouts = clothingMap[clothing.id], !cutouts.isEmpty {
                    // Use the most recent cutout
                    // Sort by timestamp desc
                    let sortedCutouts = cutouts.sorted { $0.timestamp > $1.timestamp }
                    if let bestCutout = sortedCutouts.first {
                        // Check if already replaced by this specific cutout
                        if clothing.replacedCutoutID != nil {
                            continue
                        }
                        
                        // Check if the clothing's first image is ALREADY this cutout
                        if let firstImage = clothing.imagePaths.first {
                            if firstImage == bestCutout.imagePath {
                                // Already replaced/is the same, skip
                                continue
                            }
                        }
                        
                        // Also, we need to make sure the cutout image file actually exists
                        // Optimization: Use FileManager directly instead of loading the image
                        let fileURL = ImageManager.shared.imagesDirectory.appendingPathComponent(bestCutout.imagePath)
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            candidates.append(ReplaceableItem(clothing: clothing, cutout: bestCutout))
                        }
                    }
                }
                
                processedCount += 1
                if processedCount % 20 == 0 {
                    await Task.yield()
                }
            }
            
            self.items = candidates
            self.isLoading = false
        }
    }
    
    private func performReplacement() {
        let selectedItems = items.filter { $0.isSelected }
        
        for item in selectedItems {
            let clothing = item.clothing
            let cutoutPath = item.cutout.imagePath
            
            // Logic:
            // 1. Check if cutoutPath is already in imagePaths
            if let index = clothing.imagePaths.firstIndex(of: cutoutPath) {
                // Move to front
                clothing.imagePaths.remove(at: index)
                clothing.imagePaths.insert(cutoutPath, at: 0)
            } else {
                // Insert at front
                clothing.imagePaths.insert(cutoutPath, at: 0)
            }
            
            // Mark as replaced to prevent future suggestions
            clothing.replacedCutoutID = item.cutout.id
            
            // Update timestamp to force refresh if needed? 
            // clothing.updatedAt = Date()
        }
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save replacements: \(error)")
        }
    }
}

// Helper Model for the View
struct ReplaceableItem: Identifiable {
    let id = UUID()
    let clothing: Clothing
    let cutout: CutoutItem
    var isSelected: Bool = true
}

struct ReplaceItemRow: View {
    @Binding var item: ReplaceableItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Original Image (First one)
            if let firstPath = item.clothing.imagePaths.first {
                AsyncLocalImageView(
                    fileName: firstPath,
                    displaySize: CGSize(width: 60, height: 60),
                    contentMode: .fill,
                    cornerRadius: 8
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            } else {
                Color.gray.opacity(0.2)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            }
            
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .font(.caption)
            
            // Cutout Image
            AsyncLocalImageView(
                fileName: item.cutout.imagePath,
                displaySize: CGSize(width: 60, height: 60),
                contentMode: .fit,
                cornerRadius: 8
            )
            .background(Color.gray.opacity(0.1)) // Checkerboard pattern would be better but simple gray is fine
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.clothing.name.isEmpty ? "未命名".appLocalized : item.clothing.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(item.clothing.brand?.name ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Toggle("", isOn: $item.isSelected)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
