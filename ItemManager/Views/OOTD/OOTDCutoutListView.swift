
import SwiftUI
import SwiftData

struct OOTDCutoutListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CutoutItem.timestamp, order: .reverse) private var cutouts: [CutoutItem]
    
    @Binding var isExpanded: Bool
    var onSelect: (CutoutItem) -> Void
    var onAddPhoto: () -> Void
    
    @State private var showErrorAlert = false
    @State private var searchText = ""
    @State private var selectedCategory = "全部"
    
    // Reclassify & Reprocess States
    @State private var itemToReclassify: CutoutItem?
    // @State private var showReclassifySheet = false // Removed in favor of item-based sheet
    @State private var processingItem: UUID? = nil // ID of item being processed
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    private let categories = ["全部", "裙子", "外套", "鞋子", "袜子", "玩偶", "小物", "未分类"]
    // For picker (exclude "全部")
    private var selectableCategories: [String] {
        categories.filter { $0 != "全部" }
    }
    
    var filteredCutouts: [CutoutItem] {
        var result = cutouts
        
        // Filter by Category
        if selectedCategory != "全部" {
            result = result.filter { $0.category == selectedCategory }
        }
        
        // Filter by Search Text
        if !searchText.isEmpty {
            result = result.filter { item in
                let categoryMatch = item.category.localizedCaseInsensitiveContains(searchText)
                let clothingNameMatch = item.linkedClothing?.name.localizedCaseInsensitiveContains(searchText) ?? false
                return categoryMatch || clothingNameMatch
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 5)
            
            if isExpanded {
                // Header
                HStack {
                    Text("贴纸库")
                        .font(.headline)
                    Spacer()
                    Text("共 \(filteredCutouts.count) 个")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("搜索分类或关联服饰...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            CategoryChip(title: category, isSelected: selectedCategory == category) {
                                withAnimation {
                                    selectedCategory = category
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                // Expanded View (Grid)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 16)], spacing: 16) {
                        addButton
                        
                        ForEach(filteredCutouts) { item in
                            menuForItem(item)
                        }
                    }
                    .padding()
                }
            } else {
                // Minimized View (Horizontal Scroll)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        addButton
                        
                        ForEach(cutouts.prefix(20)) { item in
                            // In minimized view, tap still adds directly? 
                            // Or should we enforce menu here too? 
                            // User said "提供点击不是直接放到画布上...是先弹出菜单"
                            // Let's use menu here too for consistency.
                            menuForItem(item)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(
            Color(uiColor: .systemBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            // Expand on tap if not tapping an item
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height < -50 {
                        withAnimation { isExpanded = true }
                    } else if value.translation.height > 50 {
                        withAnimation { isExpanded = false }
                    }
                }
        )
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(item: $itemToReclassify) { item in
            ReclassifyView(item: item, categories: selectableCategories) { newCategory in
                item.category = newCategory
                try? modelContext.save()
                itemToReclassify = nil
            }
            .presentationDetents([.height(350)])
        }
    }
    
    private func menuForItem(_ item: CutoutItem) -> some View {
        Menu {
            Button {
                onSelect(item)
                withAnimation { isExpanded = false }
            } label: {
                Label("添加到画布", systemImage: "plus.square.on.square")
            }
            
            Button {
                reprocessCutout(item)
            } label: {
                Label("重新抠图", systemImage: "arrow.triangle.2.circlepath")
            }
            
            Button {
                itemToReclassify = item
                // showReclassifySheet = true // Removed
            } label: {
                Label("修改分类", systemImage: "tag")
            }
            
            Divider()
            
            Button(role: .destructive) {
                deleteCutout(item)
            } label: {
                Label("删除", systemImage: "trash")
            }
        } label: {
            CutoutThumbnail(imagePath: item.imagePath, category: item.category)
                .overlay {
                    if processingItem == item.id {
                        ZStack {
                            Color.black.opacity(0.3)
                                .cornerRadius(12)
                            ProgressView()
                                .tint(.white)
                        }
                    }
                }
        }
        // Menu usually handles tap, but we want to make sure it works.
        // SwiftUI Menu works on tap.
    }
    
    private func reprocessCutout(_ item: CutoutItem) {
        // 1. Check if linked clothing exists and has images
        guard let clothing = item.linkedClothing,
              let firstImagePath = clothing.imagePaths.first else {
            alertMessage = "找不到关联的原图，无法重新抠图。\n(仅支持通过关联服饰创建的抠图)"
            showAlert = true
            return
        }
        
        // 2. Load original image
        processingItem = item.id
        Task {
            // Use ImageManager to load the original image
            // Note: clothing.imagePaths stores filenames
            if let originalImage = ImageManager.shared.loadImage(fileName: firstImagePath) {
                do {
                    try await CutoutService.shared.reprocessItem(item: item, with: originalImage, context: modelContext)
                    // Success feedback
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                } catch {
                    print("Reprocess failed: \(error)")
                    alertMessage = "重新抠图失败，请稍后重试。"
                    showAlert = true
                }
            } else {
                alertMessage = "原图文件已丢失。"
                showAlert = true
            }
            
            processingItem = nil
        }
    }
    
    private func deleteCutout(_ item: CutoutItem) {
        // Capture the image path before deleting the item
        let imagePath = item.imagePath
        
        // 1. Immediately delete from UI/Context with animation
        withAnimation {
            modelContext.delete(item)
        }
        
        // 2. Handle resource cleanup and persistence asynchronously
        // Using Task ensures this runs on the MainActor (since View is MainActor) but allows the UI loop to proceed
        Task {
            // Decrement ref count / delete image file (file IO is backgrounded internally in ImageManager)
            ImageManager.shared.deleteImage(fileName: imagePath, context: modelContext)
            
            // Save context with error handling
            do {
                try modelContext.save()
            } catch {
                // If save fails, show error alert
                // Note: We don't rollback UI here because delete(item) is a memory operation 
                // and save failure is rare/critical.
                print("Delete failed: \(error)")
                showErrorAlert = true
            }
        }
    }
    
    var addButton: some View {
        Button(action: onAddPhoto) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                Text("添加")
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
            .frame(width: 72, height: 72)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

struct CutoutThumbnail: View {
    let imagePath: String
    var category: String? = nil
    
    @State private var image: UIImage?
    
    @Environment(\.displayScale) var displayScale
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .padding(4)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                        .overlay(alignment: .bottomLeading) {
                            if let category = category {
                                Text(category)
                                    .font(.system(size: 8))
                                    .padding(2)
                                    .background(Color.black.opacity(0.5))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                    .padding(4)
                            }
                        }
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(width: 72, height: 72)
                }
            }
            .task {
                if image == nil {
                    // Request downsampled image (72pt * scale)
                    let targetSize = CGSize(width: 72 * displayScale, height: 72 * displayScale)
                    image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: targetSize)
                }
            }
        }
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(uiColor: .secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct ReclassifyView: View {
    let item: CutoutItem
    let categories: [String]
    let onConfirm: (String) -> Void
    
    @State private var selectedCategory: String
    
    init(item: CutoutItem, categories: [String], onConfirm: @escaping (String) -> Void) {
        self.item = item
        self.categories = categories
        self.onConfirm = onConfirm
        _selectedCategory = State(initialValue: item.category)
    }
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("选择分类", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("当前分类: \(item.category)")
                }
            }
            .navigationTitle("修改分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        onConfirm(selectedCategory)
                    }
                }
            }
        }
    }
}
