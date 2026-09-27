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
    /// 完成后的提示文案回传（由系列页展示 toast）
    var onFinished: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager
    @ObservedObject private var store = ShopCatalogStore.shared

    /// 主衣物选择（radio）；默认第一件主衣物
    @State private var primaryID: String?
    /// 小物勾选（checkbox）；默认全部小物勾选
    @State private var accessoryIDs: Set<String> = []
    /// 各单品选定的「加入方式」（2026-09-27 需求：所有入口统一在确认页按阶段选择）。
    /// 候选与默认都来自 `ShopCatalogWardrobeEntryPolicy`（与详情页弹窗同一份口径）。
    @State private var entryOptionByProduct: [String: ShopCatalogWardrobeEntryOption] = [:]
    /// 确认后的「加入方式」选择弹窗（用户需求：点「确认加入衣橱」后弹出两个选项）
    @State private var showsEntryChoiceDialog = false
    @State private var errorText: String?
    @State private var isInserting = false

    // MARK: 加入方式（按阶段，与详情页弹窗同一口径）

    /// 该商品的购买阶段（唯一共享口径）+ 价格档案是否有两个价
    private func entryPhaseAndPrices(for productID: String)
        -> (phase: ShopCatalogPurchasePhase,
            hasReservationPrice: Bool,
            hasStockPrice: Bool) {
        let archive = store.priceArchive(forProduct: productID)
        let series = store.product(id: productID).flatMap { store.series(id: $0.seriesID) }
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
        if let chosen = entryOptionByProduct[productID] { return chosen }
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
        items.filter { !ShopCatalogWardrobeCategory.isPrimary($0.product.category) }
    }

    /// 拆分条数（§23）：每件主衣物一条
    private var entryCount: Int { max(1, primaryItems.count) }

    /// 本套实际入手 = 全部主衣物条目 + 勾选小物（§23：主衣物各自成条，都计入）
    private var totalPrice: Decimal {
        let primarySum = primaryItems.reduce(Decimal(0)) { $0 + ($1.price ?? 0) }
        let accessorySum = accessoryCandidates
            .filter { accessoryIDs.contains($0.product.id) }
            .reduce(Decimal(0)) { $0 + ($1.price ?? 0) }
        return primarySum + accessorySum
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                selectedSection
                entryChoiceSection
                primarySection
                if !accessoryCandidates.isEmpty {
                    accessorySection
                }
                if primaryItems.count > 1 {
                    splitNotice
                }
                totalSection
                confirmButton
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(
            LiquidBackground(themeSkinWallpaperContext: .timeHall)
                .ignoresSafeArea()
        )
        .navigationTitle("加入少女衣橱")
        .navigationBarTitleDisplayMode(.inline)
        .alert("无法加入衣橱", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        // 确认后的「加入方式」选择弹窗（用户需求：点「确认加入衣橱」后弹出两个选项）。
        // confirmationDialog = iOS 原生底部选项弹窗，与工程内其他确认弹窗风格一致；
        // 候选文案与详情页加购弹窗同一份 `choiceTitle`，选择后按所选方式落库。
        .confirmationDialog(
            "请选择加入方式",
            isPresented: $showsEntryChoiceDialog,
            titleVisibility: .visible
        ) {
            if let unified = unifiedEntryCandidates {
                ForEach(unified.candidates, id: \.self) { candidate in
                    Button(ShopCatalogWardrobeEntryPolicy.choiceTitle(
                        for: candidate, phase: unified.phase).appLocalized) {
                        applyChoiceAndInsert(candidate)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("加入后按所选方式记账，金额仍由系统自动读取".appLocalized)
        }
        .onAppear {
            store.loadFromBundleIfNeeded()
            if primaryID == nil {
                primaryID = primaryItems.first?.product.id
            }
            if accessoryIDs.isEmpty {
                accessoryIDs = Set(accessoryCandidates.map { $0.product.id })
            }
            // 加入方式初始选中 = 阶段策略默认（点菜页自选口径优先）；
            // 已初始化过的保持用户所选（幂等，不覆盖）
            for item in items where entryOptionByProduct[item.product.id] == nil {
                entryOptionByProduct[item.product.id] = effectiveEntryOption(for: item.product.id)
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

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
            ForEach(items, id: \.product.id) { item in
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
                    primaryID = item.product.id
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: primaryID == item.product.id ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 17))
                            .foregroundStyle(primaryID == item.product.id ? themeManager.accentTextColor : themeManager.tertiaryTextColor)
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
                    if accessoryIDs.contains(item.product.id) {
                        accessoryIDs.remove(item.product.id)
                    } else {
                        accessoryIDs.insert(item.product.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: accessoryIDs.contains(item.product.id) ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                            .foregroundStyle(accessoryIDs.contains(item.product.id) ? themeManager.accentTextColor : themeManager.tertiaryTextColor)
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
            Text("本套实际入手".appLocalized)
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
            handleConfirmTap()
        } label: {
            Group {
                if isInserting {
                    ProgressView().tint(.white).padding(.vertical, 14)
                } else {
                    Text("确认加入衣橱".appLocalized)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.vertical, 14)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ThemeSkinPrimaryButtonStyle(fallbackTint: .pink, cornerRadius: 16, verticalPadding: 14))
        .disabled(isInserting)
    }

    // MARK: 入库

    // MARK: 确认后的「加入方式」选择弹窗（2026-09-27 需求）

    /// 所有选中商品的「加入方式」候选是否一致（且非空）：
    /// 一致 → 点「确认加入衣橱」弹出选择弹窗（两个选项，与详情页弹窗同一份文案）；
    /// 不一致（多件商品混合阶段）→ 弹窗给不出统一的两个选项，
    /// 不弹，按确认页里每件商品已选的方式直接落库（页内「加入方式」段兜底）。
    private var unifiedEntryCandidates:
        (candidates: [ShopCatalogWardrobeEntryOption], phase: ShopCatalogPurchasePhase)? {
        guard let firstItem = items.first else { return nil }
        let first = entryCandidates(for: firstItem.product.id)
        guard !first.isEmpty else { return nil }
        for item in items.dropFirst() where entryCandidates(for: item.product.id) != first {
            return nil
        }
        return (first, entryPhaseAndPrices(for: firstItem.product.id).phase)
    }

    /// 确认按钮 action：候选统一 → 先弹选择弹窗；否则直接按页内已选落库
    private func handleConfirmTap() {
        if unifiedEntryCandidates != nil {
            showsEntryChoiceDialog = true
        } else {
            confirmInsert()
        }
    }

    /// 弹窗选定后：所选方式应用到所有候选包含它的商品
    ///（不在候选的商品保持页内已选），随后落库
    private func applyChoiceAndInsert(_ option: ShopCatalogWardrobeEntryOption) {
        for item in items where entryCandidates(for: item.product.id).contains(option) {
            entryOptionByProduct[item.product.id] = option
        }
        confirmInsert()
    }

    private func confirmInsert() {
        isInserting = true
        defer { isInserting = false }
        guard primaryID != nil || !items.isEmpty else {
            errorText = "请先选择主衣物"
            return
        }
        let keptAccessoryIDs = accessoryIDs
        // 价格口径（2026-09-27 需求）：按用户在「加入方式」段选定的口径落库，
        // 映射唯一口径 `ShopCatalogWardrobeEntryPolicy.priceMode`（与详情页弹窗共用）；
        // 预约价口径须有可用预约记录（makeDraft 会 guard），缺记录回退现货兜底；
        // 候选为空（无任何价格档案）的商品维持既有现货兜底。
        let selections = items.map { item -> ShopCatalogWardrobeDraftBuilder.Selection in
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
                priceMode: resolvedMode
            )
        }
        do {
            let pairs = try ShopCatalogWardrobeDraftBuilder.makeSplitDrafts(
                selections: selections,
                accessoryProductIDs: keptAccessoryIDs,
                store: store,
                modelContext: modelContext
            )
            _ = try ShopCatalogWardrobeInserter.insertSet(
                drafts: pairs,
                accessoryProductIDs: keptAccessoryIDs,
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
