//
//  ShopCatalogProductDetailView.swift
//  ItemManager
//
//  商品详情（计划 §13-15 + 附录A 参考图5）：
//  约束 1「不改变现有 UI」：视觉完全沿用现有少女心愿详情页体系 ——
//  LiquidBackground + themeSkinSectionCard + themeManager 令牌 + ThemeSkinPrimaryButtonStyle，
//  只在时光馆语境下展示 Catalog 商品资料。
//
//    · 图集轮播（页码胶囊，同现有详情页）+ 大图查看（滑动/缩放/单张/批量保存 §14）
//    · 主信息卡：商品名 / 店家 · 系列 · 年份 / 配色 / 尺码
//    · 尺码表卡：结构化表格 + 「查看原尺码表 >」（§15）
//    · 价格档案卡：预约价（含定金）/ 现货价 / 差价（§13）
//    · 操作区按预约状态条件渲染：
//      预约中 → 【加入心愿】主按钮 + 我已经预约（§16-17）
//      预约未开始 → 【加入心愿】（实际作用 = 开售提醒）
//      现货在售 → 【加入少女衣橱】（不提供加入心愿）
//      预约已结束 → 置灰【预约已结束】标签；有现货则引导加入衣橱购现货
//

import SwiftUI
import SwiftData

// MARK: - 商品详情

struct ShopCatalogProductView: View {
    let productID: String

    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared
    @State private var viewerReferences: [String] = []
    @State private var viewerIndex = 0
    @State private var showsViewer = false
    @State private var showsMergeSheet = false
    /// 价格表卡片展开状态（Request 14：默认收起，点击展开查看表格 + 原图）
    @State private var isPriceChartExpanded = false

    private var product: CatalogProduct? { store.product(id: productID) }
    private var series: CatalogSeries? { product.map { store.series(id: $0.seriesID) } ?? nil }
    private var shop: CatalogShop? { series.map { store.shop(id: $0.shopID) } ?? nil }

    /// 图集引用：product.images 存的是 CatalogAsset id，经 originalURL 解析
    private var imageReferences: [String] {
        guard let product else { return [] }
        return product.images.map { store.asset(id: $0)?.originalURL ?? $0 }
    }

    var body: some View {
        ZStack {
            LiquidBackground(themeSkinWallpaperContext: .timeHall)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    carousel
                    mainInfoCard
                        .padding(.horizontal)
                        .offset(y: -36)
                    sizeChartCard
                        .padding(.horizontal)
                        .offset(y: -36)
                    seriesPriceChartCard
                        .padding(.horizontal)
                        .offset(y: -36)
                    priceArchiveCard
                        .padding(.horizontal)
                        .offset(y: -36)
                    actionSection
                        .padding(.horizontal)
                        .offset(y: -36)
                    Color.clear.frame(height: 24)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationTitle("商品详情")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsViewer) {
            ShopCatalogImageViewer(references: viewerReferences, startIndex: viewerIndex)
        }
        .sheet(isPresented: $showsMergeSheet) {
            ShopCatalogSingleInsertSheet(productID: productID)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: 图集（§14，同现有详情页轮播样式）

    @State private var carouselIndex = 0

    /// 轮播 slide（V1.4 同款不同色）：本商品图片在前（进入详情默认展示当前所选
    /// 颜色的主图），之后追加同款其他颜色商品的主图——左右滑动即可在多个
    /// 颜色图片之间切换预览；slide 带颜色标注。
    private struct CarouselSlide: Equatable {
        let ref: String
        let colorLabel: String?
    }

    private var carouselSlides: [CarouselSlide] {
        guard let product else { return [] }
        var slides = product.images.map {
            CarouselSlide(ref: store.asset(id: $0)?.originalURL ?? $0, colorLabel: ownColorLabel)
        }
        let design = ShopCatalogSameDesignGrouper.designName(of: product)
        let siblings = (store.catalog?.products ?? []).filter {
            $0.id != product.id
                && $0.seriesID == product.seriesID
                && $0.category == product.category
                && $0.archivedAt == nil
                && ShopCatalogSameDesignGrouper.designName(of: $0) == design
        }
        for sibling in siblings {
            guard let first = sibling.images.first else { continue }
            let ref = store.asset(id: first)?.originalURL ?? first
            guard !slides.contains(where: { $0.ref == ref }) else { continue }
            slides.append(CarouselSlide(
                ref: ref,
                colorLabel: store.colors(forProduct: sibling.id).first
                    ?? ShopCatalogSameDesignGrouper.colorLabel(for: sibling.name)))
        }
        return slides
    }

    private var ownColorLabel: String? {
        guard let product else { return nil }
        if let color = store.colors(forProduct: product.id).first { return color }
        return ShopCatalogSameDesignGrouper.colorLabel(for: product.name)
    }

    private var carousel: some View {
        ZStack(alignment: .bottom) {
            if carouselSlides.isEmpty {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "tshirt")
                            .font(.system(size: 60))
                            .foregroundStyle(.pink.opacity(0.3))
                    }
                    .frame(height: 400)
            } else {
                TabView(selection: $carouselIndex) {
                    ForEach(Array(carouselSlides.enumerated()), id: \.offset) { index, slide in
                        ShopCatalogAssetImage(reference: slide.ref)
                            .frame(height: 400)
                            .clipped()
                            .tag(index)
                            .onTapGesture {
                                viewerReferences = carouselSlides.map(\.ref)
                                viewerIndex = carouselIndex
                                showsViewer = true
                            }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(height: 400)

                // 颜色标注：当前 slide 对应的颜色（同款不同色滑动切换时的定位提示）
                if let colorLabel = carouselSlides.indices.contains(carouselIndex)
                    ? carouselSlides[carouselIndex].colorLabel : nil {
                    HStack {
                        Text(colorLabel.appLocalized)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                            .padding(.leading, 12)
                        Spacer()
                    }
                }

                HStack(spacing: 4) {
                    Text("\(min(carouselIndex + 1, carouselSlides.count))")
                    Text("/")
                    Text("\(carouselSlides.count)")
                }
                .font(.caption2)
                .foregroundStyle(.white)
                .themeSkinLegibleText(level: .badge, slot: .sectionCard)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: 主信息卡（参考图5：名称 / 店家·年份 / 配色 / 尺码）

    private var mainInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(product?.name ?? "")
                .font(.title2.bold())
                .foregroundStyle(themeManager.primaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if let shop { Text(shop.name) }
                if let year = series?.year { Text("· \(String(year))") }
                if let season = series?.season, !season.isEmpty { Text("· \(season)") }
                if let category = product?.category { Text("· \(category)") }
            }
            .font(.caption)
            .foregroundStyle(themeManager.secondaryTextColor)

            Divider().background(themeManager.tertiaryTextColor.opacity(0.3))

            if !colors.isEmpty {
                specRow(label: "配色", values: colors)
            }
            if !sizes.isEmpty {
                specRow(label: "尺码", values: sizes)
            }
            if let desc = product?.description, !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSkinSectionCard(cornerRadius: 16)
    }

    @ViewBuilder
    private func specRow(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label.appLocalized)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
            ShopCatalogFlowChips(values: values)
        }
    }

    private var colors: [String] { store.colors(forProduct: productID) }
    private var sizes: [String] { store.sizes(forProduct: productID) }

    // MARK: 尺码表（§15：结构化 + 原始图）

    @ViewBuilder
    private var sizeChartCard: some View {
        if let chart = store.sizeChart(forProduct: productID) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("尺码表".appLocalized)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(themeManager.primaryTextColor)
                    Spacer()
                    if let sourceRef = chart.sourceImage.flatMap({ store.asset(id: $0)?.originalURL ?? $0 }) {
                        Button {
                            viewerReferences = [sourceRef]
                            viewerIndex = 0
                            showsViewer = true
                        } label: {
                            HStack(spacing: 3) {
                                Text("查看原尺码表".appLocalized)
                                Image(systemName: "chevron.right")
                            }
                            .font(.caption)
                            .foregroundStyle(themeManager.accentTextColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if chart.hasStructuredContent {
                    structuredTable(columns: chart.columns, rows: chart.rows, cornerLabel: "尺码")
                }
                if chart.sourceImage == nil && !chart.hasStructuredContent {
                    Text("暂无尺码表数据".appLocalized)
                        .font(.caption)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeSkinSectionCard(cornerRadius: 16)
        }
    }

    private func structuredTable(columns: [String], rows: [CatalogSizeRow], cornerLabel: String) -> some View {
        // 渲染前统一规范化（CatalogManualChartText.normalized）：旧数据里已存入的
        // 重复行标签列（如首列「尺码」）在此剔除，值尾冒号清洗——保证列与数据对齐
        let normalized = CatalogManualChartText.normalized(columns: columns, rows: rows)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(cornerLabel.appLocalized)
                    .frame(width: 64, alignment: .leading)
                ForEach(normalized.columns, id: \.self) { col in
                    Text(col)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(themeManager.primaryTextColor)
            .padding(.vertical, 8)

            ForEach(Array(normalized.rows.enumerated()), id: \.offset) { _, rowEntry in
                Divider().background(themeManager.tertiaryTextColor.opacity(0.3))
                HStack(spacing: 0) {
                    Text(rowEntry.label)
                        .frame(width: 64, alignment: .leading)
                    ForEach(Array(normalized.columns.enumerated()), id: \.offset) { index, _ in
                        Text(rowEntry.values.indices.contains(index) ? (rowEntry.values[index] ?? "—") : "—")
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: 预约价格表（系列共用；单品详情自动读取所属系列配置）

    /// 价格表归属系列维度：此处只读展示，不上传（上传入口在 系列 → 编辑）。
    /// 结构化内容由上传图片 OCR 自动解析生成；解析失败时保留原图并给出明确提示。
    /// 系列预约价区间（按本系列在售商品当前预约价汇总）：
    /// 价格表 OCR 解析失败时的兜底展示，保证详情页始终能看到价格区间
    private var seriesReservationPriceRange: (min: Decimal, max: Decimal)? {
        guard let series else { return nil }
        let prices = store.products(inSeries: series.id)
            .compactMap { store.priceArchive(forProduct: $0.id).currentReservationPrice }
        guard let lowest = prices.min(), let highest = prices.max() else { return nil }
        return (lowest, highest)
    }

    @ViewBuilder
    private var seriesPriceChartCard: some View {
        if let chart = series?.priceChart {
            VStack(alignment: .leading, spacing: 12) {
                // 头部：默认收起，仅展示标题 + 预约价区间摘要；点击展开查看表格与原图
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isPriceChartExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text("预约价格表".appLocalized)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(themeManager.primaryTextColor)
                        Spacer()
                        if let range = seriesReservationPriceRange {
                            Text("\(ShopCatalogFormat.price(range.min)) – \(ShopCatalogFormat.price(range.max))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(themeManager.accentTextColor)
                        }
                        Image(systemName: isPriceChartExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                }
                .buttonStyle(.plain)

                if isPriceChartExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        if chart.hasStructuredContent {
                            structuredTable(columns: chart.columns, rows: chart.rows, cornerLabel: "项目")
                            if let unit = chart.unit {
                                Text("单位：\(unit)".appLocalized)
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.tertiaryTextColor)
                            }
                        } else {
                            Text(chart.sourceImage != nil
                                 ? "价格表图片已上传，但未能自动解析出表格内容，请在系列配置中重新上传或手动补录；上方区间按本系列在售商品汇总".appLocalized
                                 : "暂无价格表数据".appLocalized)
                                .font(.caption)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }
                        // 原图：详情页内嵌直接展示（不再只依赖全屏查看器）
                        if let sourceRef = chart.sourceImage {
                            priceChartImageSection(sourceRef)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeSkinSectionCard(cornerRadius: 16)
        }
    }

    /// 价格表原图内嵌展示：
    ///   · 文件可解析 → 圆角图片（等比、限高），点击进全屏查看器放大（沿用商品图查看器）
    ///   · 文件丢失 / 引用不可解析 → 明确提示重新上传，而不是渲染空白
    @ViewBuilder
    private func priceChartImageSection(_ ref: String) -> some View {
        if priceChartImageMissing(ref) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text("原图文件丢失，请在系列配置中重新上传价格表图片".appLocalized)
            }
            .font(.caption)
            .foregroundStyle(themeManager.tertiaryTextColor)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ShopCatalogAssetImage(reference: ref, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(themeManager.tertiaryTextColor.opacity(0.25), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewerReferences = [ref]
                        viewerIndex = 0
                        showsViewer = true
                    }
                Text("点击图片可放大查看".appLocalized)
                    .font(.caption2)
                    .foregroundStyle(themeManager.tertiaryTextColor)
            }
        }
    }

    /// 原图可解析性诊断：local: 文件丢失 / 引用无法解析时返回 true，
    /// 把「图片显示不出来」变成明确原因（数据随沙盒重置丢失时给用户可操作的提示）
    private func priceChartImageMissing(_ ref: String) -> Bool {
        ShopCatalogImageResolver.isUnavailable(ref)
    }

    // MARK: 价格档案（§13：预约价 / 现货价 / 差价；定金尾款并列 + 缺失兜底）

    /// 完整、并列展示该商品已维护的全部价格信息：
    ///   · 预约场景：预约总价 + 定金 / 尾款（同排并列，缺任一显示「暂无」）
    ///   · 现货场景：现货价；定金 / 尾款同样占位展示，缺失显示「暂无」
    /// 原则：任何字段缺失都走兜底文案，既不空白也不强解包——补录只填了现货价、
    /// 或只填了定金没填尾款时，页面都完整可读。
    @ViewBuilder
    private var priceArchiveCard: some View {
        let archive = store.priceArchive(forProduct: productID)
        if archive.reservation != nil || archive.stock != nil || archive.isCorrected {
            VStack(alignment: .leading, spacing: 12) {
                Text("价格档案".appLocalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(themeManager.primaryTextColor)
                // 展示「当前生效值」：价格修正覆盖优先，未修正则回退到历史记录推导
                priceRow(label: "预约价".appLocalized, value: archive.currentReservationPrice)
                depositBalanceRow(deposit: archive.currentDeposit,
                                  balance: archive.currentBalance)
                priceRow(label: "现货价".appLocalized, value: archive.currentStockPrice)
                if let delta = archive.stockOverReservationDelta {
                    HStack(spacing: 6) {
                        Text("差价（现货 − 预约）".appLocalized)
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                        Text(delta >= 0 ? "+¥\(NSDecimalNumber(decimal: delta).stringValue)" : "-¥\(NSDecimalNumber(decimal: abs(delta)).stringValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeManager.accentTextColor)
                        // V1.1 §1 P0：差价需同时展示百分比（相对预约价）
                        if let percent = archive.stockOverReservationDeltaPercent {
                            Text(String(format: "%@%.1f%%", percent >= 0 ? "+" : "−", abs(percent)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(themeManager.accentTextColor)
                        }
                    }
                }
                if let correctedAt = archive.correction?.correctedAt {
                    Text("价格已于 \(correctedAt.formatted(.dateTime.year().month().day())) 修正（仅更新当前价，历史销售记录不变）")
                        .font(.caption2)
                        .foregroundStyle(themeManager.tertiaryTextColor)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeSkinSectionCard(cornerRadius: 16)
        }
    }

    private func priceRow(label: String, value: Decimal?) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
            Spacer()
            priceText(value)
        }
    }

    /// 定金 / 尾款并列展示（预约场景核心字段；缺失显示「暂无」）
    private func depositBalanceRow(deposit: Decimal?, balance: Decimal?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            priceCell(label: "定金".appLocalized, value: deposit)
            Rectangle()
                .fill(themeManager.tertiaryTextColor.opacity(0.25))
                .frame(width: 1, height: 30)
            priceCell(label: "尾款".appLocalized, value: balance)
        }
    }

    private func priceCell(label: String, value: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(themeManager.tertiaryTextColor)
            priceText(value, font: .system(size: 14, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 价格值文案：无值统一兜底「暂无」，保证关键信息不空白、也不强解包崩溃
    private func priceText(_ value: Decimal?,
                           font: Font = .system(size: 16, weight: .semibold)) -> some View {
        Group {
            if let value {
                Text("¥\(NSDecimalNumber(decimal: value).stringValue)")
                    .font(font)
                    .foregroundStyle(themeManager.primaryTextColor)
            } else {
                Text("暂无".appLocalized)
                    .font(font)
                    .foregroundStyle(themeManager.tertiaryTextColor)
            }
        }
    }

    // MARK: 操作区（§7：预约期间三按钮；非预约期间两按钮；§16-17）

    @Environment(\.modelContext) private var modelContext
    @State private var showsReservationSheet = false
    @State private var actionToast: String?

    /// 该商品是否已进入心愿 / 尾款 / 衣橱（按 catalogProductID 关联现有数据）
    private var existingRecord: Clothing? {
        var descriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate { $0.catalogProductID == productID && $0.isDeleted == false }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    @ViewBuilder
    private var actionSection: some View {
        if let existing = existingRecord {
            VStack(spacing: 6) {
                Label(
                    existing.isDepositPlan ? "已在心愿尾款中" : "已在少女衣橱中",
                    systemImage: existing.isDepositPlan ? "heart.fill" : "checkmark.seal.fill"
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(themeManager.accentTextColor)
                Text("到心愿尾款或衣橱页可继续管理".appLocalized)
                    .font(.caption2)
                    .foregroundStyle(themeManager.tertiaryTextColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            VStack(spacing: 10) {
                if let product {
                    switch purchasePhase(for: product.id) {
                    case .reservationActive:
                        // 预约中：主按钮 = 加入心愿（到「心愿尾款」跟进定金/尾款）
                        primaryButton(title: "加入心愿", symbol: "heart.fill") {
                            addToWishlist(reminder: false)
                        }
                        secondaryAction(title: "我已经预约", symbol: "calendar.badge.clock") {
                            showsReservationSheet = true
                        }
                        statusCaption("预约中：加入心愿后，到「心愿尾款」随时准备付定金或尾款")
                    case .reservationUpcoming:
                        // 预约未开始：仍显示加入心愿，实际作用是开售提醒
                        primaryButton(title: "加入心愿", symbol: "heart") {
                            addToWishlist(reminder: true)
                        }
                        statusCaption("预约未开始：加入后将作为开售提醒，到点通知你来买")
                    case .inStock:
                        // 现货在售：不提供加入心愿，直接入库
                        primaryButton(title: "加入少女衣橱", symbol: nil) {
                            showsMergeSheet = true
                        }
                        statusCaption("现货在售：可直接加入衣橱留存搭配")
                    case .reservationEnded:
                        // 预约已结束：置灰标签；有现货则引导购买现货
                        endedTag
                        if hasStock {
                            primaryButton(title: "加入少女衣橱", symbol: nil) {
                                showsMergeSheet = true
                            }
                            statusCaption("预约已结束：现货在售，可加入衣橱留存")
                        } else {
                            statusCaption("预约已结束：本款已无法预约，也暂无现货")
                        }
                    case .neutral:
                        // 无任何上新窗口 / 价格档案：仅保留入库入口
                        primaryButton(title: "加入少女衣橱", symbol: nil) {
                            showsMergeSheet = true
                        }
                    }
                }
            }
            .sheet(isPresented: $showsReservationSheet) {
                ShopCatalogReservationSheet(productID: productID)
            }
            .overlay(alignment: .bottom) {
                if let actionToast {
                    Text(actionToast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 12)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            await MainActor.run { self.actionToast = nil }
                        }
                }
            }
        }
    }

    // MARK: 购买阶段（按预约状态条件渲染的依据）

    private func purchasePhase(for productID: String) -> ShopCatalogPurchasePhase {
        let events = store.saleEvents(forProduct: productID)
        let reservationStatuses = events
            .filter { $0.type == .reservation }
            .map { store.windowStatus(of: $0) }
        let stockWindowOpen = events.contains {
            $0.type != .reservation && store.windowStatus(of: $0).isOpenLike
        }
        let archive = store.priceArchive(forProduct: productID)
        return ShopCatalogPurchasePhase.resolve(
            reservationStatuses: reservationStatuses,
            stockWindowOpen: stockWindowOpen,
            hasStockPrice: archive.currentStockPrice != nil,
            hasReservationPrice: archive.reservation != nil
        )
    }

    /// 是否有可买的现货（现货窗口进行中，或价格档案含现货价）
    private var hasStock: Bool {
        guard let product else { return false }
        let events = store.saleEvents(forProduct: product.id)
        if events.contains(where: { $0.type != .reservation && store.windowStatus(of: $0).isOpenLike }) {
            return true
        }
        return store.priceArchive(forProduct: product.id).currentStockPrice != nil
    }

    /// 主按钮（与原「加入少女衣橱」同款主题样式，保持视觉一致）
    private func primaryButton(title: String, symbol: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Label(title.appLocalized, systemImage: symbol)
                } else {
                    Text(title.appLocalized)
                }
            }
            .themeSkinLegibleText(level: .chip, slot: .primaryButton)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .pink, cornerRadius: 16, verticalPadding: 14))
    }

    private func statusCaption(_ text: String) -> some View {
        Text(text.appLocalized)
            .font(.caption2)
            .foregroundStyle(themeManager.tertiaryTextColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// 置灰的「预约已结束」标签（非按钮，避免误导可点）
    private var endedTag: some View {
        Label("预约已结束".appLocalized, systemImage: "clock.badge.xmark")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("预约已结束")
    }

    private func secondaryAction(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title.appLocalized, systemImage: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(themeManager.accentTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(themeManager.accentTextColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func showActionToast(_ text: String) {
        actionToast = text
    }

    private func addToWishlist(reminder: Bool) {
        guard let draft = ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: .init(productID: productID, priceMode: .wishlist),
            store: store, modelContext: modelContext
        ) else {
            showActionToast("加入心愿失败：商品暂无价格档案")
            return
        }
        do {
            _ = try ShopCatalogWardrobeInserter.insert(
                draft: draft,
                selection: .init(productID: productID, priceMode: .wishlist),
                store: store, modelContext: modelContext
            )
            if reminder {
                scheduleSaleReminderIfNeeded()
            } else {
                showActionToast("已加入心愿，可到心愿尾款查看")
            }
        } catch {
            showActionToast("加入心愿失败：\(error.localizedDescription)")
        }
    }

    /// 预约未开始的商品：加入心愿 = 开售提醒，到预约窗口 startAt 弹本地通知
    private func scheduleSaleReminderIfNeeded() {
        let events = store.saleEvents(forProduct: productID)
        guard let fireDate = ShopCatalogSaleReminder.upcomingSaleStart(events: events) else {
            // 开售时间未定档：先入心愿，不定时提醒
            showActionToast("已加入心愿（开售时间待公布，暂无法定时提醒）")
            return
        }
        let productName = product?.name ?? ""
        let seriesName = series?.name
        Task {
            let ok = await ShopCatalogSaleReminder.schedule(
                productID: productID,
                productName: productName,
                seriesName: seriesName,
                fireDate: fireDate
            )
            showActionToast(ok
                ? "已加入心愿，\(ShopCatalogFormat.month(fireDate)) 开售时提醒你来买"
                : "已加入心愿；通知权限未开启，请到系统设置开启后才能收到开售提醒")
        }
    }
}

/// 上新窗口状态的小辅助：open / ongoing 都视为「可操作」
private extension ShopCatalogStore.SaleWindowStatus {
    var isOpenLike: Bool { self == .open || self == .ongoing }
}

// MARK: - 购买阶段（按预约状态条件渲染，纯逻辑便于单测）

/// 商品详情操作区的按钮策略依据（优先级：预约中 > 预约未开始 > 预约已结束 > 现货 > 无信息）
///
/// 规则（对应运营口径）：
/// · 预约中 → 【加入心愿】（心愿尾款跟进定金/尾款）
/// · 预约未开始 → 【加入心愿】（实际作用 = 开售提醒）
/// · 现货在售 → 【加入少女衣橱】，不提供加入心愿
/// · 预约已结束 → 置灰【预约已结束】标签；有现货则引导加入衣橱购现货
enum ShopCatalogPurchasePhase: Equatable {
    case reservationActive   // 预约中
    case reservationUpcoming // 预约未开始（加入心愿 = 开售提醒）
    case inStock             // 现货在售
    case reservationEnded    // 预约已结束
    case neutral             // 无窗口 / 无价格档案

    static func resolve(
        reservationStatuses: [ShopCatalogStore.SaleWindowStatus],
        stockWindowOpen: Bool,
        hasStockPrice: Bool,
        hasReservationPrice: Bool
    ) -> ShopCatalogPurchasePhase {
        if reservationStatuses.contains(.open) || reservationStatuses.contains(.ongoing) {
            return .reservationActive
        }
        if reservationStatuses.contains(.upcoming) {
            return .reservationUpcoming
        }
        if reservationStatuses.contains(.ended) {
            return .reservationEnded
        }
        // 没有预约窗口：看现货窗口 / 现货价档案
        if stockWindowOpen || hasStockPrice {
            return .inStock
        }
        if hasReservationPrice {
            // 只剩历史预约价：预约期已过
            return .reservationEnded
        }
        return .neutral
    }
}

// MARK: - 单件加入衣橱确认（复用多选确认页的版式，§12/§19-21）

struct ShopCatalogSingleInsertSheet: View {
    let productID: String

    var body: some View {
        NavigationStack {
            ShopCatalogWardrobeMergeView(selectedProductIDs: [productID], onFinished: { _ in })
        }
    }
}

// MARK: - 简易流式标签

struct ShopCatalogFlowChips: View {
    let values: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(values, id: \.self) { v in
                    Text(v)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - 大图查看器（计划 §14：滑动 / 缩放 / 单张保存 / 多选批量保存）

struct ShopCatalogImageViewer: View {
    let references: [String]
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var page: Int
    @State private var savedTip: String?
    /// 多选批量保存模式（计划 §14）
    @State private var isSelecting = false
    @State private var selected: Set<Int> = []

    init(references: [String], startIndex: Int) {
        self.references = references
        self.startIndex = startIndex
        _page = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(references.enumerated()), id: \.offset) { index, ref in
                    ZoomableImage(reference: ref)
                        .tag(index)
                        .onTapGesture {
                            if isSelecting {
                                toggle(index)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if isSelecting {
                                selectBadge(index)
                                    .padding(20)
                            }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                    }
                    .accessibilityLabel("关闭大图")
                    Spacer()
                    Text("\(page + 1) / \(references.count)")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button {
                        // 进入多选时默认勾选当前页
                        isSelecting.toggle()
                        if isSelecting {
                            selected = [page]
                        } else {
                            selected = []
                        }
                    } label: {
                        Text(isSelecting ? "取消".appLocalized : "多选".appLocalized)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                    }
                }
                .padding(.horizontal, 8)
                Spacer()
                if isSelecting {
                    batchSaveBar
                }
            }

            if let savedTip {
                Text(savedTip)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
            }
        }
    }

    private var batchSaveBar: some View {
        HStack(spacing: 12) {
            ForEach(Array(selected.sorted()).prefix(6), id: \.self) { index in
                Text("图\(index + 1)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if selected.count > 6 {
                Text("…")
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button {
                saveBatch()
            } label: {
                Text("保存 \(selected.count) 张")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(selected.isEmpty ? Color.gray : Color.pink))
            }
            .disabled(selected.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private func selectBadge(_ index: Int) -> some View {
        ZStack {
            Circle()
                .fill(selected.contains(index) ? Color.pink : Color.white.opacity(0.25))
                .frame(width: 26, height: 26)
            if selected.contains(index) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5).frame(width: 26, height: 26)
            }
        }
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func saveBatch() {
        var saved = 0
        for index in selected.sorted() where references.indices.contains(index) {
            guard let url = ShopCatalogImageResolver.url(for: references[index]),
                  let image = UIImage(contentsOfFile: url.path) ?? remoteImage(url)
            else { continue }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            saved += 1
        }
        showToast(saved > 0 ? "已保存 \(saved) 张到相册" : "保存失败：找不到原图")
        isSelecting = false
        selected = []
    }

    private func showToast(_ text: String) {
        savedTip = text
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run { savedTip = nil }
        }
    }

    private func remoteImage(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - 可缩放单图

private struct ZoomableImage: View {
    let reference: String
    @State private var scale: CGFloat = 1

    var body: some View {
        ShopCatalogAssetImage(reference: reference)
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { scale = max(1, min(4, $0)) }
                    .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scale = 1 } }
            )
    }
}

// MARK: - 我已经预约（计划 §17：进入现有心愿尾款）

/// 记录预约页：商品/店家/系列自动带入；颜色尺码可选；定金可改；尾款自动算；
/// 尾款时间可为「待公布」，也可手动设定（设定后提醒走现有心愿尾款通知逻辑，§18 严格沿用）。
struct ShopCatalogReservationSheet: View {
    let productID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared

    @State private var selectedColor: String?
    @State private var selectedSize: String?
    @State private var depositText: String = ""
    /// 尾款时间：nil = 待公布
    @State private var hasTailDate = false
    @State private var tailDate = Date()
    @State private var errorText: String?

    private var product: CatalogProduct? { store.product(id: productID) }
    private var series: CatalogSeries? { product.map { store.series(id: $0.seriesID) } ?? nil }
    private var shop: CatalogShop? { series.map { store.shop(id: $0.shopID) } ?? nil }
    private var archive: CatalogPriceArchive {
        store.priceArchive(forProduct: productID)
    }

    private var reservationPrice: Decimal { archive.historicalReservationPrice ?? 0 }
    private var deposit: Decimal { Decimal(Double(depositText) ?? 0) }
    private var balance: Decimal { max(0, reservationPrice - deposit) }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    LabeledContent("商品", value: product?.name ?? "")
                    LabeledContent("店家", value: shop?.name ?? "—")
                    LabeledContent("系列", value: series.map { "\($0.name)\($0.year.map { " · \($0)" } ?? "")" } ?? "—")
                }
                if !store.colors(forProduct: productID).isEmpty {
                    Section("配色") {
                        chipGrid(store.colors(forProduct: productID), selection: $selectedColor)
                    }
                }
                if !store.sizes(forProduct: productID).isEmpty {
                    Section("尺码") {
                        chipGrid(store.sizes(forProduct: productID), selection: $selectedSize)
                    }
                }
                Section("价格") {
                    LabeledContent("预约总价", value: ShopCatalogFormat.price(reservationPrice))
                    HStack {
                        Text("已付定金")
                        Spacer()
                        TextField("0", text: $depositText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        Text("元")
                    }
                    LabeledContent("待付尾款", value: ShopCatalogFormat.price(balance))
                        .foregroundStyle(themeManager.accentTextColor)
                    // §17：尾款时间可为「待公布」，也可手动设置（用于提醒）
                    Toggle("已公布尾款时间", isOn: $hasTailDate.animation())
                    if hasTailDate {
                        DatePicker("尾款时间", selection: $tailDate, displayedComponents: .date)
                    }
                }
                Section {
                    Button {
                        confirmReservation()
                    } label: {
                        Text("确认预约，进入心愿尾款")
                            .frame(maxWidth: .infinity)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .listRowBackground(Color.pink)
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("预约记录进入现有心愿尾款：已付定金 → 待付尾款 → 尾款完成 → 加入少女衣橱。不做发货 / 收货状态。")
                }
            }
            .navigationTitle("我已经预约")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                store.loadFromBundleIfNeeded()
                if depositText.isEmpty {
                    let d = archive.reservation?.deposit ?? 0
                    depositText = d > 0 ? NSDecimalNumber(decimal: d).stringValue : ""
                }
                if let end = archive.reservation?.endAt {
                    hasTailDate = true
                    tailDate = end
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func chipGrid(_ values: [String], selection: Binding<String?>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { v in
                    Button {
                        selection.wrappedValue = selection.wrappedValue == v ? nil : v
                    } label: {
                        Text(v)
                            .font(.system(size: 13, weight: selection.wrappedValue == v ? .semibold : .regular))
                            .foregroundStyle(selection.wrappedValue == v ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(selection.wrappedValue == v ? Color.pink : Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func confirmReservation() {
        guard reservationPrice > 0 else {
            errorText = "该商品没有预约价档案，无法预约"
            return
        }
        guard deposit <= reservationPrice else {
            errorText = "定金不能超过预约总价"
            return
        }
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(
            productID: productID,
            color: selectedColor,
            size: selectedSize,
            priceMode: .reservation(depositPaid: deposit)
        )
        guard var draft = ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: selection,
            store: store, modelContext: modelContext
        ) else {
            errorText = "生成预约记录失败"
            return
        }
        // §17：尾款时间可设置；未设置 = 待公布（沿用草稿里的占位）
        if hasTailDate {
            draft = draft.with(finalPaymentDate: tailDate, finalPaymentEndDate: tailDate)
        }
        do {
            _ = try ShopCatalogWardrobeInserter.insert(
                draft: draft,
                selection: selection,
                store: store, modelContext: modelContext
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
