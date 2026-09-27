//
//  OpsProductsView.swift
//  PinkHouseOps
//
//  商品管理：**商品是操作单位**（方案 §4）。
//
//  ## 为什么「商品」要单独一个分区，而不是继续塞在店家/系列的三栏里
//
//  三栏联动适合回答「这个系列下有哪些商品」；但方案里说的「一次上新」做的
//  全是在单个商品上的动作 —— 补规格、写尺码表、记一条预约价、修一次价、
//  绑图、归档。这些动作有十来个字段、五六个子表，塞进三栏的最右列会变成
//  一个又窄又长的表单，运营每次都要在一列 300pt 宽的地方填尺码表。
//
//  所以分工是：
//    · 「店家与系列」= 结构视角（谁挂在谁下面、系列档期与价格表）；
//    · 「商品管理」  = 内容视角（这一个商品的完整档案）。
//
//  ## 三条从方案里带过来的硬约束（都在这一页的交互上落地）
//
//  1. **修正 ≠ 追加**：销售记录只能「追加」，价格修正只能「覆盖当前状态」。
//     本页把两者放在**两张卡**里、按钮文案也不同（「追加一条记录」vs「应用修正」），
//     并且价格修正的表单里明确写「留空 = 清除这一项」—— 因为它是完整快照语义。
//  2. **删除靠归档**：商品不给「删除」，只有「归档 / 恢复」。归档条目在发布时
//     被剥离（线上下架），本机还留着可追溯。
//  3. **改名是款式级，Mac 端不复制那套口径**：已上线过的商品改名会被
//     `updateProduct` 拒绝并说明去哪改；本页把「编辑归属与命名」的入口留着，
//     让运营**当场看到那条拒绝原因**，而不是以为 App 坏了。
//

import SwiftUI

struct OpsProductsView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var selectedProductID: String?
    @State private var shopFilter = ""
    @State private var searchText = ""
    @State private var includeArchived = true
    @State private var sheet: ProductSheet?

    var body: some View {
        HSplitView {
            listColumn
            detailColumn
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .edit(let productID):
                ProductIdentitySheet(workspace: workspace, productID: productID)
            case .detailForm(let productID):
                ProductDetailSheet(workspace: workspace, productID: productID)
            case .bindImages(let productID):
                ProductImagesSheet(workspace: workspace, productID: productID)
            case .variantForm(let productID, let variantID):
                VariantFormSheet(workspace: workspace, productID: productID, variantID: variantID)
            case .sizeChart(let productID):
                SizeChartFormSheet(workspace: workspace, productID: productID)
            case .saleEvent(let productID):
                SaleEventFormSheet(workspace: workspace, productID: productID)
            case .priceCorrection(let productID):
                PriceCorrectionFormSheet(workspace: workspace, productID: productID)
            case .copySizeChart(let productID):
                CopySizeChartSheet(workspace: workspace, sourceProductID: productID)
            case .duplicate(let productID):
                DuplicateProductSheet(workspace: workspace, productID: productID)
            }
        }
        .onAppear { clampSelection() }
        // 选择态按 ID 收敛（R06）：只盯 count 会漏掉「商品数刚好相同」的切换
        .onChange(of: shopFilter) { _, _ in clampSelection() }
        .onChange(of: includeArchived) { _, _ in clampSelection() }
        .onChange(of: workspace.catalog.products.count) { _, _ in clampSelection() }
        .onChange(of: workspace.catalog.shops.count) { _, _ in clampSelection() }
    }

    // MARK: 派生

    private var filteredProducts: [CatalogProduct] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return workspace.catalog.products.filter { product in
            if !shopFilter.isEmpty, product.shopID != shopFilter { return false }
            if !includeArchived, product.archivedAt != nil { return false }
            guard !query.isEmpty else { return true }
            return product.name.lowercased().contains(query)
                || product.category.lowercased().contains(query)
                || (product.designName?.lowercased().contains(query) ?? false)
        }
    }

    private var selectedProduct: CatalogProduct? {
        guard let selectedProductID else { return nil }
        return workspace.catalog.products.first { $0.id == selectedProductID }
    }

    private func clampSelection() {
        if !filteredProducts.contains(where: { $0.id == selectedProductID }) {
            selectedProductID = filteredProducts.first?.id
        }
    }

    // MARK: 左：商品列表

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("商品").font(.headline)
                    Text("\(filteredProducts.count)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: 4)
                    Button {
                        sheet = .edit(newProductIDPlaceholder)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(workspace.catalog.series.isEmpty)
                    .help(workspace.catalog.series.isEmpty
                          ? "先在「店家与系列」里建好店家与系列"
                          : "新增商品")
                }
                Picker("店家", selection: $shopFilter) {
                    Text("全部店家").tag("")
                    ForEach(workspace.catalog.shops) { shop in
                        Text(shop.name).tag(shop.id)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                TextField("搜索商品名 / 品类 / 款式名", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Toggle("显示已归档", isOn: $includeArchived)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()

            if filteredProducts.isEmpty {
                Text(workspace.catalog.products.isEmpty
                     ? "还没有商品。先到「店家与系列」建好结构，再回到这里新增商品。"
                     : "没有符合条件的商品。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
            } else {
                List(selection: $selectedProductID) {
                    ForEach(filteredProducts) { product in
                        productRow(product).tag(product.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .frame(minWidth: 240, idealWidth: 280)
    }

    /// 「新增」的占位 id：`ProductIdentitySheet` 用 nil 走新建路径。
    /// 这里不用可选 case 是为了让 `ProductSheet` 的 id 稳定（同一 sheet 不重建）。
    private var newProductIDPlaceholder: String { "" }

    private func productRow(_ product: CatalogProduct) -> some View {
        let tags = workspace.publicationTags(forProduct: product.id)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(product.name).lineLimit(1)
                if product.archivedAt != nil {
                    OpsTag(text: "已归档", tint: .orange)
                }
            }
            HStack(spacing: 6) {
                Text(workspace.seriesName(for: product.seriesID))
                    .lineLimit(1)
                if !product.category.isEmpty { Text("· \(product.category)") }
                Text("· \(product.images.count) 图")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        OpsTag(text: tag, tint: tag == "已归档" ? .orange : .accentColor)
                    }
                }
            }
        }
        .opacity(product.archivedAt == nil ? 1 : 0.6)
        .contextMenu {
            Button("编辑归属与命名…") { sheet = .edit(product.id) }
            Button("绑定商品图…") { sheet = .bindImages(product.id) }
            Button("复制这个商品…") { sheet = .duplicate(product.id) }
            Divider()
            if product.archivedAt == nil {
                Button("归档（下线）") {
                    workspace.setArchived(true, kind: .product, id: product.id)
                    clampSelection()
                }
            } else {
                Button("恢复上线") {
                    workspace.setArchived(false, kind: .product, id: product.id)
                }
            }
        }
    }

    // MARK: 右：商品档案

    @ViewBuilder
    private var detailColumn: some View {
        if let product = selectedProduct {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    productHeader(product)
                    identityCard(product)
                    detailCard(product)
                    imagesCard(product)
                    variantsCard(product)
                    sizeChartCard(product)
                    saleEventsCard(product)
                    priceCard(product)
                    changeCard(product)
                    dangerCard(product)
                }
                .padding(18)
                .frame(maxWidth: 860, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("左侧选一个商品，或点右上角「+」新增。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)
        }
    }

    private func productHeader(_ product: CatalogProduct) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(product.name).font(.title3.weight(.semibold))
                if !product.category.isEmpty { OpsTag(text: product.category, tint: .accentColor) }
                if product.archivedAt != nil { OpsTag(text: "已归档", tint: .orange) }
                Spacer(minLength: 4)
            }
            OpsFootnote(text: "\(workspace.shopName(for: product.shopID)) › "
                        + "\(workspace.seriesName(for: product.seriesID))　·　"
                        + "商品 ID：\(product.id)")
        }
    }

    // MARK: 归属与命名

    private func identityCard(_ product: CatalogProduct) -> some View {
        OpsCard(title: "归属与命名", systemImage: "tag") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("店家", value: workspace.shopName(for: product.shopID))
                LabeledContent("系列", value: workspace.seriesName(for: product.seriesID))
                LabeledContent("商品名", value: product.name)
                LabeledContent("品类", value: product.category.isEmpty ? "（未填）" : product.category)
                HStack(spacing: 10) {
                    Button("编辑…") { sheet = .edit(product.id) }
                    OpsFootnote(text: "已上线过的商品改名会被拒绝 —— 改名是款式级口径，"
                                + "Mac 端不复制它（避免和 iOS 出现两套规则）。")
                }
            }
        }
    }

    // MARK: 详情

    private func detailCard(_ product: CatalogProduct) -> some View {
        OpsCard(title: "卖点描述与款式名", systemImage: "text.alignleft") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("款式名",
                               value: (product.designName?.isEmpty == false)
                                   ? (product.designName ?? "") : "（未填）")
                Text(product.description?.isEmpty == false
                     ? (product.description ?? "") : "（没有描述）")
                    .font(.callout)
                    .foregroundStyle(product.description?.isEmpty == false
                                     ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                Button("编辑…") { sheet = .detailForm(product.id) }
            }
        }
    }

    // MARK: 图片（有序）

    private func imagesCard(_ product: CatalogProduct) -> some View {
        OpsCard(title: "商品图（\(product.images.count)）", systemImage: "photo.stack") {
            VStack(alignment: .leading, spacing: 10) {
                if product.images.isEmpty {
                    Text("还没有绑定商品图。发布门禁会因为「商品没有图」而拦下这次发布。")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(product.images.enumerated()), id: \.offset) { index, assetID in
                                VStack(spacing: 3) {
                                    OpsThumbnail(url: workspace.stagedFileURL(
                                        forReference: workspace.asset(for: assetID)?.originalURL),
                                                 size: 72)
                                    Text(index == 0 ? "首图" : "\(index + 1)")
                                        .font(.caption2)
                                        .foregroundStyle(index == 0 ? Color.accentColor : .secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        sheet = .bindImages(product.id)
                    } label: {
                        Label("调整顺序 / 绑定图片", systemImage: "photo.badge.plus")
                    }
                    .disabled(workspace.catalog.assets.isEmpty)
                    if workspace.catalog.assets.isEmpty {
                        OpsFootnote(text: "还没有可用图片：先在「系列上新」导入商品图。")
                    }
                }
                OpsFootnote(text: "这个顺序**只属于这个商品**（第一张是首图），"
                            + "与可用图片列表的排列顺序无关。")
            }
        }
    }

    // MARK: 规格

    private func variantsCard(_ product: CatalogProduct) -> some View {
        let variants = workspace.variants(forProduct: product.id)
        return OpsCard(title: "规格（配色 / 尺码）· \(variants.count)", systemImage: "square.on.square") {
            VStack(alignment: .leading, spacing: 8) {
                if variants.isEmpty {
                    Text("没有规格。单规格商品可以不填；多色多码（SKU）请逐条录入。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(variants.enumerated()), id: \.element.id) { _, variant in
                            HStack(spacing: 8) {
                                OpsThumbnail(url: workspace.stagedFileURL(
                                    forReference: variant.imageAssetID.flatMap {
                                        workspace.asset(for: $0)?.originalURL
                                    }),
                                             size: 30)
                                Text(workspace.variantLabel(color: variant.color, size: variant.size))
                                    .font(.callout)
                                Spacer(minLength: 4)
                                if variant.imageAssetID == nil {
                                    OpsTag(text: "无规格图", tint: .orange)
                                }
                                Button("编辑") {
                                    sheet = .variantForm(product.id, variant.id)
                                }
                                .buttonStyle(.link).font(.caption)
                                Button("删除") {
                                    workspace.removeVariant(id: variant.id)
                                }
                                .buttonStyle(.link).font(.caption)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                Button {
                    sheet = .variantForm(product.id, nil)
                } label: {
                    Label("新增规格", systemImage: "plus")
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: 尺码表

    private func sizeChartCard(_ product: CatalogProduct) -> some View {
        let chart = workspace.sizeChart(forProduct: product.id)
        return OpsCard(title: "尺码表", systemImage: "ruler") {
            VStack(alignment: .leading, spacing: 8) {
                if let chart {
                    LabeledContent("单位", value: chart.unit ?? "（未填）")
                    LabeledContent("结构", value: chart.hasStructuredContent
                                   ? "\(chart.columns.count) 列 · \(chart.rows.count) 行"
                                   : "只有原图，没有结构化数据")
                    if chart.hasStructuredContent {
                        Text(chart.columns.joined(separator: " ｜ "))
                            .font(.caption).monospaced()
                            .foregroundStyle(.secondary)
                        ForEach(Array(chart.rows.enumerated()), id: \.offset) { _, row in
                            Text(row.label + "：" + row.values.map { $0 ?? "-" }.joined(separator: " ｜ "))
                                .font(.caption2).monospaced()
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let source = chart.sourceImage {
                        HStack(spacing: 8) {
                            OpsThumbnail(url: workspace.stagedFileURL(
                                forReference: workspace.asset(for: source)?.originalURL), size: 48)
                            OpsFootnote(text: "尺码表原图（结构化数据与原图缺一不可）")
                        }
                    }
                } else {
                    Text("这个商品还没有尺码表。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {
                        sheet = .sizeChart(product.id)
                    } label: {
                        Label(chart == nil ? "录入尺码表" : "编辑尺码表",
                              systemImage: "square.and.pencil")
                    }
                    .controlSize(.small)
                    Button("复制到其它商品…") { sheet = .copySizeChart(product.id) }
                        .controlSize(.small)
                        .disabled(chart == nil)
                        .help(chart == nil ? "这个商品还没有尺码表，没有可复制的内容" : "显式点名要复制到哪几个商品")
                    if chart != nil {
                        Button("清除尺码表") {
                            workspace.clearSizeChart(productID: product.id)
                        }
                        .controlSize(.small)
                    }
                }
                OpsFootnote(text: "Mac 端按**商品**存尺码表：不做款式级自动归一化。"
                            + "同款多色要共用一张表，用「复制到其它商品」显式点名。")
            }
        }
    }

    // MARK: 销售记录（只增）

    private func saleEventsCard(_ product: CatalogProduct) -> some View {
        let events = workspace.saleEvents(forProduct: product.id)
        return OpsCard(title: "销售记录（只追加）· \(events.count)", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 8) {
                if events.isEmpty {
                    Text("还没有价格记录。预约价 / 现货价 / 再贩都记在这里，一条都不覆盖。")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                OpsTag(text: event.type.displayName, tint: .accentColor)
                                Text(CatalogMoney(amount: event.price,
                                                  currency: event.effectiveCurrency).displayText)
                                    .font(.callout.weight(.medium))
                                if let deposit = event.deposit {
                                    Text("定金 " + CatalogMoney(
                                        amount: deposit, currency: event.effectiveCurrency).displayText)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if let balance = event.balance {
                                    Text("尾款 " + CatalogMoney(
                                        amount: balance, currency: event.effectiveCurrency).displayText)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                            }
                            Text(recordSubtitle(event))
                                .font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 3)
                        Divider()
                    }
                }
                Button {
                    sheet = .saleEvent(product.id)
                } label: {
                    Label("追加一条记录", systemImage: "plus")
                }
                .controlSize(.small)
                OpsFootnote(text: "「改价格」不走这里 —— 改当前价格用下面的「价格修正」。"
                            + "两张卡是两条流程、两份存储，混在一起会丢历史。")
            }
        }
    }

    private func recordSubtitle(_ event: CatalogSaleEvent) -> String {
        var parts: [String] = []
        if let batch = event.batchLabel, !batch.isEmpty { parts.append("批次 \(batch)") }
        if let start = event.startAt {
            parts.append(start.formatted(date: .abbreviated, time: .omitted))
        }
        parts.append("币种 \(event.effectiveCurrency.displayName)")
        if let recorded = event.recordedAt {
            parts.append("录入 " + recorded.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: 价格（当前状态）

    private func priceCard(_ product: CatalogProduct) -> some View {
        let archive = workspace.priceArchive(forProduct: product.id)
        return OpsCard(title: "当前价格", systemImage: "yensign.circle") {
            VStack(alignment: .leading, spacing: 8) {
                if let archive {
                    let currency = archive.currentCurrency
                    LabeledContent("预约价", value: moneyText(archive.currentReservationPrice, currency))
                    LabeledContent("现货价", value: moneyText(archive.currentStockPrice, currency))
                    LabeledContent("定金", value: moneyText(archive.currentDeposit, currency))
                    LabeledContent("尾款", value: moneyText(archive.currentBalance, currency))
                    if let percent = archive.stockOverReservationDeltaPercent {
                        LabeledContent("现货较预约", value: String(format: "%+.1f%%", percent))
                    } else if let reason = archive.deltaUnavailableReason {
                        LabeledContent("现货较预约", value: reason)
                    }
                    LabeledContent("币种", value: currency?.displayName ?? "未确定")
                    LabeledContent("来源", value: archive.isCorrected
                                   ? "含价格修正（覆盖在当前状态上）"
                                   : "由销售记录推导")
                    if archive.isCrossCurrency {
                        Label("这个商品的记录里出现了多种币种，差价与合计不可比。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("找不到这个商品的价格档案。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {
                        sheet = .priceCorrection(product.id)
                    } label: {
                        Label(product.priceCorrection == nil ? "应用价格修正…" : "修改价格修正…",
                              systemImage: "pencil.and.outline")
                    }
                    .controlSize(.small)
                    Button("撤销修正") {
                        workspace.clearPriceCorrection(productID: product.id)
                    }
                    .controlSize(.small)
                    .disabled(product.priceCorrection == nil)
                    .help("删除修正对象 → 当前价格回退到销售记录推导值")
                }
                OpsFootnote(text: "价格修正是一份**完整快照**：表单里留空的那一项会被**清除**"
                            + "（显示「暂无」），不会回退到历史推导。想回退请用「撤销修正」。")
            }
        }
    }

    private func moneyText(_ amount: Decimal?, _ currency: CatalogCurrency?) -> String {
        guard let amount else { return "暂无" }
        return CatalogMoney(amount: amount, currency: currency ?? .unknown).displayText
    }

    // MARK: 变更与发布状态

    private func changeCard(_ product: CatalogProduct) -> some View {
        let tags = workspace.publicationTags(forProduct: product.id)
        let changeSet = workspace.changeSet
        let kinds: [ShopCatalogEntityKind] = [.product, .variant, .sizeChart, .saleEvent]
        return OpsCard(title: "本地变更与线上状态", systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if tags.isEmpty {
                        OpsFootnote(text: "这个商品与基线一致（或还没有基线）。")
                    } else {
                        ForEach(tags, id: \.self) { tag in
                            OpsTag(text: tag, tint: tag == "已归档" || tag == "已下架" ? .orange : .accentColor)
                        }
                    }
                }
                Divider()
                OpsFootnote(text: changeSet.hasBaseline
                            ? "有基线快照：以上标签是**与线上基线逐条比对**得出的。"
                            : "还没有基线快照（从未回填过线上版本）：只能区分本地新增/修改。")
                ForEach(kinds, id: \.rawValue) { kind in
                    let delta = changeSet.delta(of: kind)
                    if !delta.isEmpty {
                        Text("\(kind.displayName)：新增 \(delta.addedIDs.count) · "
                             + "修改 \(delta.modifiedIDs.count) · 删除 \(delta.removedIDs.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if changeSet.hasBaseline {
                    OpsFootnote(text: "严格策略只作用在这些**动过**的条目上（"
                                + "\(changeSet.strictScopeIDs.count) 个 id）；存量旧数据按兼容口径走。")
                }
            }
        }
    }

    // MARK: 危险动作

    private func dangerCard(_ product: CatalogProduct) -> some View {
        OpsCard(title: "归档 / 复制", systemImage: "archivebox") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if product.archivedAt == nil {
                        Button {
                            workspace.setArchived(true, kind: .product, id: product.id)
                        } label: {
                            Label("归档（下线）", systemImage: "archivebox")
                        }
                    } else {
                        Button {
                            workspace.setArchived(false, kind: .product, id: product.id)
                        } label: {
                            Label("恢复上线", systemImage: "arrow.uturn.up")
                        }
                    }
                    Button {
                        sheet = .duplicate(product.id)
                    } label: {
                        Label("复制为新品…", systemImage: "doc.on.doc")
                    }
                }
                .controlSize(.small)
                OpsFootnote(text: "商品不提供「删除」：删掉会让引用悬空（客户端整包校验会拒绝）。"
                            + "归档是显式事实（何时下线），发布时会被剥离，本机仍可追溯。")
            }
        }
    }
}

// MARK: - sheet 载体（页面级一个枚举）

private enum ProductSheet: Identifiable {
    case edit(String)
    case detailForm(String)
    case bindImages(String)
    case variantForm(String, String?)
    case sizeChart(String)
    case saleEvent(String)
    case priceCorrection(String)
    case copySizeChart(String)
    case duplicate(String)

    var id: String {
        switch self {
        case .edit(let id): return "edit-\(id)"
        case .detailForm(let id): return "detail-\(id)"
        case .bindImages(let id): return "images-\(id)"
        case .variantForm(let id, let variantID): return "variant-\(id)-\(variantID ?? "new")"
        case .sizeChart(let id): return "chart-\(id)"
        case .saleEvent(let id): return "sale-\(id)"
        case .priceCorrection(let id): return "price-\(id)"
        case .copySizeChart(let id): return "copychart-\(id)"
        case .duplicate(let id): return "dup-\(id)"
        }
    }
}

// MARK: - 归属与命名表单

private struct ProductIdentitySheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss

    @State private var shopID = ""
    @State private var seriesID = ""
    @State private var name = ""
    @State private var category = ""

    private var isNew: Bool { productID.isEmpty }
    private var seriesOfShop: [CatalogSeries] {
        workspace.catalog.series.filter { $0.shopID == shopID }
    }

    var body: some View {
        OpsFormFrame(
            title: isNew ? "新增商品" : "编辑归属与命名",
            subtitle: isNew
                ? "商品是操作单位：一次上新里做的都是单个商品上的动作。"
                : "改动会递增编辑版本号，并作废上一次校验结果。",
            content: {
                Picker("店家", selection: $shopID) {
                    ForEach(workspace.catalog.shops) { shop in
                        Text(shop.name).tag(shop.id)
                    }
                }
                .onChange(of: shopID) { _, _ in
                    if !seriesOfShop.contains(where: { $0.id == seriesID }) {
                        seriesID = seriesOfShop.first?.id ?? ""
                    }
                }
                Picker("系列", selection: $seriesID) {
                    ForEach(seriesOfShop) { series in
                        Text(series.name).tag(series.id)
                    }
                }
                TextField("商品名（如「星月夜 JSK 粉色」）", text: $name)
                TextField("品类（如 JSK / OP / SK / 小物）", text: $category)
                if !isNew {
                    OpsFootnote(text: "已上线过的商品改名会被拒绝（改名是款式级口径，"
                                + "Mac 端不复制 iOS 的实现）。改品类同理。")
                }
            },
            onCancel: { dismiss() },
            onConfirm: { save() }
        )
        .onAppear(perform: load)
    }

    private func load() {
        guard !isNew,
              let product = workspace.catalog.products.first(where: { $0.id == productID }) else {
            shopID = workspace.catalog.shops.first?.id ?? ""
            seriesID = seriesOfShop.first?.id ?? ""
            return
        }
        shopID = product.shopID
        seriesID = product.seriesID
        name = product.name
        category = product.category
    }

    private func save() -> Bool {
        if isNew {
            return workspace.addProduct(
                shopID: shopID, seriesID: seriesID, name: name, category: category)
        }
        return workspace.updateProduct(
            id: productID, shopID: shopID, seriesID: seriesID, name: name, category: category)
    }
}

// MARK: - 详情表单

private struct ProductDetailSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String

    @State private var designName = ""
    @State private var description = ""

    var body: some View {
        OpsFormFrame(
            title: "卖点描述与款式名",
            subtitle: "款式名是**款式级属性**：改它等于改整款的展示名。已上线过的商品不能在这里改。",
            width: 520,
            contentHeight: 260,
            content: {
                TextField("款式名（可空）", text: $designName)
                Text("卖点描述（可空）")
                    .font(.callout)
                TextEditor(text: $description)
                    .font(.body)
                    .frame(height: 130)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            },
            onCancel: { dismiss() },
            onConfirm: {
                workspace.updateProductDetail(
                    id: productID,
                    description: description,
                    designName: designName)
            }
        )
        .onAppear {
            guard let product = workspace.catalog.products.first(where: { $0.id == productID }) else {
                return
            }
            designName = product.designName ?? ""
            description = product.description ?? ""
        }
    }

    @Environment(\.dismiss) private var dismiss
}

// MARK: - 商品图（有序绑定）

private struct ProductImagesSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss

    /// 有序数组 = 这个商品的图片顺序（第一张是首图）
    @State private var order: [String] = []
    @State private var didLoad = false

    private var candidates: [CatalogAsset] {
        let chosen = Set(order)
        return workspace.catalog.assets.filter { !chosen.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("商品图与顺序").font(.headline)
                Text(workspace.catalog.products.first { $0.id == productID }?.name ?? "")
                    .font(.callout).foregroundStyle(.secondary)
                OpsFootnote(text: "左边列表的顺序**就是**这个商品的图片顺序（第一张是首图）；"
                            + "它与可用图片列表的排列顺序无关。")
            }
            HStack(alignment: .top, spacing: 12) {
                selectedColumn
                Divider()
                candidateColumn
            }
            .frame(maxHeight: .infinity)
            HStack {
                Text("已选 \(order.count) 张").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    if workspace.bindImages(order, toProduct: productID) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 780, height: 560)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            order = workspace.catalog.products.first { $0.id == productID }?.images ?? []
        }
    }

    private var selectedColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("已选（\(order.count)）").font(.subheadline.weight(.semibold))
                Spacer()
                Button("清空") { order = [] }
                    .buttonStyle(.link).font(.caption)
                    .disabled(order.isEmpty)
            }
            if order.isEmpty {
                Text("还没选图。从右边加入。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            } else {
                List {
                    ForEach(Array(order.enumerated()), id: \.offset) { index, assetID in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            OpsThumbnail(url: thumbURL(assetID), size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(assetLabel(assetID)).font(.callout).lineLimit(1)
                                if index == 0 { OpsTag(text: "首图", tint: .accentColor) }
                            }
                            Spacer(minLength: 4)
                            Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                                .buttonStyle(.borderless).disabled(index == 0).help("上移")
                            Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                                .buttonStyle(.borderless)
                                .disabled(index == order.count - 1).help("下移")
                            Button { order.remove(at: index) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless).help("解除绑定（只从本商品移除，不删素材）")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var candidateColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("可用图片（\(candidates.count) 张）").font(.subheadline.weight(.semibold))
            if candidates.isEmpty {
                Text("素材都已经在这个商品上了。")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            } else {
                List(candidates) { asset in
                    HStack(spacing: 8) {
                        OpsThumbnail(url: thumbURL(asset.id), size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(assetLabel(asset.id)).font(.callout).lineLimit(1)
                            Text("\(asset.width ?? 0)×\(asset.height ?? 0)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button("加入") { order.append(asset.id) }
                            .buttonStyle(.link).font(.caption)
                        Button("置首") { order.insert(asset.id, at: 0) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard order.indices.contains(index), order.indices.contains(target) else { return }
        order.swapAt(index, target)
    }

    private func thumbURL(_ assetID: String) -> URL? {
        guard let asset = workspace.asset(for: assetID) else { return nil }
        return workspace.stagedFileURL(forReference: asset.originalURL)
            ?? workspace.stagedFileURL(forReference: asset.previewURL)
            ?? workspace.stagedFileURL(forReference: asset.thumbnailURL)
    }

    private func assetLabel(_ assetID: String) -> String {
        guard let asset = workspace.asset(for: assetID) else {
            return assetID + "（素材已不存在）"
        }
        if let url = thumbURL(assetID) { return url.lastPathComponent }
        return asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }
}

// MARK: - 规格表单

private struct VariantFormSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    let variantID: String?
    @Environment(\.dismiss) private var dismiss

    @State private var color = ""
    @State private var size = ""
    @State private var imageAssetID = ""

    var body: some View {
        OpsFormFrame(
            title: variantID == nil ? "新增规格" : "编辑规格",
            subtitle: "配色与尺码至少要填一个（两者都空等于「未区分」，那是商品本身的含义）。",
            contentHeight: 300,
            content: {
                TextField("配色（可空，如「粉色」）", text: $color)
                TextField("尺码（可空，如「M」）", text: $size)
                Picker("规格图（可空）", selection: $imageAssetID) {
                    Text("不指定").tag("")
                    ForEach(workspace.catalog.assets) { asset in
                        Text(assetLabel(asset)).tag(asset.id)
                    }
                }
                OpsFootnote(text: "同一组合不允许重复：两个长得一样的规格，运营会以为是 App 的 bug。")
            },
            onCancel: { dismiss() },
            onConfirm: {
                let asset: String? = imageAssetID.isEmpty ? nil : imageAssetID
                if let variantID {
                    return workspace.updateVariant(
                        id: variantID, color: color, size: size, imageAssetID: asset)
                }
                return workspace.addVariant(
                    productID: productID, color: color, size: size, imageAssetID: asset)
            }
        )
        .onAppear {
            guard let variantID,
                  let variant = workspace.catalog.variants.first(where: { $0.id == variantID }) else {
                return
            }
            color = variant.color ?? ""
            size = variant.size ?? ""
            imageAssetID = variant.imageAssetID ?? ""
        }
    }

    private func assetLabel(_ asset: CatalogAsset) -> String {
        workspace.stagedFileURL(forReference: asset.originalURL)?.lastPathComponent
            ?? asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }
}

// MARK: - 尺码表表单

/// 尺码表录入。列名一行、每行一条规格，值用「｜」或逗号分隔。
///
/// 行列不齐是尺码表最常见的脏数据（客户端整列错位 → 看起来「数据全错」），
/// 所以在**录入端**就挡：这里先按列数校验一遍，服务层还会再挡一次。
private struct SizeChartFormSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss

    @State private var unit = ""
    @State private var columnsText = ""
    @State private var sourceAssetID = ""
    /// 每行一条：`标签 = 值1, 值2, …`
    @State private var rowsText = ""
    @State private var localError: String?

    var body: some View {
        OpsFormFrame(
            title: "录入尺码表",
            subtitle: "整体替换这个商品的尺码表。列数变了要同时改每一行。",
            width: 560,
            contentHeight: 360,
            content: {
                TextField("单位（如 cm / inch）", text: $unit)
                TextField("列名（逗号分隔，如：胸围, 腰围, 裙长）", text: $columnsText)
                VStack(alignment: .leading, spacing: 4) {
                    Text("每一行：`尺寸 = 值1, 值2, …`").font(.callout)
                    TextEditor(text: $rowsText)
                        .font(.body.monospaced())
                        .frame(height: 140)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                }
                Picker("尺码表原图（可空）", selection: $sourceAssetID) {
                    Text("不指定").tag("")
                    ForEach(workspace.catalog.assets) { asset in
                        Text(assetLabel(asset)).tag(asset.id)
                    }
                }
                if let localError {
                    Label(localError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OpsFootnote(text: "列和行必须**同时**填写或**同时**留空；只有尺码表原图时可以都为空"
                            + "（原图给用户看，结构化数据给客户端排版）。")
            },
            onCancel: { dismiss() },
            onConfirm: { save() }
        )
        .onAppear(perform: load)
    }

    private func load() {
        guard let chart = workspace.sizeChart(forProduct: productID) else { return }
        unit = chart.unit ?? ""
        columnsText = chart.columns.joined(separator: ", ")
        sourceAssetID = chart.sourceImage ?? ""
        rowsText = chart.rows
            .map { row in row.label + " = " + row.values.map { $0 ?? "" }.joined(separator: ", ") }
            .joined(separator: "\n")
    }

    private func save() -> Bool {
        localError = nil
        let columns = columnsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "|" || $0 == "｜" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // 需求 §S3-B：只有原图时，结构化列和行可以都为空；只填一半仍拒绝
        if columns.isEmpty, rowsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard !sourceAssetID.isEmpty else {
                localError = "结构化列/行与尺码表原图至少要有一项"
                    + "（需求：只有原图时列和行可以都为空）。"
                return false
            }
            return workspace.setSizeChart(
                productID: productID, unit: unit, columns: [], rows: [],
                sourceImage: sourceAssetID.isEmpty ? nil : sourceAssetID)
        }
        guard !columns.isEmpty else {
            localError = "至少要有一个列名（或完全留空、只上传原图）。"
            return false
        }
        var rows: [CatalogSizeRow] = []
        for rawLine in rowsText.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let separatorIndex = line.firstIndex(of: "=") else {
                localError = "这一行没有「=」，格式应为 `尺寸 = 值1, 值2`：\(line)"
                return false
            }
            let label = String(line[line.startIndex..<separatorIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                localError = "有一行没有写尺寸标签：\(line)"
                return false
            }
            let valuesPart = String(line[line.index(after: separatorIndex)...])
            let values = valuesPart
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { part -> String? in
                    let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            guard values.count == columns.count else {
                localError = "「\(label)」有 \(values.count) 个值，而列名有 \(columns.count) 个 —— "
                    + "客户端会整列错位，请补齐或用逗号留空占位。"
                return false
            }
            rows.append(CatalogSizeRow(label: label, values: values))
        }
        return workspace.setSizeChart(
            productID: productID,
            unit: unit,
            columns: columns,
            rows: rows,
            sourceImage: sourceAssetID.isEmpty ? nil : sourceAssetID)
    }

    private func assetLabel(_ asset: CatalogAsset) -> String {
        workspace.stagedFileURL(forReference: asset.originalURL)?.lastPathComponent
            ?? asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }
}

// MARK: - 追加销售记录

private struct SaleEventFormSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss

    @State private var type: CatalogSaleEventType = .reservation
    @State private var priceText = ""
    @State private var depositText = ""
    @State private var balanceText = ""
    @State private var currency: CatalogCurrency = .unknown
    @State private var hasStartAt = true
    @State private var startAt = Date()
    @State private var hasEndAt = false
    @State private var endAt = Date()
    @State private var batchLabel = ""
    @State private var localError: String?

    var body: some View {
        OpsFormFrame(
            title: "追加一条销售记录",
            subtitle: "这是价格的历史事实：只会追加，永远不会覆盖已有记录。",
            width: 520,
            contentHeight: 420,
            content: {
                Picker("类型", selection: $type) {
                    ForEach(CatalogSaleEventType.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                TextField("价格（必填）", text: $priceText)
                TextField("定金（可空）", text: $depositText)
                TextField("尾款（可空）", text: $balanceText)
                Picker("币种", selection: $currency) {
                    ForEach(CatalogCurrency.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                OpsOptionalDateField(
                    label: type == .rerelease ? "批次时间（再贩必填）" : "开始时间",
                    isOn: $hasStartAt,
                    date: $startAt)
                OpsOptionalDateField(
                    label: "结束时间（选填）",
                    isOn: $hasEndAt,
                    date: $endAt)
                TextField("批次标签（可空，如「初贩」「再贩 2」）", text: $batchLabel)
                if let localError {
                    Label(localError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                OpsFootnote(text: "「币种待确认」的金额不能入库：它在跨币种差价与合计里是错的。")
            },
            onCancel: { dismiss() },
            onConfirm: { save() }
        )
    }

    private func save() -> Bool {
        localError = nil
        let price = opsResolveDecimal(priceText, label: "价格")
        if let error = price.error { localError = error; return false }
        guard let priceValue = price.value else {
            localError = "价格是必填的。"
            return false
        }
        let deposit = opsResolveDecimal(depositText, label: "定金")
        if let error = deposit.error { localError = error; return false }
        let balance = opsResolveDecimal(balanceText, label: "尾款")
        if let error = balance.error { localError = error; return false }
        return workspace.appendSaleEvent(
            productID: productID,
            type: type,
            price: priceValue,
            deposit: deposit.value,
            balance: balance.value,
            currency: currency,
            startAt: hasStartAt ? startAt : nil,
            endAt: hasEndAt ? endAt : nil,
            batchLabel: batchLabel)
    }
}

// MARK: - 价格修正

/// 价格修正是**完整快照**：留空 = 清除这一项。
///
/// 表单里必须把这句话写在明面上，否则运营会以为「留空 = 不改这一项」，
/// 于是改一次价格就把另外两个字段清掉了，而界面上只会显示「暂无」。
private struct PriceCorrectionFormSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss

    @State private var reservationText = ""
    @State private var stockText = ""
    @State private var depositText = ""
    @State private var balanceText = ""
    @State private var usesCurrency = false
    @State private var currency: CatalogCurrency = .cny
    @State private var localError: String?

    var body: some View {
        OpsFormFrame(
            title: "应用价格修正",
            subtitle: "⚠️ 这是**完整快照**：留空的那一项会被**清除**（显示「暂无」），"
                + "不会回退到销售记录推导值。只想撤销修正请用商品页的「撤销修正」。",
            width: 540,
            contentHeight: 380,
            content: {
                TextField("预约价（留空 = 清除）", text: $reservationText)
                TextField("现货价（留空 = 清除）", text: $stockText)
                TextField("定金（留空 = 清除）", text: $depositText)
                TextField("尾款（留空 = 清除）", text: $balanceText)
                Toggle("声明币种（跨币种修正会被拒绝）", isOn: $usesCurrency)
                if usesCurrency {
                    Picker("币种", selection: $currency) {
                        ForEach(CatalogCurrency.allCases.filter { !$0.isUnknown }) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }
                if let localError {
                    Label(localError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            },
            onCancel: { dismiss() },
            onConfirm: { save() }
        )
        .onAppear(perform: load)
    }

    private func load() {
        guard let correction = workspace.catalog.products
            .first(where: { $0.id == productID })?.priceCorrection else { return }
        reservationText = text(correction.reservationPrice)
        stockText = text(correction.stockPrice)
        depositText = text(correction.deposit)
        balanceText = text(correction.balance)
        if let existing = correction.currency {
            usesCurrency = true
            currency = existing.isUnknown ? .cny : existing
        }
    }

    private func text(_ value: Decimal?) -> String {
        guard let value else { return "" }
        return "\(value)"
    }

    private func save() -> Bool {
        localError = nil
        let reservation = opsResolveDecimal(reservationText, label: "预约价")
        if let error = reservation.error { localError = error; return false }
        let stock = opsResolveDecimal(stockText, label: "现货价")
        if let error = stock.error { localError = error; return false }
        let deposit = opsResolveDecimal(depositText, label: "定金")
        if let error = deposit.error { localError = error; return false }
        let balance = opsResolveDecimal(balanceText, label: "尾款")
        if let error = balance.error { localError = error; return false }
        return workspace.applyPriceCorrection(
            productID: productID,
            reservationPrice: reservation.value,
            stockPrice: stock.value,
            deposit: deposit.value,
            balance: balance.value,
            currency: usesCurrency ? currency : nil)
    }
}

// MARK: - 复制尺码表到其它商品

private struct CopySizeChartSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let sourceProductID: String
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<String> = []

    private var others: [CatalogProduct] {
        workspace.catalog.products.filter { $0.id != sourceProductID }
    }

    var body: some View {
        OpsFormFrame(
            title: "把尺码表复制到其它商品",
            subtitle: "Mac 端不做款式级自动扇出：同款多色要共用一张表，就**显式点名**这几个商品。",
            confirmTitle: "复制到已选商品",
            width: 520,
            contentHeight: 340,
            content: {
                if others.isEmpty {
                    OpsFootnote(text: "草稿里没有别的商品。")
                } else {
                    ForEach(others) { product in
                        Toggle(isOn: Binding(
                            get: { selected.contains(product.id) },
                            set: { isOn in
                                if isOn { selected.insert(product.id) } else { selected.remove(product.id) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(product.name).font(.callout)
                                Text(workspace.seriesName(for: product.seriesID))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                OpsFootnote(text: "目标商品已有的尺码表会被**整体覆盖**（含原图），"
                            + "但原图资源本身不会被删除。")
            },
            onCancel: { dismiss() },
            onConfirm: {
                workspace.copySizeChart(from: sourceProductID, to: Array(selected))
            }
        )
    }
}

// MARK: - 复制商品

private struct DuplicateProductSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss

    @State private var seriesID = ""
    @State private var suffix = "（副本）"

    private var source: CatalogProduct? {
        workspace.catalog.products.first { $0.id == productID }
    }

    var body: some View {
        OpsFormFrame(
            title: "复制为新品",
            subtitle: "新商品会拿到新的 id，规格 / 尺码表 / 销售记录都会复制一份 —— "
                + "它们互相独立，之后改一边不会影响另一边。",
            contentHeight: 260,
            content: {
                Picker("目标系列", selection: $seriesID) {
                    ForEach(workspace.catalog.series) { series in
                        Text("\(workspace.shopName(for: series.shopID)) › \(series.name)")
                            .tag(series.id)
                    }
                }
                TextField("商品名后缀", text: $suffix)
                OpsFootnote(text: "商品图会**复用同一批素材**（不复制新图，也不重新编码）。")
            },
            onCancel: { dismiss() },
            onConfirm: {
                workspace.duplicateProduct(
                    id: productID, intoSeries: seriesID, nameSuffix: suffix)
            }
        )
        .onAppear {
            seriesID = source?.seriesID ?? workspace.catalog.series.first?.id ?? ""
        }
    }
}
