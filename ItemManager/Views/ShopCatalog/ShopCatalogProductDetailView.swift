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
//    · 操作：加入心愿 / 我已经预约（§16-17）/ 加入少女衣橱（底部主按钮）
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

    private var carousel: some View {
        ZStack(alignment: .bottom) {
            if imageReferences.isEmpty {
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
                    ForEach(Array(imageReferences.enumerated()), id: \.offset) { index, ref in
                        ShopCatalogAssetImage(reference: ref)
                            .frame(height: 400)
                            .clipped()
                            .tag(index)
                            .onTapGesture {
                                viewerReferences = imageReferences
                                viewerIndex = carouselIndex
                                showsViewer = true
                            }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(height: 400)

                HStack(spacing: 4) {
                    Text("\(min(carouselIndex + 1, imageReferences.count))")
                    Text("/")
                    Text("\(imageReferences.count)")
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
                    structuredTable(chart)
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

    private func structuredTable(_ chart: CatalogSizeChart) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("尺码".appLocalized)
                    .frame(width: 64, alignment: .leading)
                ForEach(chart.columns, id: \.self) { col in
                    Text(col)
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(themeManager.primaryTextColor)
            .padding(.vertical, 8)

            ForEach(Array(chart.rows.enumerated()), id: \.offset) { _, rowEntry in
                Divider().background(themeManager.tertiaryTextColor.opacity(0.3))
                HStack(spacing: 0) {
                    Text(rowEntry.label)
                        .frame(width: 64, alignment: .leading)
                    ForEach(Array(chart.columns.enumerated()), id: \.offset) { index, _ in
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

    // MARK: 价格档案（§13：预约价 / 现货价 / 差价）

    @ViewBuilder
    private var priceArchiveCard: some View {
        let archive = store.priceArchive(forProduct: productID)
        if archive.reservation != nil || archive.stock != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("价格档案".appLocalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(themeManager.primaryTextColor)
                if let r = archive.reservation {
                    priceRow(label: "预约价（定金 ¥%@）".appLocalized(
                        NSDecimalNumber(decimal: r.deposit ?? 0).stringValue
                    ), value: r.price)
                }
                if let s = archive.stock {
                    priceRow(label: "现货价".appLocalized, value: s.price)
                }
                if let delta = archive.stockOverReservationDelta {
                    HStack(spacing: 6) {
                        Text("差价（现货 − 预约）".appLocalized)
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                        Text(delta >= 0 ? "+¥\(NSDecimalNumber(decimal: delta).stringValue)" : "-¥\(NSDecimalNumber(decimal: abs(delta)).stringValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeManager.accentTextColor)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeSkinSectionCard(cornerRadius: 16)
        }
    }

    private func priceRow(label: String, value: Decimal) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(themeManager.secondaryTextColor)
            Spacer()
            Text("¥\(NSDecimalNumber(decimal: value).stringValue)")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(themeManager.primaryTextColor)
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
                    let events = store.saleEvents(forProduct: product.id)
                    let hasActiveReservation = events.contains {
                        $0.type == .reservation && store.windowStatus(of: $0) != .ended
                    }
                    // 底部主按钮（参考图5：加入少女衣橱）
                    Button {
                        showsMergeSheet = true
                    } label: {
                        Text("加入少女衣橱".appLocalized)
                            .themeSkinLegibleText(level: .chip, slot: .primaryButton)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .pink, cornerRadius: 16, verticalPadding: 14))

                    HStack(spacing: 10) {
                        secondaryAction(title: "加入心愿", symbol: "heart") {
                            addToWishlist()
                        }
                        if hasActiveReservation {
                            secondaryAction(title: "我已经预约", symbol: "calendar.badge.clock") {
                                showsReservationSheet = true
                            }
                        }
                    }
                    if !hasActiveReservation {
                        Text("当前不在预约期，可加入心愿或直接入库".appLocalized)
                            .font(.caption2)
                            .foregroundStyle(themeManager.tertiaryTextColor)
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

    private func addToWishlist() {
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
            showActionToast("已加入心愿，可到心愿尾款查看")
        } catch {
            showActionToast("加入心愿失败：\(error.localizedDescription)")
        }
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
            draft.finalPaymentDate = tailDate
            draft.finalPaymentEndDate = tailDate
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
