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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingEditSheet = false
    @State private var showingImageViewer = false
    @State private var showingDeleteAlert = false
    @State private var showingFinalPaymentSheet = false
    @State private var showingFullPaymentReceiptAlert = false
    @State private var showCelebration = false
    @State private var currentImageIndex = 0
    @State private var showingShareSheet = false
    
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

                        // MARK: - Reservation Action / Status
                        if clothing.isFullPaymentReservation {
                            Button {
                                showingFullPaymentReceiptAlert = true
                            } label: {
                                fullPaymentReservationStatusLabel
                            }
                            .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .green, cornerRadius: 16, verticalPadding: 15))
                            .padding(.horizontal)
                            .offset(y: -40)
                        } else if WealthSavingLedger.shouldShowFinalPaymentPayoffAction(for: clothing) {
                            Button {
                                showingFinalPaymentSheet = true
                            } label: {
                                Text("尾款付清".appLocalized)
                                    .themeSkinLegibleText(level: .chip, slot: .primaryButton)
                            }
                            .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .pink, cornerRadius: 16, verticalPadding: 15))
                            .padding(.horizontal)
                            .offset(y: -40)
                        }
                        
                        // MARK: - Metadata Info (Created/Updated)
                        VStack(spacing: 4) {
                            Text("添加时间: %@".appLocalized(formattedMetadataDate(clothing.createdAt)))
                                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                            Text("修改时间: %@".appLocalized(formattedMetadataDate(clothing.updatedAt)))
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
                                    Text("社区".appLocalized)
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

            }
        }
        .navigationTitle("衣橱详情".appLocalized)
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
                            Label("编辑".appLocalized, systemImage: "pencil")
                        }
                        
                        Button {
                            duplicateClothing()
                        } label: {
                            Label("复制".appLocalized, systemImage: "doc.on.doc")
                        }
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("删除".appLocalized, systemImage: "trash")
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
        .sheet(isPresented: $showingFinalPaymentSheet) {
            FinalPaymentRecordingSheet(
                clothing: clothing,
                onRecord: recordFinalPayment
            )
        }
        .alert("确认删除".appLocalized, isPresented: $showingDeleteAlert) {
            Button("取消".appLocalized, role: .cancel) { }
            Button("删除".appLocalized, role: .destructive) {
                NotificationManager.shared.cancelNotification(for: clothing)
                // Soft delete
                clothing.isDeleted = true
                clothing.deletedAt = Date()
                clothing.deletionSource = nil
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
            Text("确定要删除这件裙装吗？它将被移动到回收站，你可以随时恢复。".appLocalized)
        }
        .alert("确认签收？".appLocalized, isPresented: $showingFullPaymentReceiptAlert) {
            Button("取消".appLocalized, role: .cancel) { }
            Button("确认签收".appLocalized) {
                markFullPaymentReservationReceived()
            }
        } message: {
            Text("确认后会把这条全款预约移入已拥有，并将「未到货」状态改回「全新」。".appLocalized)
        }
        .onAppear {
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

    private func markFullPaymentReservationReceived() {
        guard clothing.isFullPaymentReservation else { return }

        let now = Date()
        let reservationUnitAmount = clothing.fullPaymentReservationUnitAmount
        let receivedUnitPrice: Decimal
        if clothing.price > 0 {
            receivedUnitPrice = clothing.price
        } else {
            let unitPriceWithoutOneTimeFees = reservationUnitAmount - clothing.resolvedAccessoriesPrice - clothing.resolvedShippingFee
            receivedUnitPrice = unitPriceWithoutOneTimeFees > 0 ? unitPriceWithoutOneTimeFees : reservationUnitAmount
        }
        clothing.isDepositPlan = false
        clothing.deposit = 0
        clothing.balance = 0
        clothing.depositDate = nil
        clothing.finalPaymentDate = nil
        clothing.finalPaymentEndDate = nil
        clothing.isFinalPaymentSavedToWealth = false
        clothing.finalPaymentSavedAt = nil
        clothing.finalPaymentInstallmentCount = 0
        clothing.updatedAt = now
        clothing.lastModified = now
        if receivedUnitPrice > 0 {
            clothing.price = receivedUnitPrice
        }
        if shouldResetConditionAfterReceipt(clothing.condition) {
            clothing.condition = "全新"
        }

        do {
            try modelContext.save()
            NotificationCenter.default.post(name: .depositPlanDataDidChange, object: clothing.id)
        } catch {
            print("ClothingDetailView: Failed to receive full payment reservation: \(error)")
            ToastManager.shared.showError("签收失败，请稍后再试".appLocalized)
            return
        }

        NotificationManager.shared.cancelNotification(for: clothing)
        Task { @MainActor in
            await NotificationManager.shared.refreshAllKnownDepositNotifications(
                modelContext: modelContext,
                force: true,
                reason: "full-payment-received"
            )
        }
        NotificationManager.shared.updateApplicationBadge(modelContext: modelContext)
        Task { await SharedPersistence.shared.syncWidgetData(reason: "full-payment-received") }
        updateClothingCountCache()
        ToastManager.shared.showSuccess("已签收，已移入已拥有".appLocalized)
    }

    private func shouldResetConditionAfterReceipt(_ condition: String) -> Bool {
        let normalized = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || normalized == "未到货"
    }

    private func formattedMetadataDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().locale(LanguageManager.shared.locale))
    }
    
    private func validateCurrentImageIndex() {
        if clothing.imagePaths.isEmpty {
            currentImageIndex = 0
        } else if currentImageIndex >= clothing.imagePaths.count {
            currentImageIndex = max(0, clothing.imagePaths.count - 1)
        }
    }
    
    private func recordFinalPayment(amount: Decimal) {
        do {
            guard let result = try WealthSavingLedger.recordFinalPayment(
                amount: amount,
                for: clothing,
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
        NotificationCenter.default.post(name: .depositPlanDataDidChange, object: clothing.id)
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
                            Text("追根溯源".appLocalized)
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
                    Text("暂无品牌信息".appLocalized)
                        .font(.subheadline)
                        .unifiedTertiary()
                        .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                }
                
                if clothing.isDepositPlan {
                    HStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text((clothing.isFullPaymentReservation ? "全款预约" : "心愿尾款").appLocalized)
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
            Label("裙装信息".appLocalized, systemImage: "info.circle.fill")
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
        // ponytail: 与编辑页同行内粉/灰 tag，只读
        ClothingFieldTagsShowcase(
            label: field.displayName,
            value: detailValue(for: field),
            emptyText: field == .accessories ? "无" : "未填写"
        ) {
            if field == .sizes, let path = clothing.sizeChartImagePath {
                sizeChartThumbnail(path: path)
            }
        }
    }

    private func detailValue(for field: ClothingField) -> String {
        switch field {
        case .types: return clothing.types
        case .colors: return clothing.colors
        case .sizes: return clothing.sizes
        case .length: return clothing.length
        case .condition: return clothing.condition
        case .accessories: return clothing.accessories
        }
    }

    @ViewBuilder
    private func sizeChartThumbnail(path: String) -> some View {
        if let image = ImageManager.shared.loadImage(fileName: path) {
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
                    chartImagePathToView = path
                    showingChartImageViewer = true
                }
        }
    }
    
    private var formattedOriginalPrice: String {
        switch clothing.originalPriceCurrency {
        case .cny:
            if clothing.originalPriceJPY > 0 {
                return "¥%@（约 JP¥%@）".appLocalized(
                    detailNumberText(clothing.originalPrice),
                    detailNumberText(clothing.originalPriceJPY)
                )
            }
            return "¥%@".appLocalized(detailNumberText(clothing.originalPrice))
        case .jpy:
            let jpy = clothing.originalPriceJPY > 0 ? clothing.originalPriceJPY : clothing.originalPrice * clothing.originalPriceExchangeRateJPY
            return "JP¥%@（折合 ¥%@）".appLocalized(
                detailNumberText(jpy),
                detailNumberText(clothing.originalPrice)
            )
        }
    }

    private var formattedOriginalPriceRateSnapshot: String {
        let rate = clothing.originalPriceExchangeRateJPY > 0
            ? clothing.originalPriceExchangeRateJPY
            : Decimal(CurrencyExchangeRateService.defaultJPYRate)
        let rateText = rate.formatted(.number.precision(.fractionLength(0...4)))
        guard let updatedAt = clothing.originalPriceRateUpdatedAt else {
            return "1 CNY = %@ JPY（未记录时间）".appLocalized(rateText)
        }
        return "1 CNY = %@ JPY（%@）".appLocalized(rateText, formattedMetadataDate(updatedAt))
    }

    private var formattedShippingFee: String {
        switch clothing.shippingFeeCurrency {
        case .cny:
            if clothing.shippingFeeJPY > 0 {
                return "¥%@（约 JP¥%@）".appLocalized(
                    detailNumberText(clothing.resolvedShippingFee),
                    detailNumberText(clothing.shippingFeeJPY)
                )
            }
            return "¥%@".appLocalized(detailNumberText(clothing.resolvedShippingFee))
        case .jpy:
            let jpy = clothing.shippingFeeJPY > 0 ? clothing.shippingFeeJPY : clothing.resolvedShippingFee * clothing.shippingExchangeRateJPY
            return "JP¥%@（折合 ¥%@）".appLocalized(
                detailNumberText(jpy),
                detailNumberText(clothing.resolvedShippingFee)
            )
        }
    }

    /// 价格信息卡片 - 使用统一配色
    private var priceInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 价格信息标题行，右侧显示价格表缩略图
            HStack {
                Label("价格信息".appLocalized, systemImage: "yensign.circle.fill")
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
                        Text("小物明细".appLocalized)
                            .unifiedPrimary()
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                        Spacer()
                        Text("小物总价: ¥%@".appLocalized(detailNumberText(items.reduce(Decimal(0)) { $0 + $1.price })))
                            .unifiedSecondary()
                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                    }
                    .font(.subheadline)
                    
                    ForEach(items.sorted(by: { $0.sortIndex < $1.sortIndex })) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.name.isEmpty ? "未命名小物".appLocalized : item.name)
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
                                        Text("定金: ¥%@".appLocalized(detailNumberText(item.deposit)))
                                            .unifiedTertiary()
                                            .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                                    }
                                    if item.balance > 0 {
                                        Text("尾款: ¥%@".appLocalized(detailNumberText(item.balance)))
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
                Label {
                    Text((clothing.isFullPaymentReservation ? "全款预约总额" : "合计金额（含邮）").appLocalized)
                } icon: {
                    Image(systemName: "star.circle.fill")
                }
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
                Text("包含 %d 件库存，单套价值 ¥%@；邮费不随库存倍增".appLocalized(
                    clothing.stock,
                    clothing.unitTotalPrice.formatted(.number.precision(.fractionLength(0)).locale(LanguageManager.shared.locale))
                ))
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

    private var fullPaymentReservationStatusLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.headline.weight(.bold))
            Text("待签收".appLocalized)
                .font(.headline.weight(.semibold))
                .themeSkinLegibleText(level: .chip, slot: .primaryButton)
        }
    }

    private func moneyString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func detailNumberText(_ value: Decimal) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...2))
                .locale(LanguageManager.shared.locale)
        )
    }

    private func formattedRecordDate(_ date: Date?) -> String {
        date?.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.locale)) ?? "已记录".appLocalized
    }

    /// 购买信息卡片 - 使用统一配色
    private var purchaseInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("购买信息".appLocalized, systemImage: "bag.fill")
                .font(.headline)
                .unifiedPrimary()
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
            
            InfoRow(label: "购买日期", value: clothing.purchaseDate.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.locale)))
            
            if clothing.isFullPaymentReservation {
                if let reservationDate = clothing.depositDate {
                    InfoRow(label: "全款预约日期", value: reservationDate.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.locale)))
                }
            } else if clothing.reservationKind == .depositPlan {
                if let depositDate = clothing.depositDate {
                    InfoRow(label: "定金日期", value: depositDate.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.locale)))
                }
                if let finalPaymentDate = clothing.finalPaymentDate {
                    InfoRow(label: "预估尾款", value: formatFinalPaymentDate(start: finalPaymentDate, end: clothing.finalPaymentEndDate))
                }
            }
            
            let duration = Calendar.current.dateComponents([.day], from: clothing.purchaseDate, to: Date()).day ?? 0
            InfoRow(label: "拥有时长", value: "%@天".appLocalized(String(duration)))
            
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
                    Text("备注".appLocalized)
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
        let startDateString = start.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.locale))
        
        if let endDate = end {
            // Check if end date is different from start date (ignoring time)
            let calendar = Calendar.current
            if !calendar.isDate(start, inSameDayAs: endDate) {
                let endDateString = endDate.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.locale))
                return "\(startDateString) - \(endDateString)"
            }
        }
        
        return startDateString
    }
}

struct FinalPaymentRecordingSheet: View {
    let clothing: Clothing
    let onRecord: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    private var remainingAmount: Decimal { WealthSavingLedger.unpaidFinalPaymentAmount(for: clothing) }
    private var canRecord: Bool { remainingAmount > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                confirmCard
                .padding()
            }
            .navigationTitle("尾款付清".appLocalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消".appLocalized) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("付清".appLocalized) {
                        onRecord(remainingAmount)
                        dismiss()
                    }
                    .disabled(!canRecord)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var confirmCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("尾款付清".appLocalized, systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color(hex: "C94C72"))
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)

            Text(clothing.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(themeManager.primaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
                .lineLimit(2)

            Text("¥\(moneyText(remainingAmount))")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color(hex: "C94C72"))
                .themeSkinLegibleText(level: .chip, slot: .sectionCard)

            Text("确认后会把剩余尾款记为已支付，并恢复为普通已购裙装。".appLocalized)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
                .themeSkinLegibleText(level: .inline, slot: .sectionCard)
        }
        .padding()
        .themeSkinSectionCard(cornerRadius: 18)
    }

    private func moneyText(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
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
            
            Text(label.appLocalized)
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
