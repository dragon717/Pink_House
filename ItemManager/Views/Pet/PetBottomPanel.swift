import SwiftUI

struct PetBottomPanel: View {
    @ObservedObject var viewModel: PetViewModel
    @Binding var isExpanded: Bool
    @State private var selectedTab: Int = 0 // 0: 背包, 1: 商店
    
    // 面板高度配置
    private var collapsedHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        // 横屏模式下，收起高度减小，避免遮挡太多
        return screenHeight < 500 ? 80 : 200
    }
    
    private var expandedHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        // 横屏模式下，限制最大高度，避免占满屏幕导致无法操作
        // 如果高度小于 500 (通常是横屏)，则只占 80%
        return screenHeight < 500 ? screenHeight * 0.8 : 600
    }
    
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 1. Handle (拖拽手柄)
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
                            // 阻尼效果
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
                
                // 2. Tabs (背包 | 商店)
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
                    
                    // 清洁按钮 (作为独立功能保留在右侧)
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
                .background(.regularMaterial)
                
                // 3. Content Area
                ZStack {
                    Rectangle()
                        .fill(.regularMaterial)
                        .ignoresSafeArea()
                    
                    if selectedTab == 0 {
                        // 背包视图
                        InventoryView(viewModel: viewModel, isExpanded: isExpanded)
                    } else {
                        // 商店视图
                        ShopView(viewModel: viewModel, isExpanded: isExpanded)
                    }
                }
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

// MARK: - Subviews

struct InventoryView: View {
    @ObservedObject var viewModel: PetViewModel
    var isExpanded: Bool
    
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
            if isExpanded {
                // 展开：网格布局
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
                        ForEach(inventoryItems) { item in
                            InventoryItemView(item: item, count: viewModel.status.inventory[item] ?? 0)
                                .draggable(item.rawValue)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 50) // 底部留白
                }
            } else {
                // 收起：横向滚动
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 15) {
                        ForEach(inventoryItems) { item in
                            InventoryItemView(item: item, count: viewModel.status.inventory[item] ?? 0)
                                .draggable(item.rawValue)
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
    
    var body: some View {
        if isExpanded {
            // 展开：网格布局
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
                    ForEach(PetItemType.allCases) { item in
                        ShopItemView(item: item) {
                            buy(item)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 50)
            }
        } else {
            // 收起：横向滚动
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(PetItemType.allCases) { item in
                        ShopItemView(item: item) {
                            buy(item)
                        }
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
