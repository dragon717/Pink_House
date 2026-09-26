//
//  ShopCatalogStyleEntryView.swift
//  ItemManager
//
//  款式（SPU）优先的录入表单（2026-09-23 录入端重构）。
//
//  需求原文：
//    「尺码表、面料、款式描述，这些是款式（SPU）的公共属性，必须在录商品的第一步
//      就填好，只填一次。颜色图片、颜色库存，这些是颜色（SKU）的差异属性，在添加
//      每个颜色时独立填。录入逻辑必须是：先建款式，填公共尺码表；然后再加颜色，
//      加颜色时只需传图、选尺码，不再重复填尺码表数据。」
//
//  表单结构（与需求逐条对应）：
//
//    第 1 步 · 款式公共资料（只填一次）
//      · 款式名 / 分类 / 面料 / 款式描述
//      · 尺码表（列 + 行 + 单位 + 原图）—— 款式级，全色共享
//      · 预约价 / 现货价 / 定金 / 尾款（同款同价，按款式录入一次）
//
//    第 2 步 · 颜色（每个颜色独立填）
//      · 颜色名 + 配色图（相册选图 → `local:` 引用）
//      · 尺码**勾选**：候选项来自第 1 步的款式尺码表（不是再填一张表）
//
//  两种进入方式：
//    · **新建款式**：第 1、2 步都填，提交后为每个颜色建一个商品（SKU），
//      并把款式公共资料（含尺码表）写一次 —— 不是每个颜色写一次。
//    · **追加颜色到已有款式**：第 1 步变成只读的「继承款式资料」面板，
//      店主只需传图 + 勾尺码。这正是「以后上新颜色不必重复填尺码表」。
//
//  写入路径（不在前端做任何修补）：每个颜色走既有 `publish`（复用价格校验、
//  销售记录幂等、商品去重），款式公共资料单独走一次
//  `ShopCatalogDraftStore.updateStylePublicInfo` —— 尺码表因此天然是整款一份。
//

import SwiftUI

struct ShopCatalogStyleEntrySheet: View {
    let series: CatalogSeries
    @ObservedObject var draftStore: ShopCatalogDraftStore
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?

    @Environment(\.dismiss) private var dismiss

    // MARK: 进入方式

    private enum EntryMode: Hashable {
        /// 新建款式：公共资料 + 颜色都在本表单填
        case newStyle
        /// 追加颜色到已有款式：公共资料继承，只填颜色
        case existingStyle(String) // 款式键
    }

    @State private var mode: EntryMode = .newStyle

    // MARK: 第 1 步 · 款式公共资料

    @State private var designNameText = ""
    @State private var category = "JSK"
    @State private var fabricText = ""
    @State private var styleDescriptionText = ""

    // 尺码表（款式级素材，全色共享）
    @State private var chartColumnsText = ""
    @State private var chartRowsText = ""
    @State private var chartUnit = "cm"
    @State private var chartImageText = ""

    // 价格（同款同价 → 按款式录入一次）
    @State private var reservationPrice: Double?
    @State private var stockPrice: Double?
    @State private var deposit: Double?
    @State private var balance: Double?
    @State private var currency: CatalogCurrency = .cny

    // MARK: 第 2 步 · 颜色（SKU）

    private struct ColorEntry: Identifiable, Equatable {
        var id = UUID()
        var color = ""
        /// 配色图引用（`local:<文件名>`，由相册选图产生）
        var imageRef = ""
        /// 该颜色提供的尺码（候选项来自款式尺码表）
        var sizes: Set<String> = []
    }

    @State private var colors: [ColorEntry] = [ColorEntry()]
    @State private var isSubmitting = false

    /// 分类候选（计算属性：管理分类后立即生效，含自定义分类与「其他」兜底）
    private var categories: [String] { ShopCatalogStore.categoryCandidates }

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                if case .newStyle = mode {
                    stylePublicSection
                } else {
                    inheritedStyleSection
                }
                colorsSection
            }
            .navigationTitle("录入款式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("提交") { submit() }
                        .disabled(isSubmitting || !canSubmit)
                }
            }
            .onAppear {
                store.loadFromBundleIfNeeded()
                if designNameText.isEmpty { category = categories.first(where: { $0 != "其他" }) ?? "JSK" }
            }
        }
    }

    // MARK: - 进入方式

    /// 分类管理入口（2026-09-24 需求）：新增 / 改名 / 删除分类
    @State private var showsCategoryManage = false
    @ViewBuilder
    private var manageCategoriesButton: some View {
        Button {
            showsCategoryManage = true
        } label: {
            Label("管理分类（新增 / 改名 / 删除）", systemImage: "square.and.pencil")
                .font(.system(size: 13))
        }
        .sheet(isPresented: $showsCategoryManage) {
            ShopCatalogCategoryManageSheet()
        }
    }

    private var modeSection: some View {
        Section {
            Picker("录入到", selection: modeBinding) {
                Text("新款式").tag(EntryMode.newStyle)
                ForEach(existingStyles) { style in
                    Text("已有款式：\(style.designName)（\(style.colors.count) 色）")
                        .tag(EntryMode.existingStyle(style.key))
                }
            }
            .pickerStyle(.menu)
        } footer: {
            Text("尺码表 / 面料 / 款式描述属于**款式**，只需录一次；颜色图与尺码选择属于**颜色**，每加一个颜色填一次。")
                .font(.system(size: 11))
        }
    }

    /// mode 的比较需要 Equatable：`EntryMode` 已 Hashable
    private var modeBinding: Binding<EntryMode> {
        Binding(get: { mode }, set: { mode = $0 })
    }

    // MARK: - 第 1 步（新建款式）

    private var stylePublicSection: some View {
        Section {
            TextField("款式名（如：大蝴蝶结背心裙）", text: $designNameText)
            Picker("分类", selection: $category) {
                ForEach(categories.filter { $0 != "其他" }, id: \.self) { Text($0).tag($0) }
                Text("其他").tag("其他")
            }
            manageCategoriesButton
            TextField("面料（如：雪花提花布 + 蕾丝拼接）", text: $fabricText)
            TextEditor(text: $styleDescriptionText)
                .frame(minHeight: 56)
                .font(.system(size: 13))
                .overlay(alignment: .topLeading) {
                    if styleDescriptionText.isEmpty {
                        Text("款式描述（可空）")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }

            // 尺码表：列 / 行 / 单位 / 原图
            ShopCatalogChartPasteButton(kind: .sizeChart,
                                        columnsText: $chartColumnsText,
                                        rowsText: $chartRowsText)
            TextField("尺码表列名（逗号分隔，如：尺码,前裙长,推荐胸围）", text: $chartColumnsText)
                .font(.system(size: 13))
            TextEditor(text: $chartRowsText)
                .frame(minHeight: 56)
                .font(.system(size: 13))
                .overlay(alignment: .topLeading) {
                    if chartRowsText.isEmpty {
                        Text("每行「标签:值,值,…」，如 S:80,78-83,60-66")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            TextField("单位（cm）", text: $chartUnit)
            // 2026-09-26 需求：尺码表原图渲染为缩略图，不再显示文件名文本
            if !chartImageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ShopCatalogSingleImagePreview(reference: chartImageText) {
                    chartImageText = ""
                }
            }
            ShopCatalogImagePickerButton(mode: .replace, text: $chartImageText, label: "添加尺码表原图")

            priceRows
        } header: {
            Text("第 1 步 · 款式公共资料（只填一次，全色共享）")
        } footer: {
            if let issue = depositBalanceIssue {
                Text(issue).font(.system(size: 11)).foregroundStyle(.red)
            } else if !chartSizeLabels.isEmpty {
                Text("从尺码表识别出的尺码：\(chartSizeLabels.joined(separator: " / "))（第 2 步直接勾选）")
                    .font(.system(size: 11))
            } else {
                Text("尺码表可后补；填了列与行，第 2 步的颜色就能直接勾选尺码。")
                    .font(.system(size: 11))
            }
        }
    }

    @ViewBuilder
    private var priceRows: some View {
        HStack {
            Text("预约价")
            Spacer()
            TextField("可空", value: $reservationPrice, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
        }
        if reservationPrice != nil {
            HStack {
                Text("定金")
                Spacer()
                TextField("可空", value: $deposit, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
            }
            HStack {
                Text("尾款")
                Spacer()
                TextField("可空", value: $balance, format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
            }
        }
        HStack {
            Text("现货价")
            Spacer()
            TextField("可空", value: $stockPrice, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 110)
        }
        Picker("币种", selection: $currency) {
            ForEach(CatalogCurrency.allCases) { Text($0.displayName).tag($0) }
        }
    }

    // MARK: - 第 1 步（已有款式：只读继承）

    @ViewBuilder
    private var inheritedStyleSection: some View {
        Section {
            if let style = selectedExistingStyle {
                LabeledContent("款式名", value: style.designName)
                LabeledContent("分类", value: style.category)
                LabeledContent("面料", value: store.fabric(forProduct: style.representative.id) ?? "暂未录入")
                LabeledContent("款式描述",
                               value: store.styleDescription(forProduct: style.representative.id) ?? "暂未录入")
                let sizes = store.sizeRun(forProduct: style.representative.id)
                LabeledContent("款式尺码表",
                               value: sizes.isEmpty ? "暂未录入" : sizes.joined(separator: " / "))
                Text("以上为款式公共资料，本表单不重复填写、也不会覆盖；新颜色自动继承。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("请选择一个已有款式")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("第 1 步 · 款式公共资料（继承，无需重填）")
        }
    }

    // MARK: - 第 2 步 · 颜色

    private var colorsSection: some View {
        Section {
            ForEach($colors) { entry in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("颜色名（如：红色）", text: entry.color)
                        if colors.count > 1 {
                            Button(role: .destructive) {
                                colors.removeAll { $0.id == entry.wrappedValue.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .accessibilityLabel(Text("删除该颜色"))
                        }
                    }
                    ShopCatalogImagePickerButton(mode: .replace, text: entry.imageRef, label: "选择配色图")
                    // 2026-09-26 需求：配色图直接渲染缩略图，不再显示引用文件名文本
                    if !entry.wrappedValue.imageRef.isEmpty {
                        ShopCatalogSingleImagePreview(reference: entry.wrappedValue.imageRef,
                                                      height: 110) {
                            entry.wrappedValue.imageRef = ""
                        }
                    }
                    sizeChips(for: entry)
                }
                .padding(.vertical, 4)
            }
            Button {
                colors.append(ColorEntry())
            } label: {
                Label("添加颜色", systemImage: "plus.circle")
                    .font(.system(size: 13))
            }
        } header: {
            Text("第 2 步 · 颜色（每色传图 + 勾尺码）")
        } footer: {
            if availableSizes.isEmpty {
                Text("款式还没有尺码表，暂时无法勾选尺码 —— 可先只传配色图提交，补好尺码表后在此勾选。")
                    .font(.system(size: 11))
            } else {
                Text("尺码候选项来自款式尺码表，无需为每个颜色重复填表。")
                    .font(.system(size: 11))
            }
        }
    }

    /// 尺码勾选 chips（候选 = 款式尺码表的尺码轴）
    @ViewBuilder
    private func sizeChips(for entry: Binding<ColorEntry>) -> some View {
        if !availableSizes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("尺码")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(availableSizes, id: \.self) { size in
                        let isOn = entry.wrappedValue.sizes.contains(size)
                        Button {
                            if isOn { entry.wrappedValue.sizes.remove(size) }
                            else { entry.wrappedValue.sizes.insert(size) }
                        } label: {
                            Text(size)
                                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? Color.white : Color.pink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(isOn ? Color.pink : Color.pink.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 派生值

    /// 本系列里已有的款式（排除已归档），供「追加颜色」选择
    private struct ExistingStyle: Identifiable {
        let key: String
        let designName: String
        let category: String
        let representative: CatalogProduct
        let colors: [CatalogProduct]
        var id: String { key }
    }

    private var existingStyles: [ExistingStyle] {
        let products = (store.catalog?.products ?? []).filter {
            $0.seriesID == series.id && $0.archivedAt == nil
        }
        var order: [String] = []
        var buckets: [String: [CatalogProduct]] = [:]
        for product in products {
            let key = ShopCatalogStyleProfileSharing.styleKey(of: product)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(product)
        }
        return order.compactMap { key in
            guard let list = buckets[key], let first = list.first else { return nil }
            return ExistingStyle(key: key,
                                 designName: ShopCatalogSameDesignGrouper.designName(of: first),
                                 category: first.category,
                                 representative: first,
                                 colors: list)
        }
    }

    private var selectedExistingStyle: ExistingStyle? {
        guard case .existingStyle(let key) = mode else { return nil }
        return existingStyles.first { $0.key == key }
    }

    /// 第 1 步文本 → 尺码表（与草稿编辑器 / 手工表格同一解析口径）
    private var composedChart: CatalogSizeChart? {
        let parsed = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(chartColumnsText),
            rows: CatalogManualChartText.parseRows(chartRowsText))
        let image = chartImageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parsed.columns.isEmpty || !parsed.rows.isEmpty || !image.isEmpty else { return nil }
        var chart = CatalogSizeChart(id: "sizechart-style-\(designKeyForNewStyle)", productID: "")
        chart.unit = chartUnit.trimmingCharacters(in: .whitespaces).isEmpty ? nil : chartUnit
        chart.columns = parsed.columns
        chart.rows = parsed.rows
        chart.sourceImage = image.isEmpty ? nil : image
        return chart
    }

    /// 新建款式的确定性 id 片段（同名款式重复录入时同一份 id，幂等）
    private var designKeyForNewStyle: String {
        let design = designNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(series.id.prefix(8))-\(abs(design.hashValue))"
    }

    /// 款式尺码表的尺码轴（第 1 步识别结果 / 已有款式的现成尺码）
    private var chartSizeLabels: [String] {
        switch mode {
        case .newStyle:
            return ShopCatalogSizeChartSharing.sizeLabels(of: composedChart)
        case .existingStyle:
            return selectedExistingStyle.map { store.sizeRun(forProduct: $0.representative.id) } ?? []
        }
    }

    /// 颜色可勾选的尺码
    private var availableSizes: [String] { chartSizeLabels }

    private var depositBalanceIssue: String? {
        guard let r = reservationPrice, let d = deposit, let b = balance else { return nil }
        return Decimal(d) + Decimal(b) == Decimal(r) ? nil : "定金 \(Int(d)) + 尾款 \(Int(b)) ≠ 预约价 \(Int(r))"
    }

    private var canSubmit: Bool {
        guard !colors.allSatisfy({ $0.color.trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }
        guard reservationPrice != nil || stockPrice != nil else { return false }
        guard depositBalanceIssue == nil else { return false }
        if case .existingStyle = mode { return selectedExistingStyle != nil }
        return !designNameText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 提交

    private enum EntryError: LocalizedError {
        case missingDesignName
        case missingColor
        case missingPrice
        case incompleteChart
        case depositMismatch(String)

        var errorDescription: String? {
            switch self {
            case .missingDesignName: return "款式名不能为空 —— 它是款式公共资料的归属键"
            case .missingColor: return "至少填写一个颜色"
            case .missingPrice: return "预约价与现货价至少填一项"
            case .incompleteChart: return "尺码表的列与行必须同时填写（只有原图时请清空另一项）"
            case .depositMismatch(let detail): return "定金尾款对账失败：\(detail)"
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let plan = try buildSubmissionPlan()
            var publishedCount = 0
            var firstProductID: String?
            for draft in plan.drafts {
                let productID = try publishThroughStateMachine(draft)
                publishedCount += 1
                if firstProductID == nil { firstProductID = productID }
            }
            // 款式公共资料（面料 / 款式描述 / 尺码表）**写一次**，整款同步 ——
            // 不是每个颜色写一次，也不会因为只给某个颜色填过而只落在那一个颜色上。
            var styleMessage = ""
            if case .newStyle = mode, let target = firstProductID {
                styleMessage = try ShopCatalogDraftStore.updateStylePublicInfo(
                    fabric: fabricText,
                    styleDescription: styleDescriptionText,
                    sizeChart: plan.chart,
                    forProductID: target)
            }
            toast = styleMessage.isEmpty
                ? "已新增 \(publishedCount) 个颜色到「\(plan.designName)」"
                : "\(styleMessage)；已新增 \(publishedCount) 个颜色"
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// 走完草稿状态机再发布（草稿 → 提交 → 审核通过 → 发布）。
    ///
    /// 为什么不直接写覆盖层：发布这一步承载着价格校验（预约 / 现货至少一项、定金尾款对账）、
    /// 销售记录幂等（同内容重复提交不重复生成）与商品去重。另开一条写入口就等于把这些
    /// 规则复制一遍，迟早与主链路分叉 —— 这正是本项目反复踩过的坑。
    /// 代价是每条颜色会留下一条「已发布」草稿，可在草稿箱追溯本次上新。
    private func publishThroughStateMachine(_ draft: CatalogProductDraft) throws -> String? {
        try draftStore.upsert(draft)
        try draftStore.advance(draft, to: .submitted)
        guard let submitted = draftStore.drafts.first(where: { $0.id == draft.id }) else { return nil }
        try draftStore.advance(submitted, to: .reviewed)
        guard let reviewed = draftStore.drafts.first(where: { $0.id == draft.id }) else { return nil }
        _ = try draftStore.publish(reviewed, store: store)
        return draftStore.drafts.first { $0.id == draft.id }?.publishedResult?.productID
    }

    /// 提交产物：每个颜色一份草稿（走既有 publish）+ 一份款式尺码表
    private struct SubmissionPlan {
        var designName: String
        var drafts: [CatalogProductDraft]
        var chart: CatalogSizeChart?
    }

    private func buildSubmissionPlan() throws -> SubmissionPlan {
        let designName: String
        let categoryValue: String
        let chart: CatalogSizeChart?

        switch mode {
        case .newStyle:
            designName = designNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !designName.isEmpty else { throw EntryError.missingDesignName }
            categoryValue = category
            chart = composedChart
            // 只有原图（没有列/行）时列行必须同为「都填」或「都空」，避免半张表
            if let chart, chart.columns.isEmpty != chart.rows.isEmpty {
                throw EntryError.incompleteChart
            }
        case .existingStyle:
            guard let style = selectedExistingStyle else { throw EntryError.missingDesignName }
            designName = style.designName
            categoryValue = style.category
            // 追加颜色**不重写**款式公共资料：一句话都不带，避免"顺手覆盖"
            chart = nil
        }

        let validColors = colors
            .map { (color: $0.color.trimmingCharacters(in: .whitespacesAndNewlines),
                    imageRef: $0.imageRef.trimmingCharacters(in: .whitespacesAndNewlines),
                    sizes: $0.sizes) }
            .filter { !$0.color.isEmpty }
        guard !validColors.isEmpty else { throw EntryError.missingColor }
        guard reservationPrice != nil || stockPrice != nil else { throw EntryError.missingPrice }
        if let issue = depositBalanceIssue { throw EntryError.depositMismatch(issue) }

        let orderedSizes = availableSizes
        var drafts: [CatalogProductDraft] = []
        for entry in validColors {
            var draft = CatalogProductDraft()
            draft.shopID = series.shopID
            draft.seriesID = series.id
            // 商品名 = 颜色 + 款式名：既保证同款归组（款式名显式落库），
            // 也让心愿 / 尾款 / 衣橱等**记录名带颜色**（既有硬规则）
            draft.name = "\(entry.color)\(designName)"
            draft.designName = designName
            draft.category = categoryValue
            draft.price = reservationPrice ?? 0
            draft.stockPrice = stockPrice
            draft.deposit = deposit
            draft.balance = balance
            draft.currency = currency

            let assetID = entry.imageRef.isEmpty ? nil : "asset-style-\(draft.id.prefix(8))"
            if let assetID {
                draft.images = [CatalogAsset(id: assetID, type: .productImage, originalURL: entry.imageRef)]
            }
            // 规格：按款式尺码表的顺序输出勾选到的尺码（不是 Set 的随机序 —— 详情页与
            // 点菜页的尺码顺序都直接读它，顺序错乱会让两处显示不一致）
            let chosen = orderedSizes.filter { entry.sizes.contains($0) }
            if chosen.isEmpty {
                draft.variants = [CatalogProductVariant(id: "var-style-\(draft.id.prefix(8))-0",
                                                        productID: "", color: entry.color,
                                                        size: nil, imageAssetID: assetID)]
            } else {
                draft.variants = chosen.enumerated().map { index, size in
                    CatalogProductVariant(id: "var-style-\(draft.id.prefix(8))-\(index)",
                                          productID: "", color: entry.color,
                                          size: size, imageAssetID: assetID)
                }
            }
            drafts.append(draft)
        }
        return SubmissionPlan(designName: designName, drafts: drafts, chart: chart)
    }
}

// MARK: - 款式公共资料编辑（尺码表 / 面料 / 款式描述）

/// 已有款式的公共资料编辑页（SPU 级）。
///
/// 与商品深度编辑页的分工（需求原文的分层口径）：
///   · 本页 = **款式公共属性**（尺码表 / 面料 / 款式描述），保存后整款全部颜色同步；
///   · 商品深度编辑页 = **颜色差异属性**（配色图 / 尺码选择），只影响当前颜色。
///
/// 保存走 `updateStylePublicInfo` —— 三项一次落盘，不会出现「尺码表换了、面料没换」。
/// 语义与价格修正一致：整快照提交，清空即清除。
struct ShopCatalogStyleProfileEditor: View {
    /// 款内任一颜色（款式键由它归一化，传哪个颜色都落到同一份款式资料）
    let representative: CatalogProduct
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?

    @Environment(\.dismiss) private var dismiss

    @State private var fabricText = ""
    @State private var descriptionText = ""
    @State private var chartColumnsText = ""
    @State private var chartRowsText = ""
    @State private var chartUnit = ""
    @State private var chartImageText = ""

    private var designName: String {
        ShopCatalogSameDesignGrouper.designName(of: representative)
    }

    /// 同款全部颜色（保存影响范围的实话）
    private var scopeColors: [String] {
        (store.catalog?.products ?? [])
            .filter { ShopCatalogStyleProfileSharing.styleKey(of: $0)
                == ShopCatalogStyleProfileSharing.styleKey(of: representative) }
            .map { $0.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("面料（如：雪花提花布 + 蕾丝拼接）", text: $fabricText)
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 64)
                        .font(.system(size: 13))
                        .overlay(alignment: .topLeading) {
                            if descriptionText.isEmpty {
                                Text("款式描述（可空）")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("款式公共资料 · \(designName)")
                } footer: {
                    Text("保存后本款全部颜色同步（覆盖：\(scopeColors.joined(separator: " / "))）。")
                        .font(.system(size: 11))
                }

                Section {
                    ShopCatalogChartPasteButton(kind: .sizeChart,
                                                columnsText: $chartColumnsText,
                                                rowsText: $chartRowsText)
                    TextField("列名（逗号分隔，如：尺码,前裙长,推荐胸围）", text: $chartColumnsText)
                        .font(.system(size: 13))
                    TextEditor(text: $chartRowsText)
                        .frame(minHeight: 64)
                        .font(.system(size: 13))
                        .overlay(alignment: .topLeading) {
                            if chartRowsText.isEmpty {
                                Text("每行「标签:值,值,…」，如 S:80,78-83,60-66")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    TextField("单位（cm）", text: $chartUnit)
                    // 2026-09-26 需求：尺码表原图渲染为缩略图，不再显示文件名文本
                    if !chartImageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ShopCatalogSingleImagePreview(reference: chartImageText) {
                            chartImageText = ""
                        }
                    }
                    ShopCatalogImagePickerButton(mode: .replace, text: $chartImageText, label: "添加尺码表原图")
                } header: {
                    Text("款式尺码表（全款共享）")
                } footer: {
                    if recognizedSizes.isEmpty {
                        Text("列与行都清空 = 删除该款式的尺码表。")
                            .font(.system(size: 11))
                    } else {
                        Text("识别到的尺码：\(recognizedSizes.joined(separator: " / "))")
                            .font(.system(size: 11))
                    }
                }
            }
            .navigationTitle("款式资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var composedChart: CatalogSizeChart? {
        let parsed = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(chartColumnsText),
            rows: CatalogManualChartText.parseRows(chartRowsText))
        let image = chartImageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parsed.columns.isEmpty || !parsed.rows.isEmpty || !image.isEmpty else { return nil }
        var chart = CatalogSizeChart(id: "sizechart-style-\(representative.id.prefix(10))",
                                     productID: representative.id)
        chart.unit = chartUnit.trimmingCharacters(in: .whitespaces).isEmpty ? nil : chartUnit
        chart.columns = parsed.columns
        chart.rows = parsed.rows
        chart.sourceImage = image.isEmpty ? nil : image
        return chart
    }

    private var recognizedSizes: [String] {
        ShopCatalogSizeChartSharing.sizeLabels(of: composedChart)
    }

    private func load() {
        store.loadFromBundleIfNeeded()
        fabricText = store.fabric(forProduct: representative.id) ?? ""
        descriptionText = store.styleDescription(forProduct: representative.id) ?? ""
        // 尺码表读**款式共享**结果：即使本颜色没有自己的行，也能看到款式的表
        if let chart = store.sizeChart(forProduct: representative.id) {
            chartColumnsText = chart.columns.joined(separator: ",")
            chartRowsText = chart.rows
                .map { "\($0.label):" + $0.values.map { $0 ?? "" }.joined(separator: ",") }
                .joined(separator: "\n")
            chartUnit = chart.unit ?? ""
            chartImageText = chart.sourceImage ?? ""
        }
    }

    private func save() {
        do {
            let message = try ShopCatalogDraftStore.updateStylePublicInfo(
                fabric: fabricText,
                styleDescription: descriptionText,
                sizeChart: composedChart,
                forProductID: representative.id)
            toast = message
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
