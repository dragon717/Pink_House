import SwiftUI
struct PetBottomPanel: View {
    @ObservedObject var viewModel: PetViewModel
    @Binding var isExpanded: Bool
    var isLandscape: Bool = false
    @State private var selectedTab: Int = 0 // 0: 背包, 1: 商店
    
    // 面板尺寸配置
    private var collapsedHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        return screenHeight < 500 ? 80 : 200
    }
    
    private var expandedHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        return screenHeight < 500 ? screenHeight * 0.8 : 600
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
            if isLandscape {
                // 横屏布局：右侧侧边栏
                HStack(spacing: 0) {
                    // 1. Handle (左侧拖拽手柄 + 箭头)
                    ZStack {
                        Color.clear
                            .frame(width: 30)
                            
                        // 箭头按钮 (参考 OOTD 风格)
                        Button(action: {
                            withAnimation(.spring()) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.right" : "chevron.left")
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
                                // 阻尼效果：向左拖（展开），向右拖（收起）
                                // isExpanded = true (显示全部), offset = 0
                                // isExpanded = false (隐藏大部分), offset = positive
                                
                                // 逻辑：offset 控制整个 panel 的 x 位置
                                // 初始位置根据 isExpanded 决定
                                if isExpanded && translation > 0 {
                                     dragOffset = translation
                                } else if !isExpanded && translation < 0 {
                                     dragOffset = translation
                                }
                            }
                            .onEnded { value in
                                let threshold: CGFloat = 50
                                if isExpanded {
                                    if value.translation.width > threshold {
                                        withAnimation(.spring()) {
                                            isExpanded = false
                                        }
                                    }
                                } else {
                                    if value.translation.width < -threshold {
                                        withAnimation(.spring()) {
                                            isExpanded = true
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
                }
                // 位置控制
                // isExpanded: offset = 0 (显示在屏幕右侧)
                // !isExpanded: offset = sidebarWidth - collapsedWidth (大部分藏在屏幕右侧外)
                .offset(x: isExpanded ? dragOffset : (sidebarWidth - collapsedWidth) + dragOffset)
                // 确保停靠在右边
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
                
            } else {
                // 竖屏布局：底部面板 (保持原有逻辑)
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
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let translation = value.translation.height
                                if isExpanded && translation > 0 {
                                    dragOffset = translation
                                } else if !isExpanded && translation < 0 {
                                    dragOffset = translation
                                }
                            }
                            .onEnded { value in
                                let threshold: CGFloat = 50
                                if isExpanded {
                                    if value.translation.height > threshold {
                                        withAnimation(.spring()) {
                                            isExpanded = false
                                        }
                                    }
                                } else {
                                    if value.translation.height < -threshold {
                                        withAnimation(.spring()) {
                                            isExpanded = true
                                        }
                                    }
                                }
                                withAnimation {
                                    dragOffset = 0
                                }
                            }
                    )
                    
                    // 2. Tabs
                    tabHeader
                    
                    // 3. Content
                    contentArea
                }
                .background(.regularMaterial)
                .cornerRadius(20, corners: [.topLeft, .topRight])
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
                .frame(height: isExpanded ? expandedHeight : collapsedHeight)
                .offset(y: geometry.size.height - (isExpanded ? expandedHeight : collapsedHeight) + dragOffset)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
            }
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
            .disabled(viewModel.currentState != .idle)
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
                InventoryView(viewModel: viewModel, isExpanded: isExpanded, isLandscape: isLandscape)
            } else {
                // 商店视图
                ShopView(viewModel: viewModel, isExpanded: isExpanded, isLandscape: isLandscape)
            }
        }
    }
}

// MARK: - Subviews

struct InventoryView: View {
    @ObservedObject var viewModel: PetViewModel
    var isExpanded: Bool
    var isLandscape: Bool = false
    
    // 过滤出拥有的物品
    var inventoryItems: [PetItemType] {
        PetItemType.allCases.filter { (viewModel.status.inventory[$0] ?? 0) > 0 }
    }
    
    var body: some View {
        if inventoryItems.isEmpty {
            VStack {
                Image(systemName: "cube.box")
                    .font(.largeTitle)
                    .foregroundColor(.gray.opacity(0.5))
                Text("背包空空如也，去商店买点东西吧~")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // 横屏模式或者展开模式下使用网格
            if isExpanded || isLandscape {
                // 展开：网格布局
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
                        ForEach(inventoryItems) { item in
                            InventoryItemView(item: item, count: viewModel.status.inventory[item] ?? 0)
                                .draggable("inventory:\(item.rawValue)")
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 50) // 底部留白
                }
            } else {
                // 竖屏收起：横向滚动
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(inventoryItems) { item in
                            InventoryItemView(item: item, count: viewModel.status.inventory[item] ?? 0)
                                .draggable("inventory:\(item.rawValue)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
            }
        }
    }
}

struct ShopView: View {
    @ObservedObject var viewModel: PetViewModel
    var isExpanded: Bool
    var isLandscape: Bool = false
    
    var body: some View {
        // 横屏模式或者展开模式下使用网格
        if isExpanded || isLandscape {
            // 展开：网格布局
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
                    ForEach(PetItemType.allCases) { item in
                        ShopItemView(item: item) {
                            buy(item)
                        }
                        .draggable("shop:\(item.rawValue)")
                    }
                }
                .padding(20)
                .padding(.bottom, 50)
            }
        } else {
            // 竖屏收起：横向滚动
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(PetItemType.allCases) { item in
                        ShopItemView(item: item) {
                            buy(item)
                        }
                        .draggable("shop:\(item.rawValue)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
    }
    
    func buy(_ item: PetItemType) {
        if viewModel.purchaseItem(item) {
            viewModel.showFloatingText("- \(item.price)", color: .orange)
        } else {
            viewModel.showFloatingText("余额不足", color: .gray)
        }
    }
}
