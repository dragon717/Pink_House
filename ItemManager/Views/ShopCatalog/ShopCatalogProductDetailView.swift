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
//    · 主信息卡：款式名（**内外一致口径**，2026-09-23）/ 店家 · 系列 · 年份 / 配色 / 尺码
//      「内外标题一致」= 标题永远是款式名，颜色不参与标题（同款多色时只加「· N 色」标注），
//      颜色由「配色」行与轮播颜色胶囊单独呈现；与点菜页卡片共用
//      `ShopCatalogTitleResolver` + `ShopCatalogProductTitleLabel`。
//    · 尺码表卡：结构化表格常显 + **原图折叠区**（默认收起，仅一个入口；Request D / §15）
//    · 价格档案卡：预约价（含定金）/ 现货价 / 差价（§13）
//    · 操作区按购买阶段条件渲染（分支口径唯一来源 = `ShopCatalogWardrobeEntryPolicy`）：
//      预约中 → 【加入衣橱】→ 选择弹窗（定金+尾款 / 预约价全款预约）+【加入心愿】次按钮
//      预约未开始 → 【加入心愿】（实际作用 = 开售提醒）
//      预约已结束 → 置灰【预约已结束】标签 +【加入衣橱】→ 选择弹窗（默认全款）
//      尾款中 → 置灰【尾款中】标签 +【加入衣橱】→ 选择弹窗（默认定金+尾款 = 补尾款）
//      现货在售 → 【加入衣橱】→ 选择弹窗，**仅全款**、两个价格口径（按预约价 / 按现货价）
//      ⚠️ 四个阶段都**不得静默默认**一种付款方式直接落库，也不隐藏 / 置灰任何候选
//
//  2026-09-24 需求（加购分支按阶段区分）：现货阶段补齐「仅全款 + 两个价格口径」，
//  详见 docs/加购分支与现货阶段全款口径_需求实现说明.md
//

import SwiftUI
import SwiftData

// MARK: - 商品详情

struct ShopCatalogProductView: View {
    let productID: String

    @Environment(ThemeManager.self) private var themeManager
    /// 桌面端（iPad / 常规宽度）与移动端（compact）共用同一份视图，
    /// 靠 size class 决定原图展开后的最大高度，而不是写死一个手机尺寸。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var store = ShopCatalogStore.shared
    @State private var viewerReferences: [String] = []
    @State private var viewerIndex = 0
    @State private var showsViewer = false
    @State private var showsMergeSheet = false
    /// 价格表卡片展开状态（Request 14：默认收起，点击展开查看表格 + 原图）
    @State private var isPriceChartExpanded = false
    /// 尺码表**原图**展开状态（Request D：默认收起，仅留一个入口；点开看完整原图，
    /// 再次点击或「收起」按钮折叠）。这里只存用户意图，展示形态由
    /// `ShopCatalogChartDisclosure.plan` 推导——视图不再自己拼折叠分支。
    @State private var isSizeChartImageExpanded = false

    private var product: CatalogProduct? { store.product(id: productID) }
    private var series: CatalogSeries? { product.map { store.series(id: $0.seriesID) } ?? nil }
    private var shop: CatalogShop? { series.map { store.shop(id: $0.shopID) } ?? nil }

    // MARK: 轮播 / 卡片的重叠几何（唯一口径）
    //
    //  详情页的视觉设计是「卡片压住图片下沿」：轮播之后的每张卡片都靠 `.offset(y:)`
    //  整体上提，于是卡片顶边落在轮播底边**之上**。轮播底部那两个悬浮标注
    //  （颜色胶囊、分页胶囊）也是底对齐的 —— 如果不把它们抬到卡片顶边之上，
    //  就会被半埋进卡片顶边、并压住标题首行（2026-09-24 截图标注的遮挡问题）。
    //
    //  卡片顶边相对轮播底边的位置 = 上提量 − 卡片间距，所以标注的留白必须大于它。

    /// 卡片相对轮播的上提量（`.offset(y:)`），5 张卡片统一使用。
    private static let cardLiftOverCarousel: CGFloat = 36
    /// 轮播与卡片之间的 VStack 间距。
    private static let cardStackSpacing: CGFloat = 16
    /// 轮播底部悬浮标注（颜色胶囊 / 分页胶囊）距轮播底边的留白：
    /// 上提量 − 间距 + 12 视觉间隙，保证标注整体落在图片区内、不碰卡片顶边与标题。
    private static var carouselOverlayBottomInset: CGFloat {
        cardLiftOverCarousel - cardStackSpacing + 12
    }

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
                VStack(spacing: Self.cardStackSpacing) {
                    carousel
                    mainInfoCard
                        .padding(.horizontal)
                        .offset(y: -Self.cardLiftOverCarousel)
                    sizeChartCard
                        .padding(.horizontal)
                        .offset(y: -Self.cardLiftOverCarousel)
                    seriesPriceChartCard
                        .padding(.horizontal)
                        .offset(y: -Self.cardLiftOverCarousel)
                    priceArchiveCard
                        .padding(.horizontal)
                        .offset(y: -Self.cardLiftOverCarousel)
                    actionSection
                        .padding(.horizontal)
                        .offset(y: -Self.cardLiftOverCarousel)
                    Color.clear.frame(height: 24)
                }
            }
            // 底部悬浮 Dock 避让：本页从「时光馆 → 店家上新」是 push（会看到 Dock），
            // 底部操作区「加入衣橱」会被 Dock 盖住；从系列菜单 sheet 进入时环境值为 0，自动无副作用。
            .avoidingBottomDock()
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

    /// 同款其他颜色商品（同系列 + 同品类 + 同款式名 + 未归档）。
    /// 标题的「· N 色」、配色行、轮播的「其它颜色主图」都取这一份 —— 三个数字不可能对不上。
    /// 判定口径收口在 `ShopCatalogDesignPalette`（唯一处），不要在视图里再写一遍过滤。
    private var sameDesignSiblings: [CatalogProduct] {
        guard let product else { return [] }
        return ShopCatalogDesignPalette.sameDesignProducts(of: product,
                                                          among: store.catalog?.products ?? [])
    }

    /// 标题（内外一致口径，2026-09-23）：**标题 = 款式名**，颜色不参与标题文字；
    /// 同款多色时由「· N 色」标注 + 配色行 + 轮播颜色胶囊分别呈现。
    /// 与点菜页卡片、商品管理款式组共用 `ShopCatalogTitleResolver`，
    /// 同一个商品在哪儿看都是同一句话。
    private var productTitle: ShopCatalogProductTitle? {
        guard let product else { return nil }
        return ShopCatalogTitleResolver.title(product: product, siblings: sameDesignSiblings)
    }

    private var carouselSlides: [CarouselSlide] {
        guard let product else { return [] }
        var slides = product.images.map {
            CarouselSlide(ref: store.asset(id: $0)?.originalURL ?? $0, colorLabel: ownColorLabel)
        }
        for sibling in sameDesignSiblings {
            guard let first = sibling.images.first else { continue }
            let ref = store.asset(id: first)?.originalURL ?? first
            guard !slides.contains(where: { $0.ref == ref }) else { continue }
            slides.append(CarouselSlide(
                ref: ref,
                colorLabel: ShopCatalogColorPresentation.label(
                    explicitColors: store.colors(forProduct: sibling.id),
                    name: sibling.name)))
        }
        return slides
    }

    /// 本商品的颜色标注：与所有颜色入口同一份取值口径
    /// （显式规格色优先 → 名称里的颜色词 → 无则不给标注）
    private var ownColorLabel: String? {
        guard let product else { return nil }
        return ShopCatalogColorPresentation.label(
            explicitColors: store.colors(forProduct: product.id),
            name: product.name)
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
                // 与分页胶囊共用同一条底边留白，否则两者会各自半埋进卡片顶边。
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
                    .padding(.bottom, Self.carouselOverlayBottomInset)
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
                .padding(.bottom, Self.carouselOverlayBottomInset)
            }
        }
    }

    // MARK: 主信息卡（参考图5：名称 / 店家·年份 / 配色 / 尺码）

    private var mainInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题 = 款式名（与点菜页卡片、商品管理款式组同一口径）；
            // 颜色只在下方「配色」行与轮播颜色胶囊里单独呈现。
            if let productTitle {
                ShopCatalogProductTitleLabel(
                    title: productTitle,
                    font: .title2.bold(),
                    textColor: themeManager.primaryTextColor,
                    annotationColor: themeManager.tertiaryTextColor,
                    lineLimit: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(product?.name ?? "")
                    .font(.title2.bold())
                    .foregroundStyle(themeManager.primaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                if let shop { Text(shop.name) }
                if let yearMonth = series?.yearMonthText { Text("· \(yearMonth)") }
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
            // 面料 / 款式描述：**款式级公共属性**（2026-09-23 录入端重构）——
            // 读的是款式档案，同款各颜色显示同一份；不再是「每个颜色各存一份描述」。
            // 款式描述对旧数据回退 `product.description`（重构前描述写在商品上）。
            if let fabric = styleFabric {
                specRow(label: "面料", values: [fabric])
            }
            if let desc = styleDescription, !desc.isEmpty {
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

    /// 「配色」行 = **同款全部颜色**（本商品在前，同款其他颜色商品依次追加）。
    ///
    /// 2026-09-23 系统性修复：旧口径只读本商品自己的规格色（`store.colors(forProduct:)`），
    /// 而 SPU/SKU 结构下每个颜色是独立商品 → 本商品只有自己那一色，纯名称命名时一条都没有
    /// → 整行消失，但标题仍写着「· N 色」。现在与标题同源（`designColors`）。
    private var colors: [String] { store.designColors(forProduct: productID) }
    /// 尺码行（卡外的尺码信息）：与点菜页 chips / 预约尺码共用同一份「款式级尺码列」——
    /// 同款任一颜色填了尺码表，这里就跟着变（2026-09-23 款式共享）。
    private var sizes: [String] { store.sizeRun(forProduct: productID) }

    /// 款式面料（**款式级公共属性**：同款各颜色显示同一份）
    private var styleFabric: String? { store.fabric(forProduct: productID) }

    /// 款式描述（**款式级公共属性**：档案优先，回退商品自身 description 兼容旧数据）
    private var styleDescription: String? { store.styleDescription(forProduct: productID) }

    // MARK: 尺码表（§15：结构化 + 原始图）

    /// 尺码表原图引用：`sourceImage` 既可能是 CatalogAsset id（模型约定 / 迁移产物），
    /// 也可能是运营手填的文件名 / `local:` / URL —— 两种口径统一走同一个解析入口。
    private func sizeChartReference(_ chart: CatalogSizeChart) -> String? {
        ShopCatalogChartReference.resolve(chart.sourceImage) { store.asset(id: $0)?.originalURL }
    }

    /// 尺码表展示计划：与价格表共用同一套判定（`ShopCatalogChartPresentation`），
    /// 两张卡只允许消费同一份 `Plan`，不可能再各偏一边。
    private var sizeChartPlan: ShopCatalogChartPresentation.Plan? {
        guard let chart = store.sizeChart(forProduct: productID) else { return nil }
        return ShopCatalogChartPresentation.plan(
            hasStructuredContent: chart.hasStructuredContent,
            reference: sizeChartReference(chart),
            isImageUnavailable: ShopCatalogImageResolver.isUnavailable)
    }

    /// 尺码表卡：结构化表格常显 + **原图默认收起**（Request D）。
    ///
    /// 折叠范围只有「原图」一块：表格是尺码表的主要信息，常显不折叠。
    /// 收起态**只有一个可点击入口**（需求原文），所以原先头部那个「查看原尺码表 >」
    /// 不再与入口并列——否则收起态会出现两个可点目标。全屏查看改由
    /// 「展开 → 点图片」到达，路径仍然是 2 步。
    /// 模型契约（`CatalogSizeChart.hasStructuredContent` 注释「只有原图时商品详情
    /// 仅展示原图」）依然成立：只有原图时，入口本身就是「这张卡有原图」的可见证据，
    /// 点开即见完整原图；`plan.isEmpty` 也照旧把「只有原图」算作有内容。
    @ViewBuilder
    private var sizeChartCard: some View {
        if let chart = store.sizeChart(forProduct: productID), let plan = sizeChartPlan {
            VStack(alignment: .leading, spacing: 12) {
                Text("尺码表".appLocalized)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(themeManager.primaryTextColor)
                if plan.showsTable {
                    structuredTable(columns: chart.columns, rows: chart.rows, cornerLabel: "尺码")
                }
                // 原图折叠区：渲染决策一律来自 ShopCatalogChartDisclosure，
                // 视图只持有用户意图（isSizeChartImageExpanded），不自己拼折叠分支。
                sizeChartImageSection(plan)
                if plan.isEmpty {
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

    // MARK: 尺码表原图折叠区（Request D）

    /// 尺码表原图的收起 / 展开：
    ///   · **收起（默认）**——只显示一个可点击入口，文案与 chevron 方向明示当前状态；
    ///   · **展开**——完整原图（点图进全屏放大）+ 一个显式「收起」按钮；
    ///     点入口本身同样能收起（需求：「再次点击**或通过关闭操作**收起」）；
    ///   · **文件丢失**——警示直出、不折叠（`ShopCatalogChartDisclosure` 既定口径：
    ///     折叠一个待办提示，等于让用户永远不知道要重新上传）。
    @ViewBuilder
    private func sizeChartImageSection(_ plan: ShopCatalogChartPresentation.Plan) -> some View {
        let disclosure = ShopCatalogChartDisclosure.plan(image: plan.image,
                                                        isExpanded: isSizeChartImageExpanded)
        VStack(alignment: .leading, spacing: 10) {
            if disclosure.showsTrigger {
                Button {
                    toggleSizeChartImage()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(sizeChartTriggerTitle(disclosure.trigger))
                        Spacer(minLength: 8)
                        Image(systemName: disclosure.trigger == .expand ? "chevron.down" : "chevron.up")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.accentTextColor)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(themeManager.accentTextColor.opacity(0.10))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(sizeChartTriggerTitle(disclosure.trigger)))
                .accessibilityHint(Text(disclosure.trigger == .expand
                                        ? "展开查看完整尺码表原图".appLocalized
                                        : "收起尺码表原图".appLocalized))
            }
            if disclosure.showsImage {
                VStack(alignment: .leading, spacing: 8) {
                    chartImageBlock(plan.image,
                                    missingHint: "原尺码表图片文件已丢失，请在商品资料中重新上传".appLocalized)
                    Button {
                        toggleSizeChartImage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                            Text("收起".appLocalized)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(themeManager.secondaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(themeManager.tertiaryTextColor.opacity(0.12))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("收起尺码表原图".appLocalized))
                }
                // 入口与图片同属一个容器，收起时整块淡出并向上收回 → 视觉上「折叠」
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if disclosure.showsMissingHint {
                chartImageBlock(plan.image,
                                missingHint: "原尺码表图片文件已丢失，请在商品资料中重新上传".appLocalized)
            }
        }
    }

    /// 展开与收起共用同一段动画，两条触发路径（点入口 / 点「收起」）手感一致。
    private func toggleSizeChartImage() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isSizeChartImageExpanded.toggle()
        }
    }

    private func sizeChartTriggerTitle(_ trigger: ShopCatalogChartDisclosure.Trigger) -> String {
        switch trigger {
        case .expand:   return "查看尺码表原图".appLocalized
        case .collapse: return "收起尺码表原图".appLocalized
        case .none:     return ""
        }
    }

    private func structuredTable(columns: [String], rows: [CatalogSizeRow], cornerLabel: String, labelWidth: CGFloat = 64) -> some View {
        // 渲染前统一规范化（CatalogManualChartText.normalized）：旧数据里已存入的
        // 重复行标签列（如首列「尺码」）在此剔除，值尾冒号清洗——保证列与数据对齐
        let normalized = CatalogManualChartText.normalized(columns: columns, rows: rows)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(cornerLabel.appLocalized)
                    .frame(width: labelWidth, alignment: .leading)
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
                        .frame(width: labelWidth, alignment: .leading)
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

    /// 价格表展示计划：与尺码表共用同一套判定（`ShopCatalogChartPresentation`）。
    private var priceChartPlan: ShopCatalogChartPresentation.Plan? {
        guard let chart = series?.priceChart else { return nil }
        let reference = ShopCatalogChartReference.resolve(chart.sourceImage) {
            store.asset(id: $0)?.originalURL
        }
        return ShopCatalogChartPresentation.plan(
            hasStructuredContent: chart.hasStructuredContent,
            reference: reference,
            isImageUnavailable: ShopCatalogImageResolver.isUnavailable)
    }

    @ViewBuilder
    private var seriesPriceChartCard: some View {
        if let chart = series?.priceChart, let plan = priceChartPlan {
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
                    // 说明：本卡不需要 `ShopCatalogChartDisclosure`——它折叠的是「表格 + 原图」
                    // 整块（表格原本也不常显），而尺码表卡折叠的只是原图、表格常显，
                    // 两者的折叠语义不同，共用同一套折叠判定反而会互相牵制。
                    // 展示内容（`plan`）仍与尺码表卡同源，这里不重复判定。
                    VStack(alignment: .leading, spacing: 12) {
                        if plan.showsTable {
                            // 首列 96pt（2026-09-24 需求）：表头「裙装名称」4 字 + 常见
                            // 款式名（如「托胸贴布绣 JSK」）单行放下，不折行不挤压相邻列；
                            // 尺码表卡保持默认 64pt 不受影响
                            structuredTable(columns: chart.columns, rows: chart.rows,
                                            cornerLabel: "裙装名称", labelWidth: 96)
                            if let unit = chart.unit {
                                Text("单位：\(unit)".appLocalized)
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.tertiaryTextColor)
                            }
                        } else {
                            Text(priceChartFallbackText(plan))
                                .font(.caption)
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }
                        // 原图：内嵌直接展示（与尺码表同一渲染入口，不再只依赖全屏查看器）
                        chartImageBlock(plan.image,
                                        missingHint: "价格表原图文件已丢失，请在系列配置中重新上传".appLocalized)
                        // 多图（2026-09-24 需求）：首图由 plan 渲染，这里补第 2 张起
                        extraPriceChartImages
                    }
                    .transition(.opacity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themeSkinSectionCard(cornerRadius: 16)
        }
    }

    /// 价格表多图（2026-09-24 需求）的补充展示：首图由 `chartImageBlock(plan.image:)`
    /// 渲染（单一展示口径不动），这里只补第 2 张起的原图。
    /// 引用解析与 `priceChartPlan` 同源：asset id → originalURL，其余原样交给解析器。
    private var extraPriceChartImageReferences: [String] {
        guard let chart = series?.priceChart,
              let images = chart.sourceImages, images.count > 1 else { return [] }
        return images.dropFirst().compactMap {
            ShopCatalogChartReference.resolve($0) { store.asset(id: $0)?.originalURL }
        }
    }

    @ViewBuilder
    private var extraPriceChartImages: some View {
        let references = extraPriceChartImageReferences
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(references.enumerated()), id: \.offset) { index, reference in
                    ShopCatalogAssetImage(reference: reference, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: chartImageMaxHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(themeManager.tertiaryTextColor.opacity(0.25), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // 第 2 张起点开查看器时带上全部原图（含首图），可左右翻阅
                            var all: [String] = []
                            if case .ready(let firstRef) = priceChartPlan?.image {
                                all.append(firstRef)
                            }
                            all.append(contentsOf: references)
                            viewerReferences = all
                            viewerIndex = all.firstIndex(of: reference) ?? index + 1
                            showsViewer = true
                        }
                }
            }
        }
    }

    /// 无结构化内容时的兜底文案：区分「本来没有登记」「有图但没解析出表格」「有图但文件丢了」，
    /// 三种情况的用户动作完全不同，不能合成一句话。
    private func priceChartFallbackText(_ plan: ShopCatalogChartPresentation.Plan) -> String {        switch plan.image {
        case .none:
            return "暂无价格表数据".appLocalized
        case .ready:
            return "价格表图片已上传，但未能自动解析出表格内容，可在系列配置中手动补录；上方区间按本系列在售商品汇总".appLocalized
        case .unavailable:
            return "价格表图片已登记，但原图文件已丢失，请在系列配置中重新上传".appLocalized
        }
    }

    /// 原图展开后的最大高度：把「移动端 / 桌面端」的差异收敛在这一个数字上。
    ///   · compact（手机）：360pt，保证一张长尺码表不会单独吃掉整屏，价格与操作区仍在手边；
    ///   · regular（iPad / 桌面宽度）：520pt，宽幅尺码表能一次看全，不必依赖全屏查看器。
    private var chartImageMaxHeight: CGFloat {
        horizontalSizeClass == .regular ? 520 : 360
    }

    /// 图表原图内嵌展示（尺码表 / 价格表**共用**同一渲染）：
    ///   · `.ready` → 圆角图片（等比、限高），点击进全屏查看器放大（沿用商品图查看器）
    ///   · `.unavailable` → 明确提示重新上传，而不是渲染一张空白图
    ///   · `.none` → 不渲染
    @ViewBuilder
    private func chartImageBlock(_ state: ShopCatalogChartPresentation.ImageState,
                                 missingHint: String) -> some View {
        switch state {
        case .none:
            EmptyView()
        case .unavailable:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                Text(missingHint)
            }
            .font(.caption)
            .foregroundStyle(themeManager.tertiaryTextColor)
        case .ready(let ref):
            VStack(alignment: .leading, spacing: 6) {
                ShopCatalogAssetImage(reference: ref, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: chartImageMaxHeight)
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
    /// 加购弹窗口径（付定金 / 全款）；`showsEntryChoice = true` 时它是弹窗内的**默认选中项**
    @State private var entryOption: ShopCatalogWardrobeEntryOption = .depositPaid
    /// 弹窗是否显示「加入方式」选择段（2026-09-24：预约中 / 预约已结束统一入口）
    @State private var showsEntryChoice = false
    @State private var actionToast: String?

    /// 打开加购确认页（金额一律由系统从后台档案读取，用户不填写）
    ///
    /// `showsChoice = true`：阶段化统一入口 —— 弹窗内先展示「加入方式」选择段
    /// （候选按阶段规则给出 + 默认选中），用户选定并确认后才落库；
    /// `showsChoice = false`：单口径直达（金额预览 + 确认）。
    private func openEntrySheet(_ option: ShopCatalogWardrobeEntryOption, showsChoice: Bool = false) {
        // 该口径取数所需的价格档案不存在 → 退回现货加购（多选确认页），
        // 不让用户点进一个必然「没有价格可记」的弹窗。
        let needsReservationPrice = option == .depositPaid || option == .fullPaid
        let needsStockPrice = option == .fullStockPaid
        if (needsReservationPrice && !hasReservationPrice) || (needsStockPrice && !hasStockPrice) {
            showsMergeSheet = true
            return
        }
        entryOption = option
        showsEntryChoice = showsChoice
        showsReservationSheet = true
    }

    /// 后台是否有预约价（定金 / 尾款的来源）
    private var hasReservationPrice: Bool {
        (store.priceArchive(forProduct: productID).currentReservationPrice ?? 0) > 0
    }

    /// 后台是否有现货价（现货阶段「按现货价全款加入」的取数来源）
    private var hasStockPrice: Bool {
        (store.priceArchive(forProduct: productID).currentStockPrice ?? 0) > 0
    }

    /// 该阶段是否要弹「加入方式」选择弹窗，以及默认选中哪一项。
    ///
    /// 唯一口径在 `ShopCatalogWardrobeEntryPolicy.defaultChoiceOption`，视图只做透传 ——
    /// 返回 nil = 该阶段没有可选项（无价格档案等），走各自的原路径。
    private func choiceDefault(
        for phase: ShopCatalogPurchasePhase
    ) -> ShopCatalogWardrobeEntryOption? {
        ShopCatalogWardrobeEntryPolicy.defaultChoiceOption(
            phase: phase,
            hasReservationPrice: hasReservationPrice,
            hasStockPrice: hasStockPrice
        )
    }

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
            // `isFinalPaymentPlan` = 已付定且仍有尾款待补（全款入橱不算「在心愿尾款中」）
            let awaitingFinalPayment = existing.isFinalPaymentPlan
            VStack(spacing: 6) {
                Label(
                    awaitingFinalPayment ? "已在心愿尾款中" : "已在少女衣橱中",
                    systemImage: awaitingFinalPayment ? "heart.fill" : "checkmark.seal.fill"
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
                        // 预约中（2026-09-24 需求）：主按钮 =【加入衣橱】→ 选择弹窗
                        //   · 两个选项：「加入心愿尾款（定金+尾款）」（**默认选中**）/
                        //     「预约价全款预约」；不得静默默认付款方式，必须选定并确认
                        //   · 弹窗内金额预览随所选口径联动（定金+尾款 vs 预约价全款）
                        // 【加入心愿】保留为次按钮（只收藏不开计划的能力不剥夺）
                        if let defaultOption = choiceDefault(for: .reservationActive) {
                            primaryButton(title: "加入衣橱", symbol: "tshirt.fill") {
                                openEntrySheet(defaultOption, showsChoice: true)
                            }
                            statusCaption("预约中：默认按「定金+尾款」记账，也可切换为预约价全款，在下一步弹窗中选择"
                                + reservationWindowCaptionSuffix
                                + balanceDueCaptionSuffix)
                            secondaryAction(title: "加入心愿", symbol: "heart.fill") {
                                addToWishlist(reminder: false)
                            }
                        } else {
                            primaryButton(title: "加入心愿", symbol: "heart.fill") {
                                addToWishlist(reminder: false)
                            }
                            statusCaption("预约中：加入心愿后，到「心愿尾款」随时准备付定金或尾款")
                        }
                    case .reservationUpcoming:
                        // 预约未开始：仍显示加入心愿，实际作用是开售提醒
                        primaryButton(title: "加入心愿", symbol: "heart") {
                            addToWishlist(reminder: true)
                        }
                        statusCaption("预约未开始：加入后将作为开售提醒，到点通知你来买")
                    case .inStock:
                        // 现货阶段（2026-09-24 需求）：定金 + 尾款阶段已经结束，**只提供全款**，
                        // 但两个价格口径由用户选：
                        //   ① 按预约价全款加入（`fullPaid`）② 按现货价全款加入（`fullStockPaid`）
                        // 两个选项都记为衣橱「已全款」、都不生成心愿尾款任务，
                        // 差别只在入橱金额取自哪份价格档案 —— 因此也不能静默默认，必须弹窗选定。
                        if let defaultOption = choiceDefault(for: .inStock) {
                            primaryButton(title: "加入衣橱", symbol: "tshirt.fill") {
                                openEntrySheet(defaultOption, showsChoice: true)
                            }
                            statusCaption("现货在售：仅按全款加入，可按预约价或现货价记清，在下一步弹窗中选择")
                        } else {
                            primaryButton(title: "加入少女衣橱", symbol: nil) {
                                showsMergeSheet = true
                            }
                            statusCaption("现货在售：可直接加入衣橱留存搭配")
                        }
                    case .reservationEnded:
                        // 预约已结束（2026-09-24 需求）：主按钮 =【加入衣橱】→ 选择弹窗
                        //   · 两个选项：「加入心愿尾款（定金+尾款）」/「预约价全款预约」
                        //     （**默认选中**全款——结束后多数是整笔补齐）；
                        //     两个选项在弹窗内同屏可选，不隐藏、不置灰 ——
                        //     「官方补款期 / 只交过定金 / 闲鱼全款收转单」仍能记定金 + 尾款
                        //     （2026-09-23「只改引导不剥夺能力」的裁定继续成立，形态从折叠区升级为选择弹窗）
                        endedTag
                        if let defaultOption = choiceDefault(for: .reservationEnded) {
                            primaryButton(
                                title: "加入衣橱",
                                symbol: "tshirt.fill"
                            ) {
                                openEntrySheet(defaultOption, showsChoice: true)
                            }
                            statusCaption("预约已结束：默认按后台预约价一次记清，也可切换为定金+尾款，在下一步弹窗中选择"
                                + reservationWindowCaptionSuffix
                                + balanceDueCaptionSuffix)
                        } else if hasStock {
                            primaryButton(title: "加入少女衣橱", symbol: nil) {
                                showsMergeSheet = true
                            }
                            statusCaption("预约已结束：现货在售，可加入衣橱留存")
                        } else {
                            statusCaption("预约已结束：本款已无法预约，也暂无现货")
                        }
                    case .balancePending:
                        // 尾款中（2026-09-24 需求三）：主按钮 =【加入衣橱】→ 选择弹窗
                        //   · 默认选中「加入心愿尾款（定金 + 尾款）」——这一阶段的动作就是补尾款；
                        //   · 两个选项在弹窗内同屏可选，不隐藏、不置灰
                        //     （2026-09-23「只改引导不剥夺能力」继续成立）。
                        //   与「预约已结束」的唯一差别就是这里的默认选中项。
                        balanceDueTag
                        if let defaultOption = choiceDefault(for: .balancePending) {
                            primaryButton(title: "加入衣橱", symbol: "tshirt.fill") {
                                openEntrySheet(defaultOption, showsChoice: true)
                            }
                            statusCaption("尾款中：默认按「定金 + 尾款」记账（补尾款），也可切换为预约价全款，在下一步弹窗中选择"
                                + balanceDueCaptionSuffix)
                        } else if hasStock {
                            primaryButton(title: "加入少女衣橱", symbol: nil) {
                                showsMergeSheet = true
                            }
                            statusCaption("尾款中：现货在售，可加入衣橱留存")
                        } else {
                            statusCaption("尾款中：正在收尾款，暂无现货价")
                        }
                    case .neutral:
                        // 无任何上新窗口：只看价格档案给全款口径；
                        // 什么都没有时仅保留入库入口
                        if let defaultOption = choiceDefault(for: .neutral) {
                            primaryButton(title: "加入衣橱", symbol: "tshirt.fill") {
                                openEntrySheet(defaultOption, showsChoice: true)
                            }
                            statusCaption("可按预约价或现货价全款记清，在下一步弹窗中选择")
                        } else {
                            primaryButton(title: "加入少女衣橱", symbol: nil) {
                                showsMergeSheet = true
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showsReservationSheet) {
                // 阶段一并带进弹窗：候选列表与文案都按它取（现货阶段 = 两个全款价格口径）
                ShopCatalogReservationSheet(productID: productID,
                                            option: entryOption,
                                            showsEntryChoice: showsEntryChoice,
                                            phase: product.map { purchasePhase(for: $0.id) } ?? .neutral)
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

    /// 「其他记账方式」折叠区已升级为**选择弹窗**（2026-09-24 需求）：
    /// 原折叠区（2026-09-23 需求二「全款为主，定金尾款为隐藏备用」）的两个口径现在都住在
    /// 加购弹窗的「加入方式」选择段里——仍是**一次点击可达、同屏可选、不隐藏不置灰**，
    /// 「官方补款期 / 只交过定金 / 闲鱼全款收转单」的记账能力完整保留。

    // MARK: 购买阶段（按预约状态条件渲染的依据）

    private func purchasePhase(for productID: String) -> ShopCatalogPurchasePhase {
        // 1. 系列层「发售阶段」优先（2026-09-23 需求二）：运营在系列上显式声明，
        //    并且「过了预约结束时间」会自动流转为「预约已结束」（读取时判定，见
        //    `CatalogSeriesSalePhaseResolver` 的类型注释）。
        //
        //    未声明（旧数据 salePhase == nil）→ 落到下面第 2 步的档期推导，
        //    行为与改动前完全一致（不需要给存量系列做任何数据迁移）。
        // 2. 既有口径：按销售事件档期推导
        if let series,
           let declared = CatalogSeriesSalePhaseResolver.effectivePhase(of: series, now: Date()) {
            // 生效阶段由「声明 + 预约结束时间 + 尾款时间 + 当前时间」共同决定（读取时判定）：
            // 具体尾款时间到点 → 尾款中；无尾款时间则维持既有流转（预约中 → 预约已结束）。
            switch declared {
            case .reservationActive: return .reservationActive
            case .reservationEnded: return .reservationEnded
            case .balancePending: return .balancePending
            case .inStock: return .inStock
            }
        }
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

    /// 置灰的「尾款中」标签（同 `endedTag`，非按钮），并带上系列声明的尾款时间
    private var balanceDueTag: some View {
        Label(balanceDueTagText, systemImage: "creditcard.fill")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(balanceDueTagText)
    }

    /// 「尾款中」标签文案（含尾款期，若运营填过）——只在系列级数据里取，不落任何本地状态
    private var balanceDueTagText: String {
        guard let series, let value = CatalogSeriesBalanceDue.valueText(of: series) else {
            return "尾款中"
        }
        let label = CatalogSeriesBalanceDue.hasDeclaredEnd(of: series) ? "尾款期" : "尾款时间"
        return "尾款中 · \(label)：\(value)"
    }

    /// 状态说明里追加的尾款时间后缀（未声明尾款时间 → 空串，不产生多余标点）
    private var balanceDueCaptionSuffix: String {
        guard let series, let value = CatalogSeriesBalanceDue.valueText(of: series) else { return "" }
        // 「尾款期」还是「尾款时间」看有没有声明结束（2026-09-24 需求五）
        return CatalogSeriesBalanceDue.hasDeclaredEnd(of: series)
            ? "；尾款期：\(value)" : "；尾款时间：\(value)"
    }

    /// 状态说明里追加的预约期后缀（未声明 → 空串）。2026-09-24 需求五：预约中
    /// 同时有开始与结束，商品页就把整段预约期如实说明出来。
    private var reservationWindowCaptionSuffix: String {
        guard let series, let window = CatalogSeriesReservationWindow.windowText(of: series) else { return "" }
        return "；预约期：\(window)"
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
/// 规则（对应运营口径，分支候选一律走 `ShopCatalogWardrobeEntryPolicy`）：
/// · 预约中 → 【加入衣橱】→ 选择弹窗（定金+尾款 / 预约价全款）+【加入心愿】次按钮
/// · 预约未开始 → 【加入心愿】（实际作用 = 开售提醒）
/// · 预约已结束 / 尾款中 → 置灰阶段标签 +【加入衣橱】→ 选择弹窗（默认分别是全款 / 定金+尾款）
/// · **现货在售 → 【加入衣橱】→ 选择弹窗，仅全款、两个价格口径（按预约价 / 按现货价）**；
///   没有任何价格档案时才退回「加入少女衣橱」（多选确认页）
enum ShopCatalogPurchasePhase: Equatable {
    case reservationActive   // 预约中
    case reservationUpcoming // 预约未开始（加入心愿 = 开售提醒）
    case inStock             // 现货在售
    case reservationEnded    // 预约已结束
    /// 尾款中（2026-09-24 需求三）：系列声明的结算期 —— 预约窗口已关、正在收尾款。
    /// 与 `reservationEnded` 的区别是**加购引导**：这里主推定金 + 尾款（补尾款的动作），
    /// 所以不能塌缩成 `reservationEnded`，否则默认选中会变成「预约价全款预约」。
    case balancePending
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
            if references.isEmpty {
                // 空引用兜底（2026-09-24 黑屏根因修复）：调用方传空数组时
                // TabView 零页面 → 纯黑屏 +「1 / 0」计数（用户看到的正是这个）。
                // 这里给明确提示，保证任何调用方都不会再渲染出无内容的黑屏。
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("暂无可查看的图片".appLocalized)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
            } else {
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
            }

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
                    if !references.isEmpty {
                        Text("\(page + 1) / \(references.count)")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
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

// MARK: - 加购记账确认（需求 N §II：金额自动读取，用户不输入）

/// 加购记账确认页：商品 / 店家 / 系列自动带入；颜色、尺码可选；
/// **金额一律只读展示**——预约价、已付定金、待付尾款、本次入橱金额全部取后台价格档案。
/// 需求 §I 核心原则：所有金额必须由系统自动读取后台数据，绝对不能让用户手动输入。
///
/// 三个阶段 / 四种口径（需求 §II + 2026-09-24 现货阶段）：
///   · `.depositPaid`    支付定金 → 衣橱「已付定」，心愿尾款里自动生成待补任务
///   · `.fullPaid`       全款（金额 = 后台**预约价**）→ 衣橱「已全款」，**绝不生成**任何心愿尾款任务
///   · `.fullStockPaid`  全款（金额 = 后台**现货价**）→ 同样「已全款」、同样不生成尾款任务
///                       （现货阶段的两个价格口径，差别只在入橱金额取自哪份档案）
struct ShopCatalogReservationSheet: View {
    let productID: String
    /// 加购口径（默认付定金）；`showsEntryChoice = true` 时作为**默认选中项**
    var option: ShopCatalogWardrobeEntryOption = .depositPaid
    /// 显示「加入方式」选择段（2026-09-24 需求：预约中 / 预约已结束 / 尾款中 / 现货的统一入口弹窗——
    /// **不得静默默认**任何付款方式直接加入，必须先选定并确认后才落库）
    var showsEntryChoice: Bool = false
    /// 当前购买阶段：选择段候选与选项文案的唯一依据（由详情页按同一份阶段口径传入）
    var phase: ShopCatalogPurchasePhase = .reservationEnded

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared

    /// 当前生效的加购口径：选择段里用户可切换（默认选中 = 外部按阶段规则传入）
    @State private var selectedOption: ShopCatalogWardrobeEntryOption = .depositPaid
    /// 防御：候选与选中项必须自洽（候选随阶段 / 价格档案变化），
    /// 选中的那一项万一不在候选里就退回候选第一项 ——
    /// 否则确认按钮会按一个界面上根本看不到的口径落库。
    private var effectiveOption: ShopCatalogWardrobeEntryOption {
        if !showsEntryChoice || choiceOptions.contains(selectedOption) { return selectedOption }
        return choiceOptions.first ?? selectedOption
    }

    @State private var selectedColor: String?
    @State private var selectedSize: String?
    /// 尾款时间：nil = 待公布（仅付定金口径可设）
    @State private var hasTailDate = false
    @State private var tailDate = Date()
    @State private var errorText: String?

    private var product: CatalogProduct? { store.product(id: productID) }
    private var series: CatalogSeries? { product.map { store.series(id: $0.seriesID) } ?? nil }
    private var shop: CatalogShop? { series.map { store.shop(id: $0.shopID) } ?? nil }
    private var archive: CatalogPriceArchive {
        store.priceArchive(forProduct: productID)
    }

    /// 后台预约价（= 定金 + 尾款总和）；「预约价全款」口径的入橱金额
    private var reservationPrice: Decimal { archive.currentReservationPrice ?? 0 }
    /// 后台现货价；「现货价全款」口径的入橱金额
    private var stockPrice: Decimal { archive.currentStockPrice ?? 0 }
    private var hasReservationPrice: Bool { reservationPrice > 0 }
    private var hasStockPrice: Bool { stockPrice > 0 }
    /// 后台已付定金（只读：用户已经付给店家的钱，系统自己算）
    private var backendDeposit: Decimal { min(max(0, archive.currentDeposit ?? 0), reservationPrice) }
    /// 待付尾款（全款口径为 0，因为不存在待补任务）
    ///
    /// 走 `ShopCatalogWardrobeAmount`（需求 §II「尾款金额自动读取后台录入的『尾款』数据」），
    /// 与落库用的 `ShopCatalogWardrobeDraftBuilder` **同一份算法**——
    /// 弹窗上显示的待补金额必须等于最终写到心愿尾款里的金额。
    private var pendingBalance: Decimal {
        guard !isFullPaid else { return 0 }
        return ShopCatalogWardrobeAmount.pendingBalance(
            backendBalance: archive.currentBalance,
            reservationPrice: reservationPrice,
            depositPaid: backendDeposit
        )
    }
    /// 本次入橱记账金额（按所选口径取自对应价格档案，用户零输入）
    private var entryAmount: Decimal {
        switch effectiveOption {
        case .fullPaid: return reservationPrice
        case .fullStockPaid: return stockPrice
        case .depositPaid, .wishlist: return backendDeposit
        }
    }
    /// 是否「全款一次记清」口径（两个价格口径都算）
    private var isFullPaid: Bool { effectiveOption.isFullPayment }
    /// 全款口径的金额来源文案（预览与底注共用，保证两处口径一致）
    private var fullPaymentBasisText: String {
        effectiveOption == .fullStockPaid ? "现货价" : "预约价"
    }

    /// 选择段候选：唯一来源是阶段化策略（现货阶段 = 两个全款价格口径）——
    /// 视图不再自己写死 `[.depositPaid, .fullPaid]`，否则策略改了界面不动。
    private var choiceOptions: [ShopCatalogWardrobeEntryOption] {
        ShopCatalogWardrobeEntryPolicy.options(
            phase: phase,
            hasReservationPrice: hasReservationPrice,
            hasStockPrice: hasStockPrice
        )
    }

    /// 尺码候选：款式共享口径（同款任一颜色填过尺码表 → 这里就有；2026-09-23）
    private var sizeRun: [String] { store.sizeRun(forProduct: productID) }

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    LabeledContent("商品", value: product?.name ?? "")
                    LabeledContent("店家", value: shop?.name ?? "—")
                    LabeledContent("系列", value: series.map { "\($0.name)\($0.yearMonthText.map { " · \($0)" } ?? "")" } ?? "—")
                }
                if showsEntryChoice && !choiceOptions.isEmpty {
                    // 加入方式选择段（2026-09-24 需求）：候选与默认选中都按阶段策略取 ——
                    //   · 预约中 / 预约已结束 / 尾款中：定金+尾款 / 预约价全款
                    //   · 现货阶段：仅全款，两个价格口径（预约价 / 现货价）
                    // 用户**必须在此选定**，下方金额预览与确认按钮随所选口径实时联动 ——
                    // 不存在静默默认路径
                    Section(phase == .inStock ? "全款计价方式" : "加入方式") {
                        ForEach(choiceOptions, id: \.self) { candidate in
                            entryChoiceRow(
                                option: candidate,
                                isSelected: selectedOption == candidate
                            ) { selectedOption = candidate }
                        }
                    }
                }
                if !store.colors(forProduct: productID).isEmpty {
                    Section("配色") {
                        chipGrid(store.colors(forProduct: productID), selection: $selectedColor)
                    }
                }
                if !sizeRun.isEmpty {
                    Section("尺码") {
                        chipGrid(sizeRun, selection: $selectedSize)
                    }
                }
                Section("金额（自动读取，无需填写）") {
                    if hasReservationPrice {
                        LabeledContent("预约价", value: ShopCatalogFormat.price(reservationPrice))
                        LabeledContent("已付定金", value: ShopCatalogFormat.price(backendDeposit))
                    }
                    // 现货价行：现货阶段的第二个价格口径要靠它对比（没有就不显示，避免空行）
                    if hasStockPrice {
                        LabeledContent("现货价", value: ShopCatalogFormat.price(stockPrice))
                    }
                    LabeledContent("待付尾款", value: ShopCatalogFormat.price(pendingBalance))
                        .foregroundStyle(isFullPaid ? themeManager.secondaryTextColor : themeManager.accentTextColor)
                    LabeledContent(isFullPaid ? "本次入橱（全款·\(fullPaymentBasisText)）" : "本次入橱（已付定）",
                                   value: ShopCatalogFormat.price(entryAmount))
                        .foregroundStyle(themeManager.accentTextColor)
                    // 全款口径不生成任何尾款任务，因此也不提供尾款时间设置
                    if !isFullPaid {
                        Toggle("已公布尾款时间", isOn: $hasTailDate.animation())
                        if hasTailDate {
                            DatePicker("尾款时间", selection: $tailDate, displayedComponents: .date)
                        }
                    }
                }
                Section {
                    Button {
                        confirmEntry()
                    } label: {
                        Text(isFullPaid ? "确认全款入橱（已全款）" : "确认定金入橱（已付定）")
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
                    Text(isFullPaid
                         ? "全款入橱：按后台\(fullPaymentBasisText)一次记清，衣橱记为「已全款」，**不会**生成任何心愿尾款任务。"
                         : "定金入橱：按后台已付定金记账，尾款自动进入心愿尾款等你补款。")
                }
            }
            .navigationTitle(showsEntryChoice
                             ? "加入衣橱"
                             : (isFullPaid ? "全款加购" : "付定金加购"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                store.loadFromBundleIfNeeded()
                // 默认选中 = 外部按「阶段化默认口径」传入的选项（预约中 → 心愿尾款；
                // 预约已结束 → 全款预约）；选择段内用户可随时切换
                selectedOption = option
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

    /// 选择段的单个选项行（radio 风格：圆圈 + 标题 + 一句话说明）
    private func entryChoiceRow(option: ShopCatalogWardrobeEntryOption,
                                isSelected: Bool,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color.pink : Color.secondary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ShopCatalogWardrobeEntryPolicy.choiceTitle(for: option, phase: phase))
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text(ShopCatalogWardrobeEntryPolicy.choiceCaption(for: option))
                        .font(.system(size: 11))
                        .foregroundStyle(themeManager.secondaryTextColor)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private func confirmEntry() {
        guard effectiveOption != .wishlist else { return }
        // 取数校验按**所选口径**判：现货价全款只要求有现货价，其余口径要求有预约价
        let requiredPrice = effectiveOption == .fullStockPaid ? stockPrice : reservationPrice
        guard requiredPrice > 0 else {
            errorText = effectiveOption == .fullStockPaid
                ? "该商品没有现货价档案，无法加购"
                : "该商品没有预约价档案，无法加购"
            return
        }
        let priceMode: ShopCatalogWardrobeDraftBuilder.PriceMode
        switch effectiveOption {
        case .fullPaid: priceMode = .fullReservation
        case .fullStockPaid: priceMode = .fullStock
        case .depositPaid, .wishlist: priceMode = .reservation(depositPaid: backendDeposit)
        }
        let selection = ShopCatalogWardrobeDraftBuilder.Selection(
            productID: productID,
            color: selectedColor,
            size: selectedSize,
            priceMode: priceMode
        )
        guard var draft = ShopCatalogWardrobeDraftBuilder.makeDraft(
            selection: selection,
            store: store, modelContext: modelContext
        ) else {
            errorText = "生成衣橱记录失败"
            return
        }
        // §17：尾款时间可设置；未设置 = 待公布（沿用草稿里的占位）。
        // 全款口径没有尾款任务，不写尾款时间。
        if !isFullPaid, hasTailDate {
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
