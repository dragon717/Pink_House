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
//  · S5 的「提交」= **保存**：逐类型写入本地草稿并落盘。反馈只有一条、只有两种：
//    保存成功 / 保存失败（带可定位原因）。**不顺手发布** —— R07 比对草稿基线，
//    而 App 从不回填它，自动发布只会被稳定拒绝（2026-10-07 实测退出码 5）；
//    发布 = 「发布整个系列」一键（或右上角「云端更新」），失败给日志文件路径。
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

    /// 起始步骤。默认 S1；快照 harness 需要从 S2 起手（拍「系列价格表」那张卡），
    /// 所以留一个显式入口 —— 与 `OpsMainView(initialSection:)` 同一个手法：
    /// **只是初值**，之后完全由「上一步 / 下一步」驱动。
    init(workspace: OpsWorkspace, initialStep: OpsSeriesWizardStep = .selectShopSeries) {
        _workspace = ObservedObject(wrappedValue: workspace)
        _step = State(initialValue: initialStep)
    }

    @State private var step: OpsSeriesWizardStep = .selectShopSeries
    /// 「下一步」被本步校验拦下时展示的问题（逐条、带定位）
    @State private var gateIssues: [OpsSeriesEntryIssue] = []
    /// S5 提交后的**唯一**结果反馈（nil = 还没提交过）。
    /// 只有一个值 —— 新的提交会整体替换上一条，不会叠加。
    @State private var submitFeedback: OpsSeriesSubmitFeedback?
    /// 「发布整个系列」的结果反馈（nil = 还没发布过）。同样只保留一条。
    @State private var publishFeedback: OpsSeriesPublishFeedback?
    /// 发布进行中（落库草稿箱 → 受控发布 → 回读）。期间发布按钮禁用。
    @State private var isPublishing = false

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
                feedback: submitFeedback,
                publishFeedback: publishFeedback,
                isPublishing: isPublishing,
                onCommit: { commit() },
                onPublish: { publishSeries() })
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
                // ⚠️ 切系列必须**重新装载价格表块**，否则就是数据损坏：
                // 向导草稿是长期存在的（`seriesEntryJSON`），在 A 系列填/传的价格表
                // 会被原样写进 B 系列，而界面上完全看不出异常。
                reloadPriceChartFromSelectedSeries()
            })
    }

    /// 把 S2 的价格表块换成「当前所选系列此刻的样子」。
    ///
    /// · 系列已有价格表 → 开关自动打开、单位/列名/行/原图一并载入（进来就能改）；
    /// · 系列没有价格表、或选了「新建系列」→ **清空**，绝不把上一个系列的表格带过去。
    ///
    /// ⭐ 只在**用户显式切换系列**时调用，不做 `onAppear` 自动装载 ——
    /// 那会把手打了一半、还没提交的向导内容用系列上的旧值覆盖掉（违反「失败不丢输入」）。
    private func reloadPriceChartFromSelectedSeries() {
        guard let series = workspace.catalog.series.first(where: { $0.id == draft.seriesID }),
              let chart = series.priceChart else {
            workspace.seriesEntry.declaresPriceChart = false
            workspace.seriesEntry.priceChartUnit = ""
            workspace.seriesEntry.priceChartColumnsText = ""
            workspace.seriesEntry.priceChartRowsText = ""
            workspace.seriesEntry.priceChartImageAssetIDs = []
            return
        }
        workspace.seriesEntry.declaresPriceChart = true
        workspace.seriesEntry.priceChartUnit = chart.unit ?? ""
        workspace.seriesEntry.priceChartColumnsText = chart.columns.joined(separator: ", ")
        workspace.seriesEntry.priceChartRowsText = chart.rows
            .map { $0.label + " = " + $0.values.map { $0 ?? "" }.joined(separator: ", ") }
            .joined(separator: "\n")
        workspace.seriesEntry.priceChartImageAssetIDs =
            chart.sourceImages ?? chart.sourceImage.map { [$0] } ?? []
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
                // ⭐ 指路：价格表是**系列级**资料，收在 S2。不写这一句，
                // 在 S1 找「上传价格表」的人会以为这个功能不见了
                // （2026-10-06 用户就是这么问的）。
                OpsFootnote(text: "系列价格表在下一步「**S2·系列资料**」里上传图片或录表格 ——"
                            + "本页只做选择，不收内容。")
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

    // 系列价格表（S2）：上传原图 + 结构化列行。三处独立状态，因为它们是三件事：
    @State private var showsPriceChartImporter = false
    /// 上传**失败**的逐条原因（含格式不支持）。与下面的 note 分开存 ——
    /// 「传上去 3 张、坏了 1 张」时两句话要同时看得见，不能只留一句。
    @State private var priceChartUploadError: String?
    /// 上一次上传**成功**的结果摘要
    @State private var priceChartUploadNote: String?
    /// 模板会一次覆盖单位/列名/数据行三个字段，已填内容时先问一句
    @State private var confirmsPriceChartTemplateFill = false

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

                priceChartCard

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
                                    + "按当前类型与该类型的颜色、尺码放在一起（需求 §S2）。"
                                    + "上面那张「系列价格表」是给客户看的**展示表**，不是定价来源。")
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

    // MARK: S2 系列价格表（上传原图 + 结构化列行）

    private var priceChartCard: some View {
        OpsCard(title: "系列价格表（可选）", systemImage: "tablecells") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: bind(\.declaresPriceChart)) {
                    opsMarkdown("在本向导里维护系列价格表"
                                + "（关闭 = 本次提交**完全不碰**系列已有的价格表）")
                }
                if draft.declaresPriceChart {
                    priceChartEditor
                } else {
                    OpsFootnote(text: "价格表是**系列级**的：整包系列共用一份，单品的详情页自动读它，"
                                + "不需要在每个商品上再录一遍。"
                                + "想上传原图或改表格，打开上面这个开关即可（选到已有价格表的系列时会自动打开）。")
                }
            }
        }
        .confirmationDialog("用标准模板填入价格表？",
                            isPresented: $confirmsPriceChartTemplateFill) {
            Button("覆盖当前的单位 / 列名 / 数据行", role: .destructive) {
                applyPriceChartTemplate()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前的列名与数据行会被模板替换掉，这一步不能撤销。")
        }
    }

    private var priceChartEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 单位是**金额单位**，不是尺码表的长度单位 —— 从旁边那张卡抄过来会填错
            TextField("单位（如 元 / ¥）", text: bind(\.priceChartUnit))
                .textFieldStyle(.roundedBorder)
            TextField("列名（只写数据列，逗号分隔，如：\(CatalogChartTemplate.PriceChart.columnsText)）",
                      text: bind(\.priceChartColumnsText))
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("每一行：`\(CatalogChartTemplate.PriceChart.sampleRowText)`")
                        .font(.caption)
                    Spacer(minLength: 8)
                    Button("用标准模板填入") { requestPriceChartTemplateFill() }
                        .controlSize(.small)
                        .help("填入一份格式一定正确的价格表（4 个数据列 × 3 行），照着改数字即可")
                }
                TextEditor(text: bind(\.priceChartRowsText))
                    .font(.body.monospaced())
                    .frame(height: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            }
            OpsFootnote(text: "**款式写在「=」左边**，不写进列名（渲染时它单独占角落那一列）；"
                        + "「=」右边的**值个数要和列名一样多**。分隔符用半角逗号「,」。")

            priceChartUploadArea

            // 识别结论（判定与文案来自共享包，Mac 只负责画）——
            // 与系列配置 sheet 那张卡、S3 的尺码表走的是同一个出口。
            OpsChartRecognitionBlock(recognition: priceChartRecognition,
                                     isInputEmpty: draft.isPriceChartTextEmpty)
        }
    }

    // MARK: 上传 / 展示

    private var priceChartUploadArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    priceChartUploadError = nil
                    showsPriceChartImporter = true
                } label: {
                    Label("选择价格表图片…", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
                .help("可一次选多张。第一张即客户端详情页展示的主图。")
                Text("可多选；支持 \(OpsWorkspace.priceChartFileFormatList)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if draft.priceChartImageAssetIDs.isEmpty {
                OpsFootnote(text: "还没有原图。**只有原图、没有表格也是合法的**"
                            + "（客户端会直接展示原图，而不是显示「暂无数据」）。")
            } else {
                Text("已关联 \(draft.priceChartImageAssetIDs.count) 张原图"
                     + "（第一张即客户端详情页的主图）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(draft.priceChartImageAssetIDs.enumerated()),
                                id: \.element) { index, assetID in
                            priceChartThumbnail(assetID: assetID, index: index)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // 成功与失败**同时**可见（部分成功时两句话都得在）
            // ⚠️ 两句都是**变量**，一律过 `opsMarkdown` —— 「取消关联」那条里带
            // `**没有删除**`，用 `Label(变量, systemImage:)` 会把星号逐字显示出来
            // （仓库铁律：变量文案不过这一层就不解析 Markdown）。
            if let priceChartUploadNote {
                Label {
                    opsMarkdown(priceChartUploadNote)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(OpsFlowPalette.okGreen)
            }
            if let priceChartUploadError {
                Label {
                    opsMarkdown(priceChartUploadError)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(OpsFlowPalette.warnOrange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpsFlowPalette.tileLilac, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(OpsFlowPalette.tileBorder, lineWidth: 1)
        }
        .fileImporter(
            isPresented: $showsPriceChartImporter,
            allowedContentTypes: OpsWorkspace.priceChartPickerTypes,
            allowsMultipleSelection: true) { result in
            handlePriceChartImport(result)
        }
    }

    private func priceChartThumbnail(assetID: String, index: Int) -> some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                OpsThumbnail(
                    url: workspace.stagedFileURL(
                        forReference: workspace.asset(for: assetID)?.originalURL),
                    size: 64)
                Button {
                    workspace.removePriceChartImage(assetID: assetID)
                    priceChartUploadError = nil
                    priceChartUploadNote = "已取消关联 1 张原图（文件仍在素材里，**没有删除**）。"
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(2)
                .help("取消关联这张原图（不会删除文件）")
            }
            Text(index == 0 ? "主图" : "#\(index + 1)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// 文件选择的结果处理。三类结果**必须分开**（仓库铁律）：
    /// 取消 = 什么都不说；部分失败 = 成功与失败两句同时在；全失败 = 逐条原因 + 顶部横幅。
    private func handlePriceChartImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            let outcome = workspace.appendPriceChartImages(from: urls)
            priceChartUploadNote = outcome.addedCount > 0
                ? "已上传 \(outcome.addedCount) 张价格表原图"
                    + "（现共 \(draft.priceChartImageAssetIDs.count) 张）。"
                : nil
            if outcome.failures.isEmpty {
                priceChartUploadError = nil
            } else {
                priceChartUploadError = "有 \(outcome.failures.count) 个文件没能上传：\n"
                    + outcome.failures.map { "· " + $0 }.joined(separator: "\n")
            }
        case .failure(let error):
            priceChartUploadNote = nil
            let message = "没能读取所选文件：\(error.localizedDescription)"
            priceChartUploadError = message
            workspace.reportFailure("价格表原图上传失败：" + message)
        }
    }

    // MARK: 标准模板 / 识别结论

    /// 点「用标准模板填入」：空的就直接填，非空先确认（不静默覆盖已填内容）。
    private func requestPriceChartTemplateFill() {
        if draft.isPriceChartTextEmpty {
            applyPriceChartTemplate()
        } else {
            confirmsPriceChartTemplateFill = true
        }
    }

    /// 模板内容**只从共享包读**（`CatalogChartTemplate.PriceChart`）——
    /// 界面不自己拼一份，所以「模板内容」与「模板还能不能过识别」永远只有一个答案。
    private func applyPriceChartTemplate() {
        workspace.seriesEntry.priceChartUnit = CatalogChartTemplate.PriceChart.unit
        workspace.seriesEntry.priceChartColumnsText = CatalogChartTemplate.PriceChart.columnsText
        workspace.seriesEntry.priceChartRowsText = CatalogChartTemplate.PriceChart.rowsText
    }

    /// 价格表识别结论。结构与落库**同一份解析**（`draft.parsedPriceChart`），
    /// 判定与文案交给共享包 —— 本视图不许自己拼「识别成功 / 识别失败」。
    private var priceChartRecognition: CatalogChartRecognition {
        let parsed = draft.parsedPriceChart
        return OpsChartRecognition.make(kind: .price,
                                        parsed: parsed.parsed,
                                        issue: parsed.issue)
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

    /// S5 提交后的**唯一**结果反馈。同一时刻只有一个值，新提交整体替换旧值。
    ///
    /// 只有两种结局（需求 2026-10-07 重做版）：
    /// · `.saved` —— 「保存成功」：逐类型写入本地草稿并落盘成功；
    /// · `.failed(reason)` —— 「保存失败：<原因>」：校验拦截 / 落盘失败 /
    ///   系列价格表 / 单个类型写入失败，原因都带可定位来源。
    ///
    /// ## 为什么这里**不**顺手发布
    ///
    /// 发布要比对草稿的 `baseReleaseSeq` / `baseRootIndexHash`（R07），
    /// 而 App 目前从不回填这两个字段 —— 自动发布只会稳定被 R07 拒（退出码 5，
    /// 实测 2026-10-07 16:22）。把一条「永远失败的路径」塞进提交按钮，
    /// 「发布整个系列」是一键的：内部自动完成基线那一套，失败提示带日志路径。
    enum OpsSeriesSubmitFeedback: Equatable {
        case saved
        case failed(String)
    }

    /// 提交 = **保存**（同步）。失败不清空表单：草稿与向导内容原样留在界面上，
    /// 改完直接再点一次，新提示替换旧提示。
    private func commit() {
        let report = workspace.commitSeriesEntry()
        if report.blocked {
            let reasons = report.blockedByValidation
                .map { ($0.entryName.isEmpty ? "" : $0.entryName + "：") + $0.message }
                .joined(separator: "；")
            submitFeedback = .failed("校验未通过（未写入任何内容）—— " + reasons)
            return
        }
        if !report.draftSaved {
            submitFeedback = .failed("草稿落盘失败（内容仍在表单中）—— "
                                     + (workspace.lastError ?? "未知原因"))
            return
        }
        if let priceChartError = report.priceChartError {
            submitFeedback = .failed("系列价格表写入失败 —— " + priceChartError)
            return
        }
        if let badEntry = report.entryResults.first(where: { !$0.ok }) {
            submitFeedback = .failed("类型「\(badEntry.entryName)」写入失败 —— " + badEntry.message)
            return
        }
        submitFeedback = .saved
    }

    // MARK: 发布整个系列（一键）

    /// 发布结果反馈。运营只看两种：成功 / 失败（失败带原因、失败条目与日志路径）。
    enum OpsSeriesPublishFeedback: Equatable {
        case published(releaseSeq: Int)
        /// `itemFailures` 为条目级明细（发布器整体失败时为空）
        case failed(reason: String, itemFailures: [OpsSeriesPublishItem], logPath: String?)
    }

    /// 一键发布：整个系列一次提交（落库草稿箱 → 标记发布中 → 一次发布请求）。
    /// 内部的「取线上发布头 / 采用基线」都在编排层自动完成，运营无感。
    private func publishSeries() {
        guard !isPublishing else { return }
        isPublishing = true
        publishFeedback = nil
        let cloud = OpsCloudSyncModel.shared
        Task { @MainActor in
            let outcome = await workspace.publishSeries(cloud: cloud)
            switch outcome {
            case .published(let seq):
                publishFeedback = .published(releaseSeq: seq)
            case .failed(let reason, let items):
                publishFeedback = .failed(
                    reason: reason, itemFailures: items, logPath: cloud.lastRunLogURL?.path)
            }
            isPublishing = false
        }
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
                LabeledContent("系列价格表", value: priceChartSummaryLine)
                OpsFootnote(text: "本页**只读**，不重复编辑价格或尺码表；"
                            + "发现问题用每张卡右上角的「返回修改」。")
            }
        }
    }

    /// S4 的系列价格表摘要（只读）。
    ///
    /// 「只有原图」必须**说成一个合法状态**，不能显示成「0 列 · 0 行」——
    /// 后者看起来像「没做成」，而它其实是模型允许的形态
    /// （`CatalogPriceChart.hasStructuredContent == false`，客户端直接展示原图）。
    private var priceChartSummaryLine: String {
        guard draft.declaresPriceChart else { return "本次提交不改动（沿用系列上已有的）" }
        let images = draft.priceChartImageAssetIDs.count
        let imagePart = images == 0 ? "无原图" : "\(images) 张原图"
        if let parsed = draft.parsedPriceChart.parsed {
            return "\(parsed.columns.count) 列 · \(parsed.rows.count) 行 · " + imagePart
        }
        if images > 0 {
            return "只有原图、没有结构化列行（客户端直接展示原图）· " + imagePart
        }
        return "（还没上传原图、也没有表格）"
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

/// S5 提交环节（需求 2026-10-07 重做版）：
///
/// · 提交 = **保存**。反馈只有一条，只有两种：保存成功 / 保存失败（带原因）；
/// · 发布一键完成：点「发布整个系列」（或右上角「云端更新」），内部自动完成
///   「取线上发布头 → 采用基线 → 整包发布 → 回读确认」，运营无感；
/// · 禁止其他交互：不弹二次确认、没有成功引导、没有「重开向导」或跳转按钮 ——
///   提交按钮就是这一步的全部交互；
/// · 失败不清空表单（草稿与向导内容原样保留，改完直接再点提交，新提示替换旧提示）。
struct OpsSeriesWizardPublishView: View {
    @ObservedObject var workspace: OpsWorkspace
    let issues: [OpsSeriesEntryIssue]
    let feedback: OpsSeriesWizardView.OpsSeriesSubmitFeedback?
    let publishFeedback: OpsSeriesWizardView.OpsSeriesPublishFeedback?
    let isPublishing: Bool
    let onCommit: () -> Void
    let onPublish: () -> Void

    /// 线上版本号从这里读（只读展示，不提供任何入口）。
    @ObservedObject private var cloudSync = OpsCloudSyncModel.shared

    private var draft: OpsSeriesEntryDraft { workspace.seriesEntry }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stateMachineCard
                actionsCard
                publishCard
                honestyCard
                if !issues.isEmpty {
                    issuesCard
                }
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
                OpsFootnote(text: "提交 = **保存**：逐类型写入本地草稿并落盘。"
                            + "上云点下面的「发布整个系列」或右上角「云端更新」。")
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
                    Label("提交整个系列（写入草稿）", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!issues.isEmpty || workspace.isCorrupted)
                if let feedback {
                    submitFeedbackLine(feedback)
                }
            }
        }
    }

    /// 发布整个系列：**一次点击**发整个系列（不逐条提交；内部自动完成基线那一套）。
    private var publishCard: some View {
        OpsCard(title: "发布整个系列", systemImage: "icloud.and.arrow.up") {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onPublish) {
                    Label("发布整个系列", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!issues.isEmpty || workspace.isCorrupted || isPublishing)
                if isPublishing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("发布中…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let publishFeedback {
                    publishFeedbackLine(publishFeedback)
                    // 明确的重试入口（需求 §4）：失败时就在同一处，
                    // 运营不必去别处找「刚才那条去哪了」。
                    if case .failed = publishFeedback {
                        Button("重试发布") { onPublish() }
                            .controlSize(.small)
                            .disabled(isPublishing)
                    }
                }
            }
        }
    }

    /// 发布反馈：一条。成功 = 「发布成功」；失败 = 「发布失败：原因」（+ 日志路径）。
    @ViewBuilder
    private func publishFeedbackLine(_ feedback: OpsSeriesWizardView.OpsSeriesPublishFeedback)
        -> some View {
        switch feedback {
        case .published(let seq):
            Label("发布成功（releaseSeq \(seq)）", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed(let reason, let items, let logPath):
            VStack(alignment: .leading, spacing: 3) {
                opsMarkdown("发布失败：" + reason)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                // 条目级失败：不逐条列出来，运营不知道该改哪一条
                ForEach(items.filter { !$0.ok }) { item in
                    Text("· \(item.name.isEmpty ? item.id : item.name)："
                         + (item.message ?? "未说明原因"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let logPath {
                    Text("日志：\(logPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 唯一的结果反馈：一条。同一时刻最多一条，新提交整体替换（同一个 `@State`）。
    @ViewBuilder
    private func submitFeedbackLine(_ feedback: OpsSeriesWizardView.OpsSeriesSubmitFeedback)
        -> some View {
        switch feedback {
        case .saved:
            Label("保存成功", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed(let reason):
            // 一条提示 = 「保存失败」+ 可定位原因，不拆成两块。
            // 变量文案过 opsMarkdown（`Text(变量)` 不解析 Markdown）；
            // 允许选中，方便把原因原样带走去改表单。
            opsMarkdown("保存失败：" + reason)
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var honestyCard: some View {
        OpsCard(title: "发布与上架状态", systemImage: "cloud") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("线上当前版本",
                               value: cloudSync.onlineHead.map { "releaseSeq \($0.releaseSeq)" }
                                ?? "未读取（云端同步面板里读）")
                LabeledContent("公共 CloudKit 上架", value: "以受控发布器的回读确认为准")
                OpsFootnote(text: "发布一键完成：点「发布整个系列」或右上角「云端更新」。"
                            + "环境与凭证在 设置（Cmd+,）里配置。"
                            + "失败时给出日志路径，把日志交给 Agent 即可定位。")
            }
        }
    }
}
