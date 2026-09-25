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
    @State private var errorText: String?
    @State private var isInserting = false

    /// 展示价 = 用户选定口径对应的当前价（与落库口径一致）
    private func price(for productID: String) -> Decimal? {
        let archive = store.priceArchive(forProduct: productID)
        if priceChoices[productID] == .reservation {
            return archive.currentReservationPrice ?? archive.reservation?.price
        }
        return archive.currentStockPrice ?? archive.historicalReservationPrice
    }

    /// 价格标签：预约口径带「预约」前缀，便于和现货区分
    private func priceLabel(for productID: String) -> String {
        guard let price = price(for: productID) else { return "价格未填" }
        let amount = "¥\(NSDecimalNumber(decimal: price).stringValue)"
        return priceChoices[productID] == .reservation ? "预约 \(amount)" : amount
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
        .onAppear {
            store.loadFromBundleIfNeeded()
            if primaryID == nil {
                primaryID = primaryItems.first?.product.id
            }
            if accessoryIDs.isEmpty {
                accessoryIDs = Set(accessoryCandidates.map { $0.product.id })
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
            confirmInsert()
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

    private func confirmInsert() {
        isInserting = true
        defer { isInserting = false }
        guard primaryID != nil || !items.isEmpty else {
            errorText = "请先选择主衣物"
            return
        }
        let keptAccessoryIDs = accessoryIDs
        // 价格口径（V1.3）：点菜页自选的口径优先；预约口径须有可用预约记录，否则回退现货
        let selections = items.map { item -> ShopCatalogWardrobeDraftBuilder.Selection in
            let id = item.product.id
            let archive = store.priceArchive(forProduct: id)
            if priceChoices[id] == .reservation, let event = archive.reservation {
                return ShopCatalogWardrobeDraftBuilder.Selection(
                    productID: id,
                    color: colorByProduct[id],
                    size: sizeByProduct[id],
                    priceMode: .reservation(depositPaid: event.deposit ?? 0)
                )
            }
            return ShopCatalogWardrobeDraftBuilder.Selection(
                productID: id,
                color: colorByProduct[id],
                size: sizeByProduct[id],
                priceMode: .stock
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
