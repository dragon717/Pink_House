import SwiftUI

enum PanelState {
    case hidden
    case collapsed
    case expanded
    
    var isExpanded: Bool {
        return self == .expanded
    }
}

struct PetBottomPanel: View {
    @ObservedObject var viewModel: PetViewModel
    @Binding var panelState: PanelState
    @Binding var showRenameAlert: Bool // 新增绑定
    var isLandscape: Bool = false
    @State private var selectedTab: Int = 0 // 0: 背包, 1: 商店
    
    // 面板尺寸配置 (改为基于 GeometryProxy 计算)
    private func getCollapsedHeight(screenHeight: CGFloat) -> CGFloat {
        // 动态计算：屏幕高度的 25%，但不超过 220，不小于 140 (确保能容纳 Tab 和一行物品)
        return min(max(screenHeight * 0.25, 140), 220)
    }
    
    private func getExpandedHeight(screenHeight: CGFloat) -> CGFloat {
        // 屏幕高度的 75%
        return screenHeight * 0.75
    }
    
    // 横屏模式下的宽度配置
    private var sidebarWidth: CGFloat {
        return 350
    }
    
    private var collapsedWidth: CGFloat {
        return 80 // 收起时露出的宽度（或者完全收起只露把手）
    }
    
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let collapsedH = getCollapsedHeight(screenHeight: screenHeight)
            let expandedH = getExpandedHeight(screenHeight: screenHeight)
            
            if isLandscape {
                // 横屏布局：右侧侧边栏 (暂时保持原有逻辑，映射 state)
                HStack(spacing: 0) {
                    // 1. Handle (左侧拖拽手柄 + 箭头)
                    ZStack {
                        Color.clear
                            .frame(width: 30)
                            
                        // 箭头按钮 (参考 OOTD 风格)
                        Button(action: {
                            withAnimation(.spring()) {
                                toggleLandscapeState()
                            }
                        }) {
                            Image(systemName: panelState == .expanded ? "chevron.right" : "chevron.left")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                        .offset(x: 8) // 向右偏移，使其靠近内容区域
                    }
                    .frame(maxHeight: .infinity)
                    // 确保 ZStack 本身可以响应拖拽
                    .contentShape(Rectangle()) 
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let translation = value.translation.width
                                // 简单适配横屏拖拽逻辑
                                if panelState == .expanded && translation > 0 {
                                     dragOffset = translation
                                } else if panelState != .expanded && translation < 0 {
                                     dragOffset = translation
                                }
                            }
                            .onEnded { value in
                                let threshold: CGFloat = 50
                                if panelState == .expanded {
                                    if value.translation.width > threshold {
                                        withAnimation(.spring()) {
                                            panelState = .collapsed
                                        }
                                    }
                                } else {
                                    if value.translation.width < -threshold {
                                        withAnimation(.spring()) {
                                            panelState = .expanded
                                        }
                                    }
                                }
                                withAnimation {
                                    dragOffset = 0
                                }
                            }
                    )
                    
                    VStack(spacing: 0) {
                        // 2. Tabs
                        tabHeader
                        
                        // 3. Content
                        contentArea
                    }
                    .frame(width: sidebarWidth)
                    .padding(.bottom, 100) // 增加底部内边距，避开 TabBar
                }
                // 位置控制
                .offset(x: panelState == .expanded ? dragOffset : (sidebarWidth - collapsedWidth) + dragOffset)
                // 确保停靠在右边
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: panelState)
                
            } else {
                // 竖屏布局：底部面板
                VStack(spacing: 0) {
                    // 1. Handle
                    VStack {
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 40, height: 5)
                            .padding(.top, 10)
                            .padding(.bottom, 5)
                    }
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    
                    // 2. Tabs
                    tabHeader
                    
                    // 3. Content
                    contentArea
                }
                .background(.regularMaterial)
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
                .frame(height: panelState == .expanded ? expandedH : collapsedH)
                // 关键修改：根据状态控制 offset y
                // Hidden: offset = height (完全移出屏幕)
                // Collapsed/Expanded: offset = 0 (正常显示，高度由 frame 控制)
                // 加上 dragOffset 实现拖拽跟手
                .offset(y: calculateVerticalOffset(geometry: geometry, collapsedH: collapsedH, expandedH: expandedH))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: panelState)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation.height
                            // 限制拖拽范围，避免这Expanded状态下过度上拉
                            if panelState == .expanded && translation < 0 {
                                dragOffset = translation * 0.2 // 阻尼
                            } else {
                                dragOffset = translation
                            }
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 50
                            let translation = value.translation.height
                            
                            withAnimation(.spring()) {
                                if panelState == .expanded {
                                    if translation > threshold {
                                        // 向下拖拽 -> 折叠
                                        panelState = .collapsed
                                    }
                                } else if panelState == .collapsed {
                                    if translation < -threshold {
                                        // 向上拖拽 -> 展开
                                        panelState = .expanded
                                    } else if translation > threshold {
                                        // 向下拖拽 -> 隐藏
                                        panelState = .hidden
                                    }
                                }
                                dragOffset = 0
                            }
                        }
                )
            }
        }
    }
    
    private func calculateVerticalOffset(geometry: GeometryProxy, collapsedH: CGFloat, expandedH: CGFloat) -> CGFloat {
        if panelState == .hidden {
            return geometry.size.height + 200 // 增加额外偏移，确保完全移出可视区域
        }
        
        // 基础位置是底部对齐
        // GeometryReader 内部元素默认左上对齐 (0,0)
        // 我们需要把它推到底部
        let currentHeight = panelState == .expanded ? expandedH : collapsedH
        let baseOffset = geometry.size.height - currentHeight
        
        // 增加拖拽时的弹性效果或跟手
        // 当 collapsed 向下拖时，dragOffset > 0，面板向下移动
        // 当 expanded 向下拖时，dragOffset > 0，面板向下移动
        
        return baseOffset + dragOffset
    }

    private func toggleLandscapeState() {
        if panelState == .expanded {
            panelState = .collapsed
        } else {
            panelState = .expanded
        }
    }
    
    // 抽取的 Tab Header
    private var tabHeader: some View {
        HStack {
            Button(action: { selectedTab = 0 }) {
                Text("背包")
                    .font(.headline)
                    .fontWeight(selectedTab == 0 ? .bold : .regular)
                    .foregroundColor(selectedTab == 0 ? .primary : .secondary)
            }
            
            Text("|")
                .foregroundColor(.secondary.opacity(0.3))
                .padding(.horizontal, 10)
            
            Button(action: { selectedTab = 1 }) {
                Text("商店")
                    .font(.headline)
                    .fontWeight(selectedTab == 1 ? .bold : .regular)
                    .foregroundColor(selectedTab == 1 ? .primary : .secondary)
            }
            
            Spacer()
            
            // 清洁按钮
            Button(action: { viewModel.clean() }) {
                HStack(spacing: 4) {
                    Image(systemName: "shower.fill")
                    Text("20")
                        .font(.caption)
                        .fontWeight(.bold)
                    Image(systemName: "fish.circle.fill")
                        .font(.caption2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .clipShape(Capsule())
            }
            // .disabled(viewModel.currentState != .idle) // 移除禁用，改为点击提示
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .padding(.top, isLandscape ? 10 : 0) // 横屏时增加顶部 padding
        .background(.regularMaterial)
    }
    
    // 抽取的 Content Area
    private var contentArea: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            
            if selectedTab == 0 {
                // 背包视图
                InventoryView(viewModel: viewModel, panelState: panelState, showRenameAlert: $showRenameAlert, isLandscape: isLandscape)
            } else {
                // 商店视图
                ShopView(viewModel: viewModel, panelState: panelState, isLandscape: isLandscape)
            }
        }
    }
}

// MARK: - Subviews

struct InventoryView: View {
    @ObservedObject var viewModel: PetViewModel
    @ObservedObject var config = PetConfigManager.shared
    var panelState: PanelState
    @Binding var showRenameAlert: Bool // 新增绑定
    var isLandscape: Bool = false
    
    @State private var searchText = ""
    @State private var selectedCategoryId = "all"
    
    // Alert State
    @State private var selectedItemToUse: PetItemDefinition?
    @State private var showUseAlert = false
    
    // 过滤出拥有的物品
    var filteredItems: [PetItemDefinition] {
        var items = viewModel.status.inventory
            .filter { $0.value > 0 }
            .compactMap { PetConfigManager.shared.getItem(byId: $0.key) }
            .sorted { $0.sortIndex < $1.sortIndex }
            
        // Filter by Category
        if selectedCategoryId != "all" {
            items = items.filter { $0.category == selectedCategoryId }
        }
        
        // Filter by Search
        if !searchText.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return items
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search & Filter Header (Only when expanded or landscape)
            if panelState == .expanded || isLandscape {
                VStack(spacing: 12) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("搜索背包...", text: $searchText)
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
                            ForEach(config.categories) { category in
                                Button(action: {
                                    withAnimation {
                                        selectedCategoryId = category.id
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: category.icon)
                                        Text(category.name)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategoryId == category.id ? Color.pink : Color.secondary.opacity(0.1))
                                    .foregroundColor(selectedCategoryId == category.id ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 10)
            }
            
            if filteredItems.isEmpty {
                VStack {
                    Image(systemName: "cube.box")
                    .font(.largeTitle)
                    .foregroundColor(.gray.opacity(0.5))
                    Text(searchText.isEmpty && selectedCategoryId == "all" ? "背包空空如也，去商店买点东西吧~" : "没有找到相关物品")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 横屏模式或者展开模式下使用网格
                if panelState == .expanded || isLandscape {
                    // 展开：网格布局
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
                            ForEach(filteredItems) { item in
                                InventoryItemView(item: item, count: viewModel.status.inventory[item.id] ?? 0)
                                    .draggable("inventory:\(item.id)")
                                    .onTapGesture {
                                        if item.id == "renameCard" {
                                            showRenameAlert = true
                                        } else {
                                            selectedItemToUse = item
                                            showUseAlert = true
                                        }
                                    }
                            }
                        }
                        .padding(20)
                        .padding(.bottom, 50) // 底部留白
                    }
                } else {
                    // 竖屏收起：横向滚动
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(filteredItems) { item in
                                InventoryItemView(item: item, count: viewModel.status.inventory[item.id] ?? 0)
                                    .draggable("inventory:\(item.id)")
                                    .onTapGesture {
                                        if item.id == "renameCard" {
                                            showRenameAlert = true
                                        } else {
                                            selectedItemToUse = item
                                            showUseAlert = true
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .alert(isPresented: $showUseAlert) {
            if let item = selectedItemToUse {
                return Alert(
                    title: Text("使用 \(item.name)"),
                    message: Text(getUsageMessage(for: item)),
                    primaryButton: .default(Text("使用")) {
                        viewModel.consumeItem(item)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            } else {
                return Alert(title: Text("错误"), message: Text("未选择物品"), dismissButton: .cancel())
            }
        }
    }
    
    private func getUsageMessage(for item: PetItemDefinition) -> String {
        let petName = viewModel.status.petName ?? "萌宠"
        if item.isToy {
            return "确定要让\(petName)玩 \(item.name) 吗？\n将消耗 \(item.energyCost ?? 0) 点精力，增加心情。"
        } else if item.isDrink {
            return "确定要给\(petName)喝 \(item.name) 吗？"
        } else if item.category == "food" {
            return "确定要给\(petName)喂食 \(item.name) 吗？"
        } else if item.id == "energyPill" {
            return "确定要使用 \(item.name) 吗？\n将快速恢复精力。"
        } else if item.id == "renameCard" {
            return "确定要使用 \(item.name) 吗？"
        } else {
            return "确定要使用 \(item.name) 吗？"
        }
    }
}

struct ShopView: View {
    @ObservedObject var viewModel: PetViewModel
    @ObservedObject var config = PetConfigManager.shared
    
    var panelState: PanelState
    var isLandscape: Bool = false
    
    @State private var searchText = ""
    @State private var selectedCategoryId = "all"
    
    var filteredItems: [PetItemDefinition] {
        var items = config.items.sorted { $0.sortIndex < $1.sortIndex }
        
        // Filter by Category
        if selectedCategoryId != "all" {
            items = items.filter { $0.category == selectedCategoryId }
        }
        
        // Filter by Search
        if !searchText.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return items
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search & Filter Header (Only when expanded or landscape)
            if panelState == .expanded || isLandscape {
                VStack(spacing: 12) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("搜索商品...", text: $searchText)
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
                            ForEach(config.categories) { category in
                                Button(action: {
                                    withAnimation {
                                        selectedCategoryId = category.id
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: category.icon)
                                        Text(category.name)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategoryId == category.id ? Color.pink : Color.secondary.opacity(0.1))
                                    .foregroundColor(selectedCategoryId == category.id ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 10)
            }
            
            // Content
            if panelState == .expanded || isLandscape {
                // 展开：网格布局
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
                        ForEach(filteredItems) { item in
                            ShopItemView(item: item) {
                                buy(item)
                            }
                            .draggable("shop:\(item.id)")
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 50)
                }
            } else {
                // 竖屏收起：横向滚动
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(filteredItems) { item in
                            ShopItemView(item: item) {
                                buy(item)
                            }
                            .draggable("shop:\(item.id)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
        }
    }
    
    func buy(_ item: PetItemDefinition) {
        _ = viewModel.purchaseItem(item)
    }
}
