//
//  AssetPanel.swift
//  ItemManager
//
//  右侧素材面板 - 服饰/特效/模版/素材
//

import SwiftUI
import SwiftData

struct AssetPanel: View {
    @Binding var selectedCategory: AssetCategory
    var onAssetSelect: (SpatialAsset) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var cutoutItems: [CutoutItem]
    
    @State private var searchText = ""
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            HStack {
                Text("素材")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "xmark" : "line.3.horizontal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(colorScheme == .dark ? Color(uiColor: .systemGray5).opacity(0.9) : Color.white.opacity(0.8))

            if isExpanded {
                // 分类标签
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AssetCategory.allCases, id: \.self) { category in
                            CategoryTab(
                                title: category.rawValue,
                                isSelected: selectedCategory == category
                            ) {
                                withAnimation {
                                    selectedCategory = category
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                // 搜索栏
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("搜索...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(colorScheme == .dark ? Color(uiColor: .systemGray4).opacity(0.5) : Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                // 素材列表
                ScrollView {
                    LazyVStack(spacing: 12) {
                        switch selectedCategory {
                        case .clothing:
                            ClothingAssetList(searchText: searchText, onSelect: onAssetSelect)
                        case .effect:
                            EffectAssetList(onSelect: onAssetSelect)
                        case .template:
                            TemplateAssetList(onSelect: onAssetSelect)
                        case .material:
                            MaterialAssetList(onSelect: onAssetSelect)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: isExpanded ? 320 : 50)
        .frame(maxHeight: .infinity)
        .background(colorScheme == .dark ? Color(uiColor: .systemGray5).opacity(0.9) : Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.trailing, 8)
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - 分类标签

struct CategoryTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.purple : Color.gray.opacity(0.15))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 服饰素材列表

struct ClothingAssetList: View {
    let searchText: String
    let onSelect: (SpatialAsset) -> Void
    
    @Query(filter: #Predicate<CutoutItem> { $0.category != "已删除" }) private var cutouts: [CutoutItem]
    
    var filteredCutouts: [CutoutItem] {
        if searchText.isEmpty {
            return cutouts
        }
        return cutouts.filter { cutout in
            (cutout.clothingName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            cutout.category.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(filteredCutouts.prefix(20)) { cutout in
                ClothingAssetCard(cutout: cutout) {
                    let asset = SpatialAsset(
                        type: .clothing,
                        name: cutout.clothingName ?? "未命名",
                        imagePath: cutout.imagePath,
                        thumbnail: ImageManager.shared.loadImage(fileName: cutout.imagePath),
                        metadata: ["category": cutout.category]
                    )
                    onSelect(asset)
                }
            }
        }
    }
}

// MARK: - 服饰卡片

struct ClothingAssetCard: View {
    let cutout: CutoutItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 缩略图
                if let image = ImageManager.shared.loadImage(fileName: cutout.imagePath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "tshirt")
                                .foregroundStyle(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(cutout.clothingName ?? "未命名")
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    Text(cutout.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.purple)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 特效素材列表

struct EffectAssetList: View {
    let onSelect: (SpatialAsset) -> Void
    
    let effects = [
        ("粒子星光", "sparkles", Color.yellow),
        ("花瓣飘落", "leaf", Color.pink),
        ("蝴蝶飞舞", "butterfly", Color.purple),
        ("雪花飘落", "snowflake", Color.cyan),
        ("光晕效果", "sun.max", Color.orange),
        ("魔法光环", "circle.hexagongrid", Color.blue)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(effects, id: \.0) { effect in
                EffectAssetCard(name: effect.0, icon: effect.1, color: effect.2) {
                    let asset = SpatialAsset(
                        type: .effect,
                        name: effect.0,
                        imagePath: nil,
                        thumbnail: nil,
                        metadata: ["effectType": effect.0]
                    )
                    onSelect(asset)
                }
            }
        }
    }
}

// MARK: - 特效卡片

struct EffectAssetCard: View {
    let name: String
    let icon: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                }
                
                Text(name)
                    .font(.subheadline)
                
                Spacer()
                
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(color)
            }
            .padding()
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 模版素材列表

struct TemplateAssetList: View {
    let onSelect: (SpatialAsset) -> Void
    
    let templates = [
        ("洛可可风格", "rococo", Color.pink),
        ("法式复古", "french", Color.brown),
        ("现代简约", "modern", Color.gray),
        ("梦幻花园", "garden", Color.green),
        ("星空主题", "starry", Color.indigo)
    ]
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(templates, id: \.0) { template in
                TemplateCard(name: template.0, color: template.2) {
                    let asset = SpatialAsset(
                        type: .template,
                        name: template.0,
                        imagePath: nil,
                        thumbnail: nil,
                        metadata: ["templateType": template.1]
                    )
                    onSelect(asset)
                }
            }
        }
    }
}

// MARK: - 模版卡片

struct TemplateCard: View {
    let name: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.3))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        Image(systemName: "square.grid.2x2")
                            .font(.largeTitle)
                            .foregroundStyle(color)
                    )
                
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 材质素材列表

struct MaterialAssetList: View {
    let onSelect: (SpatialAsset) -> Void
    
    let materials = [
        ("丝绸", "silk", Color.pink.opacity(0.5)),
        ("天鹅绒", "velvet", Color.purple.opacity(0.6)),
        ("蕾丝", "lace", Color.white.opacity(0.8)),
        ("皮革", "leather", Color.brown.opacity(0.7)),
        ("金属", "metal", Color.gray.opacity(0.8)),
        ("珍珠", "pearl", Color.white.opacity(0.9))
    ]
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(materials, id: \.0) { material in
                MaterialCard(name: material.0, color: material.2) {
                    let asset = SpatialAsset(
                        type: .material,
                        name: material.0,
                        imagePath: nil,
                        thumbnail: nil,
                        metadata: ["materialType": material.1]
                    )
                    onSelect(asset)
                }
            }
        }
    }
}

// MARK: - 材质卡片

struct MaterialCard: View {
    let name: String
    let color: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(color)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        AssetPanel(
            selectedCategory: .constant(.clothing),
            onAssetSelect: { _ in }
        )
    }
}
