//
//  OpsSeriesWizardTypeEditor.swift
//  PinkHouseOps
//
//  系列上新向导 S3：系列内多类型录入（需求 v1.2 的核心编辑页面）。
//
//  ## 页面结构
//
//      左列：类型条目列表（多选生成的条目，可增删、可切换）
//      右列：当前类型的完整编辑区
//            S3-A 公共资料（款式名；类型由多选结果确定）
//            S3-B 尺码表（结构化列/行 + 单位 + 原图；或「无尺码/均码」）
//            S3-C 价格（预约价/定金/尾款/现货价同屏；互相独立）
//            S3-D 颜色 SKU（颜色名 + 颜色图 + 可售尺码勾选）
//
//  ## 从需求逐条落下的交互约束
//
//  · 类型选择是**多选**，不是单选下拉框（§S3）；每个已选类型都有一套独立编辑区；
//  · 删除一个类型只删它**尚未提交的草稿条目**，且有明确确认，
//    不影响同系列其他类型（§S3）；
//  · 切换类型不丢输入 —— 输入直接写进 `workspace.seriesEntry`（自动持久化）；
//  · 可售尺码勾选项**来自当前类型尺码表**并按其原始顺序（§S3-B/§S3-D）；
//  · 颜色 SKU 不填价格 / 任务名称 / 批次 / 独立尺码表 / 款式描述（§S3-D）；
//  · 全程没有「任务名称」「批次」「款式描述」输入框（§1 / §5 验收）。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - S3 主视图（条目列表 + 当前类型编辑区）

struct OpsSeriesWizardTypeEntriesView: View {
    @ObservedObject var workspace: OpsWorkspace
    /// 请求返回 S4 时由外壳回调（S4 的「返回修改」会跳进来）
    var onRequestReview: () -> Void

    @State private var selectedEntryID: String?
    @State private var customCategoryText = ""
    @State private var entryPendingRemoval: OpsSeriesTypeEntry?
    @State private var showCustomCategory = false

    private var draft: OpsSeriesEntryDraft { workspace.seriesEntry }

    // MARK: 派生

    private var issues: [OpsSeriesEntryIssue] {
        OpsSeriesEntryValidator.validate(draft, catalog: workspace.catalog)
            .filter { $0.area == .typeEntries }
    }

    private func issues(forEntry entryID: String) -> [OpsSeriesEntryIssue] {
        issues.filter { $0.entryID == entryID }
    }

    private var selectedEntry: OpsSeriesTypeEntry? {
        draft.typeEntries.first { $0.id == selectedEntryID }
    }

    private var selectedBinding: Binding<OpsSeriesTypeEntry> {
        Binding(
            get: {
                draft.typeEntries.first { $0.id == selectedEntryID }
                    ?? draft.typeEntries.first
                    ?? OpsSeriesTypeEntry(category: "")
            },
            set: { newValue in
                if let index = workspace.seriesEntry.typeEntries.firstIndex(where: { $0.id == newValue.id }) {
                    workspace.seriesEntry.typeEntries[index] = newValue
                }
            })
    }

    var body: some View {
        HSplitView {
            entryListColumn
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 360)
            if let entry = selectedEntry ?? draft.typeEntries.first {
                OpsSeriesWizardTypeEditorView(workspace: workspace, entry: selectedBindingFor(entry))
                    .frame(minWidth: 560, idealWidth: 760)
            } else {
                emptyEditor
                    .frame(minWidth: 480, idealWidth: 640)
            }
        }
        .onAppear { clampSelection() }
        .onChange(of: draft.typeEntries.count) { _, _ in clampSelection() }
        .confirmationDialog(
            "删除类型「\(entryPendingRemoval?.displayName ?? "")」？",
            isPresented: Binding(
                get: { entryPendingRemoval != nil },
                set: { if !$0 { entryPendingRemoval = nil } }),
            titleVisibility: .visible) {
            Button("删除这个类型的草稿资料", role: .destructive) {
                if let target = entryPendingRemoval {
                    workspace.seriesEntry.typeEntries.removeAll { $0.id == target.id }
                }
                entryPendingRemoval = nil
            }
            Button("取消", role: .cancel) { entryPendingRemoval = nil }
        } message: {
            opsMarkdown("只删除该类型**尚未提交**的草稿资料，不影响同系列的其他类型，也不影响已写入目录的商品。")
                .font(.callout)
        }
    }

    private func selectedBindingFor(_ entry: OpsSeriesTypeEntry) -> Binding<OpsSeriesTypeEntry> {
        Binding(
            get: {
                workspace.seriesEntry.typeEntries.first { $0.id == entry.id } ?? entry
            },
            set: { newValue in
                if let index = workspace.seriesEntry.typeEntries.firstIndex(where: { $0.id == newValue.id }) {
                    workspace.seriesEntry.typeEntries[index] = newValue
                }
            })
    }

    private func clampSelection() {
        if !draft.typeEntries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = draft.typeEntries.first?.id
        }
    }

    private var emptyEditor: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(OpsFlowPalette.textSecondary)
            opsMarkdown("先在左上方**勾选类型**（如 JSK、OP、小物）——"
                        + "每个已选类型都会生成一套独立编辑区。")
                .font(.callout)
                .foregroundStyle(OpsFlowPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OpsFlowPalette.tileLilac, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }

    // MARK: 左列

    private var entryListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("本系列已选类型").font(.headline)
                    .foregroundStyle(OpsFlowPalette.textPrimary)
                Text("已选：\(draft.selectedCategorySummary)")
                    .font(.caption)
                    .foregroundStyle(OpsFlowPalette.textSecondary)
                categoryPicker
                Divider()
                Text("添加同类型另一款款式").font(.subheadline.weight(.semibold))
                    .foregroundStyle(OpsFlowPalette.textPrimary)
                addSameCategoryRow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if draft.typeEntries.isEmpty {
                Text("还没有类型。至少选择一个类型才能继续。")
                    .font(.callout).foregroundStyle(OpsFlowPalette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
            } else {
                List(selection: $selectedEntryID) {
                    ForEach(draft.typeEntries) { entry in
                        entryRow(entry).tag(entry.id)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(OpsFlowPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(OpsFlowPalette.cardBorder, lineWidth: 1))
        .shadow(color: OpsFlowPalette.cardShadow, radius: 10, x: 0, y: 4)
        .padding(12)
        .frame(maxHeight: .infinity)
    }

    /// 类型多选区（需求：多选，不是单选下拉框；保留枚举 + 扩展入口）
    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(OpsSeriesEntryCategory.known, id: \.self) { category in
                Toggle(isOn: bindingForKnownCategory(category)) {
                    HStack {
                        Text(category).font(.callout)
                        Spacer()
                        Text("已选 \(entryCount(for: category))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            HStack(spacing: 6) {
                TextField("自定义类型（扩展入口）", text: $customCategoryText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button("添加") { addCustomCategory() }
                    .controlSize(.small)
                    .disabled(customCategoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var addSameCategoryRow: some View {
        Menu {
            ForEach(orderedCategoriesInUse, id: \.self) { category in
                Button("新增一条 \(category) 款式") {
                    appendEntry(category: category)
                }
            }
        } label: {
            Label("添加条目…", systemImage: "plus")
        }
        .controlSize(.small)
        .disabled(orderedCategoriesInUse.isEmpty)
    }

    private var orderedCategoriesInUse: [String] {
        var ordered: [String] = []
        for entry in draft.typeEntries {
            let category = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !category.isEmpty, !ordered.contains(category) { ordered.append(category) }
        }
        return ordered
    }

    private func entryCount(for category: String) -> Int {
        draft.typeEntries.filter { $0.category == category }.count
    }

    /// 勾选 = 该类型至少有一条条目；勾上 → 建条目，取消 → 询问后删（走确认弹窗）
    private func bindingForKnownCategory(_ category: String) -> Binding<Bool> {
        Binding(
            get: { entryCount(for: category) > 0 },
            set: { isOn in
                if isOn {
                    appendEntry(category: category)
                } else if let first = draft.typeEntries.first(where: { $0.category == category }) {
                    entryPendingRemoval = first
                }
            })
    }

    private func addCustomCategory() {
        let category = customCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { return }
        appendEntry(category: category)
        customCategoryText = ""
    }

    private func appendEntry(category: String) {
        let entry = OpsSeriesTypeEntry(category: category)
        workspace.seriesEntry.typeEntries.append(entry)
        selectedEntryID = entry.id
    }

    private func entryRow(_ entry: OpsSeriesTypeEntry) -> some View {
        let entryIssues = issues(forEntry: entry.id)
        return OpsFlowTile(color: entry.id == selectedEntryID
            ? OpsFlowPalette.tilePink : OpsFlowPalette.tileLilac.opacity(0.55),
            selected: entry.id == selectedEntryID) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.displayName).lineLimit(1)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(OpsFlowPalette.textPrimary)
                    if entry.lastCommitOK == true {
                        OpsFlowChip(text: "已提交", tint: OpsFlowPalette.okGreen, filled: true)
                    } else if entry.lastCommitOK == false {
                        OpsFlowChip(text: "上次提交失败", tint: OpsFlowPalette.warnOrange)
                    }
                }
                HStack(spacing: 8) {
                    Text("\(entry.colors.count) 颜色")
                    if entry.usesSizeChart {
                        Text("有尺码表")
                    } else {
                        Text("均码")
                    }
                    if entryIssues.isEmpty {
                        Text("校验通过").foregroundStyle(OpsFlowPalette.okGreen)
                    } else {
                        Text("\(entryIssues.count) 个问题").foregroundStyle(OpsFlowPalette.warnOrange)
                    }
                }
                .font(.caption)
                .foregroundStyle(OpsFlowPalette.textSecondary)
            }
        }
        .contextMenu {
            Button("删除这个类型…", role: .destructive) { entryPendingRemoval = entry }
        }
    }
}

// MARK: - 单个类型条目的编辑区（S3-A/B/C/D）

struct OpsSeriesWizardTypeEditorView: View {
    @ObservedObject var workspace: OpsWorkspace
    @Binding var entry: OpsSeriesTypeEntry

    /// 图片导入的目标槽位（封面在 S2，这里只有尺码表原图与颜色图）
    private enum ImageSlot: Equatable {
        case chartSource
        case color(String)
    }
    @State private var importSlot: ImageSlot?
    @State private var showsImporter = false

    private var parsedChart: OpsSeriesParsedSizeChart? {
        OpsSeriesSizeChartParsing.parse(entry: entry).chart
    }

    private var entryIssues: [OpsSeriesEntryIssue] {
        var issues: [OpsSeriesEntryIssue] = []
        OpsSeriesEntryValidator.validateEntry(entry, into: &issues)
        return issues
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                publicInfoCard
                sizeChartCard
                priceCard
                colorSKUCard
                issuesCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OpsFlowPageBackground())
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false) { result in
            guard let slot = importSlot else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let assetID = workspace.importSingleImage(from: url) {
                    assignAsset(assetID, to: slot)
                }
            case .failure(let error):
                workspace.reportFailure("图片上传失败：\(error.localizedDescription)")
            }
            importSlot = nil
        }
    }

    private func assignAsset(_ assetID: String, to slot: ImageSlot) {
        switch slot {
        case .chartSource:
            entry.chartSourceImageAssetID = assetID
        case .color(let colorID):
            if let index = entry.colors.firstIndex(where: { $0.id == colorID }) {
                entry.colors[index].imageAssetID = assetID
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            if !entry.category.isEmpty {
                OpsFlowChip(text: entry.category, tint: OpsFlowPalette.accentPink, filled: true)
            }
            Text("当前编辑").font(.headline)
                .foregroundStyle(OpsFlowPalette.textPrimary)
            Spacer(minLength: 4)
        }
    }

    // MARK: S3-A 公共资料

    private var publicInfoCard: some View {
        OpsCard(title: "款式公共资料（当前类型的所有颜色共享）", systemImage: "tag") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("类型", value: entry.category.isEmpty ? "（未选择）" : entry.category)
                VStack(alignment: .leading, spacing: 3) {
                    Text("款式名（必填）").font(.callout)
                    TextField("如「星月夜」", text: $entry.designName)
                        .textFieldStyle(.roundedBorder)
                }
                OpsFootnote(text: "本页面**没有**「款式描述」输入框（需求 §S3-A）；"
                            + "尺码表只包含结构化列/行、单位和原图。")
            }
        }
    }

    // MARK: S3-B 尺码表

    private var sizeChartCard: some View {
        OpsCard(title: "尺码表（归属当前类型，不与其他类型共用）", systemImage: "ruler") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $entry.usesSizeChart) {
                    opsMarkdown("这个类型区分尺码（关闭 = **无尺码/均码**，如小物）")
                }
                if entry.usesSizeChart {
                    TextField("单位（如 cm）", text: $entry.chartUnit)
                        .textFieldStyle(.roundedBorder)
                    TextField("列名（逗号分隔，如：尺码, 前裙长, 推荐胸围）",
                              text: $entry.chartColumnsText)
                        .textFieldStyle(.roundedBorder)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("每一行一条：`S = 80, 78-83`").font(.callout)
                        TextEditor(text: $entry.chartRowsText)
                            .font(.body.monospaced())
                            .frame(height: 110)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    }
                    chartSourceRow
                    if let chart = parsedChart {
                        OpsFootnote(text: "可售尺码勾选项将从这些行按**原始顺序**生成："
                                    + chart.sizeLabels.joined(separator: "、"))
                    } else {
                        OpsFootnote(text: "还没有结构化内容：列和行**同时**填写或**同时**留空；"
                                    + "只有原图时可以都为空。")
                    }
                } else {
                    OpsFootnote(text: "均码模式：颜色 SKU 不勾尺码（规格不区分尺码）。"
                                + "**不能借用其他类型的尺码表**。")
                }
            }
        }
    }

    private var chartSourceRow: some View {
        HStack(spacing: 8) {
            OpsThumbnail(
                url: entry.chartSourceImageAssetID.flatMap {
                    workspace.stagedFileURL(forReference: workspace.asset(for: $0)?.originalURL)
                }, size: 40)
            Picker("尺码表原图", selection: $entry.chartSourceImageAssetID) {
                Text("不指定").tag(String?.none)
                ForEach(workspace.catalog.assets) { asset in
                    Text(assetFileLabel(asset)).tag(String?.some(asset.id))
                }
            }
            .controlSize(.small)
            Button("上传原图…") {
                importSlot = .chartSource
                showsImporter = true
            }
            .controlSize(.small)
        }
    }

    // MARK: S3-C 价格

    private var priceCard: some View {
        OpsCard(title: "价格（当前类型只填一次；不同类型互相独立）", systemImage: "yensign.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("币种", selection: $entry.currency) {
                    ForEach(CatalogCurrency.allCases.filter { !$0.isUnknown }) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack(spacing: 10) {
                    priceField("预约价", $entry.reservationPriceText)
                    priceField("定金", $entry.depositText)
                    priceField("尾款", $entry.balanceText)
                    priceField("现货价", $entry.stockPriceText)
                }
                priceSummary
                OpsFootnote(text: "预约价与现货价**至少填一项**且**互相独立**："
                            + "改现货价不清空、不覆盖、不重算预约价；改预约价不改现货价。"
                            + "三者全填时校验「定金 + 尾款 = 预约价」。"
                            + "颜色 SKU 页**不重复填写价格**。")
            }
        }
    }

    private func priceField(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
        }
    }

    private var priceSummaryText: String {
        let parsed = OpsSeriesPriceParsing.parse(entry: entry)
        let currency = parsed.price.currency
        let symbol = currency.isUnknown ? "¥" : currency.symbol
        func amount(_ value: Decimal?) -> String {
            guard let value else { return "暂无" }
            return "\(symbol)\(value)"
        }
        if let reservation = parsed.price.reservation {
            var line = "预约价 " + amount(reservation)
            if let deposit = parsed.price.deposit, let balance = parsed.price.balance {
                let ok = deposit + balance == reservation
                line += " = 定金 " + amount(deposit) + " + 尾款 " + amount(balance)
                    + (ok ? " ✓" : "（不等，见下方校验）")
            }
            if let stock = parsed.price.stock {
                line += "；现货价 " + amount(stock) + "（独立）"
            }
            return line
        }
        if let stock = parsed.price.stock {
            return "现货价 " + amount(stock) + "（独立）"
        }
        return "预约价与现货价至少填一项。"
    }

    @ViewBuilder
    private var priceSummary: some View {
        let parsed = OpsSeriesPriceParsing.parse(entry: entry)
        if parsed.price.reservation != nil || parsed.price.stock != nil {
            opsMarkdown(priceSummaryText)
                .font(.callout.weight(.medium))
        } else {
            Text("预约价与现货价至少填一项。")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    // MARK: S3-D 颜色 SKU

    private var colorSKUCard: some View {
        OpsCard(title: "颜色 SKU（\(entry.colors.count)）", systemImage: "paintpalette") {
            VStack(alignment: .leading, spacing: 10) {
                if entry.colors.isEmpty {
                    Text("还没有颜色。至少填写一个颜色，名称不能为空。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach($entry.colors) { $color in
                        colorRow($color)
                        Divider()
                    }
                }
                Button {
                    entry.colors.append(OpsSeriesColorSKU())
                } label: {
                    Label("添加颜色", systemImage: "plus")
                }
                .controlSize(.small)
                OpsFootnote(text: "追加颜色时，本类型的公共资料、尺码表和价格**只读继承**，"
                            + "不会因为新增颜色被覆盖；颜色也不能追加到其他类型。"
                            + "颜色 SKU **不填**价格 / 任务名称 / 批次 / 独立尺码表 / 款式描述。")
            }
        }
    }

    private func colorRow(_ color: Binding<OpsSeriesColorSKU>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OpsThumbnail(
                    url: color.wrappedValue.imageAssetID.flatMap {
                        workspace.stagedFileURL(forReference: workspace.asset(for: $0)?.originalURL)
                    }, size: 36)
                TextField("颜色名称（必填，如「绯红」）", text: color.name)
                    .textFieldStyle(.roundedBorder)
                Button("上传图…") {
                    importSlot = .color(color.wrappedValue.id)
                    showsImporter = true
                }
                .controlSize(.small)
                Button(role: .destructive) {
                    entry.colors.removeAll { $0.id == color.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("删除这个颜色（只影响当前类型）")
            }
            sizeChecklist(for: color)
        }
        .padding(.vertical, 2)
    }

    /// 可售尺码勾选：**只来自当前类型尺码表**，按尺码表原始顺序展示；
    /// 均码模式（无尺码表）不展示勾选。
    @ViewBuilder
    private func sizeChecklist(for color: Binding<OpsSeriesColorSKU>) -> some View {
        if entry.usesSizeChart, let chart = parsedChart {
            VStack(alignment: .leading, spacing: 4) {
                Text("可售尺码（来自当前类型尺码表）").font(.caption).foregroundStyle(.secondary)
                // 勾选项顺序 = 尺码表原始顺序（绝不用无序集合遍历序）
                HStack(spacing: 10) {
                    ForEach(chart.sizeLabels, id: \.self) { label in
                        Toggle(label, isOn: Binding(
                            get: { color.wrappedValue.selectedSizes.contains(label) },
                            set: { isOn in
                                var picked = color.wrappedValue.selectedSizes
                                if isOn {
                                    if !picked.contains(label) { picked.append(label) }
                                } else {
                                    picked.removeAll { $0 == label }
                                }
                                // 保存时立即归一成尺码表原始顺序
                                color.wrappedValue.selectedSizes =
                                    chart.sizeLabels.filter { picked.contains($0) }
                            }))
                            .toggleStyle(.checkbox)
                            .font(.callout)
                    }
                }
            }
            .padding(.leading, 44)
        } else if entry.usesSizeChart {
            Text("尺码表还没有结构化内容：先在上方填写列与行，才能生成可售尺码勾选项。")
                .font(.caption).foregroundStyle(.orange)
                .padding(.leading, 44)
        } else {
            Text("无尺码/均码：不需要勾选尺码。")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 44)
        }
    }

    // MARK: 当前条目的校验结果（实时）

    @ViewBuilder
    private var issuesCard: some View {
        let issues = entryIssues
        if !issues.isEmpty {
            OpsCard(title: "这个类型还没有完成的部分", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues) { issue in
                        Label {
                            opsMarkdown(issue.message)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    // MARK: 小工具

    private func assetFileLabel(_ asset: CatalogAsset) -> String {
        workspace.stagedFileURL(forReference: asset.originalURL)?.lastPathComponent
            ?? asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }
}
