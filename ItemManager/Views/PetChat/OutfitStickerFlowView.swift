import SwiftUI
import SwiftData

// MARK: - 搭配贴纸流程视图
/// 处理搭配推荐的完整流程：检查抠图 -> 生成贴纸 -> 放入手帐
struct OutfitStickerFlowView: View {
    let clothings: [Clothing]
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    
    // 流程状态
    @State private var flowState: FlowState = .checkingCutouts
    @State private var clothingsNeedingCutout: [Clothing] = []
    @State private var availableCutouts: [CutoutItem] = []
    @State private var generatedOutfit: Outfit?
    @State private var errorMessage: String?
    
    // 确认弹窗
    @State private var showingCutoutConfirm = false
    @State private var showingSaveMenu = false
    
    enum FlowState {
        case checkingCutouts      // 检查抠图
        case generatingLayout     // 生成布局
        case savingToBook         // 保存到手帐
        case completed            // 完成
        case error                // 错误
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    switch flowState {
                    case .checkingCutouts:
                        checkingCutoutsView
                    case .generatingLayout:
                        generatingLayoutView
                    case .savingToBook:
                        savingToBookView
                    case .completed:
                        completedView
                    case .error:
                        errorView
                    }
                }
                .padding()
            }
            .navigationTitle("魔法贴纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                    }
                }
            }
        }
        .onAppear {
            checkCutouts()
        }
        .alert("需要抠图", isPresented: $showingCutoutConfirm) {
            Button("去抠图") {
                // 跳转到抠图页面
                showingCutoutConfirm = false
                // TODO: 导航到抠图页面
            }
            Button("跳过", role: .cancel) {
                showingCutoutConfirm = false
                // 继续流程，只使用有抠图的裙装
                proceedWithAvailableCutouts()
            }
        } message: {
            let names = clothingsNeedingCutout.map { $0.name }.joined(separator: "、")
            Text("以下裙装还没有抠图：\n\(names)\n\n需要去生成抠图吗？")
        }
    }
    
    // MARK: - 检查抠图
    private var checkingCutoutsView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("正在检查抠图...")
                .font(.headline)
            
            Text("共 \(clothings.count) 件推荐单品")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 生成布局
    private var generatingLayoutView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("正在生成搭配布局...")
                .font(.headline)
            
            Text("使用 \(availableCutouts.count) 个贴纸")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 保存到手帐
    private var savingToBookView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("正在保存到手帐...")
                .font(.headline)
        }
    }
    
    // MARK: - 完成
    private var completedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text("搭配已生成！")
                .font(.title2)
                .fontWeight(.bold)
            
            if let outfit = generatedOutfit {
                Text("已保存到默认手帐")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                // 预览图
                OutfitPreviewCard(outfit: outfit)
                    .frame(height: 200)
            }
            
            Button {
                onComplete()
            } label: {
                Text("完成")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top)
        }
    }
    
    // MARK: - 错误
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            
            Text("出错了")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(errorMessage ?? "未知错误")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                onCancel()
            } label: {
                Text("返回")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top)
        }
    }
    
    // MARK: - 检查抠图
    private func checkCutouts() {
        Task {
            do {
                // 在主线程执行数据库查询
                let (foundCutouts, missingCutouts) = try await MainActor.run {
                    () -> ([CutoutItem], [Clothing]) in
                    
                    // 获取所有抠图
                    let allCutoutsDescriptor = FetchDescriptor<CutoutItem>()
                    let allCutouts = try modelContext.fetch(allCutoutsDescriptor)
                    
                    let resolved = OOTDCutoutResolver.resolveCutouts(for: clothings, from: allCutouts)
                    try? modelContext.save()
                    return (resolved.found, resolved.missing)
                }
                
                self.availableCutouts = foundCutouts
                self.clothingsNeedingCutout = missingCutouts
                
                if missingCutouts.isEmpty {
                    // 所有裙装都有抠图，直接生成布局
                    self.flowState = .generatingLayout
                    generateLayout()
                } else if foundCutouts.count >= 2 {
                    // 至少有2个抠图，询问是否继续
                    self.showingCutoutConfirm = true
                } else {
                    // 抠图不足，显示错误
                    self.errorMessage = "至少需要2件单品的抠图才能生成搭配，请先为裙装生成抠图~"
                    self.flowState = .error
                }
            } catch {
                self.errorMessage = "检查抠图失败：\(error.localizedDescription)"
                self.flowState = .error
            }
        }
    }
    
    // MARK: - 继续使用可用抠图
    private func proceedWithAvailableCutouts() {
        flowState = .generatingLayout
        generateLayout()
    }
    
    // MARK: - 生成布局
    private func generateLayout() {
        Task {
            do {
                // 使用布局引擎生成 Outfit
                let outfit = OOTDLayoutEngine.shared.createOutfitWithLayout(
                    cutouts: availableCutouts,
                    book: nil,
                    description: "AI搭配推荐"
                )
                
                await MainActor.run {
                    self.generatedOutfit = outfit
                    self.flowState = .savingToBook
                    saveToBook()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "生成布局失败：\(error.localizedDescription)"
                    self.flowState = .error
                }
            }
        }
    }
    
    // MARK: - 保存到手帐
    private func saveToBook() {
        Task {
            do {
                // 获取或创建默认手帐
                let book = try await getOrCreateDefaultBook()
                
                // 设置 outfit 的书组
                await MainActor.run {
                    generatedOutfit?.book = book
                    
                    // 保存到数据库
                    if let outfit = generatedOutfit {
                        modelContext.insert(outfit)
                        if let items = outfit.items {
                            for item in items {
                                modelContext.insert(item)
                            }
                        }
                        try? modelContext.save()
                    }
                    
                    self.flowState = .completed
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "保存失败：\(error.localizedDescription)"
                    self.flowState = .error
                }
            }
        }
    }
    
    // MARK: - 获取或创建默认手帐
    private func getOrCreateDefaultBook() async throws -> BookGroup {
        try await MainActor.run {
            // 获取所有书组，在内存中筛选
            let allBooksDescriptor = FetchDescriptor<BookGroup>()
            let allBooks = try modelContext.fetch(allBooksDescriptor)
            
            if let existingBook = allBooks.first(where: { $0.title == "默认手帐" && $0.deletedAt == nil }) {
                return existingBook
            }
            
            // 创建默认手帐
            let newBook = BookGroup(title: "默认手帐")
            modelContext.insert(newBook)
            try modelContext.save()
            return newBook
        }
    }
}

// MARK: - 搭配预览卡片
struct OutfitPreviewCard: View {
    let outfit: Outfit
    @State private var loadedImages: [UUID: UIImage] = [:]
    
    var body: some View {
        ZStack {
            // 背景 - 使用白色确保可见
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            // 贴纸预览
            if let items = outfit.items, !items.isEmpty {
                ForEach(items.prefix(4), id: \.id) { item in
                    OutfitPreviewItemView(
                        item: item,
                        loadedImage: loadedImages[item.id]
                    )
                }
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                    Text("暂无预览")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 300, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await loadPreviewImages()
        }
    }
    
    private func loadPreviewImages() async {
        guard let items = outfit.items else { return }
        
        for item in items.prefix(4) {
            guard let cutout = item.cutout else { continue }
            
            // 使用优化加载器异步加载
            if let image = await OptimizedImageLoader.shared.loadStickerImage(
                fileName: cutout.imagePath,
                targetSize: CGSize(width: 100, height: 100)
            ) {
                await MainActor.run {
                    loadedImages[item.id] = image
                }
            }
        }
    }
}

// MARK: - 预览单项视图
struct OutfitPreviewItemView: View {
    let item: OutfitItem
    let loadedImage: UIImage?

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    // item.x/y 是相对坐标（0-1），转换为预览尺寸（300x200）
                    // 注意：App启动时已通过 OOTDCoordinateMigrationService 将所有数据迁移为相对坐标
                    .position(
                        x: CGFloat(item.x) * 260 + 20,
                        y: CGFloat(item.y) * 180 + 10
                    )
                    .rotationEffect(Angle(degrees: item.rotation))
            } else {
                // 加载中占位
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 70, height: 70)
                        .position(
                            x: CGFloat(item.x) * 260 + 20,
                            y: CGFloat(item.y) * 180 + 10
                        )
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                    )
            }
        }
    }

}
