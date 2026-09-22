import SwiftUI

// MARK: - 系列点菜式选购页（V1.3）
//
//  系列对外只保留一条主链路（系列详情页的合并大卡 → 本页）：整卡进入后
//  按品类（JSK / KC / 小物 / 包…）分区列出全部单品，明码标价、各带商品照；
//  勾选任意单品合并到同一次加入操作（同一链路下）。
//  规格图文绑定：选中某个配色规格时，该行展示区同步切换为该规格绑定的照片
//  （variant.imageAssetID；未绑定规格图的沿用商品首图）。
//
//  V1.3 商品卡片合并 + 双价展示（2026-09-22）：
//    · 同款不同色（仅颜色词差异）合并为一张卡片，卡片内颜色 chips 切换
//    · 价格双阶段：预约期间默认按预约价加入；预约结束且现货/预约双价并存时
//      卡片上同时展示两价，用户自选按哪种价格加入（默认现货）

struct ShopCatalogSeriesMenuView: View {
    @ObservedObject var store: ShopCatalogStore
    let seriesID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    /// 勾选的单品（合并到同一次加入操作）
    @State private var checked: Set<String> = []
    /// 各单品当前选中的配色（规格图文绑定 + 记录规格）
    @State private var selectedColor: [String: String] = [:]
    /// 各单品当前选中的尺码（来自尺码表行标签，回退规格尺码）
    @State private var selectedSize: [String: String] = [:]
    /// 合并卡片内当前激活的单品（cardKey → productID）
    @State private var activeProductByCard: [String: String] = [:]
    /// 用户自选的加购价格口径（预约结束后双价并存的卡片可改；缺省走阶段默认）
    @State private var priceChoiceByProduct: [String: ShopCatalogCardPriceChoice] = [:]
    @State private var showsMerge = false
    @State private var mergeToast: String?
    /// 大图预览：正在查看的单品（点击行内缩略图弹出，关闭即返回原页面）
    @State private var viewerProduct: CatalogProduct?

    private var series: CatalogSeries? { store.series(id: seriesID) }
    private var products: [CatalogProduct] { store.products(inSeries: seriesID) }
    private var categories: [String] { store.categories(inSeries: seriesID) }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground(themeSkinWallpaperContext: .timeHall)
                    .ignoresSafeArea()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        ForEach(categories, id: \.self) { category in
                            let items = products.filter { $0.category == category }
                            if !items.isEmpty {
                                categorySection(category, items: items)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 96)
                }
            }
            .navigationTitle(series?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { selectionBar }
            .sheet(isPresented: $showsMerge) {
                NavigationStack {
                    ShopCatalogWardrobeMergeView(
                        selectedProductIDs: checked.sorted(),
                        priceChoices: checked.reduce(into: [:]) { dict, id in
                            if let p = store.product(id: id) { dict[id] = effectiveChoice(for: p) }
                        },
                        colorByProduct: checked.reduce(into: [:]) { dict, id in
                            if let p = store.product(id: id) { dict[id] = selectionColor(for: p) }
                        },
                        sizeByProduct: checked.reduce(into: [:]) { dict, id in
                            if let p = store.product(id: id) { dict[id] = effectiveSize(for: p) }
                        }
                    ) { count in
                        mergeToast = "已加入少女衣橱（\(count) 条记录）"
                        checked = []
                    }
                }
                .presentationDetents([.large])
            }
            .fullScreenCover(item: $viewerProduct) { product in
                ShopCatalogImageViewer(references: viewerReferences(for: product),
                                       startIndex: viewerStartIndex(for: product))
            }
            .overlay(alignment: .bottom) {
                if let mergeToast {
                    Text(mergeToast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.bottom, 70)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_600_000_000)
                            await MainActor.run { self.mergeToast = nil }
                        }
                }
            }
        }
    }

    // MARK: 页头（系列主视觉 + 汇总）

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("点菜式选购".appLocalized)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(themeManager.secondaryTextColor)
            Text("同款不同色合并为一张卡片；点颜色 / 尺码选择规格，双价并存可自选现货 / 预约价加入")
                .font(.caption)
                .foregroundStyle(themeManager.tertiaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: 合并卡片分组（同款不同色 → 一张卡）

    /// 一张合并卡片：同品类 + 同款名（商品名剥离颜色词）的若干单品
    struct CardGroup: Identifiable {
        let category: String
        let baseName: String
        let products: [CatalogProduct]
        var id: String { "\(category)|\(baseName)" }
    }

    private func cardGroups(in items: [CatalogProduct]) -> [CardGroup] {
        var order: [String] = []
        var buckets: [String: [CatalogProduct]] = [:]
        for p in items {
            // V1.4：显式款式名（designName）优先，缺省按名称剥离颜色词派生
            let design = ShopCatalogSameDesignGrouper.designName(of: p)
            let key = "\(p.category)|\(design)"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(p)
        }
        return order.compactMap { key in
            guard let list = buckets[key], let first = list.first else { return nil }
            return CardGroup(category: first.category,
                             baseName: ShopCatalogSameDesignGrouper.designName(of: first),
                             products: list)
        }
    }

    /// 卡片当前激活的单品（默认第一个颜色）
    private func activeProduct(of group: CardGroup) -> CatalogProduct? {
        if let id = activeProductByCard[group.id],
           let p = group.products.first(where: { $0.id == id }) {
            return p
        }
        return group.products.first
    }

    // MARK: 价格阶段与加购口径

    /// 卡片所处的销售阶段（决定价格展示与加购默认口径）
    private func cardPricePhase(for product: CatalogProduct) -> ShopCatalogCardPricePhase {
        let archive = store.priceArchive(forProduct: product.id)
        let reservationOpen = store.saleEvents(forProduct: product.id).contains {
            $0.type == .reservation && store.windowStatus(of: $0) == .open
        }
        return ShopCatalogCardPricePhase.of(
            stockPrice: archive.currentStockPrice,
            reservationPrice: archive.currentReservationPrice,
            reservationOpen: reservationOpen
        )
    }

    /// 实际生效的加购口径：用户自选优先；预约口径需要可用的预约记录，缺记录回退现货
    private func effectiveChoice(for product: CatalogProduct) -> ShopCatalogCardPriceChoice {
        let chosen = priceChoiceByProduct[product.id] ?? cardPricePhase(for: product).defaultChoice
        if chosen == .reservation && store.priceArchive(forProduct: product.id).reservation == nil {
            return .stock
        }
        return chosen
    }

    /// 勾选合计 / 展示用价格：按生效口径取当前价（修正后口径），缺价回退历史预约价
    private func displayPrice(for product: CatalogProduct) -> Decimal? {
        let archive = store.priceArchive(forProduct: product.id)
        switch effectiveChoice(for: product) {
        case .reservation:
            return archive.currentReservationPrice
        case .stock:
            return archive.currentStockPrice ?? archive.historicalReservationPrice
        }
    }

    /// 预约口径的默认已付定金（沿用预约记录上的定金，缺省 0）
    private func defaultReservationDeposit(for product: CatalogProduct) -> Decimal {
        store.priceArchive(forProduct: product.id).reservation?.deposit ?? 0
    }

    /// 加购记录的颜色：合并卡片走颜色词标签；未合并单品沿用规格选择
    private func selectionColor(for product: CatalogProduct) -> String? {
        let group = cardGroups(in: products).first { $0.products.contains { $0.id == product.id } }
        if let group, group.products.count > 1 {
            return ShopCatalogSameDesignGrouper.colorLabel(for: product.name)
        }
        return selectedColor[product.id] ?? store.colors(forProduct: product.id).first
    }

    // MARK: 尺码选择（V1.4：选择区补充尺码维度）

    /// 可选尺码：尺码表行标签优先（S / M …），无尺码表时回退规格里的尺码
    private func sizeOptions(for product: CatalogProduct) -> [String] {
        let fromChart = store.sizeChart(forProduct: product.id)?
            .rows.map(\.label).filter { !$0.isEmpty } ?? []
        if !fromChart.isEmpty { return fromChart }
        return store.sizes(forProduct: product.id)
    }

    /// 实际生效的尺码：用户已选优先，否则取第一个可选尺码
    private func effectiveSize(for product: CatalogProduct) -> String? {
        let options = sizeOptions(for: product)
        if let chosen = selectedSize[product.id], options.contains(chosen) { return chosen }
        return options.first
    }

    // MARK: 品类分区

    private func categorySection(_ category: String, items: [CatalogProduct]) -> some View {
        let groups = cardGroups(in: items)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(category.appLocalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(themeManager.primaryTextColor)
                Text("\(items.count) 件")
                    .font(.caption)
                    .foregroundStyle(themeManager.tertiaryTextColor)
                Spacer()
            }
            .padding(.horizontal, 4)
            ForEach(groups) { group in
                menuItemRow(group)
            }
        }
    }

    // MARK: 商品卡片行（照片 + 双价 + 颜色切换 + 勾选）

    @ViewBuilder
    private func menuItemRow(_ group: CardGroup) -> some View {
        if let p = activeProduct(of: group) {
            let colorCount = group.products.count
            HStack(alignment: .top, spacing: 12) {
                Button {
                    viewerProduct = p
                } label: {
                    ShopCatalogAssetImage(reference: imageReference(for: p))
                        .aspectRatio(3 / 4, contentMode: .fill)
                        .frame(width: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看大图")

                VStack(alignment: .leading, spacing: 6) {
                    NavigationLink {
                        ShopCatalogProductView(productID: p.id)
                    } label: {
                        HStack(spacing: 4) {
                            Text(colorCount > 1 ? group.baseName : p.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(themeManager.primaryTextColor)
                                .multilineTextAlignment(.leading)
                            if colorCount > 1 {
                                Text("· \(colorCount) 色")
                                    .font(.system(size: 11))
                                    .foregroundStyle(themeManager.tertiaryTextColor)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }
                    }
                    .buttonStyle(.plain)

                    priceLine(p)
                    if colorCount > 1 {
                        colorChips(group, active: p)
                    } else {
                        specChips(p)
                    }
                    sizeChips(p)
                }

                Spacer(minLength: 0)

                checkCircle(p)
            }
            .padding(10)
            .themeSkinSectionCard(cornerRadius: 14)
        }
    }

    /// 尺码选择 chips（V1.4）：来自尺码表行标签（S / M…），仅一个可选尺码时不显示
    @ViewBuilder
    private func sizeChips(_ p: CatalogProduct) -> some View {
        let options = sizeOptions(for: p)
        if options.count > 1 {
            let selected = effectiveSize(for: p)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("尺码".appLocalized)
                        .font(.system(size: 10))
                        .foregroundStyle(themeManager.tertiaryTextColor)
                    ForEach(options, id: \.self) { size in
                        let isSelected = size == selected
                        Button {
                            selectedSize[p.id] = size
                        } label: {
                            Text(size.appLocalized)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .white : themeManager.secondaryTextColor)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(isSelected ? Color.pink : Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 明码标价（V1.4 双价阶段）：
    ///   · 双价并存（无论预约窗口状态）：现货 / 预约 chips 用户自选（默认走阶段口径）
    ///   · 仅单侧价格：按所存口径明码标价
    @ViewBuilder
    private func priceLine(_ p: CatalogProduct) -> some View {
        let archive = store.priceArchive(forProduct: p.id)
        let phase = cardPricePhase(for: p)
        HStack(spacing: 6) {
            switch phase {
            case .noPrice:
                Text("价格待补充")
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.secondaryTextColor)
            case .reservationOnly:
                priceText(label: "预约", price: archive.currentReservationPrice, emphasized: true)
            case .spotOnly:
                priceText(label: "现货", price: archive.currentStockPrice, emphasized: false)
            case .reservationOpen:
                // V1.4：双价并存即开放自选（默认按阶段口径 = 预约价）；仅预约价时明码标价
                if archive.currentStockPrice != nil {
                    priceChoiceChips(p, archive: archive)
                } else {
                    priceText(label: "预约", price: archive.currentReservationPrice, emphasized: true)
                }
            case .chooseAfterEnded:
                priceChoiceChips(p, archive: archive)
            }
            statusTag(p)
            Spacer(minLength: 0)
        }
    }

    private func priceText(label: String, price: Decimal?, emphasized: Bool, muted: Bool = false) -> some View {
        Group {
            if let price {
                Text("\(label) \(ShopCatalogFormat.price(price))")
                    .font(.system(size: 13, weight: emphasized ? .semibold : .regular))
                    .foregroundStyle(muted
                                     ? themeManager.secondaryTextColor
                                     : (emphasized ? themeManager.accentTextColor : themeManager.primaryTextColor))
            }
        }
    }

    /// 预约结束后双价自选 chips（默认现货）
    private func priceChoiceChips(_ p: CatalogProduct, archive: CatalogPriceArchive) -> some View {
        let selected = effectiveChoice(for: p)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                priceChoiceChip(p,
                                choice: .stock,
                                title: "现货 \(ShopCatalogFormat.price(archive.currentStockPrice ?? 0))",
                                isSelected: selected == .stock)
                priceChoiceChip(p,
                                choice: .reservation,
                                title: "预约 \(ShopCatalogFormat.price(archive.currentReservationPrice ?? 0))",
                                isSelected: selected == .reservation)
            }
        }
    }

    private func priceChoiceChip(_ p: CatalogProduct, choice: ShopCatalogCardPriceChoice,
                                 title: String, isSelected: Bool) -> some View {
        Button {
            priceChoiceByProduct[p.id] = choice
        } label: {
            Text(title.appLocalized)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : themeManager.secondaryTextColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(isSelected ? Color.pink : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    /// 合并卡片的颜色 chips：切换激活单品（同款不同色）
    private func colorChips(_ group: CardGroup, active p: CatalogProduct) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(group.products) { product in
                    let isActive = product.id == p.id
                    let label = ShopCatalogSameDesignGrouper.colorLabel(for: product.name)
                    Button {
                        activeProductByCard[group.id] = product.id
                        // 命中同名规格色时同步规格图文绑定（切换行内照片）
                        if store.colors(forProduct: product.id).contains(label) {
                            selectedColor[product.id] = label
                        }
                    } label: {
                        Text(label.appLocalized)
                            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? .white : themeManager.secondaryTextColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(isActive ? Color.pink : Color.secondary.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 规格选择（图文绑定，未合并单品）：配色 chips，选中即切换本行照片为该规格绑定图
    @ViewBuilder
    private func specChips(_ p: CatalogProduct) -> some View {
        let colors = store.colors(forProduct: p.id)
        if colors.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(colors, id: \.self) { color in
                        let isSelected = (selectedColor[p.id] ?? colors.first) == color
                        Button {
                            selectedColor[p.id] = color
                        } label: {
                            Text(color.appLocalized)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .white : themeManager.secondaryTextColor)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(isSelected ? Color.pink : Color.secondary.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// 规格图文绑定：选中配色 → 该规格绑定的照片；未绑定/未选 → 商品首图
    private func imageReference(for p: CatalogProduct) -> String? {
        let variants = store.variants(forProduct: p.id)
        if let color = selectedColor[p.id] ?? store.colors(forProduct: p.id).first,
           let bound = variants.first(where: { $0.color == color })?.imageAssetID {
            return store.asset(id: bound)?.originalURL ?? bound
        }
        guard let first = p.images.first else { return nil }
        return store.asset(id: first)?.originalURL ?? first
    }

    /// 大图预览：该单品全部商品照（与缩略图同一解析口径）
    private func viewerReferences(for p: CatalogProduct) -> [String] {
        p.images.map { store.asset(id: $0)?.originalURL ?? $0 }
    }

    /// 大图预览起始页 = 缩略图当前展示的那张（选中配色绑定的照片），缺省首页
    private func viewerStartIndex(for p: CatalogProduct) -> Int {
        guard let current = imageReference(for: p) else { return 0 }
        let refs = viewerReferences(for: p)
        return refs.firstIndex(of: current) ?? 0
    }

    // MARK: 勾选与底部操作条

    private func checkCircle(_ p: CatalogProduct) -> some View {
        Button {
            if checked.contains(p.id) {
                checked.remove(p.id)
            } else {
                checked.insert(p.id)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(checked.contains(p.id) ? Color.pink : Color.white.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                if checked.contains(p.id) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("已选 \(checked.count) 件")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(themeManager.primaryTextColor)
                if !checked.isEmpty {
                    Text("合计约 \(ShopCatalogFormat.price(checkedTotal))")
                        .font(.caption)
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
            }
            Spacer()
            Button {
                guard !checked.isEmpty else { return }
                showsMerge = true
            } label: {
                Text("勾选合并加入少女衣橱")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(checked.isEmpty ? Color.gray.opacity(0.5) : Color.pink))
            }
            .disabled(checked.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    /// 勾选合计（按生效价格口径：现货价 / 预约价；缺价计 0）
    private var checkedTotal: Decimal {
        checked.reduce(Decimal(0)) { total, id in
            guard let p = store.product(id: id) else { return total }
            return total + (displayPrice(for: p) ?? 0)
        }
    }

    @ViewBuilder
    private func statusTag(_ p: CatalogProduct) -> some View {
        let events = store.saleEvents(forProduct: p.id)
        if let active = events.first(where: { store.windowStatus(of: $0) == .open }) {
            tag(text: active.type == .reservation ? "预约中" : "现货中")
        } else if let upcoming = events.first(where: { store.windowStatus(of: $0) == .upcoming }) {
            tag(text: "即将开始")
        }
    }

    private func tag(text: String) -> some View {
        Text(text.appLocalized)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(themeManager.accentTextColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(themeManager.accentTextColor.opacity(0.1)))
    }
}
