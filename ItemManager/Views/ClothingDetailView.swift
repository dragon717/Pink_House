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
    @State private var showingFinalPaymentSheet = false
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

                        if shouldShowFinalPaymentStatusCard {
                            finalPaymentStatusCard
                                .padding(.horizontal)
                                .offset(y: -40)
                        }

                        if shouldShowFinalPaymentVaultCard {
                            finalPaymentWealthCard
                                .padding(.horizontal)
                                .offset(y: -40)
                        }
                        
                        // MARK: - Pay Balance Button
                        if clothing.reservationKind == .depositPlan && WealthSavingLedger.finalPaymentDueAmount(for: clothing) > 0 {
                            Button {
                                showingFinalPaymentSheet = true
                            } label: {
                                Text("记录已付尾款")
                                    .themeSkinLegibleText(level: .chip, slot: .primaryButton)
                            }
                            .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .pink, cornerRadius: 16, verticalPadding: 15))
                            .padding(.horizontal)
                            .offset(y: -40)
                        }
                        
                        // MARK: - Metadata Info (Created/Updated)
                        VStack(spacing: 4) {
                            Text("添加时间: \(clothing.createdAt.formatted(date: .numeric, time: .shortened))")
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            Text("修改时间: \(clothing.updatedAt.formatted(date: .numeric, time: .shortened))")
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                                        .themeSkinLegibleText(level: .chip, slot: .iconCircleButton)
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
        .sheet(isPresented: $showingFinalPaymentSheet) {
            FinalPaymentRecordingSheet(
                clothing: clothing,
                wealthSavingEntries: wealthSavingEntries,
                onRecord: recordFinalPayment
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
        .onAppear {
            WealthSavingLedger.migrateLegacySavedFinalPayments(
                clothings: [clothing],
                entries: wealthSavingEntries,
                context: modelContext
            )
            // 进入详情页时，若定金和尾款 存在，自动重算总价并保存
            if clothing.reservationKind == .depositPlan && (clothing.deposit > 0 || clothing.balance > 0) {
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
    
    private func recordFinalPayment(
        mode: FinalPaymentMode,
        amount: Decimal,
        installmentCount: Int?
    ) {
        do {
            guard let result = try WealthSavingLedger.recordFinalPayment(
                amount: amount,
                for: clothing,
                entries: wealthSavingEntries,
                mode: mode,
                installmentCount: installmentCount,
                context: modelContext
            ) else { return }

            if clothing.price == 0 {
                clothing.price = clothing.deposit + clothing.balance
                try? modelContext.save()
            }

            if result.paidOff {
                finalizeFinalPaymentAfterPaidOff()
            } else {
                Task { await SharedPersistence.shared.syncWidgetData(reason: "final-payment-partial-recorded") }
                wealthSavingCelebrationAmount = result.paidAmount
            }
        } catch {
            print("ClothingDetailView: Failed to record final payment: \(error)")
        }
    }

    private func finalizeFinalPaymentAfterPaidOff() {
        // Cancel notification since it's no longer a deposit plan
        NotificationManager.shared.cancelNotification(for: clothing)
        NotificationManager.shared.handlePaymentConfirmed(for: clothing.id, modelContext: modelContext)

        Task { @MainActor in
            await NotificationManager.shared.refreshAllKnownDepositNotifications(
                modelContext: modelContext,
                force: true,
                reason: "payment-confirmed"
            )
        }
        NotificationManager.shared.updateApplicationBadge(modelContext: modelContext)
        Task { await SharedPersistence.shared.syncWidgetData(reason: "final-payment-paid-off") }

        // Trigger Celebration Effect
        if isPayBalanceCelebrationEnabled {
            showCelebration = true
        }

        // Trigger Reward only after cumulative payment is fully settled.
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
                .themeSkinLegibleText(level: .badge, slot: .sectionCard)
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
                                .themeSkinLegibleText(level: .chip, slot: .primaryButton)
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
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                }
                
                if clothing.isDepositPlan {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text(clothing.isFullPaymentReservation ? "全款预约" : "心愿尾款")
                            .font(.caption)
                            .bold()
                    }
                    .unifiedAccent()
                    .themeSkinLegibleText(level: .chip, slot: .discountBadge)
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
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            
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
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                
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
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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

    private var formattedOriginalPriceRateSnapshot: String {
        let rate = clothing.originalPriceExchangeRateJPY > 0
            ? clothing.originalPriceExchangeRateJPY
            : Decimal(CurrencyExchangeRateService.defaultJPYRate)
        let rateText = rate.formatted(.number.precision(.fractionLength(0...4)))
        guard let updatedAt = clothing.originalPriceRateUpdatedAt else {
            return "1 CNY = \(rateText) JPY（未记录时间）"
        }
        return "1 CNY = \(rateText) JPY（\(updatedAt.formatted(date: .numeric, time: .shortened))）"
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
            
            if clothing.isFullPaymentReservation {
                InfoRow(label: "全款预约金额", value: "¥\(clothing.fullPaymentReservationTotalAmount.formatted(.number.precision(.fractionLength(0))))")
                if clothing.stock > 1 {
                    InfoRow(label: "单件预约金额", value: "¥\(clothing.fullPaymentReservationUnitAmount.formatted(.number.precision(.fractionLength(0))))")
                }
            } else if clothing.reservationKind == .depositPlan {
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
                InfoRow(label: "原价汇率", value: formattedOriginalPriceRateSnapshot)
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
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        Spacer()
                        Text("小物总价: ¥\(items.reduce(Decimal(0)) { $0 + $1.price }.formatted(.number.precision(.fractionLength(0...2))))")
                            .unifiedSecondary()
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                    .font(.subheadline)
                    
                    ForEach(items.sorted(by: { $0.sortIndex < $1.sortIndex })) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.name.isEmpty ? "未命名小物" : item.name)
                                    .unifiedPrimary()
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                Spacer()
                                Text("¥\(NSDecimalNumber(decimal: item.price).doubleValue.formatted(.number.precision(.fractionLength(0...2))))")
                                    .unifiedSecondary()
                                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            }
                            
                            // Show deposit/balance for accessory if it exists
                            if clothing.reservationKind == .depositPlan && (item.deposit > 0 || item.balance > 0) {
                                HStack {
                                    if item.deposit > 0 {
                                        Text("定金: ¥\(item.deposit.formatted(.number.precision(.fractionLength(0...2))))")
                                            .unifiedTertiary()
                                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                    }
                                    if item.balance > 0 {
                                        Text("尾款: ¥\(item.balance.formatted(.number.precision(.fractionLength(0...2))))")
                                            .unifiedTertiary()
                                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                Label(clothing.isFullPaymentReservation ? "全款预约总额" : "合计金额（含邮）", systemImage: "star.circle.fill")
                    .font(.subheadline)
                    .unifiedSecondary()
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Spacer()
                
                let totalAll = clothing.isFullPaymentReservation ? clothing.fullPaymentReservationTotalAmount : clothing.inventoryTotalPrice
                
                Text("¥\(totalAll.formatted(.number.precision(.fractionLength(0))))")
                    .font(.title3)
                    .bold()
                    .unifiedAccent()
                    .themeSkinLegibleText(level: .chip, slot: .sectionCard)
            }
            .padding(12)
            .background(themeManager.secondaryTextColor.opacity(0.1))
            .cornerRadius(12)
            
            if clothing.stock > 1 && !clothing.isFullPaymentReservation {
                Text("包含 \(clothing.stock) 件库存，单套价值 ¥\(clothing.unitTotalPrice.formatted(.number.precision(.fractionLength(0))))；邮费不随库存倍增")
                    .font(.caption)
                    .unifiedTertiary()
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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

    private var finalPaymentRecords: [WealthSavingEntry] {
        WealthSavingLedger.finalPaymentRecords(for: clothing.id, in: wealthSavingEntries)
    }

    private var finalPaymentInstallmentTotal: Int {
        let recordedTotal = finalPaymentRecords.map(\.installmentCount).max() ?? 0
        let savedTotal = max(clothing.finalPaymentInstallmentCount, recordedTotal)
        if savedTotal > 0 { return savedTotal }
        if finalPaymentRecords.contains(where: { $0.paymentMode == .oneTime }) { return 1 }
        return max(finalPaymentRecords.count, 1)
    }

    private var shouldShowFinalPaymentStatusCard: Bool {
        guard !clothing.isFullPaymentReservation else { return false }
        return clothing.reservationKind == .depositPlan ||
            clothing.finalPaymentInstallmentCount > 0 ||
            !finalPaymentRecords.isEmpty
    }

    private var shouldShowFinalPaymentVaultCard: Bool {
        guard clothing.reservationKind == .depositPlan else { return false }
        return WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: wealthSavingEntries) > 0
    }

    private var finalPaymentStatusCard: some View {
        let paid = WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: wealthSavingEntries)
        let due = WealthSavingLedger.finalPaymentDueAmount(for: clothing)
        let remaining = WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: wealthSavingEntries)
        let vaultBalance = WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries)
        let total = finalPaymentInstallmentTotal
        let nextIndex = min(WealthSavingLedger.nextInstallmentIndex(for: clothing, entries: wealthSavingEntries), total)
        let isPaidOff = due > 0 && remaining <= 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: isPaidOff ? "checkmark.seal.fill" : "creditcard.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isPaidOff ? .green : Color(hex: "C94C72"))
                    .frame(width: 38, height: 38)
                    .background((isPaidOff ? Color.green : Color(hex: "C94C72")).opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("尾款支付进度")
                        .font(.headline)
                        .foregroundStyle(themeManager.primaryTextColor)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    Text(finalPaymentStatusSubtitle(total: total, paidOff: isPaidOff))
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                }

                Spacer()

                Text(isPaidOff ? "已付清" : "剩余 ¥\(moneyString(remaining))")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(isPaidOff ? .green : Color(hex: "C94C72"))
                    .themeSkinLegibleText(level: .chip, slot: .discountBadge)
                    .background((isPaidOff ? Color.green : Color(hex: "C94C72")).opacity(0.12), in: Capsule())
            }

            FinalPaymentSegmentedProgressView(
                total: total,
                completed: finalPaymentRecords.count,
                activeIndex: isPaidOff ? nil : nextIndex,
                accent: Color(hex: "C94C72"),
                completedColor: .green
            )

            HStack(spacing: 0) {
                finalPaymentMetric(title: "已付", value: "¥\(moneyString(paid))", color: .green)
                Divider().frame(height: 34)
                finalPaymentMetric(title: "剩余", value: "¥\(moneyString(remaining))", color: Color(hex: "C94C72"))
                Divider().frame(height: 34)
                finalPaymentMetric(title: isPaidOff ? "账单" : "可抵扣", value: isPaidOff ? "\(finalPaymentRecords.count) 笔" : "¥\(moneyString(vaultBalance))", color: .orange)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

            if !finalPaymentRecords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近账单")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    ForEach(Array(finalPaymentRecords.suffix(3).reversed())) { entry in
                        HStack(spacing: 8) {
                            Text(entry.paymentMode == .installment ? "第 \(entry.installmentIndex)/\(entry.installmentCount) 期" : "一次性")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(hex: "C94C72"))
                                .themeSkinLegibleText(level: .chip, slot: .discountBadge)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(hex: "C94C72").opacity(0.10), in: Capsule())
                            Text("¥\(moneyString(entry.amount))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(themeManager.primaryTextColor)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            Spacer()
                            Text(entry.paidAt?.formatted(date: .numeric, time: .omitted) ?? "已记录")
                                .font(.caption2)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        }
                    }
                }
            }

            if isPaidOff {
                Text("尾款已付清，小金库入口已收起；若有剩余备款已转回未指定小匣。")
                    .font(.caption2)
                    .foregroundStyle(themeManager.tertiaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 18)
    }

    private var finalPaymentWealthCard: some View {
        let saved = WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries)
        let paid = WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: wealthSavingEntries)
        let remainingPayment = WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: wealthSavingEntries)
        let numerator = WealthSavingLedger.progressNumerator(for: clothing, entries: wealthSavingEntries)
        let target = WealthSavingLedger.purchaseTarget(for: clothing)
        let cap = WealthSavingLedger.assignableSavingCap(for: clothing)
        let remaining = WealthSavingLedger.remainingAssignableAmount(for: clothing, entries: wealthSavingEntries)
        let overflow = WealthSavingLedger.overflowAmount(for: clothing, entries: wealthSavingEntries)
        let ratio = WealthSavingLedger.progressRatio(for: clothing, entries: wealthSavingEntries)

        return VStack(alignment: .leading, spacing: 12) {
            Label("可抵扣小金库", systemImage: "tray.and.arrow.down.fill")
                .font(.headline)
                .unifiedPrimary()
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)

            HStack(spacing: 10) {
                Image(systemName: saved > 0 ? "checkmark.seal.fill" : "yensign.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 42, height: 42)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(paid > 0 ? "已付 ¥\(NSDecimalNumber(decimal: paid).stringValue) · 剩余 ¥\(NSDecimalNumber(decimal: remainingPayment).stringValue)" : (saved > 0 ? "可抵扣 ¥\(NSDecimalNumber(decimal: saved).stringValue)" : "为这条裙装存一笔"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(themeManager.primaryTextColor)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    Text("小金库只作为尾款抵扣资金；实付进度见上方分期卡片")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                }

                Spacer()

                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ratio > 1 ? Color(hex: "C94C72") : .orange)
                    .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(ratio, 1.0))
                    .tint(ratio > 1 ? Color(hex: "C94C72") : .orange)
                Text("进度 ¥\(NSDecimalNumber(decimal: numerator).stringValue) / ¥\(NSDecimalNumber(decimal: target).stringValue)")
                    .font(.caption2)
                    .foregroundStyle(themeManager.tertiaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Text("指定上限 ¥\(NSDecimalNumber(decimal: cap).stringValue) · 还能存 ¥\(NSDecimalNumber(decimal: remaining).stringValue)")
                    .font(.caption2)
                    .foregroundStyle(remaining > 0 ? themeManager.tertiaryTextColor : Color(hex: "C94C72"))
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                Text("已付尾款 ¥\(NSDecimalNumber(decimal: paid).stringValue) · 剩余尾款 ¥\(NSDecimalNumber(decimal: remainingPayment).stringValue) · 可抵扣 ¥\(NSDecimalNumber(decimal: saved).stringValue)")
                    .font(.caption2)
                    .foregroundStyle(themeManager.tertiaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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
                        .themeSkinLegibleText(level: .chip, slot: .primaryButton)
                        .background(Color(hex: "C94C72").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 16)
    }

    private func finalPaymentStatusSubtitle(total: Int, paidOff: Bool) -> String {
        if paidOff {
            return "尾款已完成，分期账单会保留在详情页"
        }
        if total > 1 {
            return "分期 \(finalPaymentRecords.count)/\(total)，每一期是一段短进度"
        }
        return "可一次性付清，也可选择分期后逐期记录"
    }

    private func finalPaymentMetric(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(themeManager.secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private func moneyString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
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
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            
            InfoRow(label: "购买日期", value: clothing.purchaseDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
            
            if clothing.isFullPaymentReservation {
                if let reservationDate = clothing.depositDate {
                    InfoRow(label: "全款预约日期", value: reservationDate.formatted(.dateTime.year().month().day().locale(Locale(identifier: "zh_CN"))))
                }
            } else if clothing.reservationKind == .depositPlan {
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
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
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

struct FinalPaymentSegmentedProgressView: View {
    let total: Int
    let completed: Int
    var activeIndex: Int? = nil
    var accent: Color = Color(hex: "C94C72")
    var completedColor: Color = .green
    var height: CGFloat = 7
    var fillsAvailableWidth: Bool = true

    @State private var isAnimated = false

    private var safeTotal: Int { max(total, 1) }
    private let segmentSpacing: CGFloat = 7

    private var baseSegmentWidth: CGFloat {
        switch safeTotal {
        case 1...3: return 44
        case 4...6: return 34
        default: return 26
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let segmentWidth = resolvedSegmentWidth(availableWidth: proxy.size.width)
            let contentWidth = CGFloat(safeTotal) * segmentWidth + CGFloat(max(safeTotal - 1, 0)) * segmentSpacing

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: segmentSpacing) {
                    ForEach(1...safeTotal, id: \.self) { index in
                        segment(index: index, width: segmentWidth)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollDisabled(contentWidth <= proxy.size.width + 0.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height + 4)
        .accessibilityLabel("尾款分期进度 \(min(completed, safeTotal)) / \(safeTotal)")
        .onAppear(perform: restartAnimation)
        .onChange(of: completed) { _, _ in restartAnimation() }
        .onChange(of: total) { _, _ in restartAnimation() }
        .onChange(of: activeIndex) { _, _ in restartAnimation() }
    }

    private func resolvedSegmentWidth(availableWidth: CGFloat) -> CGFloat {
        guard fillsAvailableWidth, availableWidth > 0 else { return baseSegmentWidth }

        let totalSpacing = CGFloat(max(safeTotal - 1, 0)) * segmentSpacing
        let fittedWidth = (availableWidth - totalSpacing) / CGFloat(safeTotal)
        return max(baseSegmentWidth, fittedWidth)
    }

    private func segment(index: Int, width: CGFloat) -> some View {
        let isComplete = index <= completed
        let isActive = activeIndex == index && !isComplete
        let fillScale: CGFloat = isComplete ? 1.0 : (isActive ? 0.34 : 0.0)
        let fillColor = isComplete ? completedColor : accent

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(isActive ? 0.18 : 0.12))
            Capsule()
                .fill(fillColor)
                .scaleEffect(x: isAnimated ? fillScale : 0.0, y: 1, anchor: .leading)
                .opacity(fillScale > 0 ? 1 : 0)
            if isActive {
                Capsule()
                    .stroke(accent.opacity(0.58), lineWidth: 1.2)
            }
        }
        .frame(width: width, height: height)
        .animation(
            .spring(response: 0.42, dampingFraction: 0.82)
                .delay(Double(index - 1) * 0.045),
            value: isAnimated
        )
    }

    private func restartAnimation() {
        isAnimated = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            isAnimated = true
        }
    }
}

struct FinalPaymentRecordingSheet: View {
    let clothing: Clothing
    let wealthSavingEntries: [WealthSavingEntry]
    let onRecord: (FinalPaymentMode, Decimal, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @State private var mode: FinalPaymentMode = .oneTime
    @State private var selectedInstallmentCount: Int?
    @State private var amountText: String = ""

    private let installmentOptions = [2, 3, 4, 6, 12]

    private var totalDue: Decimal {
        WealthSavingLedger.finalPaymentDueAmount(for: clothing)
    }

    private var paidTotal: Decimal {
        WealthSavingLedger.paidFinalPaymentTotal(for: clothing.id, in: wealthSavingEntries)
    }

    private var paidRatio: Double {
        guard totalDue > 0 else { return 0 }
        return min(NSDecimalNumber(decimal: paidTotal / totalDue).doubleValue, 1.0)
    }

    private var remainingAmount: Decimal {
        WealthSavingLedger.remainingFinalPaymentAmount(for: clothing, entries: wealthSavingEntries)
    }

    private var vaultBalance: Decimal {
        WealthSavingLedger.activeTotal(for: clothing.id, in: wealthSavingEntries)
    }

    private var paidRecords: [WealthSavingEntry] {
        WealthSavingLedger.finalPaymentRecords(for: clothing.id, in: wealthSavingEntries)
    }

    private var effectiveInstallmentCount: Int? {
        guard mode == .installment else { return nil }
        if clothing.finalPaymentInstallmentCount > 0 {
            return clothing.finalPaymentInstallmentCount
        }
        return selectedInstallmentCount
    }

    private var nextInstallmentIndex: Int {
        WealthSavingLedger.nextInstallmentIndex(for: clothing, entries: wealthSavingEntries)
    }

    private var isLastInstallment: Bool {
        guard let count = effectiveInstallmentCount else { return false }
        return nextInstallmentIndex >= count
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "."))
    }

    private var effectiveAmount: Decimal? {
        guard remainingAmount > 0 else { return nil }
        switch mode {
        case .oneTime:
            return remainingAmount
        case .installment:
            guard effectiveInstallmentCount != nil else { return nil }
            if isLastInstallment {
                return remainingAmount
            }
            guard let parsedAmount, parsedAmount > 0 else { return nil }
            return min(parsedAmount, remainingAmount)
        }
    }

    private var canRecord: Bool {
        effectiveAmount != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    modePicker

                    if mode == .installment {
                        installmentSelector
                        installmentAmountEditor
                    } else {
                        oneTimeAmountCard
                    }

                    ledgerPreview
                }
                .padding()
            }
            .navigationTitle("记录已付尾款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记录") {
                        guard let amount = effectiveAmount else { return }
                        onRecord(mode, amount, effectiveInstallmentCount)
                        dismiss()
                    }
                    .disabled(!canRecord)
                }
            }
            .onAppear {
                if clothing.finalPaymentInstallmentCount > 0 {
                    selectedInstallmentCount = clothing.finalPaymentInstallmentCount
                    mode = clothing.finalPaymentInstallmentCount == 1 ? .oneTime : .installment
                }
                refreshDefaultAmount()
            }
            .onChange(of: mode) { _, _ in
                refreshDefaultAmount()
            }
            .onChange(of: selectedInstallmentCount) { _, _ in
                refreshDefaultAmount()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(clothing.name)
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                .lineLimit(2)

            HStack(spacing: 0) {
                paymentStat(title: "应付尾款", value: totalDue, color: Color(hex: "C94C72"))
                Divider().frame(height: 34)
                paymentStat(title: "已付", value: paidTotal, color: .green)
                Divider().frame(height: 34)
                paymentStat(title: "剩余", value: remainingAmount, color: .orange)
            }

            ProgressView(value: paidRatio)
                .tint(Color(hex: "C94C72"))

            Text("可抵扣小金库 ¥\(moneyText(vaultBalance))，记录付款时会自动优先抵扣；不足部分记为外部实付。")
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 20)
    }

    private var modePicker: some View {
        Picker("支付方式", selection: $mode) {
            Text(FinalPaymentMode.oneTime.displayName)
                .themeSkinLegibleText(level: .inline, slot: .segmentedControl)
                .tag(FinalPaymentMode.oneTime)
            Text(FinalPaymentMode.installment.displayName)
                .themeSkinLegibleText(level: .inline, slot: .segmentedControl)
                .tag(FinalPaymentMode.installment)
        }
        .pickerStyle(.segmented)
    }

    private var oneTimeAmountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("一次性付清", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color(hex: "C94C72"))
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            Text("本次将记录剩余全部尾款 ¥\(moneyText(remainingAmount))。")
                .font(.subheadline)
                .foregroundStyle(themeManager.secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 18)
    }

    private var installmentSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(clothing.finalPaymentInstallmentCount > 0 ? "已选择 \(clothing.finalPaymentInstallmentCount) 期" : "请选择分期期数")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)

            if clothing.finalPaymentInstallmentCount <= 0 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(installmentOptions, id: \.self) { count in
                        Button {
                            selectedInstallmentCount = count
                        } label: {
                            Text("\(count) 期")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(selectedInstallmentCount == count ? .white : Color(hex: "C94C72"))
                                .themeSkinLegibleText(level: .chip, slot: .filterChip)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(selectedInstallmentCount == count ? Color(hex: "C94C72") : Color(hex: "C94C72").opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let count = effectiveInstallmentCount {
                FinalPaymentSegmentedProgressView(
                    total: count,
                    completed: paidRecords.count,
                    activeIndex: nextInstallmentIndex,
                    accent: Color(hex: "C94C72"),
                    completedColor: .green,
                    height: 7
                )
                Text("本次为第 \(min(nextInstallmentIndex, count)) / \(count) 期；默认金额按剩余尾款均分，最后一期自动兜底。")
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 18)
    }

    private var installmentAmountEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本期实付金额")
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeManager.secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            HStack {
                Text("¥")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.orange)
                    .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                TextField("请选择期数后自动均分", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            .padding()
            .themeSkinSectionCard(cornerRadius: 18)

            if isLastInstallment {
                Text("最后一期会自动记录剩余尾款 ¥\(moneyText(remainingAmount))，避免分期尾差。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            } else if let effectiveAmount, let parsedAmount, parsedAmount > effectiveAmount {
                Text("本期最多记录剩余尾款 ¥\(moneyText(effectiveAmount))。")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            }
        }
    }

    private var ledgerPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("账单明细", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)

            if paidRecords.isEmpty {
                Text("还没有实付账单。已有小金库存款会作为可抵扣余额保留。")
                    .font(.caption)
                    .foregroundStyle(themeManager.secondaryTextColor)
                    .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            } else {
                ForEach(paidRecords) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.paymentMode == .installment ? "第 \(entry.installmentIndex)/\(entry.installmentCount) 期" : "一次性付清")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(themeManager.primaryTextColor)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            Text(paymentBreakdownText(entry))
                                .font(.caption2)
                                .foregroundStyle(themeManager.secondaryTextColor)
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        }
                        Spacer()
                        Text("¥\(moneyText(entry.amount))")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(hex: "C94C72"))
                            .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 18)
    }

    private func paymentStat(title: String, value: Decimal, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(themeManager.secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            Text("¥\(moneyText(value))")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .themeSkinLegibleText(level: .chip, slot: .sectionCard)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }

    private func refreshDefaultAmount() {
        switch mode {
        case .oneTime:
            amountText = moneyText(remainingAmount)
        case .installment:
            guard let count = effectiveInstallmentCount else {
                amountText = ""
                return
            }
            let defaultAmount = WealthSavingLedger.defaultInstallmentAmount(
                for: clothing,
                entries: wealthSavingEntries,
                installmentCount: count
            )
            amountText = moneyText(defaultAmount)
        }
    }

    private func paymentBreakdownText(_ entry: WealthSavingEntry) -> String {
        let paidDate = entry.paidAt?.formatted(date: .numeric, time: .omitted) ?? "已记录"
        return "\(paidDate) · 小金库抵扣 ¥\(moneyText(entry.vaultDeductionAmount)) · 外部实付 ¥\(moneyText(entry.externalPaymentAmount))"
    }

    private func moneyText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
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
        case "裙装总价", "裙装单价", "原价", "全款预约金额", "单件预约金额": return "tag"
        case "库存数量": return "number.circle"
        case "购买日期": return "calendar"
        case "定金日期", "全款预约日期": return "calendar.badge.clock"
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
