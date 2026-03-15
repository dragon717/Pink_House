//
//  GlobalSearchView.swift
//  ItemManager
//
//  全局搜索视图 - 复用衣橱搜索能力，预留其他模块拓展
//

import SwiftUI
import SwiftData

// MARK: - 全局搜索视图
@available(iOS 18.0, *)
struct GlobalSearchView: View {
    @Binding var searchText: String
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Query(filter: #Predicate<Clothing> { $0.deletedAt == nil }) var clothings: [Clothing]
    
    @StateObject private var searchManager = GlobalSearchManager.shared
    @State private var selectedClothing: Clothing?
    @State private var navigateToDetail = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                LiquidBackground()
                    .ignoresSafeArea()
                
                content
            }
            .navigationTitle("全局搜索")
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索裙装、品牌、标签、类型、颜色、尺码、价格..."
            )
            .onChange(of: searchText) { _, newValue in
                performSearch(query: newValue)
            }
            .onAppear {
                // 配置搜索服务
                let clothingService = ClothingSearchService(clothings: clothings)
                searchManager.configureClothingService(clothingService)
            }
            .navigationDestination(isPresented: $navigateToDetail) {
                if let clothing = selectedClothing {
                    ClothingDetailView(clothing: clothing)
                }
            }
        }
    }
    
    // MARK: - 内容视图
    @ViewBuilder
    private var content: some View {
        if searchText.isEmpty {
            emptyStateView
        } else if searchManager.searchResults.isEmpty && !searchManager.isSearching {
            noResultsView
        } else {
            resultsListView
        }
    }
    
    // MARK: - 空状态视图
    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 最近搜索
                if !searchManager.recentSearches.isEmpty {
                    recentSearchesSection
                }
                
                // 搜索建议
                searchSuggestionsSection
                
                // 搜索能力展示
                searchCapabilitiesSection
            }
            .padding()
        }
    }
    
    // MARK: - 最近搜索
    private var recentSearchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最近搜索")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Button {
                    searchManager.clearRecentSearches()
                } label: {
                    Text("清除")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            FlowLayout(spacing: 8) {
                ForEach(searchManager.recentSearches, id: \.self) { search in
                    Button {
                        searchText = search
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                            Text(search)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - 搜索建议
    private var searchSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("搜索建议")
                .font(.headline)
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                suggestionRow(icon: "tshirt", text: "输入裙装名称")
                suggestionRow(icon: "bag", text: "输入品牌名")
                suggestionRow(icon: "tag", text: "输入标签名")
                suggestionRow(icon: "paintpalette", text: "输入颜色如 粉色、黑色")
                suggestionRow(icon: "ruler", text: "输入尺码如 S、M、L")
                suggestionRow(icon: "yensign.circle", text: "输入价格范围如 2000-3000")
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func suggestionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    // MARK: - 搜索能力展示
    private var searchCapabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可搜索内容")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                capabilityCard(
                    icon: "tshirt",
                    title: "裙装",
                    description: "名称、类型、颜色、尺码",
                    color: themeManager.accentTextColor
                )
                capabilityCard(
                    icon: "bag",
                    title: "品牌",
                    description: "品牌名称",
                    color: themeManager.secondaryTextColor
                )
                capabilityCard(
                    icon: "tag",
                    title: "标签",
                    description: "自定义标签",
                    color: themeManager.primaryTextColor
                )
                capabilityCard(
                    icon: "yensign.circle",
                    title: "价格",
                    description: "价格范围搜索",
                    color: themeManager.tertiaryTextColor
                )
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func capabilityCard(icon: String, title: String, description: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(themeManager.primaryTextColor)

            Text(description)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - 无结果视图
    private var noResultsView: some View {
        ContentUnavailableView {
            Label("未找到结果", systemImage: "magnifyingglass")
        } description: {
            Text("尝试其他关键词或检查拼写")
        } actions: {
            Button("查看搜索建议") {
                searchText = ""
            }
        }
    }
    
    // MARK: - 结果列表视图
    private var resultsListView: some View {
        List {
            ForEach(searchManager.searchResults) { section in
                Section {
                    ForEach(section.items) { item in
                        SearchResultRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleResultTap(item)
                            }
                    }
                } header: {
                    HStack {
                        Image(systemName: section.type.icon)
                        Text(section.type.rawValue)
                        Spacer()
                        Text("\(section.items.count) 个结果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
            }
            
            // 底部留白
            Color.clear
                .frame(height: 50)
                .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - 执行搜索
    private func performSearch(query: String) {
        searchManager.performSearch(query: query) { item in
            if let clothing = item as? Clothing {
                selectedClothing = clothing
                navigateToDetail = true
            }
        }
    }
    
    // MARK: - 处理结果点击
    private func handleResultTap(_ item: SearchResultItem) {
        if let clothing = item.originalItem as? Clothing {
            selectedClothing = clothing
            navigateToDetail = true
        }
        item.action()
    }
}

// MARK: - 搜索结果行
@available(iOS 18.0, *)
struct SearchResultRow: View {
    let item: SearchResultItem
    
    var body: some View {
        HStack(spacing: 12) {
            // 图片或图标
            if let imagePath = item.imagePath {
                AsyncLocalImageView(
                    fileName: imagePath,
                    displaySize: CGSize(width: 50, height: 50),
                    contentMode: .fill,
                    cornerRadius: 8,
                    placeholderColor: Color.gray.opacity(0.2)
                )
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let icon = item.icon {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 50)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: item.type.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 50)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // 文字内容
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // 类型标签
            HStack(spacing: 4) {
                Image(systemName: item.type.icon)
                    .font(.caption)
                Text(item.type.rawValue)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - FlowLayout 辅助视图
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - 预览
#Preview {
    if #available(iOS 18.0, *) {
        GlobalSearchView(searchText: .constant(""))
    } else {
        Text("需要 iOS 18+")
    }
}
