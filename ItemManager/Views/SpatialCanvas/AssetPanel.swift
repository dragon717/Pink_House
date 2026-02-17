//
//  AssetPanel.swift
//  ItemManager
//
//  右侧素材面板 - 服饰/特效/模版/素材
//

import SwiftUI
import SwiftData
import UIKit
import RealityKit
import simd

// MARK: - SpatialAsset 类型

struct SpatialAsset: Identifiable {
    let id = UUID()
    let type: AssetType
    let name: String
    let imagePath: String?
    let thumbnail: UIImage?
    let metadata: [String: String]
    
    enum AssetType {
        case model
        case clothing
        case effect
        case template
        case material
    }
    
    init(
        type: AssetType,
        name: String,
        imagePath: String? = nil,
        thumbnail: UIImage? = nil,
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.name = name
        self.imagePath = imagePath
        self.thumbnail = thumbnail
        self.metadata = metadata
    }
}

struct AssetPanel: View {
    @Binding var selectedCategory: AssetCategory
    var onAssetSelect: (SpatialAsset) -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var cutoutItems: [CutoutItem]
    
    @State private var searchText = ""
    @State private var isExpanded = true
    @State private var isSearchActive = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // 顶部标题栏 + 分类标签 + 搜索栏 合并为一行
                VStack(spacing: 8) {
                    // 第一行：标题和关闭按钮
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
                            Image(systemName: "xmark")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color.gray.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    
                    // 第二行：分类标签和搜索
                    HStack(spacing: 8) {
                        // 搜索框（当激活时显示）
                        if isSearchActive {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 14))
                                
                                TextField("搜索素材...", text: $searchText)
                                    .font(.system(size: 14))
                                    .textFieldStyle(PlainTextFieldStyle())
                                
                                if !searchText.isEmpty {
                                    Button(action: { searchText = "" }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                            .font(.system(size: 14))
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                        
                        // 分类标签（当搜索未激活时显示）
                        if !isSearchActive {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(AssetCategory.allCases, id: \.self) { category in
                                        CategoryTab(
                                            title: category.rawValue,
                                            category: category,
                                            isSelected: selectedCategory == category
                                        ) {
                                            withAnimation {
                                                selectedCategory = category
                                            }
                                        }
                                    }
                                }
                            }
                            .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                        
                        // 搜索按钮
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                isSearchActive.toggle()
                                if !isSearchActive {
                                    searchText = ""
                                }
                            }
                        } label: {
                            Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundStyle(isSearchActive ? .primary : .secondary)
                                .frame(width: 32, height: 32)
                                .background(isSearchActive ? Color.pink.opacity(0.2) : Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colorScheme == .dark ? Color(uiColor: .systemGray5).opacity(0.9) : Color.white.opacity(0.8))
                
                // 素材列表
                ScrollView {
                    LazyVStack(spacing: 12) {
                        switch selectedCategory {
                        case .models:
                            Model3DAssetList(searchText: searchText, onSelect: onAssetSelect)
                        case .clothing:
                            ClothingAssetList(searchText: searchText, onSelect: onAssetSelect)
                        case .effect:
                            EffectAssetList(searchText: searchText, onSelect: onAssetSelect)
                        case .template:
                            TemplateAssetList(searchText: searchText, onSelect: onAssetSelect)
                        case .material:
                            MaterialAssetList(searchText: searchText, onSelect: onAssetSelect)
                        case .accessories:
                            AccessoriesAssetList(searchText: searchText, onSelect: onAssetSelect)
                        case .furniture:
                            FurnitureAssetList(searchText: searchText, onSelect: onAssetSelect)
                        }
                    }
                    .padding()
                }
            } else {
                // 折叠状态 - 显示小按钮
                VStack {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color(uiColor: .systemGray5).opacity(0.9) : Color.white.opacity(0.8))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .padding(.top, 16)
            }
        }
        .frame(width: isExpanded ? 320 : 60)
        .frame(maxHeight: .infinity)
        .background(isExpanded ? (colorScheme == .dark ? Color(uiColor: .systemGray5).opacity(0.9) : Color.white.opacity(0.8)) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 0, style: .continuous))
        .padding(.trailing, 8)
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - 分类标签

struct CategoryTab: View {
    let title: String
    let category: AssetCategory
    let isSelected: Bool
    let action: () -> Void
    
    var categoryColor: Color {
        switch category {
        case .models:
            return .purple
        case .clothing:
            return .orange
        case .effect:
            return .pink
        case .template:
            return .cyan
        case .material:
            return .purple
        case .accessories:
            return .blue
        case .furniture:
            return .brown
        }
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? categoryColor : Color.gray.opacity(0.15))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - 服饰素材列表 (只显示3D模型)

struct ClothingAssetList: View {
    let searchText: String
    let onSelect: (SpatialAsset) -> Void
    
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil && $0.model3DPath != nil }) private var clothing3DModels: [Clothing]
    
    var filteredClothing: [Clothing] {
        if searchText.isEmpty {
            return clothing3DModels
        }
        return clothing3DModels.filter { clothing in
            clothing.name.localizedCaseInsensitiveContains(searchText) ||
            clothing.types.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if filteredClothing.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("暂无3D模型")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("使用相机拍摄20+张照片\n或从图库选择图片生成3D模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
            } else {
                ForEach(filteredClothing.prefix(20)) { clothing in
                    Clothing3DAssetCard(clothing: clothing) {
                        // 使用解析后的路径（支持相对路径）
                        let resolvedPath = clothing.resolvedModel3DPath ?? ""
                        let asset = SpatialAsset(
                            type: .clothing,
                            name: clothing.name,
                            imagePath: clothing.model3DThumbnailPath,
                            thumbnail: loadThumbnail(for: clothing),
                            metadata: [
                                "modelPath": resolvedPath,
                                "modelType": clothing.model3DType ?? "multi",
                                "typeDescription": clothing.model3DTypeDescription ?? "3D"
                            ]
                        )
                        onSelect(asset)
                    }
                }
            }
        }
    }
    
    private func loadThumbnail(for clothing: Clothing) -> UIImage? {
        // 使用解析后的路径加载缩略图
        if let resolvedPath = clothing.resolvedModel3DThumbnailPath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: resolvedPath)),
           let image = UIImage(data: data) {
            return image
        }
        // 尝试加载第一张源图片
        if let firstResolvedPath = clothing.resolvedImagePaths.first,
           let data = try? Data(contentsOf: URL(fileURLWithPath: firstResolvedPath)),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
}

// MARK: - 3D服饰卡片

struct Clothing3DAssetCard: View {
    let clothing: Clothing
    let onTap: () -> Void
    
    /// 加载缩略图图片
    private var thumbnailImage: UIImage? {
        // 优先使用解析后的缩略图路径
        if let resolvedPath = clothing.resolvedModel3DThumbnailPath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: resolvedPath)),
           let image = UIImage(data: data) {
            return image
        }
        // 尝试第一张源图片
        if let firstResolvedPath = clothing.resolvedImagePaths.first,
           let data = try? Data(contentsOf: URL(fileURLWithPath: firstResolvedPath)),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 缩略图
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "cube.box")
                                .foregroundStyle(.purple)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(clothing.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        // 3D类型标签
                        Text(clothing.model3DTypeDescription ?? "3D")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        Text(clothing.types)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
    let searchText: String
    let onSelect: (SpatialAsset) -> Void
    
    let effects = [
        ("粒子星光", "sparkles", Color.yellow),
        ("花瓣飘落", "leaf", Color.pink),
        ("蝴蝶飞舞", "🦋", Color.purple),
        ("雪花飘落", "snowflake", Color.cyan),
        ("光晕效果", "sun.max", Color.orange),
        ("魔法光环", "circle.hexagongrid", Color.blue)
    ]
    
    var filteredEffects: [(String, String, Color)] {
        if searchText.isEmpty {
            return effects
        }
        return effects.filter { effect in
            effect.0.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(filteredEffects, id: \.0) { effect in
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
    
    private var isEmoji: Bool {
        icon.count == 1 && icon.unicodeScalars.first?.properties.isEmoji == true
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 图标
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    if isEmoji {
                        Text(icon)
                            .font(.system(size: 28))
                    } else {
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(color)
                    }
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
    let searchText: String
    let onSelect: (SpatialAsset) -> Void
    
    let templates = [
        ("洛可可风格", "rococo", Color.pink),
        ("法式复古", "french", Color.brown),
        ("现代简约", "modern", Color.gray),
        ("梦幻花园", "garden", Color.green),
        ("星空主题", "starry", Color.indigo)
    ]
    
    var filteredTemplates: [(String, String, Color)] {
        if searchText.isEmpty {
            return templates
        }
        return templates.filter { template in
            template.0.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(filteredTemplates, id: \.0) { template in
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
    let searchText: String
    let onSelect: (SpatialAsset) -> Void
    
    let materials = [
        ("丝绸", "silk", Color.pink.opacity(0.5)),
        ("天鹅绒", "velvet", Color.purple.opacity(0.6)),
        ("蕾丝", "lace", Color.white.opacity(0.8)),
        ("皮革", "leather", Color.brown.opacity(0.7)),
        ("金属", "metal", Color.gray.opacity(0.8)),
        ("珍珠", "pearl", Color.white.opacity(0.9))
    ]
    
    var filteredMaterials: [(String, String, Color)] {
        if searchText.isEmpty {
            return materials
        }
        return materials.filter { material in
            material.0.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(filteredMaterials, id: \.0) { material in
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

// MARK: - 配饰素材列表

struct AccessoriesAssetList: View {
    let searchText: String
    let onSelect: (SpatialAsset) -> Void
    
    let accessories = [
        ("项链", "necklace", Color.yellow),
        ("耳环", "earrings", Color.pink),
        ("手链", "bracelet", Color.blue),
        ("戒指", "ring", Color.orange),
        ("发饰", "hairpin", Color.purple),
        ("包包", "bag", Color.brown)
    ]
    
    var filteredAccessories: [(String, String, Color)] {
        if searchText.isEmpty {
            return accessories
        }
        return accessories.filter { item in
            item.0.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(filteredAccessories, id: \.0) { item in
                AccessoryCard(name: item.0, color: item.2) {
                    let asset = SpatialAsset(
                        type: .effect,
                        name: item.0,
                        imagePath: nil,
                        thumbnail: nil,
                        metadata: ["accessoryType": item.1]
                    )
                    onSelect(asset)
                }
            }
        }
    }
}

// MARK: - 配饰卡片

struct AccessoryCard: View {
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
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(color)
                    )
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

// MARK: - 家具素材列表

struct FurnitureAssetList: View {
    let searchText: String
    let onSelect: (SpatialAsset) -> Void
    
    let furniture = [
        ("沙发", "sofa", Color.brown),
        ("椅子", "chair", Color.orange),
        ("桌子", "table", Color.gray),
        ("床", "bed", Color.blue),
        ("柜子", "cabinet", Color.purple),
        ("灯具", "lamp", Color.yellow)
    ]
    
    var filteredFurniture: [(String, String, Color)] {
        if searchText.isEmpty {
            return furniture
        }
        return furniture.filter { item in
            item.0.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(filteredFurniture, id: \.0) { item in
                FurnitureCard(name: item.0, color: item.2) {
                    let asset = SpatialAsset(
                        type: .template,
                        name: item.0,
                        imagePath: nil,
                        thumbnail: nil,
                        metadata: ["furnitureType": item.1]
                    )
                    onSelect(asset)
                }
            }
        }
    }
}

// MARK: - 家具卡片

struct FurnitureCard: View {
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
                        Image(systemName: "cube.box")
                            .font(.title2)
                            .foregroundStyle(color)
                    )
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

// MARK: - 3D模型素材列表

struct Model3DAssetList: View {
    let searchText: String
    let onSelect: (SpatialAsset) -> Void
    
    @Query(filter: #Predicate<Model3D> { $0.isDeleted == false }) private var models: [Model3D]
    
    var filteredModels: [Model3D] {
        let validModels = models.filter { $0.modelPath != nil }
        if searchText.isEmpty {
            return validModels
        }
        return validModels.filter { model in
            model.name.localizedCaseInsensitiveContains(searchText) ||
            model.types.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            if filteredModels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "cube.box")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("暂无3D模型")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("使用相机拍摄20+张照片\n或从图库选择图片生成3D模型")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                .onAppear {
                    print("[Model3DAssetList] ===== 调试信息 =====")
                    print("[Model3DAssetList] 查询到所有 Model3D 数量: \(models.count)")
                    for model in models {
                        print("[Model3DAssetList]  - id: \(model.id), name: \(model.name), isDeleted: \(model.isDeleted), modelPath: \(model.modelPath ?? "nil")")
                    }
                    print("[Model3DAssetList] 有 modelPath 的数量: \(models.filter { $0.modelPath != nil }.count)")
                    print("[Model3DAssetList] ==================")
                }
            } else {
                ForEach(filteredModels.prefix(20)) { model in
                    Model3DAssetCard(model: model) {
                        let resolvedPath = model.resolvedModelPath ?? ""
                        let asset = SpatialAsset(
                            type: .model,
                            name: model.name,
                            imagePath: model.thumbnailPath,
                            thumbnail: loadThumbnail(for: model),
                            metadata: [
                                "modelPath": resolvedPath,
                                "modelType": model.modelType ?? "multi",
                                "typeDescription": model.modelTypeDescription ?? "3D",
                                "model3DID": model.id.uuidString
                            ]
                        )
                        onSelect(asset)
                    }
                }
                .onAppear {
                    print("[Model3DAssetList] 显示 \(filteredModels.count) 个 3D 模型")
                }
            }
        }
    }
    
    private func loadThumbnail(for model: Model3D) -> UIImage? {
        if let resolvedPath = model.resolvedThumbnailPath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: resolvedPath)),
           let image = UIImage(data: data) {
            return image
        }
        if let firstResolvedPath = model.resolvedSourceImagePaths.first,
           let data = try? Data(contentsOf: URL(fileURLWithPath: firstResolvedPath)),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
}

// MARK: - 3D模型卡片

struct Model3DAssetCard: View {
    let model: Model3D
    let onTap: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var showingRenameAlert = false
    @State private var showingDeleteAlert = false
    @State private var showingUsageAlert = false
    @State private var showingThumbnailEditor = false
    @State private var showingShareSheet = false
    @State private var newName: String = ""
    @State private var usageCount: Int = 0
    
    private var thumbnailImage: UIImage? {
        if let resolvedPath = model.resolvedThumbnailPath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: resolvedPath)),
           let image = UIImage(data: data) {
            return image
        }
        if let firstResolvedPath = model.resolvedSourceImagePaths.first,
           let data = try? Data(contentsOf: URL(fileURLWithPath: firstResolvedPath)),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "cube.box")
                                .foregroundStyle(.purple)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(model.modelTypeDescription ?? "3D")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        Text(model.types)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .contextMenu {
            Button {
                newName = model.name
                showingRenameAlert = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            
            Button {
                showingThumbnailEditor = true
            } label: {
                Label("设置缩略图", systemImage: "camera.viewfinder")
            }
            
            Button {
                showingShareSheet = true
            } label: {
                Label("导出模型分享", systemImage: "square.and.arrow.up")
            }
            
            Button(role: .destructive) {
                checkUsageAndShowDeleteAlert()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .alert("重命名", isPresented: $showingRenameAlert) {
            TextField("请输入新名称", text: $newName)
            Button("取消", role: .cancel) { }
            Button("确定") {
                renameModel()
            }
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                performDelete()
            }
        } message: {
            Text("确定要删除「\(model.name)」吗？此操作无法撤销，模型文件和数据将被永久删除。")
        }
        .alert("无法删除", isPresented: $showingUsageAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("该模型正在被 \(usageCount) 个场景使用，请先从场景中移除后再删除。")
        }
        .sheet(isPresented: $showingThumbnailEditor) {
            ModelThumbnailEditorView(model: model)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let resolvedPath = model.resolvedModelPath {
                ShareSheet(items: [URL(fileURLWithPath: resolvedPath)])
            }
        }
    }
    
    private func renameModel() {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        model.name = newName
        model.updatedAt = Date()
        try? modelContext.save()
    }
    
    private func checkUsageAndShowDeleteAlert() {
        let descriptor = FetchDescriptor<SceneObjectData>()
        let allObjects = (try? modelContext.fetch(descriptor)) ?? []
        usageCount = allObjects.filter { $0.model3D?.id == model.id }.count
        
        if usageCount > 0 {
            showingUsageAlert = true
        } else {
            showingDeleteAlert = true
        }
    }
    
    private func performDelete() {
        let fileManager = FileManager.default
        if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelDir = documentsPath.appendingPathComponent("Models/\(model.id.uuidString)")
            try? fileManager.removeItem(at: modelDir)
        }
        
        modelContext.delete(model)
        try? modelContext.save()
    }
}

// MARK: - 3D模型缩略图编辑器

struct ModelThumbnailEditorView: View {
    let model: Model3D
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 3)
    @State private var cameraRotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    @State private var isSaving = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.95, blue: 0.93))
                    .ignoresSafeArea()
                
                if let resolvedPath = model.resolvedModelPath {
                    SingleModelRealityView(
                        modelPath: resolvedPath,
                        cameraPosition: $cameraPosition,
                        cameraRotation: $cameraRotation
                    )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        
                        Text("无法加载模型")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                VStack {
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button {
                            resetCamera()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("重置视角")
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        Spacer()
                        
                        Button {
                            dismiss()
                        } label: {
                            Text("取消")
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        Button {
                            saveThumbnail()
                        } label: {
                            HStack(spacing: 4) {
                                if isSaving {
                                    ProgressView()
                                } else {
                                    Image(systemName: "checkmark")
                                }
                                Text("保存")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(isSaving)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("设置缩略图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                cameraPosition = model.cameraPosition
                cameraRotation = model.cameraRotation
            }
        }
    }
    
    private func resetCamera() {
        cameraPosition = SIMD3<Float>(0, 0, 3)
        cameraRotation = SIMD3<Float>(0, 0, 0)
    }
    
    private func saveThumbnail() {
        isSaving = true
        
        Task {
            await MainActor.run {
                model.cameraPosition = cameraPosition
                model.cameraRotation = cameraRotation
                model.updatedAt = Date()
                
                let modelID = model.id
                let fileManager = FileManager.default
                guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    isSaving = false
                    return
                }
                
                let modelDir = documentsPath.appendingPathComponent("Models/\(modelID.uuidString)")
                try? fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
                
                if let firstImagePath = model.resolvedSourceImagePaths.first,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: firstImagePath)),
                   let image = UIImage(data: data) {
                    
                    let thumbnailSize = CGSize(width: 200, height: 200)
                    let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
                    let thumbnail = renderer.image { context in
                        let bgColor = UIColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1.0)
                        bgColor.setFill()
                        context.fill(CGRect(origin: .zero, size: thumbnailSize))
                        image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                    }
                    
                    let thumbnailFileName = "thumbnail.jpg"
                    let thumbnailPath = modelDir.appendingPathComponent(thumbnailFileName)
                    if let data = thumbnail.jpegData(compressionQuality: 0.8) {
                        try? data.write(to: thumbnailPath)
                        let relativePath = "Models/\(modelID.uuidString)/\(thumbnailFileName)"
                        model.setThumbnailPath(relativePath)
                    }
                }
                
                try? modelContext.save()
                isSaving = false
                dismiss()
            }
        }
    }
}

struct SingleModelRealityView: View {
    let modelPath: String
    @Binding var cameraPosition: SIMD3<Float>
    @Binding var cameraRotation: SIMD3<Float>
    
    @StateObject private var cameraController = CameraController()
    
    var body: some View {
        GeometryReader { geometry in
            RealityView { content in
                let rootEntity = Entity()
                rootEntity.name = "sceneRoot"
                content.add(rootEntity)
                
                cameraController.distance = cameraPosition.z
                cameraController.rotationY = cameraRotation.y
                cameraController.rotationX = cameraRotation.x
                
                _ = cameraController.setupCamera(in: rootEntity)
                
                if let modelEntity = try? Entity.load(contentsOf: URL(fileURLWithPath: modelPath)) {
                    modelEntity.position = SIMD3<Float>(0, 0, 0)
                    rootEntity.addChild(modelEntity)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let delta = value.translation
                        let rotationSpeed: Float = 0.005
                        cameraController.rotationY += Float(delta.width) * rotationSpeed
                        cameraController.rotationX += Float(delta.height) * rotationSpeed
                        cameraRotation.y = cameraController.rotationY
                        cameraRotation.x = cameraController.rotationX
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let scaleFactor: Float = Float(value)
                        let baseDistance: Float = 3.0
                        cameraController.distance = baseDistance / scaleFactor
                        cameraController.distance = max(0.5, min(10, cameraController.distance))
                        cameraPosition.z = cameraController.distance
                    }
            )
        }
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        AssetPanel(
            selectedCategory: .constant(.models),
            onAssetSelect: { _ in }
        )
    }
}
