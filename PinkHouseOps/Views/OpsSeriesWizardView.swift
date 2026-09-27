//
//  OpsSeriesWizardView.swift
//  PinkHouseOps
//
//  系列上新向导 S1–S5 的外壳（需求《Mac 商品发布流程实现需求说明》v1.2）。
//
//  ## 分步与门禁
//
//  每一步「下一步」都只检查**本步**的校验问题（`OpsSeriesEntryIssue.area`），
//  有问题就停在当前页并逐条列出 —— 需求 §4 的错误文案逐字对齐：
//  「至少选择一个类型」「款式名不能为空」「定金 + 尾款必须等于预约价」…
//
//  ## 全流程硬边界（§5 验收）
//
//  · 找不到「任务名称」输入框；找不到「批次」输入框 —— 类型上没有这两个字段；
//  · 一个系列可以同时选择多个类型，仍在同一个系列流程内完成；
//  · S4 只读；发现问题时「返回修改」回到对应步骤；
//  · S5 的「提交」= 逐类型写入本地草稿（复用现有链路），**不是**发布：
//    发布走受控发布链路（导出待发布包 → 受控发布器），公共 CloudKit
//    上架状态以回读确认为准，这里绝不显示虚假的「已上架」。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 步骤

enum OpsSeriesWizardStep: Int, CaseIterable, Identifiable {
    case selectShopSeries = 1
    case seriesProfile = 2
    case typeEntries = 3
    case review = 4
    case publish = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .selectShopSeries: return "S1·选择店家与系列"
        case .seriesProfile: return "S2·系列资料与发售阶段"
        case .typeEntries: return "S3·系列内多类型录入"
        case .review: return "S4·检查与预览"
        case .publish: return "S5·状态与发布"
        }
    }

    /// 步骤条上的紧凑标题（完整标题在窄窗口会被截断，图2 的步骤条本身就是短词）
    var compactTitle: String {
        switch self {
        case .selectShopSeries: return "S1·店家与系列"
        case .seriesProfile: return "S2·系列资料"
        case .typeEntries: return "S3·类型录入"
        case .review: return "S4·检查预览"
        case .publish: return "S5·状态发布"
        }
    }

    var area: OpsSeriesEntryArea? {
        switch self {
        case .selectShopSeries: return .shopSeries
        case .seriesProfile: return .seriesProfile
        case .typeEntries: return .typeEntries
        case .review, .publish: return nil
        }
    }
}

// MARK: - 外壳

struct OpsSeriesWizardView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var step: OpsSeriesWizardStep = .selectShopSeries
    /// 「下一步」被本步校验拦下时展示的问题（逐条、带定位）
    @State private var gateIssues: [OpsSeriesEntryIssue] = []
    /// S5 的提交报告（nil = 还没提交过）
    @State private var commitReport: OpsSeriesEntryCommitReport?

    private var draft: OpsSeriesEntryDraft { workspace.seriesEntry }

    /// `draft` 是计算属性，没有 `$` 投影 —— 向导字段的 Binding 统一走这个辅助，
    /// 写入永远落到 `workspace.seriesEntry`（@Published，自动持久化）。
    private func bind<T>(_ keyPath: WritableKeyPath<OpsSeriesEntryDraft, T>) -> Binding<T> {
        Binding(
            get: { workspace.seriesEntry[keyPath: keyPath] },
            set: { workspace.seriesEntry[keyPath: keyPath] = $0 })
    }

    private var allIssues: [OpsSeriesEntryIssue] {
        OpsSeriesEntryValidator.validate(draft, catalog: workspace.catalog)
    }

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()
                .overlay(OpsFlowPalette.cardBorder)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .background(OpsFlowPageBackground())
    }

    // MARK: 步骤条（图2 顶部：数字圆徽 + 连接线 + 标题）

    private var stepHeader: some View {
        OpsFlowStepHeader(
            steps: OpsSeriesWizardStep.allCases.map(\.compactTitle),
            currentIndex: OpsSeriesWizardStep.allCases.firstIndex(of: step) ?? 0)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch step {
        case .selectShopSeries: shopSeriesStep
        case .seriesProfile: seriesProfileStep
        case .typeEntries:
            OpsSeriesWizardTypeEntriesView(workspace: workspace)
        case .review:
            OpsSeriesWizardReviewView(
                workspace: workspace,
                issues: allIssues,
                onReturnToStep: { target in
                    gateIssues = []
                    step = target
                })
        case .publish:
            OpsSeriesWizardPublishView(
                workspace: workspace,
                issues: allIssues,
                report: commitReport,
                onCommit: { commit() },
                onResetWizard: {
                    commitReport = nil
                    workspace.resetSeriesEntry()
                    step = .selectShopSeries
                })
        }
    }

    // MARK: S1 选择店家与系列

    private var shopSeriesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OpsCard(title: "店家与系列（必填）", systemImage: "storefront") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("店家", selection: shopChoice) {
                            Text("请选择店家").tag("")
                            Text("＋ 新建店家…").tag(Self.newShopChoiceTag)
                            ForEach(workspace.catalog.shops) { shop in
                                Text(shop.name).tag(shop.id)
                            }
                        }
                        if draft.createsNewShop {
                            newShopFields
                        }
                        Picker("系列", selection: seriesChoice) {
                            Text("请选择系列").tag("")
                            Text("＋ 新建系列…").tag("__new__")
                            ForEach(seriesUnderShop) { series in
                                Text(series.name).tag(series.id)
                            }
                        }
                        if draft.seriesID.isEmpty {
                            newSeriesFields
                        }
                        // 需求 §S1：不显示、不保存任务名称与批次
                        OpsFootnote(text: "本流程**没有**「任务名称」与「批次」（需求 §S1）："
                                    + "一次上新的归属就是店家 → 系列。")
                    }
                }
                affiliationSummary
            }
            .padding(18)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    /// 「＋ 新建店家…」在店家 Picker 里的哨兵 tag（与系列的 "__new__" 同一手法）
    static let newShopChoiceTag = "__new_shop__"

    /// 已有店家 id；「＋ 新建店家…」= createsNewShop 开关。选择态与草稿互转。
    private var shopChoice: Binding<String> {
        Binding(
            get: { draft.createsNewShop ? Self.newShopChoiceTag : draft.shopID },
            set: { newValue in
                if newValue == Self.newShopChoiceTag {
                    workspace.seriesEntry.createsNewShop = true
                } else {
                    workspace.seriesEntry.createsNewShop = false
                    workspace.seriesEntry.shopID = newValue
                }
            })
    }

    /// 新建店家的内联字段（店名必填、别名可选）。
    /// 输入随草稿持久化 —— 与新系列字段同一原则：失败不丢输入。
    private var newShopFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("新店家名（必填）", text: bind(\.newShopName))
                .textFieldStyle(.roundedBorder)
            TextField("别名（英文逗号分隔，可空，用于搜索匹配）", text: bind(\.newShopAliasesText))
                .textFieldStyle(.roundedBorder)
            OpsFootnote(text: "提交时先建店家、再建系列：店家和系列会一起出现在「店家与系列」页，"
                        + "后续操作里都能正常选用。")
        }
    }

    /// 已有系列 id；空 = 新建。选择态与草稿互转。
    private var seriesChoice: Binding<String> {
        Binding(
            get: { draft.seriesID },
            set: { newValue in
                workspace.seriesEntry.seriesID = newValue == "__new__" ? "" : newValue
            })
    }

    private var seriesUnderShop: [CatalogSeries] {
        guard !draft.shopID.isEmpty else { return [] }
        return workspace.catalog.series.filter { $0.shopID == draft.shopID }
    }

    private var newSeriesFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("新系列名（必填）", text: bind(\.newSeriesName))
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                TextField("年份（可空，如 2026）", text: bind(\.newSeriesYearText))
                TextField("月份（可空，1–12）", text: bind(\.newSeriesMonthText))
                TextField("季节（可空，如「冬」）", text: bind(\.newSeriesSeason))
            }
        }
    }

    /// 页面下方的归属摘要（需求 §S1）
    @ViewBuilder
    private var affiliationSummary: some View {
        let names = affiliationNames
        OpsCard(title: "归属摘要", systemImage: "arrow.turn.down.right") {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("店家", value: names.shop)
                LabeledContent("系列", value: names.series)
                LabeledContent("已选类型", value: draft.selectedCategorySummary)
            }
        }
    }

    private var affiliationNames: (shop: String, series: String) {
        let shop: String
        if draft.createsNewShop {
            let name = draft.newShopName.trimmingCharacters(in: .whitespacesAndNewlines)
            shop = name.isEmpty ? "（新建）" : name + "（新建）"
        } else {
            shop = workspace.catalog.shops.first { $0.id == draft.shopID }?.name
                ?? "（未选择）"
        }
        let series: String
        if draft.seriesID.isEmpty {
            let name = draft.newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
            series = name.isEmpty ? "（未选择）" : name + "（新建）"
        } else {
            series = workspace.catalog.series.first { $0.id == draft.seriesID }?.name
                ?? "（不存在）"
        }
        return (shop, series)
    }

    // MARK: S2 系列资料与发售阶段

    @State private var showsCoverImporter = false

    private var seriesProfileStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OpsCard(title: "系列封面", systemImage: "photo") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            OpsThumbnail(
                                url: draft.coverAssetID.flatMap {
                                    workspace.stagedFileURL(
                                        forReference: workspace.asset(for: $0)?.originalURL)
                                }, size: 64)
                            Picker("封面", selection: bind(\.coverAssetID)) {
                                Text("不指定").tag(String?.none)
                                ForEach(workspace.catalog.assets) { asset in
                                    Text(assetFileLabel(asset)).tag(String?.some(asset.id))
                                }
                            }
                            .controlSize(.small)
                            Button("上传封面…") { showsCoverImporter = true }
                                .controlSize(.small)
                        }
                        OpsFootnote(text: "没有封面也能继续；发布门禁会按「商品没有图」等口径另行提示。")
                    }
                }

                OpsCard(title: "销售阶段与时间", systemImage: "calendar.badge.clock") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("销售阶段", selection: phaseChoice) {
                            Text("不声明（由档期推导）").tag(String?.none)
                            ForEach(CatalogSeriesSalePhase.allCases) { item in
                                Text(item.displayName).tag(String?.some(item.rawValue))
                            }
                        }
                        OpsOptionalDateField(
                            label: "预约结束时间（声明「预约中」时**必填**，驱动自动流转）",
                            isOn: bind(\.hasReservationEnd),
                            date: bind(\.reservationEndAt))
                        OpsOptionalDateField(
                            label: "尾款开始时间（可选）",
                            isOn: bind(\.hasBalanceStart),
                            date: bind(\.balanceStartAt))
                        OpsOptionalDateField(
                            label: "尾款结束时间（可选，**仅展示和提醒，不自动切换为现货**）",
                            isOn: bind(\.hasBalanceEnd),
                            date: bind(\.balanceEndAt))
                        OpsFootnote(text: "本页面**不填写商品价格** —— 价格统一放到下一步，"
                                    + "按当前类型与该类型的颜色、尺码放在一起（需求 §S2）。")
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .fileImporter(
            isPresented: $showsCoverImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let assetID = workspace.importSingleImage(from: url) {
                    workspace.seriesEntry.coverAssetID = assetID
                }
            case .failure(let error):
                workspace.reportFailure("图片上传失败：\(error.localizedDescription)")
            }
        }
    }

    private var phaseChoice: Binding<String?> {
        Binding(
            get: { draft.declaresPhase ? draft.phaseRawValue : nil },
            set: { newValue in
                workspace.seriesEntry.phase = newValue.flatMap { CatalogSeriesSalePhase(rawValue: $0) }
            })
    }

    private func assetFileLabel(_ asset: CatalogAsset) -> String {
        workspace.stagedFileURL(forReference: asset.originalURL)?.lastPathComponent
            ?? asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }

    // MARK: 底部导航（图2 底部的深藏青说明条）

    private var footer: some View {
        OpsFlowFooterBar {
            if !gateIssues.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                OpsFlowFooterText(text: gateIssues.map(\.message).joined(separator: "；"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                OpsFlowFooterText(
                    text: "所有编辑先写进本机草稿；发布走受控发布链路完成。",
                    dimmed: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if step != OpsSeriesWizardStep.allCases.first {
                Button("上一步") {
                    gateIssues = []
                    if let previous = OpsSeriesWizardStep(rawValue: step.rawValue - 1) {
                        step = previous
                    }
                }
                .buttonStyle(OpsFlowSecondaryButtonStyle(tint: .white, ghost: true))
            }
            if step != OpsSeriesWizardStep.allCases.last {
                Button("下一步") { goNext() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(OpsFlowPrimaryButtonStyle(tint: OpsFlowPalette.primaryPurple))
            }
        }
    }

    private func goNext() {
        // 只拦本步的问题：后面步骤的问题由后面那步的「下一步」与 S4/S5 的全量校验负责
        if let area = step.area {
            let stepIssues = allIssues.filter { $0.area == area }
            guard stepIssues.isEmpty else {
                gateIssues = stepIssues
                return
            }
        }
        gateIssues = []
        if let next = OpsSeriesWizardStep(rawValue: step.rawValue + 1) {
            step = next
        }
    }

    // MARK: S5 提交

    private func commit() {
        commitReport = workspace.commitSeriesEntry()
    }
}

// MARK: - S4 检查与预览（只读）

struct OpsSeriesWizardReviewView: View {
    @ObservedObject var workspace: OpsWorkspace
    let issues: [OpsSeriesEntryIssue]
    /// 返回修改：回到对应步骤
    let onReturnToStep: (OpsSeriesWizardStep) -> Void

    private var draft: OpsSeriesEntryDraft { workspace.seriesEntry }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                seriesSummary
                ForEach(draft.typeEntries) { entry in
                    entrySummary(entry)
                }
                issueSummary
            }
            .padding(18)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    private var seriesSummary: some View {
        // 「＋ 新建店家」在 S4 还没落库（提交发生在 S5），按新建语义展示而不是「未选择」
        let shopName: String
        if draft.createsNewShop {
            let name = draft.newShopName.trimmingCharacters(in: .whitespacesAndNewlines)
            shopName = name.isEmpty ? "（新建）" : name + "（新建）"
        } else {
            shopName = workspace.catalog.shops.first { $0.id == draft.shopID }?.name ?? "（未选择）"
        }
        let seriesName = draft.seriesID.isEmpty
            ? (draft.newSeriesName.isEmpty ? "（未选择）" : draft.newSeriesName + "（新建）")
            : (workspace.catalog.series.first { $0.id == draft.seriesID }?.name ?? "（不存在）")
        let cover = draft.coverAssetID != nil ? "有" : "无"
        let phaseText = draft.phase?.displayName ?? "不声明（由档期推导）"
        return OpsCard(title: "系列（只读摘要）", systemImage: "storefront") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("店家", value: shopName)
                LabeledContent("系列", value: seriesName)
                LabeledContent("封面", value: cover)
                LabeledContent("销售阶段", value: phaseText)
                if draft.hasReservationEnd {
                    LabeledContent("预约结束", value: draft.reservationEndAt.formatted(
                        .dateTime.year().month().day().hour().minute()))
                }
                if draft.hasBalanceStart {
                    LabeledContent("尾款开始", value: draft.balanceStartAt.formatted(
                        .dateTime.year().month().day().hour().minute()))
                }
                if draft.hasBalanceEnd {
                    LabeledContent("尾款结束（仅提醒）", value: draft.balanceEndAt.formatted(
                        .dateTime.year().month().day().hour().minute()))
                }
                LabeledContent("已选类型", value: draft.selectedCategorySummary)
                OpsFootnote(text: "本页**只读**，不重复编辑价格或尺码表；"
                            + "发现问题用每张卡右上角的「返回修改」。")
            }
        }
    }

    private func entrySummary(_ entry: OpsSeriesTypeEntry) -> some View {
        let chart = OpsSeriesSizeChartParsing.parse(entry: entry).chart
        let price = OpsSeriesPriceParsing.parse(entry: entry)
        let entryIssues = issues.filter { $0.entryID == entry.id }
        return OpsCard(title: "类型：\(entry.displayName)", systemImage: "tshirt") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer()
                    Button("返回修改") { onReturnToStep(.typeEntries) }
                        .controlSize(.small)
                }
                LabeledContent("款式名", value: entry.designName.isEmpty ? "（未填）" : entry.designName)
                LabeledContent("类型", value: entry.category)

                // 尺码表
                Divider()
                if entry.usesSizeChart {
                    if let chart {
                        LabeledContent("单位", value: chart.unit ?? "（未填）")
                        LabeledContent("尺码表",
                                       value: "\(chart.columns.count) 列 · \(chart.rows.count) 行"
                                       + (entry.chartSourceImageAssetID != nil ? " · 有原图" : " · 无原图"))
                        Text(chart.columns.joined(separator: " ｜ "))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        ForEach(Array(chart.rows.enumerated()), id: \.offset) { _, row in
                            Text(row.label + "：" + row.values.map { $0 ?? "-" }.joined(separator: " ｜ "))
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("尺码表", value: "只有原图，没有结构化列/行")
                    }
                } else {
                    LabeledContent("尺码表", value: "无尺码/均码")
                }

                // 颜色
                Divider()
                ForEach(entry.colors) { color in
                    HStack(spacing: 8) {
                        OpsThumbnail(url: color.imageAssetID.flatMap {
                            workspace.stagedFileURL(forReference: workspace.asset(for: $0)?.originalURL)
                        }, size: 28)
                        Text(color.name.isEmpty ? "（未命名颜色）" : color.name)
                        Text("可售尺码：" + (color.selectedSizes.isEmpty ? "（未勾选）"
                                           : color.selectedSizes.joined(separator: "、")))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                // 价格（按类型展示，不合并多类型）
                Divider()
                opsMarkdown(priceSummaryLine(entry, price))
                    .font(.callout.weight(.medium))
                LabeledContent("独立校验", value: depositBalanceVerdict(entry, price))
                LabeledContent("预约 / 现货", value: "两个独立字段保存，互不覆盖")

                if !entryIssues.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(entryIssues) { issue in
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
    }

    /// 需求 §S4 的价格摘要格式：
    /// 「JSK：预约价 ¥688 = 定金 ¥208 + 尾款 ¥480；现货价 ¥820（独立）」
    private func priceSummaryLine(_ entry: OpsSeriesTypeEntry,
                                  _ parsed: (price: OpsSeriesParsedPrice, issues: [String])) -> String {
        let currency = parsed.price.currency
        let symbol = currency.isUnknown ? "¥" : currency.symbol
        func amount(_ value: Decimal?) -> String {
            guard let value else { return "暂无" }
            return "\(symbol)\(value)"
        }
        var parts: [String] = []
        if let reservation = parsed.price.reservation {
            var line = "预约价 " + amount(reservation)
            if parsed.price.deposit != nil || parsed.price.balance != nil {
                line += " = 定金 " + amount(parsed.price.deposit)
                    + " + 尾款 " + amount(parsed.price.balance)
            }
            parts.append(line)
        }
        if let stock = parsed.price.stock {
            parts.append("现货价 " + amount(stock) + "（独立）")
        }
        return "\(entry.displayName)：" + (parts.isEmpty ? "价格未填写" : parts.joined(separator: "；"))
    }

    private func depositBalanceVerdict(_ entry: OpsSeriesTypeEntry,
                                       _ parsed: (price: OpsSeriesParsedPrice, issues: [String])) -> String {
        if parsed.price.reservation != nil, parsed.price.deposit != nil,
           parsed.price.balance != nil {
            return parsed.price.deposit! + parsed.price.balance! == parsed.price.reservation!
                ? "定金 + 尾款 = 预约价 ✓" : "定金 + 尾款 ≠ 预约价（有校验问题）"
        }
        return "未同时填写（不适用）"
    }

    @ViewBuilder
    private var issueSummary: some View {
        let global = issues.filter { $0.entryID == nil }
        if !global.isEmpty {
            OpsCard(title: "系列级问题", systemImage: "exclamationmark.triangle.fill") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(global) { issue in
                        HStack {
                            opsMarkdown(issue.message)
                            Spacer(minLength: 8)
                            Button("返回修改") {
                                onReturnToStep(issue.area == .seriesProfile ? .seriesProfile : .selectShopSeries)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - S5 状态与发布

struct OpsSeriesWizardPublishView: View {
    @ObservedObject var workspace: OpsWorkspace
    let issues: [OpsSeriesEntryIssue]
    let report: OpsSeriesEntryCommitReport?
    let onCommit: () -> Void
    let onResetWizard: () -> Void

    private var draft: OpsSeriesEntryDraft { workspace.seriesEntry }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stateMachineCard
                if let report {
                    reportCard(report)
                }
                if !issues.isEmpty {
                    issuesCard
                }
                actionsCard
                honestyCard
            }
            .padding(18)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    /// 系列级沿用现有草稿状态机：写入草稿 → 校验/构建待发布包 → 受控发布 → 回读 → 线上
    private var stateMachineCard: some View {
        OpsCard(title: "系列级状态", systemImage: "arrow.clockwise.circle") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("草稿", value: workspace.draft?.title ?? "（无草稿）")
                LabeledContent("编辑版本", value: "第 \(workspace.currentRevision) 版"
                    + (workspace.hasUnsavedChanges ? "（有未保存修改）" : "（已保存）"))
                LabeledContent("系列内类型", value: draft.selectedCategorySummary)
                OpsFootnote(text: "每个类型走同一条商品发布链路："
                            + "草稿 → 校验与构建待发布包 → 受控发布 → 回读确认。")
            }
        }
    }

    @ViewBuilder
    private func reportCard(_ report: OpsSeriesEntryCommitReport) -> some View {
        OpsCard(title: "上次系列级提交结果（逐类型）", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 8) {
                if report.blocked {
                    opsMarkdown("整次提交被校验拦下，**没有写入任何内容**（需求 §S3-E："
                                + "任何一个类型缺必填项时，不能假装全部完成）。")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(report.blockedByValidation) { issue in
                        Text("· \(issue.entryName.isEmpty ? "" : issue.entryName + "：")\(issue.message)")
                            .font(.callout)
                    }
                } else {
                    ForEach(report.entryResults) { result in
                        HStack(spacing: 8) {
                            Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.ok ? Color.green : Color.orange)
                            Text(result.entryName)
                            opsMarkdown(result.message)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !report.draftSaved {
                        opsMarkdown("⚠️ 草稿**落盘失败**：内容还在界面上，请重新保存（需求 §S5：提交失败不丢失输入）。")
                            .font(.callout).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var issuesCard: some View {
        OpsCard(title: "还有校验问题（提交会被拦下）", systemImage: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues) { issue in
                    Text("· \(issue.entryName.isEmpty ? "" : issue.entryName + "：")\(issue.message)")
                        .font(.callout)
                }
            }
        }
    }

    private var actionsCard: some View {
        OpsCard(title: "提交整个系列", systemImage: "paperplane.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onCommit) {
                    Label("提交整个系列（逐类型写入草稿）", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!issues.isEmpty || workspace.isCorrupted)
                if !issues.isEmpty {
                    OpsFootnote(text: "还有校验问题未解决 —— 先到「S3 类型录入」逐条处理，"
                                + "或回 S4 查看定位。**输入不会因为提交被拦而丢失**。")
                }
                if let report, report.allOK {
                    Button("这个系列已完成，重开一个新向导") { onResetWizard() }
                }
            }
        }
    }

    private var honestyCard: some View {
        OpsCard(title: "发布与上架状态（不显示虚假的「已上架」）", systemImage: "cloud") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("已写入本地草稿",
                               value: report?.allOK == true ? "是（逐类型）" : "尚未全部完成")
                LabeledContent("App 侧发布", value: "本工具校验并构建待发布包 → 交给受控发布器")
                LabeledContent("公共 CloudKit 上架", value: "以发布器的**回读确认**为准；未回读前一律显示「待回读」")
                OpsFootnote(text: "本页**不会**声称「已上架」——上架与否只看受控发布器的回读结果"
                            + "（方案 R07/R09 的既有口径）。")
            }
        }
    }
}
