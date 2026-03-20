//
//  WardrobeSelectionSheet.swift
//  ItemManager
//
//  从衣橱选择图片导入拼豆工坊
//

import SwiftUI
import SwiftData

struct WardrobeSelectionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // 查询衣橱数据
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }, sort: \Clothing.sortIndex)
    private var clothings: [Clothing]
    
    @Query(sort: \Brand.name)
    private var brands: [Brand]
    
    @Query(sort: \Tag.name)
    private var tags: [Tag]
    
    // 搜索和筛选状态
    @State private var searchText = ""
    @State private var selectedBrandIDs: Set<UUID> = []
    @State private var selectedTagIDs: Set<UUID> = []
    
    // 选中回调
    let onSelect: (Clothing) -> Void
    
    // 筛选后的衣物列表
    var filteredClothings: [Clothing] {
        let searchService = ClothingSearchService(clothings: clothings)
        let searchResults = searchService.search(query: searchText)
        let baseResults = searchText.isEmpty ? clothings : searchResults
        
        // 使用统一的筛选服务
        let config = ClothingFilterService.FilterConfig(
            selectedTagIDs: selectedTagIDs,
            selectedBrandIDs: selectedBrandIDs
        )
        
        return ClothingFilterService.filter(baseResults, config: config)
    }
    
    // 网格布局
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 搜索栏
                    searchBar
                    
                    // 筛选栏
                    filterBar
                    
                    // 衣物列表
                    clothingGrid
                }
            }
            .navigationTitle("从衣橱选择")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - 搜索栏
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索裙装名称、品牌、标签...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // MARK: - 筛选栏
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 品牌筛选
                brandFilterMenu
                
                // Tag 筛选
                tagFilterMenu
                
                // 清除筛选按钮
                if !selectedBrandIDs.isEmpty || !selectedTagIDs.isEmpty {
                    Button {
                        selectedBrandIDs.removeAll()
                        selectedTagIDs.removeAll()
                    } label: {
                        Label("清除筛选", systemImage: "xmark")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.pink.opacity(0.1))
                            .foregroundColor(.pink)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - 品牌筛选菜单
    private var brandFilterMenu: some View {
        Menu {
            Button(role: .destructive) {
                selectedBrandIDs.removeAll()
            } label: {
                Label("清除品牌筛选", systemImage: "xmark")
            }
            
            Divider()
            
            // 无品牌选项
            Button {
                toggleBrandSelection(ClothingFilterService.noBrandUUID)
            } label: {
                HStack {
                    Text("无品牌")
                    Spacer()
                    if selectedBrandIDs.contains(ClothingFilterService.noBrandUUID) {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            ForEach(brands) { brand in
                Button {
                    toggleBrandSelection(brand.id)
                } label: {
                    HStack {
                        Text(brand.name)
                        Spacer()
                        if selectedBrandIDs.contains(brand.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedBrandIDs.isEmpty ? "bag" : "bag.fill")
                Text(brandFilterLabel)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedBrandIDs.isEmpty ? Color.gray.opacity(0.1) : Color.pink.opacity(0.1))
            .foregroundColor(selectedBrandIDs.isEmpty ? .primary : .pink)
            .clipShape(Capsule())
        }
    }
    
    // 品牌筛选标签文字
    private var brandFilterLabel: String {
        if selectedBrandIDs.isEmpty {
            return "品牌"
        } else if selectedBrandIDs.contains(ClothingFilterService.noBrandUUID) {
            return "无品牌"
        } else {
            return "已选 \(selectedBrandIDs.count)"
        }
    }
    
    // MARK: - Tag 筛选菜单
    private var tagFilterMenu: some View {
        Menu {
            Button(role: .destructive) {
                selectedTagIDs.removeAll()
            } label: {
                Label("清除标签筛选", systemImage: "xmark")
            }
            
            Divider()
            
            // 无标签选项
            Button {
                toggleTagSelection(ClothingFilterService.noTagUUID)
            } label: {
                HStack {
                    Text("无标签")
                    Spacer()
                    if selectedTagIDs.contains(ClothingFilterService.noTagUUID) {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            ForEach(tags) { tag in
                Button {
                    toggleTagSelection(tag.id)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: tag.colorHex))
                            .frame(width: 8, height: 8)
                        Text(tag.name)
                        Spacer()
                        if selectedTagIDs.contains(tag.id) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedTagIDs.isEmpty ? "tag" : "tag.fill")
                Text(tagFilterLabel)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedTagIDs.isEmpty ? Color.gray.opacity(0.1) : Color.pink.opacity(0.1))
            .foregroundColor(selectedTagIDs.isEmpty ? .primary : .pink)
            .clipShape(Capsule())
        }
    }
    
    // 标签筛选标签文字
    private var tagFilterLabel: String {
        if selectedTagIDs.isEmpty {
            return "标签"
        } else if selectedTagIDs.contains(ClothingFilterService.noTagUUID) {
            return "无标签"
        } else {
            return "已选 \(selectedTagIDs.count)"
        }
    }
    
    // MARK: - 衣物网格
    private var clothingGrid: some View {
        ScrollView {
            if filteredClothings.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredClothings) { clothing in
                        ClothingSelectionCard(clothing: clothing) {
                            onSelect(clothing)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
    }
    
    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "hanger")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("没有找到符合条件的裙装")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            if !searchText.isEmpty || !selectedBrandIDs.isEmpty || !selectedTagIDs.isEmpty {
                Text("尝试清除搜索词或筛选条件")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button {
                    searchText = ""
                    selectedBrandIDs.removeAll()
                    selectedTagIDs.removeAll()
                } label: {
                    Text("清除所有筛选")
                        .foregroundColor(.pink)
                }
                .padding(.top, 8)
            } else {
                Text("衣橱中还没有添加裙装")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding(.horizontal, 40)
    }
    
    // MARK: - 辅助方法
    private func toggleBrandSelection(_ id: UUID) {
        if selectedBrandIDs.contains(id) {
            selectedBrandIDs.remove(id)
        } else {
            selectedBrandIDs.insert(id)
        }
    }
    
    private func toggleTagSelection(_ id: UUID) {
        if selectedTagIDs.contains(id) {
            selectedTagIDs.remove(id)
        } else {
            selectedTagIDs.insert(id)
        }
    }
}

// MARK: - 衣物选择卡片
struct ClothingSelectionCard: View {
    let clothing: Clothing
    let onTap: () -> Void
    
    @State private var image: UIImage?
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // 主图 - 使用正方形比例，参考 ClothingCard 实现
                ZStack {
                    if let image = image {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                            )
                    } else {
                        // 占位图
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray.opacity(0.5))
                            )
                            .background(Color.gray.opacity(0.1))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                
                // 名称
                Text(clothing.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 品牌
                if let brand = clothing.brand {
                    Text(brand.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let firstImagePath = clothing.imagePaths.first else { return }
        
        // 使用 200x200 尺寸，与 ClothingCard 保持一致
        let size = CGSize(width: 200, height: 200)
        if let cached = ImageManager.shared.cachedImage(fileName: firstImagePath, targetSize: size) {
            self.image = cached
            return
        }
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        if Task.isCancelled { return }
        
        self.image = await ImageManager.shared.loadImageAsync(fileName: firstImagePath, targetSize: size)
    }
}

// MARK: - 预览
#Preview {
    WardrobeSelectionSheet { clothing in
        print("Selected: \(clothing.name)")
    }
}
