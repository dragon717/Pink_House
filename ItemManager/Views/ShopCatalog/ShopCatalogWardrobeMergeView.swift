//
//  ShopCatalogWardrobeMergeView.swift
//  ItemManager
//
//  多选「加入少女衣橱」确认页（计划 §12 + 附录A 参考图6，P0）：
//    · 已选择的商品（N 件）缩略图 + 价格
//    · 请选择主衣物（radio，决定衣橱记录主类型，§20）
//    · 小物（checkbox，勾选写入现有「小物」栏，§21）
//    · 多件主衣物 → 默认建议拆成多条衣橱条目（§23），不报错阻断
//    · 本套实际入手总价 + 确认加入衣橱
//
//  视觉：沿用现有少女心愿风格（themeManager 令牌 + themeSkinSectionCard，
//  约束 1「不改变现有 UI，只扩展」）。
//

import SwiftUI
import SwiftData

struct ShopCatalogWardrobeMergeView: View {
    let selectedProductIDs: [String]
    /// 各单品自选的加购价格口径（系列点菜页传入；缺省全部按现货价）
    var priceChoices: [String: ShopCatalogCardPriceChoice] = [:]
    /// 各单品选定的颜色（系列点菜页传入；缺省不写颜色）
    var colorByProduct: [String: String] = [:]
    /// 各单品选定的尺码（系列点菜页传入；缺省不写尺码）
    var sizeByProduct: [String: String] = [:]
    /// 保存成功后通知调用方刷新勾选；成功反馈由统一入橱服务展示。
    var onFinished: (Int) -> Void
    let saveIndividually: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared

    init(selectedProductIDs: [String], priceChoices: [String: ShopCatalogCardPriceChoice] = [:],
         colorByProduct: [String: String] = [:], sizeByProduct: [String: String] = [:],
         store: ShopCatalogStore = .shared, saveIndividually: Bool = false,
         onFinished: @escaping (Int) -> Void) {
        self.selectedProductIDs = selectedProductIDs
        self.priceChoices = priceChoices
        self.colorByProduct = colorByProduct
        self.sizeByProduct = sizeByProduct
        self.onFinished = onFinished
        self.saveIndividually = saveIndividually
        _store = ObservedObject(wrappedValue: store)
    }

    /// 默认第一件主衣物；小物不预选，保留用户每次勾选 / 取消的结果。
    @State private var selection = ShopCatalogWardrobeMergeSelection()
    /// 各单品选定的「加入方式」（2026-09-27 需求：所有入口统一在确认页按阶段选择）。
    /// 候选与默认都来自 `ShopCatalogWardrobeEntryPolicy`（与详情页弹窗同一份口径）。
    @State private var entryOptionByProduct: [String: ShopCatalogWardrobeEntryOption] = [:]
    @State private var errorText: String?
    @State private var isInserting = false
    @State private var purchaseBatchSelection = ShopCatalogPurchaseBatchSelection()
    @State private var userNote = ""

    private var reservationBatchBySeries: [String: String] { purchaseBatchSelection.selectedIDs }
    private var needsPurchaseBatchSelection: Bool {
        purchaseBatchSelection.requiresSelection(for: batchSeries)
    }

    // MARK: 加入方式（按阶段，与详情页弹窗同一口径）

    /// 该商品的购买阶段（唯一共享口径）+ 价格档案是否有两个价
    private func entryPhaseAndPrices(for productID: String)
        -> (phase: ShopCatalogPurchasePhase,
            hasReservationPrice: Bool,
            hasStockPrice: Bool) {
        let archive = store.priceArchive(forProduct: productID)
        let originalSeries = store.product(id: productID).flatMap { store.seriesForPurchase(id: $0.seriesID) }
        let series = originalSeries.flatMap {
            $0.paymentSchedule(batchID: reservationBatchBySeries[$0.id])
        } ?? originalSeries
        let phase = ShopCatalogWardrobeEntryPolicy.purchasePhase(
            for: productID, series: series, store: store)
        return (phase,
                (archive.currentReservationPrice ?? 0) > 0,
                (archive.currentStockPrice ?? 0) > 0)
    }

    /// 该商品在该阶段的「加入方式」候选（空 = 无可用价格档案，走现货兜底）
    private func entryCandidates(for productID: String) -> [ShopCatalogWardrobeEntryOption] {
        let info = entryPhaseAndPrices(for: productID)
        return ShopCatalogWardrobeEntryPolicy.options(
            phase: info.phase,
            hasReservationPrice: info.hasReservationPrice,
            hasStockPrice: info.hasStockPrice)
    }

    /// 实际生效的加入方式：用户已选优先；尚未初始化（首帧渲染）时按阶段策略取
    private func effectiveEntryOption(for productID: String) -> ShopCatalogWardrobeEntryOption? {
        if let chosen = entryOptionByProduct[productID], entryCandidates(for: productID).contains(chosen) { return chosen }
        let info = entryPhaseAndPrices(for: productID)
        return ShopCatalogWardrobeEntryPolicy.mergeEntryInitialOption(
            preferredCardChoice: priceChoices[productID],
            phase: info.phase,
            hasReservationPrice: info.hasReservationPrice,
            hasStockPrice: info.hasStockPrice)
    }

    /// 展示价 = 用户选定口径对应的当前价（与落库口径一致）：
    /// 定金+尾款 / 预约价全款 → 预约价；现货价全款 → 现货价（缺则历史预约价）
    private func price(for productID: String) -> Decimal? {
        let archive = store.priceArchive(forProduct: productID)
        switch effectiveEntryOption(for: productID) {
        case .fullStockPaid:
            return archive.currentStockPrice ?? archive.historicalReservationPrice
        default:
            return archive.currentReservationPrice ?? archive.reservation?.price
        }
    }

    /// 价格标签：预约口径带「预约」前缀，便于和现货区分
    private func priceLabel(for productID: String) -> String {
        guard let price = price(for: productID) else { return "价格未填" }
        let amount = "¥\(NSDecimalNumber(decimal: price).stringValue)"
        return effectiveEntryOption(for: productID) == .fullStockPaid ? amount : "预约 \(amount)"
    }

    private var items: [(product: CatalogProduct, price: Decimal?)] {
        selectedProductIDs.compactMap { id in
            guard let p = store.product(id: id) else { return nil }
            return (p, price(for: id))
        }
    }

    private var primaryItems: [(product: CatalogProduct, price: Decimal?)] {
        items.filter { ShopCatalogWardrobeCategory.isPrimary($0.product.category) }
    }

    private var accessoryCandidates: [(product: CatalogProduct, price: Decimal?)] {
        items.filter {
            !ShopCatalogWardrobeCategory.isPrimary($0.product.category)
                && $0.product.id != selection.primaryID
        }
    }

    private var includedItems: [(product: CatalogProduct, price: Decimal?)] {
        if saveIndividually { return items }
        let ids = Set(selection.includedProducts(in: items.map(\.product)).map(\.id))
        return items.filter { ids.contains($0.product.id) }
    }

    /// 拆分条数（§23）：每件主衣物一条
    private var entryCount: Int { max(1, primaryItems.count) }

    /// 本套实际入手 = 全部主衣物条目 + 勾选小物（§23：主衣物各自成条，都计入）
    private var totalPrice: Decimal {
        includedItems.reduce(Decimal(0)) { $0 + ($1.price ?? 0) }
    }

    var body: some View {
        confirmationContent
        .safeAreaInset(edge: .bottom) {
            if saveIndividually {
                VStack(spacing: 12) {
                    totalSection
                    confirmButton
                }
                .padding(16)
                .background(.ultraThinMaterial)
            }
        }
        .background(
            LiquidBackground(themeSkinWallpaperContext: .timeHall)
                .ignoresSafeArea()
        )
        .interactiveDismissDisabled(isInserting)
        .disabled(isInserting)
        .navigationTitle((saveIndividually ? "逐件加入衣橱" : "加入少女衣橱").appLocalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }.disabled(isInserting)
            }
        }
        .alert("无法加入衣橱", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear {
            store.loadFromBundleIfNeeded()
            selection.initializePrimary(in: items.map(\.product))
            // 加入方式初始选中 = 阶段策略默认（点菜页自选口径优先）；
            // 已初始化过的保持用户所选（幂等，不覆盖）
            for item in items where entryOptionByProduct[item.product.id] == nil {
                entryOptionByProduct[item.product.id] = effectiveEntryOption(for: item.product.id)
            }
        }
    }

    private var confirmationContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                selectedSection
                entryChoiceSection
                reservationBatchSection
                if saveIndividually {
                    Text("选好后一次确认，每件商品分别保存为独立衣物，小物也单独入橱。".appLocalized)
                        .font(.footnote)
                        .foregroundStyle(themeManager.secondaryTextColor)
                } else {
                    primarySection
                    if !accessoryCandidates.isEmpty { accessorySection }
                    if primaryItems.count > 1 { splitNotice }
                }
                if !saveIndividually { totalSection }
                TextField("备注（选填，写下你想记录的内容）", text: $userNote, axis: .vertical)
                    .padding(14)
                    .themeSkinSectionCard(cornerRadius: 16)
                if !saveIndividually { confirmButton }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var batchSeries: [CatalogSeries] {
        ShopCatalogPurchaseBatchSelection.requirements(in:
            includedItems.compactMap { store.seriesForPurchase(id: $0.product.seriesID) })
    }

    @ViewBuilder
    private var reservationBatchSection: some View {
        if !batchSeries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(batchSeries) { series in
                    if batchSeries.count > 1 { Text(series.name).font(.subheadline) }
                    ShopCatalogPurchaseBatchPicker(series: series, selectedID: Binding(
                        get: { purchaseBatchSelection.selectedIDs[series.id] },
                        set: { purchaseBatchSelection.selectedIDs[series.id] = $0 }))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .themeSkinSectionCard(cornerRadius: 16)
        }
    }

    // MARK: 已选择的商品

    private var selectedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已选择的商品（\(items.count)件）".appLocalized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeManager.primaryTextColor)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items, id: \.product.id) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            ShopCatalogAssetImage(
                                reference: item.product.images.first.flatMap { store.asset(id: $0)?.originalURL ?? $0 },
                                mediaKey: item.product.images.first.flatMap { store.asset(id: $0)?.mediaKey })
                                .aspectRatio(3 / 4, contentMode: .fill)
                                .frame(width: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text(item.product.name)
                                .font(.system(size: 11))
                                .foregroundStyle(themeManager.primaryTextColor)
                                .lineLimit(1)
                            Text(priceLabel(for: item.product.id))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(themeManager.accentTextColor)
                        }
                        .frame(width: 74)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSkinSectionCard(cornerRadius: 16)
    }

    // MARK: 加入方式（每件商品按阶段选择；2026-09-27 需求）

    /// 「加入方式」选择段：候选与文案按阶段策略取（与详情页弹窗同一份
    /// `ShopCatalogWardrobeEntryPolicy`），用户选定后金额预览与落库口径联动。
    /// 候选为空（无可用价格档案）的商品不出现在这里，落库时走现货兜底。
    private var entryChoiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("加入方式".appLocalized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeManager.primaryTextColor)
            Text("（按每件商品当前的销售阶段选择记账方式，金额仍由系统自动读取）".appLocalized)
                .font(.system(size: 11))
                .foregroundStyle(themeManager.tertiaryTextColor)
            ForEach(includedItems, id: \.product.id) { item in
                let candidates = entryCandidates(for: item.product.id)
                if !candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.product.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(themeManager.secondaryTextColor)
                            .lineLimit(1)
                        ForEach(candidates, id: \.self) { candidate in
                            entryChoiceRow(
                                productID: item.product.id,
                                option: candidate,
                                phase: entryPhaseAndPrices(for: item.product.id).phase
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSkinSectionCard(cornerRadius: 16)
    }

    /// 单个加入方式选项行（radio 风格，与详情页弹窗的选择段同款）
    private func entryChoiceRow(productID: String,
                                option: ShopCatalogWardrobeEntryOption,
                                phase: ShopCatalogPurchasePhase) -> some View {
        let isSelected = effectiveEntryOption(for: productID) == option
        return Button {
            entryOptionByProduct[productID] = option
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? themeManager.accentTextColor : themeManager.tertiaryTextColor)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ShopCatalogWardrobeEntryPolicy.choiceTitle(for: option, phase: phase).appLocalized)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(themeManager.primaryTextColor)
                    Text(ShopCatalogWardrobeEntryPolicy.choiceCaption(for: option).appLocalized)
                        .font(.system(size: 11))
                        .foregroundStyle(themeManager.tertiaryTextColor)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: 主衣物（radio，§20）

    private var primarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("请选择主衣物".appLocalized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeManager.primaryTextColor)
            Text("（主衣物决定衣橱记录的类型）".appLocalized)
                .font(.system(size: 11))
                .foregroundStyle(themeManager.tertiaryTextColor)

            let candidates = primaryItems.isEmpty ? items : primaryItems
            ForEach(candidates, id: \.product.id) { item in
                Button {
                    selection.primaryID = item.product.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection.primaryID == item.product.id ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(selection.primaryID == item.product.id ? themeManager.accentTextColor : themeManager.tertiaryTextColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.product.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(themeManager.primaryTextColor)
                            Text("\(item.product.category) · 决定主类型".appLocalized)
                                .font(.system(size: 11))
                                .foregroundStyle(themeManager.tertiaryTextColor)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSkinSectionCard(cornerRadius: 16)
    }

    // MARK: 小物（checkbox，§21）

    private var accessorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("小物".appLocalized)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(themeManager.primaryTextColor)
            Text("（勾选后写入小物栏，随主衣物一起入库）".appLocalized)
                .font(.system(size: 11))
                .foregroundStyle(themeManager.tertiaryTextColor)
            ForEach(accessoryCandidates, id: \.product.id) { item in
                Button {
                    if selection.accessoryIDs.contains(item.product.id) {
                        selection.accessoryIDs.remove(item.product.id)
                    } else {
                        selection.accessoryIDs.insert(item.product.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection.accessoryIDs.contains(item.product.id) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(selection.accessoryIDs.contains(item.product.id) ? themeManager.accentTextColor : themeManager.tertiaryTextColor)
                        Text(item.product.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(themeManager.primaryTextColor)
                        Spacer()
                        Text(priceLabel(for: item.product.id))
                            .font(.system(size: 12))
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeSkinSectionCard(cornerRadius: 16)
    }

    // MARK: 多主衣物拆分提示（§23）

    private var splitNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
            Text("检测到 \(primaryItems.count) 件主衣物，将拆成 \(entryCount) 条衣橱条目（小物随第一条记录入库）".appLocalized)
                .font(.system(size: 12))
        }
        .foregroundStyle(themeManager.accentTextColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(themeManager.accentTextColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: 总价 + 确认

    private var totalSection: some View {
        HStack {
            Text((saveIndividually ? "所选商品合计" : "本套实际入手").appLocalized)
                .font(.system(size: 14))
                .foregroundStyle(themeManager.secondaryTextColor)
            Spacer()
            Text("¥\(NSDecimalNumber(decimal: totalPrice).stringValue)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(themeManager.accentTextColor)
        }
        .padding(.horizontal, 4)
    }

    private var confirmButton: some View {
        Button {
            confirmInsert()
        } label: {
            Group {
                if isInserting {
                    ProgressView().tint(.white).padding(.vertical, 14)
                } else {
                    Text((saveIndividually ? "一键逐件加入衣橱" : "确认加入衣橱").appLocalized)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .pink, cornerRadius: 16, verticalPadding: 14))
        .disabled(isInserting || needsPurchaseBatchSelection)
        .accessibilityIdentifier("catalog.wardrobe.confirm")
    }

    // MARK: 入库

    /// 按页内每件商品已选的加入方式直接保存，不再次要求选择。
    private func confirmInsert() {
        guard !isInserting, !needsPurchaseBatchSelection else { return }
        isInserting = true
        Task { @MainActor in
            defer { isInserting = false }
            await performInsert()
        }
    }

    private func performInsert() async {
        guard selection.primaryID != nil || !items.isEmpty else {
            errorText = "请先选择主衣物"
            return
        }
        let keptAccessoryIDs: Set<String> = saveIndividually ? [] : selection.includedAccessoryIDs
        if needsPurchaseBatchSelection {
            errorText = "请选择购买的团次或批次"
            return
        }
        // 价格口径（2026-09-27 需求）：按用户在「加入方式」段选定的口径落库，
        // 映射唯一口径 `ShopCatalogWardrobeEntryPolicy.priceMode`（与详情页弹窗共用）；
        // 预约价口径须有可用预约记录（makeDraft 会 guard），缺记录回退现货兜底；
        // 候选为空（无任何价格档案）的商品维持既有现货兜底。
        let selections = includedItems.map { item -> ShopCatalogWardrobeDraftBuilder.Selection in
            let id = item.product.id
            let archive = store.priceArchive(forProduct: id)
            let resolvedMode: ShopCatalogWardrobeDraftBuilder.PriceMode
            if let option = effectiveEntryOption(for: id) {
                let deposit = ShopCatalogWardrobeEntryPolicy.backendDeposit(
                    currentDeposit: archive.currentDeposit,
                    reservationPrice: archive.currentReservationPrice ?? 0)
                let mode = ShopCatalogWardrobeEntryPolicy.priceMode(
                    for: option, backendDeposit: deposit)
                // 预约价两个口径（定金+尾款 / 预约价全款）都挂在预约记录上取数，
                // 缺记录（理论上候选已被 hasReservationPrice 挡住，这里防御）→ 回退现货
                let needsReservationEvent = option == .depositPaid || option == .fullPaid
                if needsReservationEvent && archive.reservation == nil {
                    resolvedMode = .stock
                } else {
                    resolvedMode = mode
                }
            } else {
                resolvedMode = .stock
            }
            return ShopCatalogWardrobeDraftBuilder.Selection(
                productID: id,
                color: colorByProduct[id],
                size: sizeByProduct[id],
                priceMode: resolvedMode,
                reservationBatchID: reservationBatchBySeries[item.product.seriesID]
            )
        }
        do {
            let pairs = try saveIndividually
                ? ShopCatalogWardrobeIndividualAddition(productIDs: selectedProductIDs)
                    .makeDrafts(selections: selections, store: store)
                : ShopCatalogWardrobeDraftBuilder.makeSplitDrafts(
                    selections: selections, accessoryProductIDs: keptAccessoryIDs,
                    store: store, primaryProductID: selection.primaryID)
            _ = try await ShopCatalogWardrobeAddition.addSet(
                drafts: pairs.map { (draft: $0.draft.with(note: userNote), selection: $0.selection) },
                accessoryProductIDs: keptAccessoryIDs,
                accessorySelections: Dictionary(selections.filter { keptAccessoryIDs.contains($0.productID) }
                    .map { ($0.productID, $0) }, uniquingKeysWith: { first, _ in first }),
                store: store,
                modelContext: modelContext
            )
            onFinished(pairs.count)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
