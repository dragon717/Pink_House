import SwiftUI

// MARK: - 系列点菜式选购页（V1.2）
//
//  系列对外只保留一条主链路（系列详情页的合并大卡 → 本页）：整卡进入后
//  按品类（JSK / KC / 小物 / 包…）分区列出全部单品，明码标价、各带商品照；
//  勾选任意单品合并到同一次加入操作（同一链路下）。
//  规格图文绑定：选中某个配色规格时，该行展示区同步切换为该规格绑定的照片
//  （variant.imageAssetID；未绑定规格图的沿用商品首图）。

struct ShopCatalogSeriesMenuView: View {
    @ObservedObject var store: ShopCatalogStore
    let seriesID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    /// 勾选的单品（合并到同一次加入操作）
    @State private var checked: Set<String> = []
    /// 各单品当前选中的配色（规格图文绑定 + 记录规格）
    @State private var selectedColor: [String: String] = [:]
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
                    ShopCatalogWardrobeMergeView(selectedProductIDs: checked.sorted()) { count in
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
            Text("勾选任意单品合并下单加入衣橱；点配色可切换对应照片")
                .font(.caption)
                .foregroundStyle(themeManager.tertiaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: 品类分区

    private func categorySection(_ category: String, items: [CatalogProduct]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
            ForEach(items) { p in
                menuItemRow(p)
            }
        }
    }

    // MARK: 单品行（照片 + 明码标价 + 规格图文绑定 + 勾选）

    private func menuItemRow(_ p: CatalogProduct) -> some View {
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
                        Text(p.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(themeManager.primaryTextColor)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(themeManager.tertiaryTextColor)
                    }
                }
                .buttonStyle(.plain)

                priceLine(p)
                specChips(p)
            }

            Spacer(minLength: 0)

            checkCircle(p)
        }
        .padding(10)
        .themeSkinSectionCard(cornerRadius: 14)
    }

    /// 明码标价：现货价 / 预约价（同商品详情口径），带预约中/现货中状态标
    private func priceLine(_ p: CatalogProduct) -> some View {
        let archive = store.priceArchive(forProduct: p.id)
        return HStack(spacing: 6) {
            if let stock = archive.currentStockPrice {
                Text("现货 \(ShopCatalogFormat.price(stock))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(themeManager.primaryTextColor)
            }
            if let r = archive.historicalReservationPrice {
                Text(archive.currentStockPrice == nil ? "" : "· ")
                + Text("预约 \(ShopCatalogFormat.price(r))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(themeManager.accentTextColor)
            }
            if archive.currentStockPrice == nil && archive.historicalReservationPrice == nil {
                Text("价格待补充")
                    .font(.system(size: 13))
                    .foregroundStyle(themeManager.secondaryTextColor)
            }
            statusTag(p)
            Spacer(minLength: 0)
        }
    }

    /// 规格选择（图文绑定）：配色 chips，选中即切换本行照片为该规格绑定图
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

    /// 勾选合计（现货价优先，其次预约价；缺价计 0）
    private var checkedTotal: Decimal {
        checked.reduce(Decimal(0)) { total, id in
            let archive = store.priceArchive(forProduct: id)
            return total + (archive.currentStockPrice ?? archive.historicalReservationPrice ?? 0)
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
