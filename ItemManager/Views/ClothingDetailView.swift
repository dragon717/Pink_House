//
//  ClothingDetailView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/17/26.
//

import SwiftUI
import SwiftData

struct ClothingDetailView: View {
    @Bindable var clothing: Clothing
    @Query private var wealthSavingEntries: [WealthSavingEntry]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingEditSheet = false
    @State private var showingImageViewer = false
    @State private var showingDeleteAlert = false
    @State private var showingConfirmPaymentAlert = false
    @State private var showCelebration = false
    @State private var currentImageIndex = 0
    @State private var showingShareSheet = false
    @State private var showingWealthSavingSheet = false
    @State private var wealthSavingCelebrationAmount: Decimal?
    
    // 表图大图查看状态
    @State private var showingChartImageViewer = false
    @State private var chartImagePathToView: String? = nil

    @AppStorage("isPayBalanceCelebrationEnabled") private var isPayBalanceCelebrationEnabled = false

    @ObservedObject private var visibilityManager = FieldVisibilityManager.shared
    @ObservedObject private var networkManager = NetworkSettingsManager.shared
    
    private var containerPalette: AdaptivePaletteV2 {
        themeManager.getPaletteForContainer(
            containerBackground: .ultraThinMaterial,
            colorScheme: colorScheme
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Background
                LiquidBackground(themeSkinWallpaperContext: .wardrobe)
                    .ignoresSafeArea()
                    .environment(\.containerPalette, containerPalette)
                
                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - Image Carousel
                        // Adjust height based on orientation (portrait vs landscape)
                        // Ensure height is at least 1 to avoid "Failed to create image slot" warnings
                        let carouselHeight = max(1, geometry.size.height > geometry.size.width ? 400.0 : geometry.size.height * 0.7)
                        imageCarousel(height: carouselHeight, width: geometry.size.width)
                        
                        // MARK: - Main Info Card
                        mainInfoCard
                            .padding(.horizontal)
                            .offset(y: -40) // Overlap the image slightly
                        
                        // MARK: - Detail Info
                        detailInfoCard
                            .padding(.horizontal)
                            .offset(y: -40)
                        
                        // MARK: - Price Info
                        priceInfoCard
                            .padding(.horizontal)
                            .offset(y: -40)
                        
                        // MARK: - Purchase Info
                        purchaseInfoCard
                            .padding(.horizontal)
                            .offset(y: -40)

                        finalPaymentWealthCard
                            .padding(.horizontal)
                            .offset(y: -40)
                        
                        // MARK: - Pay Balance Button
                        if clothing.isDepositPlan {
                            Button {
                                showingConfirmPaymentAlert = true
                            } label: {
                                Text("已付尾款")
                            }
                            .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .pink, cornerRadius: 16, verticalPadding: 15))
                            .padding(.horizontal)
                            .offset(y: -40)
                        }
                        
                        // MARK: - Metadata Info (Created/Updated)
                        VStack(spacing: 4) {
                            Text("添加时间: \(clothing.createdAt.formatted(date: .numeric, time: .shortened))")
                            Text("修改时间: \(clothing.updatedAt.formatted(date: .numeric, time: .shortened))")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 20)
                        .offset(y: -20)
                        
                        // Bottom Padding for FAB
                        Color.clear.frame(height: 80)
                    }
                }
                .ignoresSafeArea(edges: .top)
                
                // MARK: - FAB (社区按钮：跟随联网设置显示/隐藏)
                if networkManager.canShowNetworkUI() {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                // Action for Community/Square
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.title2)
                                    Text("社区")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                                .shadow(radius: 4)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
                
                // MARK: - Celebration Overlay
                if showCelebration {
                    CelebrationOverlay(isPresented: $showCelebration)
                        .ignoresSafeArea()
                        .zIndex(100)
                }

                if let wealthSavingCelebrationAmount {
                    VaultSavingCelebrationOverlay(
                        amount: wealthSavingCelebrationAmount,
                        onComplete: { self.wealthSavingCelebrationAmount = nil }
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(101)
                }
            }
        }
        .navigationTitle("衣橱详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    // 分享按钮
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    
                    // 更多操作菜单
                    Menu {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        
                        Button {
                            duplicateClothing()
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationStack {
                ClothingEditView(clothing: clothing)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareCardSheet(
                shareType: .clothing(clothing),
                onDismiss: { showingShareSheet = false }
            )
        }
        .fullScreenCover(isPresented: $showingImageViewer) {
            if !clothing.imagePaths.isEmpty {
                ImageViewer(imagePaths: clothing.imagePaths, selectedIndex: $currentImageIndex)
            }
        }
        .sheet(isPresented: $showingChartImageViewer) {
            chartImageViewerSheet
                .presentationBackground(.black)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingWealthSavingSheet) {
            VaultSavingSheet(
                targetClothing: clothing,
                currentSavedAmount: WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries),
                onSave: saveWealthSavingAmount
            )
        }
        .alert("确认删除", isPresented: $showingDeleteAlert) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                NotificationManager.shared.cancelNotification(for: clothing)
                // Soft delete
                clothing.isDeleted = true
                clothing.deletedAt = Date()
                clothing.lastModified = Date()

                // 记录删除到 DeleteTracker，防止iCloud同步覆盖
                DeleteTracker.shared.recordDeletedClothing(id: clothing.id)

                Task { @MainActor in
                    await NotificationManager.shared.refreshAllKnownDepositNotifications(
                        modelContext: modelContext,
                        force: true,
                        reason: "detail-delete"
                    )
                }

                Task { await SharedPersistence.shared.syncWidgetData() }
                
                // 更新衣物数量缓存，用于魔法任务进度实时显示
                updateClothingCountCache()
                
                dismiss()
            }
        } message: {
            Text("确定要删除这件裙装吗？它将被移动到回收站，你可以随时恢复。")
        }
        .alert("确认已付尾款", isPresented: $showingConfirmPaymentAlert) {
            Button("取消", role: .cancel) { }
            Button("确认", role: .none) {
                confirmPayment()
            }
        } message: {
            Text("确认后将移除心愿尾款，并清空定金和预估尾款时间信息。")
        }
        .onAppear {
            WealthSavingLedger.migrateLegacySavedFinalPayments(
                clothings: [clothing],
                entries: wealthSavingEntries,
                context: modelContext
            )
            // 进入详情页时，若定金和尾款 存在，自动重算总价并保存
            if clothing.deposit > 0 || clothing.balance > 0 {
                let newTotal = clothing.deposit + clothing.balance
                if clothing.price != newTotal {
                    clothing.price = newTotal
                }
            }
            // 确保 currentImageIndex 不会越界
            validateCurrentImageIndex()
        }
        .onChange(of: clothing.imagePaths) { _, _ in
            // 当图片路径变化时（如删除图片），验证索引
            validateCurrentImageIndex()
        }
    }
    
    private func validateCurrentImageIndex() {
        if clothing.imagePaths.isEmpty {
            currentImageIndex = 0
        } else if currentImageIndex >= clothing.imagePaths.count {
            currentImageIndex = max(0, clothing.imagePaths.count - 1)
        }
    }
    
    private func confirmPayment() {
        // Cancel notification since it's no longer a deposit plan
        NotificationManager.shared.cancelNotification(for: clothing)
        NotificationManager.shared.handlePaymentConfirmed(for: clothing.id, modelContext: modelContext)
        
        // Calculate total price if currently 0
        if clothing.price == 0 {
            clothing.price = clothing.deposit + clothing.balance
        }

        WealthSavingLedger.markActiveSavingsUsed(
            for: clothing.id,
            entries: wealthSavingEntries
        )
        
        clothing.isDepositPlan = false
        clothing.isFinalPaymentSavedToWealth = false
        clothing.finalPaymentSavedAt = nil
        clothing.depositDate = nil
        clothing.finalPaymentDate = nil
        clothing.finalPaymentEndDate = nil
        let now = Date()
        clothing.updatedAt = now
        clothing.lastModified = now
        // Try to save context (though it autosaves usually)
        try? modelContext.save()
        Task { @MainActor in
            await NotificationManager.shared.refreshAllKnownDepositNotifications(
                modelContext: modelContext,
                force: true,
                reason: "payment-confirmed"
            )
        }
        NotificationManager.shared.updateApplicationBadge(modelContext: modelContext)
        Task { await SharedPersistence.shared.syncWidgetData() }
        
        // Trigger Celebration Effect
        if isPayBalanceCelebrationEnabled {
            showCelebration = true
        }
        
        // Trigger Reward
        RewardManager.shared.triggerReward(type: .payBalance)
    }
    
    /// 更新衣物数量缓存，用于魔法任务进度实时显示
    private func updateClothingCountCache() {
        FeatureUnlockManager.shared.refreshClothingCountCache(from: modelContext, reason: "clothing-detail")
    }
    
    private func duplicateClothing() {
        let newClothing = Clothing(
            name: clothing.name,
            brand: clothing.brand,
            types: clothing.types,
            colors: clothing.colors,
            sizes: clothing.sizes,
            length: clothing.length,
            condition: clothing.condition,
            accessories: clothing.accessories,
            imagePaths: clothing.imagePaths,
            isShared: clothing.isShared,
            originalPrice: clothing.originalPrice,
            price: clothing.price,
            deposit: clothing.deposit,
            balance: clothing.balance,
            accessoriesPrice: clothing.accessoriesPrice,
            purchaseDate: clothing.purchaseDate,
            depositDate: clothing.depositDate,
            isDepositPlan: clothing.isDepositPlan,
            finalPaymentDate: clothing.finalPaymentDate,
            finalPaymentEndDate: clothing.finalPaymentEndDate,
            note: clothing.note,
            stock: clothing.stock,
            status: clothing.status
        )
        
        newClothing.copyCurrencyAndShippingMetadata(from: clothing)
        newClothing.tags = clothing.tags
        
        // 复制尺码表图和价格表图
        newClothing.sizeChartImagePath = clothing.sizeChartImagePath
        newClothing.priceChartImagePath = clothing.priceChartImagePath
        
        // Duplicate accessory items
        if let items = clothing.accessoryItems {
            newClothing.accessoryItems = items.map { item in
                AccessoryItem(name: item.name, price: item.price, deposit: item.deposit, balance: item.balance, sortIndex: item.sortIndex, imagePaths: item.imagePaths)
            }
        }
        
        // Increment reference count for images
        for imagePath in clothing.imagePaths {
            ImageManager.shared.incrementRefCount(fileName: imagePath, context: modelContext)
        }
        // 增加尺码表图和价格表图的引用计数
        if let sizeChartPath = clothing.sizeChartImagePath {
            ImageManager.shared.incrementRefCount(fileName: sizeChartPath, context: modelContext)
        }
        if let priceChartPath = clothing.priceChartImagePath {
            ImageManager.shared.incrementRefCount(fileName: priceChartPath, context: modelContext)
        }
        
        modelContext.insert(newClothing)
        
        do {
            try modelContext.save()
            NotificationManager.shared.scheduleNotification(for: newClothing, modelContext: modelContext)
            // 更新衣物数量缓存，用于魔法任务进度实时显示
            updateClothingCountCache()
        } catch {
            print("ClothingDetailView: Failed to save duplicated clothing: \(error)")
        }
        
        Task { await SharedPersistence.shared.syncWidgetData(reason: "clothing-detail-duplicate") }
        
        dismiss()
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func imageCarousel(height: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            // 使用 ID 强制刷新整个 TabView 当图片数量变化时
            TabView(selection: $currentImageIndex) {
                if clothing.imagePaths.isEmpty {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: "tshirt")
                                .font(.system(size: 60))
                                .foregroundStyle(.pink.opacity(0.3))
                        }
                        .tag(0)
                } else {
                    // 使用 enumerated 避免索引问题
                    ForEach(Array(clothing.imagePaths.enumerated()), id: \.element) { index, imagePath in
                        let targetSize = CGSize(width: width, height: height)
                        
                        CarouselItemView(imagePath: imagePath, targetSize: targetSize)
                            .tag(index)
                            .onTapGesture {
                                // 只有在有图片时才允许打开查看器
                                if !clothing.imagePaths.isEmpty {
                                    showingImageViewer = true
                                }
                            }
                    }
                }
            }
            .id("carousel-\(clothing.imagePaths.count)") // 强制刷新当图片数量变化
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: height)
            
            // Page Indicator Overlay
            if !clothing.imagePaths.isEmpty {
                HStack(spacing: 4) {
                    Text("\(min(currentImageIndex + 1, clothing.imagePaths.count))")
                    Text("/")
                    Text("\(clothing.imagePaths.count)")
                }
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(.bottom, 60) // Adjust based on overlap
            }
        }
    }
    
    // customNavBar removed
    
    /// 主信息卡片 - 使用统一配色
    private var mainInfoCard: some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                // 裙装名称支持长按拷贝
                CopyableText(
                    text: clothing.name,
                    font: .title2,
                    foregroundStyle: themeManager.primaryTextColor,
                    alignment: .leading
                )
                .bold()
                Spacer()

                // 追根溯源按钮：跟随联网设置显示/隐藏
                if networkManager.canShowNetworkUI() {
                    Button {
                        // 追根溯源操作
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("追根溯源")
                        }
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.brown))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            if let tags = clothing.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(tags) { tag in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .font(.caption)
                                    .unifiedSecondary()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: tag.colorHex).opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            }
            
            Divider()
                .background(themeManager.tertiaryTextColor.opacity(0.3))
            
            HStack {
                if let brand = clothing.brand {
                    if let path = brand.imagePath,
                       let image = ImageManager.shared.loadImage(fileName: path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 24, height: 24)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(hex: brand.colorHex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(brand.name.prefix(1))
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                            )
                    }
                    // 品牌名称支持长按拷贝
                    CopyableText(
                        text: brand.name,
                        font: .subheadline,
                        foregroundStyle: themeManager.secondaryTextColor,
                        alignment: .leading
                    )
                } else {
                    Text("暂无品牌信息")
                        .font(.subheadline)
                        .unifiedTertiary()
                }
                
                if clothing.isDepositPlan {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("心愿尾款")
                            .font(.caption)
                            .bold()
                    }
                    .unifiedAccent()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeManager.accentTextColor.opacity(0.1))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 16)
    }
    
    /// 详细信息卡片 - 使用统一配色
    private var detailInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("裙装信息", systemImage: "info.circle.fill")
                .font(.headline)
                .unifiedPrimary()
            
            ForEach(visibilityManager.fieldOrder, id: \.self) { field in
                if visibilityManager.isVisible(field) {
                    buildDetailRow(for: field)
                }
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 16)
    }
    
    @ViewBuilder
    private func buildDetailRow(for field: ClothingField) -> some View {
        switch field {
        case .types:
            InfoRow(label: "类型", value: clothing.types.isEmpty ? "未填写" : clothing.types)
        case .colors:
            InfoRow(label: "颜色", value: clothing.colors.isEmpty ? "未填写" : clothing.colors)
        case .sizes:
            // 尺码行特殊处理，显示尺码表缩略图
            HStack {
                Image(systemName: "ruler")
                    .font(.caption)
                    .foregroundStyle(themeManager.tertiaryTextColor)
                    .frame(width: 20)
                
                Text("尺码")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.secondaryTextColor)
                
                Spacer()
                
                // 显示尺码表缩略图（如果有）
                if let path = clothing.sizeChartImagePath,
                   let image = ImageManager.shared.loadImage(fileName: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .onTapGesture {
                            // 点击查看大图
                            chartImagePathToView = path
                            showingChartImageViewer = true
                        }
                }
                
                Text(clothing.sizes.isEmpty ? "未填写" : clothing.sizes)
                    .font(.subheadline)
                    .foregroundStyle(themeManager.primaryTextColor)
            }
            .contentShape(Rectangle())
        case .length:
            InfoRow(label: "衣长", value: clothing.length.isEmpty ? "未填写" : clothing.length)
        case .condition:
            InfoRow(label: "状态", value: clothing.condition)
        case .accessories:
            InfoRow(label: "小物", value: clothing.accessories.isEmpty ? "无" : clothing.accessories)
        }
    }
    
    private var formattedOriginalPrice: String {
        switch clothing.originalPriceCurrency {
        case .cny:
            if clothing.originalPriceJPY > 0 {
                return "¥\(clothing.originalPrice.formatted(.number.precision(.fractionLength(0...2))))（约 JP¥\(clothing.originalPriceJPY.formatted(.number.precision(.fractionLength(0...2))))）"
            }
            return "¥\(clothing.originalPrice.formatted(.number.precision(.fractionLength(0...2))))"
        case .jpy:
            let jpy = clothing.originalPriceJPY > 0 ? clothing.originalPriceJPY : clothing.originalPrice * clothing.originalPriceExchangeRateJPY
            return "JP¥\(jpy.formatted(.number.precision(.fractionLength(0...2))))（折合 ¥\(clothing.originalPrice.formatted(.number.precision(.fractionLength(0...2))))）"
        }
    }

    private var formattedShippingFee: String {
        switch clothing.shippingFeeCurrency {
        case .cny:
            if clothing.shippingFeeJPY > 0 {
                return "¥\(clothing.resolvedShippingFee.formatted(.number.precision(.fractionLength(0...2))))（约 JP¥\(clothing.shippingFeeJPY.formatted(.number.precision(.fractionLength(0...2))))）"
            }
            return "¥\(clothing.resolvedShippingFee.formatted(.number.precision(.fractionLength(0...2))))"
        case .jpy:
            let jpy = clothing.shippingFeeJPY > 0 ? clothing.shippingFeeJPY : clothing.resolvedShippingFee * clothing.shippingExchangeRateJPY
            return "JP¥\(jpy.formatted(.number.precision(.fractionLength(0...2))))（折合 ¥\(clothing.resolvedShippingFee.formatted(.number.precision(.fractionLength(0...2))))）"
        }
    }

    /// 价格信息卡片 - 使用统一配色
    private var priceInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 价格信息标题行，右侧显示价格表缩略图
            HStack {
                Label("价格信息", systemImage: "yensign.circle.fill")
                    .font(.headline)
                    .unifiedPrimary()
                
                Spacer()
                
                // 显示价格表缩略图（如果有）
                if let path = clothing.priceChartImagePath,
                   let image = ImageManager.shared.loadImage(fileName: path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .onTapGesture {
                            // 点击查看大图
                            chartImagePathToView = path
                            showingChartImageViewer = true
                        }
                }
            }
            
            if clothing.isDepositPlan {
                // Show total deposit/balance including accessories
                InfoRow(label: "总定金", value: "¥\(clothing.totalDeposit.formatted(.number.precision(.fractionLength(0))))")
                InfoRow(label: "总尾款", value: "¥\(clothing.totalBalance.formatted(.number.precision(.fractionLength(0))))")
                
                Divider()
                    .background(themeManager.tertiaryTextColor.opacity(0.3))
                
                // Show Breakdown for Dress
                InfoRow(label: "裙装定金", value: "¥\(clothing.deposit.formatted(.number.precision(.fractionLength(0))))")
                InfoRow(label: "裙装尾款", value: "¥\(clothing.balance.formatted(.number.precision(.fractionLength(0))))")
            }
            
            if clothing.originalPrice > 0 || clothing.originalPriceJPY > 0 {
                InfoRow(label: "原价", value: formattedOriginalPrice)
            }

            if clothing.resolvedShippingFee > 0 || clothing.shippingFeeJPY > 0 {
                InfoRow(label: "邮费", value: formattedShippingFee)
            }
            
            InfoRow(label: "裙装单价", value: "¥\(clothing.price.formatted(.number.precision(.fractionLength(0))))")
            
            if clothing.stock > 1 {
                InfoRow(label: "库存数量", value: "\(clothing.stock)")
                InfoRow(label: "裙装总价", value: "¥\((clothing.price * Decimal(clothing.stock)).formatted(.number.precision(.fractionLength(0))))")
            }
            
            if let items = clothing.accessoryItems, !items.isEmpty {
                Divider()
                    .background(themeManager.tertiaryTextColor.opacity(0.3))
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("小物明细")
                            .unifiedPrimary()
                        Spacer()
                        Text("小物总价: ¥\(items.reduce(Decimal(0)) { $0 + $1.price }.formatted(.number.precision(.fractionLength(0...2))))")
                            .unifiedSecondary()
                    }
                    .font(.subheadline)
                    
                    ForEach(items.sorted(by: { $0.sortIndex < $1.sortIndex })) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.name.isEmpty ? "未命名小物" : item.name)
                                    .unifiedPrimary()
                                Spacer()
                                Text("¥\(NSDecimalNumber(decimal: item.price).doubleValue.formatted(.number.precision(.fractionLength(0...2))))")
                                    .unifiedSecondary()
                            }
                            
                            // Show deposit/balance for accessory if it exists
                            if item.deposit > 0 || item.balance > 0 {
                                HStack {
                                    if item.deposit > 0 {
                                        Text("定金: ¥\(item.deposit.formatted(.number.precision(.fractionLength(0...2))))")
                                            .unifiedTertiary()
                                    }
                                    if item.balance > 0 {
                                        Text("尾款: ¥\(item.balance.formatted(.number.precision(.fractionLength(0...2))))")
                                            .unifiedTertiary()
                                    }
                                    Spacer()
                                }
                                .font(.caption)
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
            
            HStack {
                Label("合计金额（含邮）", systemImage: "star.circle.fill")
                    .font(.subheadline)
                    .unifiedSecondary()
                Spacer()
                
                let totalAll = clothing.inventoryTotalPrice
                
                Text("¥\(totalAll.formatted(.number.precision(.fractionLength(0))))")
                    .font(.title3)
                    .bold()
                    .unifiedAccent()
            }
            .padding(12)
            .background(themeManager.secondaryTextColor.opacity(0.1))
            .cornerRadius(12)
            
            if clothing.stock > 1 {
                Text("包含 \(clothing.stock) 件库存，单套价值 ¥\(clothing.unitTotalPrice.formatted(.number.precision(.fractionLength(0))))；邮费不随库存倍增")
                    .font(.caption)
                    .unifiedTertiary()
                    .padding(.horizontal, 4)
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 16)
    }
    
    /// 表图大图查看 Sheet
    private var chartImageViewerSheet: some View {
        // 使用 Group 确保视图立即创建，避免 if let 导致的延迟
        Group {
            if let path = chartImagePathToView {
                ChartImageViewer(imagePath: path, onDismiss: { showingChartImageViewer = false })
            } else {
                Color.black
            }
        }
    }

    private var finalPaymentWealthCard: some View {
        let saved = WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries)
        let numerator = WealthSavingLedger.progressNumerator(for: clothing, entries: wealthSavingEntries)
        let target = WealthSavingLedger.purchaseTarget(for: clothing)
        let cap = WealthSavingLedger.assignableSavingCap(for: clothing)
        let remaining = WealthSavingLedger.remainingAssignableAmount(for: clothing, entries: wealthSavingEntries)
        let overflow = WealthSavingLedger.overflowAmount(for: clothing, entries: wealthSavingEntries)
        let ratio = WealthSavingLedger.progressRatio(for: clothing, entries: wealthSavingEntries)

        return VStack(alignment: .leading, spacing: 12) {
            Label("小金库存钱进度", systemImage: "tray.and.arrow.down.fill")
                .font(.headline)
                .unifiedPrimary()

            HStack(spacing: 10) {
                Image(systemName: saved > 0 ? "checkmark.seal.fill" : "yensign.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 42, height: 42)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(saved > 0 ? "已存 ¥\(NSDecimalNumber(decimal: saved).stringValue)" : "为这条裙装存一笔")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text(clothing.isDepositPlan ? "进度包含已付定金，存款最多补齐剩余应付" : "普通裙装只统计小金库存款进度")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }

                Spacer()

                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ratio > 1 ? Color(hex: "C94C72") : .orange)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(ratio, 1.0))
                    .tint(ratio > 1 ? Color(hex: "C94C72") : .orange)
                Text("进度 ¥\(NSDecimalNumber(decimal: numerator).stringValue) / ¥\(NSDecimalNumber(decimal: target).stringValue)")
                    .font(.caption2)
                    .foregroundStyle(themeManager.tertiaryTextColor)
                Text("指定上限 ¥\(NSDecimalNumber(decimal: cap).stringValue) · 还能存 ¥\(NSDecimalNumber(decimal: remaining).stringValue)")
                    .font(.caption2)
                    .foregroundStyle(remaining > 0 ? themeManager.tertiaryTextColor : Color(hex: "C94C72"))
            }

            Button {
                showingWealthSavingSheet = true
            } label: {
                Label(remaining > 0 ? "存一笔到小金库" : "已存到上限", systemImage: "tray.and.arrow.down")
            }
            .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .orange, cornerRadius: 14, verticalPadding: 11))
            .disabled(remaining <= 0)

            if overflow > 0 {
                Button {
                    moveOverflowSavingToUnassigned()
                } label: {
                    Label("转出超额 ¥\(NSDecimalNumber(decimal: overflow).stringValue) 到未指定", systemImage: "arrow.uturn.left.circle.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color(hex: "C94C72"))
                        .background(Color(hex: "C94C72").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 16)
    }

    private var finalPaymentSavedText: String {
        guard let date = clothing.finalPaymentSavedAt else {
            return "已计入马上来财统计"
        }
        return "存入于 \(date.formatted(date: .numeric, time: .omitted))，付款后会自动转为已用"
    }

    private func saveWealthSavingAmount(_ amount: Decimal) {
        do {
            guard let entry = try WealthSavingLedger.addSaving(
                amount: amount,
                for: clothing,
                entries: wealthSavingEntries,
                note: "为「\(clothing.name)」存钱",
                context: modelContext
            ) else { return }
            Task { await SharedPersistence.shared.syncWidgetData() }
            wealthSavingCelebrationAmount = entry.amount
        } catch {
            print("ClothingDetailView: Failed to save wealth saving entry: \(error)")
        }
    }

    private func moveOverflowSavingToUnassigned() {
        do {
            let movedAmount = try WealthSavingLedger.moveOverflowToUnassigned(
                for: clothing,
                entries: wealthSavingEntries,
                context: modelContext
            )
            if movedAmount > 0 {
                Task { await SharedPersistence.shared.syncWidgetData() }
            }
        } catch {
            print("ClothingDetailView: Failed to move overflow wealth saving: \(error)")
        }
    }
    
    /// 购买信息卡片 - 使用统一配色
    private var purchaseInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("购买信息", systemImage: "bag.fill")
                .font(.headline)
                .unifiedPrimary()
            
            InfoRow(label: "购买日期", value: clothing.purchaseDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
            
            if clothing.isDepositPlan {
                if let depositDate = clothing.depositDate {
                    InfoRow(label: "定金日期", value: depositDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                }
                if let finalPaymentDate = clothing.finalPaymentDate {
                    InfoRow(label: "预估尾款", value: formatFinalPaymentDate(start: finalPaymentDate, end: clothing.finalPaymentEndDate))
                }
            }
            
            let duration = Calendar.current.dateComponents([.day], from: clothing.purchaseDate, to: Date()).day ?? 0
            InfoRow(label: "拥有时长", value: "\(duration)天")
            
            if clothing.balance > 0 {
                // 如果是心愿尾款，显示总尾款（含小物），否则显示尾款×库存的总价格
                if clothing.isDepositPlan {
                    InfoRow(label: "总尾款金额", value: "¥\(clothing.totalBalance.formatted(.number.precision(.fractionLength(0))))")
                } else {
                    // 非心愿尾款时，显示尾款×库存的总价格
                    let totalBalance = clothing.balance * Decimal(clothing.stock)
                    InfoRow(label: "尾款金额", value: "¥\(totalBalance.formatted(.number.precision(.fractionLength(0))))")
                }
            }
            
            if !clothing.note.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("备注")
                        .font(.subheadline)
                        .unifiedSecondary()
                    // 备注也支持长按拷贝
                    CopyableText(
                        text: clothing.note,
                        font: .body,
                        foregroundStyle: themeManager.primaryTextColor,
                        alignment: .leading
                    )
                }
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 16)
    }
    
    private func formatFinalPaymentDate(start: Date, end: Date?) -> String {
        let startDateString = start.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
        
        if let endDate = end {
            // Check if end date is different from start date (ignoring time)
            let calendar = Calendar.current
            if !calendar.isDate(start, inSameDayAs: endDate) {
                let endDateString = endDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN")))
                return "\(startDateString) - \(endDateString)"
            }
        }
        
        return startDateString
    }
}

/// 信息行组件 - 使用统一配色
struct InfoRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: iconForLabel(label))
                .font(.caption)
                .foregroundStyle(themeManager.tertiaryTextColor)
                .frame(width: 20)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(themeManager.secondaryTextColor)
            
            Spacer()
            
            // 使用 CopyableText 支持长按拷贝字段值
            CopyableText(
                text: value,
                font: .subheadline,
                foregroundStyle: themeManager.primaryTextColor,
                alignment: .trailing
            )
        }
        .contentShape(Rectangle())
    }
    
    private func iconForLabel(_ label: String) -> String {
        switch label {
        case "类型": return "tshirt"
        case "颜色": return "paintpalette"
        case "尺码": return "ruler"
        case "衣长": return "arrow.up.and.down"
        case "状态": return "star.circle"
        case "小物": return "sparkles"
        case "裙装总价", "裙装单价", "原价": return "tag"
        case "库存数量": return "number.circle"
        case "购买日期": return "calendar"
        case "定金日期": return "calendar.badge.clock"
        case "预估尾款": return "hourglass"
        case "拥有时长": return "clock"
        case "尾款金额": return "creditcard"
        default: return "circle"
        }
    }
}

struct CarouselItemView: View {
    let imagePath: String
    let targetSize: CGSize
    
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task {
            self.image = await ImageManager.shared.loadImageAsync(fileName: imagePath, targetSize: targetSize)
        }
    }
}
