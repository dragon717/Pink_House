//
//  OpsSeriesConfigView.swift
//  PinkHouseOps
//
//  系列配置一站式：**发售阶段 + 预约/尾款区间 + 系列价格表**。
//
//  ## 为什么是一个 sheet 而不是两个入口
//
//  这三样东西都躺在**同一个** `CatalogSeries` 上（方案 §「系列配置一站式」：
//  发售阶段 / 图文 / 价格表只有一处存储，批次与单品只持 `seriesID` 引用、不带副本）。
//  所以界面上也只能有一个入口：两个入口会让运营在两边各改一半，
//  而两边都看不到对方字段的全貌。
//
//  外壳用 `OpsFormFrame`（成功才关窗），但内部是**两个独立的保存动作** ——
//  因为服务层就是两个命令，各自只写自己负责的字段：
//    · `updateSeriesSalePhase` 写阶段与两个区间，**不碰任何价格**；
//    · `updateSeriesPriceChart` 写价格表，**不碰阶段与区间**。
//  把它们合成一个「保存」，就会出现「保存了一下，结果把我没动的另一组字段也覆盖了」。
//
//  ## 自动流转只看两个时间
//
//  「预约结束时间」与「尾款开始时间」驱动阶段自动流转（读取时判定，无定时任务）。
//  大致时间是**人的描述**、不是时间点，所以只展示、不驱动 ——
//  界面上必须把这件事写出来，否则运营会以为填了「大货到后 1 个月」就会自动转。
//

import SwiftUI
import AppKit
import PinkHouseOpsCore

struct OpsReservationBatchEditor: View {
    @Binding var batches: [CatalogReservationBatch]
    var reservationEndAt: Date? = nil

    var body: some View {
        ForEach($batches) { $batch in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("团次名称（如先行团、一团）", text: $batch.name)
                    Button("删除", role: .destructive) { batches.removeAll { $0.id == batch.id } }
                }
                Picker("该团尾款期", selection: Binding(
                    get: { batch.balanceDueKind },
                    set: {
                        batch.balanceDueKind = $0
                        if $0 == .exact, batch.balanceDueAt == nil { batch.balanceDueAt = Date() }
                    })) {
                    ForEach(CatalogBalanceDueKind.allCases) { kind in
                        Text(kind.displayName).tag(Optional(kind))
                    }
                    Text("未公布").tag(Optional<CatalogBalanceDueKind>.none)
                }
                .pickerStyle(.segmented)
                if batch.balanceDueKind == .approximate {
                    TextField("大致尾款时间（如 1月上旬、圣诞节前）", text: Binding(
                        get: { batch.balanceDueText ?? "" }, set: {
                            batch.balanceDueText = $0
                            batch.balanceDueReferenceAt = Date()
                        }))
                    TextField("尾款结束 / 时长（选填，如十天、十五天、一个月）", text: Binding(
                        get: { batch.balanceDueEndText ?? "" }, set: {
                            batch.balanceDueEndText = $0
                            if batch.balanceDueReferenceAt == nil { batch.balanceDueReferenceAt = Date() }
                        }))
                    if let window = batch.estimatedWindow(anchor: reservationEndAt) {
                        Text("预计尾款日期：\(window.start, format: .dateTime.year().month().day())")
                            .font(.callout).foregroundStyle(.secondary)
                        Text(window.basis).font(.caption).foregroundStyle(.secondary)
                        if window.end != window.start {
                            Text("预计结束日期：\(window.end, format: .dateTime.year().month().day())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    OpsFootnote(text: "结束可填十天、十五天、一个月，从预计尾款开始日推算；一个月按日历月计算。月份和旬取中间日：上旬5日、中旬15日、下旬25日。节日前按节日当天提前6天估算；省略年份按录入时间固定，也可写明年份。")
                } else if batch.balanceDueKind == .exact {
                    DatePicker("尾款开始", selection: Binding(
                        get: { batch.balanceDueAt ?? Date() }, set: { batch.balanceDueAt = $0 }))
                    OpsOptionalDateField(label: "尾款结束（选填）",
                        isOn: Binding(get: { batch.balanceDueEndAt != nil },
                                      set: { batch.balanceDueEndAt = $0 ? batch.balanceDueAt : nil }),
                        date: Binding(get: { batch.balanceDueEndAt ?? batch.balanceDueAt ?? Date() },
                                      set: { batch.balanceDueEndAt = $0 }))
                }
                OpsOptionalDateField(label: "该团预约结束时间（选填）",
                    isOn: Binding(get: { batch.reservationEndAt != nil },
                                  set: { batch.reservationEndAt = $0 ? Date() : nil }),
                    date: Binding(get: { batch.reservationEndAt ?? Date() },
                                  set: { batch.reservationEndAt = $0 }))
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        Button("添加团次", systemImage: "plus") {
            batches.append(CatalogReservationBatch(name: "", balanceDueKind: .approximate,
                balanceDueReferenceAt: Date()))
        }
    }
}

struct OpsReservationBatchSummary: View {
    let batches: [CatalogReservationBatch]
    var reservationEndAt: Date? = nil

    var body: some View {
        ForEach(batches) { batch in
            VStack(alignment: .leading, spacing: 3) {
                Text(batch.name).font(.callout.weight(.semibold))
                if let end = batch.reservationEndAt {
                    Text("预约结束：\(end, format: .dateTime.year().month().day().hour().minute())")
                }
                switch batch.balanceDueKind {
                case .exact:
                    if let start = batch.balanceDueAt {
                        Text("尾款开始：\(start, format: .dateTime.year().month().day().hour().minute())")
                    }
                    if let end = batch.balanceDueEndAt {
                        Text("尾款结束：\(end, format: .dateTime.year().month().day().hour().minute())")
                    }
                case .approximate:
                    Text("尾款开始：\(batch.balanceDueText ?? "待公布")")
                    if let end = batch.balanceDueEndText { Text("尾款结束：\(end)") }
                    if let window = batch.estimatedWindow(anchor: reservationEndAt) {
                        Text("预计尾款日期：\(window.start, format: .dateTime.year().month().day())（估算）")
                        if window.end != window.start {
                            Text("预计结束日期：\(window.end, format: .dateTime.year().month().day())（估算）")
                        }
                        Text(window.basis)
                    }
                case .none:
                    Text("尾款时间待公布")
                }
            }
            .font(.caption)
        }
    }
}

struct SeriesConfigSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    @ObservedObject private var cloud = OpsCloudSyncModel.shared
    let seriesID: String
    @Environment(\.dismiss) private var dismiss

    // 发售阶段
    @State private var declaresPhase = false
    @State private var phase: CatalogSeriesSalePhase = .reservationActive
    @State private var hasReservationStart = true
    @State private var reservationStartAt = Date()
    @State private var hasReservationEnd = true
    @State private var reservationEndAt = Date()
    @State private var balanceDueKind: CatalogBalanceDueKind = .approximate
    @State private var balanceDueText = ""
    @State private var hasBalanceDueAt = false
    @State private var balanceDueAt = Date()
    @State private var hasBalanceDueEndAt = false
    @State private var balanceDueEndAt = Date()
    @State private var reservationBatches: [CatalogReservationBatch] = []
    @State private var phaseError: String?

    // 封面（§6.2 系列级可编辑）
    @State private var coverAssetID: String?
    @State private var coverMessage: String?

    // 价格表
    @State private var chartUnit = CatalogChartKind.price.defaultUnit
    @State private var chartColumnsText = ""
    @State private var chartRowsText = ""
    @State private var chartSourceImage = ""
    @State private var chartError: String?

    /// 「用标准模板填入」的确认弹窗：**已经填过内容时先问一句**。
    /// 这个按钮会一次覆盖单位 / 列名 / 数据行三个字段 ——
    /// 悄悄吃掉运营手打的一整张价格表是不能接受的
    /// （与尺码表那个按钮同一口径，见 `OpsSeriesWizardTypeEditor`）。
    @State private var confirmsTemplateFill = false

    @State private var didLoad = false

    private var series: CatalogSeries? {
        workspace.catalog.series.first { $0.id == seriesID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("系列配置").font(.headline)
                if let series {
                    Text("\(workspace.shopName(for: series.shopID)) › \(series.name)")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let message = workspace.catalogEditSyncMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if workspace.canRetrySavedSeriesSync {
                    HStack {
                        Button("重试更新开发环境和用户环境") { workspace.retrySavedSeriesSync() }
                            .disabled(cloud.isRunning || cloud.isSyncing)
                        if let url = cloud.lastRunLogURL {
                            Button("打开更新日志") { NSWorkspace.shared.open(url) }
                        }
                    }
                    Text("失败原因见上方；凭证或连接配置可在工具栏齿轮「设置」中检查。重试会先核对已发送请求的结果。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("保存后自动更新开发环境和用户环境；以上方两端回读结果为准，无需再次发布。手机端可在时光馆首页下拉刷新。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                OpsFootnote(text: "这里是这一份系列配置的**唯一入口**。保存只写各自负责的字段："
                            + "第一阶段那组**不碰任何价格**，价格表那组**不碰阶段与区间**。")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    phaseSection
                    Divider()
                    coverSection
                    Divider()
                    priceChartSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("关闭") { dismiss() }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 640, height: 640)
        .onAppear(perform: load)
    }

    // MARK: 发售阶段

    private var phaseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("发售阶段").font(.subheadline.weight(.semibold))
            Toggle(isOn: $declaresPhase) { Text("声明发售阶段（不声明 = 由档期推导）") }
            if declaresPhase {
                Picker("阶段", selection: $phase) {
                    ForEach(CatalogSeriesSalePhase.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }
            OpsOptionalDateField(
                label: "预约开始时间（必填，若声明了预约期）",
                isOn: $hasReservationStart,
                date: $reservationStartAt,
                help: "没有开始时间就只有一个孤零零的结束时间")
            OpsOptionalDateField(
                label: "预约结束时间（**驱动自动流转**）",
                isOn: $hasReservationEnd,
                date: $reservationEndAt,
                help: "选填。但声明「预约中」时必须填 —— 缺了它系列会一直停在预约中。")

            if reservationBatches.isEmpty {
                Picker("尾款时间粒度", selection: $balanceDueKind) {
                    ForEach(CatalogBalanceDueKind.allCases) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                if balanceDueKind == .approximate {
                    TextField("尾款大致时间（如「大货到后 1 个月」）", text: $balanceDueText)
                    OpsFootnote(text: "大致时间是**人的描述**，不是时间点：它只展示、**不驱动**自动流转。")
                } else {
                    OpsOptionalDateField(
                        label: "尾款开始时间（**驱动自动流转**）",
                        isOn: $hasBalanceDueAt,
                        date: $balanceDueAt,
                        help: "选了「具体时间」就必须填")
                    OpsOptionalDateField(
                        label: "尾款结束时间（选填）",
                        isOn: $hasBalanceDueEndAt,
                        date: $balanceDueEndAt)
                }
            }
            Divider()
            Text("预约团次与尾款时间").font(.subheadline.weight(.semibold))
            OpsReservationBatchEditor(batches: $reservationBatches,
                reservationEndAt: hasReservationEnd ? reservationEndAt : nil)
            OpsFootnote(text: "按实际团数添加先行团、一团、二团等。每团单独填写尾款时间，入橱按所选团次确定日期。")
            if let phaseError {
                Label(phaseError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OpsFootnote(text: "阶段是「读取时判定」的（`effectivePhase`），不会有定时任务去回写；"
                        + "所以这里声明的阶段与两个区间就是全部依据。"
                        + "注意：预约已结束**只改引导，不剥夺能力**。")
            Button {
                saveSalePhase()
            } label: {
                Label("保存发售阶段", systemImage: "calendar.badge.clock")
            }
            .controlSize(.small)
        }
    }

    private func saveSalePhase() {
        phaseError = nil
        if declaresPhase, phase == .reservationActive, !hasReservationEnd,
           !( !reservationBatches.isEmpty && reservationBatches.allSatisfy { $0.reservationEndAt != nil }) {
            phaseError = "声明「预约中」必须填预约结束时间 —— 自动流转靠它。"
            return
        }
        if reservationBatches.isEmpty, balanceDueKind == .exact, hasBalanceDueEndAt, !hasBalanceDueAt {
            phaseError = "尾款时间选了「具体时间」，请填上时间。"
            return
        }
        if let error = CatalogReservationBatch.validationError(in: reservationBatches) {
            phaseError = error
            return
        }
        let input = OpsSeriesSalePhaseInput(
            declaresPhase: declaresPhase, phase: phase,
            reservationStartAt: hasReservationStart ? reservationStartAt : nil,
            reservationEndAt: hasReservationEnd ? reservationEndAt : nil,
            balanceDueKind: balanceDueKind, balanceDueText: balanceDueText,
            balanceDueAt: hasBalanceDueAt ? balanceDueAt : nil,
            balanceDueEndAt: hasBalanceDueEndAt ? balanceDueEndAt : nil)
        let ok = workspace.updateSeriesSalePhase(
            id: seriesID,
            phase: input.phase,
            reservationStartAt: input.reservationStartAt,
            reservationEndAt: input.reservationEndAt,
            balanceDueKind: input.balanceDueKind,
            balanceDueText: input.balanceDueText,
            balanceDueAt: input.balanceDueAt,
            balanceDueEndAt: input.balanceDueEndAt,
            reservationBatches: reservationBatches) && workspace.saveCatalogEditorChanges(seriesID: seriesID, fields: [.schedule])
        if !ok { phaseError = workspace.statusText ?? "保存失败，请看上方的提示。" }
    }

    // MARK: 封面（§6.2）

    private var coverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("系列封面").font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                OpsPreviewableThumbnail(
                    url: workspace.previewImageURL(forReference: coverAssetID), size: 48)
                Picker("封面", selection: $coverAssetID) {
                    Text("不指定").tag(String?.none)
                    ForEach(workspace.catalog.assets) { asset in
                        Text(assetLabel(asset)).tag(String?.some(asset.id))
                    }
                }
                .controlSize(.small)
                Button("保存封面") {
                    if let coverAssetID,
                       workspace.updateSeriesCover(seriesID: seriesID, assetID: coverAssetID),
                       workspace.saveCatalogEditorChanges(seriesID: seriesID, fields: [.cover]) {
                        coverMessage = nil
                    } else if coverAssetID == nil {
                        coverMessage = "请先选择一张图（封面不提供「清除」——要换就换一张）。"
                    } else {
                        coverMessage = workspace.statusText ?? "保存失败，请看上方的提示。"
                    }
                }
                .controlSize(.small)
            }
            if let coverMessage {
                Text(coverMessage).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: 价格表

    private var priceChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("系列价格表").font(.subheadline.weight(.semibold))
                if series?.priceChart != nil { OpsTag(text: "已有", tint: .accentColor) }
                Spacer(minLength: 4)
            }
            OpsFootnote(text: "系列级价格表整包系列共用，单品的详情页自动读它 —— "
                        + "不需要在每个商品上再录一遍。")
            // ⚠️ 价格表的「单位」是**金额单位**（详情页展示为「单位：元」）。
            // 原先这里写的是「单位（如 cm / inch）」—— 那是**尺码表**的长度单位，
            // 从旁边那张卡抄过来的，照着填会把长度单位写到价格表上。
            TextField("单位（如 元 / ¥）", text: $chartUnit)
            // 示例列名/行格式原先抄的是**尺码表**那套（尺码 = 值1, 值2），
            // 与价格表的实际结构不符，照着填必然识别失败。
            // ⚠️ 「款式」是**行标签列**（渲染时在角落），不要写进列名 —— 与尺码表同一条口径。
            // ⭐ 示例文本一律读共享包的标准模板：placeholder 与下面那句「每一行」提示
            // **同源**，就不会再出现「placeholder 举例 4 列、提示却写 3 列」这种自相矛盾
            // （2026-10-01 用户报障的直接原因之一）。
            TextField("列名（只写数据列，逗号分隔，如：\(CatalogChartTemplate.PriceChart.columnsText)）",
                      text: $chartColumnsText)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("每一行：`\(CatalogChartTemplate.PriceChart.sampleRowText)`")
                        .font(.caption)
                    Spacer(minLength: 8)
                    Button("用标准模板填入") { requestTemplateFill() }
                        .controlSize(.small)
                        .help("填入一份格式一定正确的价格表（4 个数据列 × 3 行），照着改数字即可")
                }
                TextEditor(text: $chartRowsText)
                    .font(.body.monospaced())
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            }
            OpsFootnote(text: "**款式写在「=」左边**，不写进列名（渲染时它单独占角落那一列）；"
                        + "「=」右边的**值个数要和列名一样多**。分隔符用半角逗号「,」。")
            // 识别结果（2026-10-01 需求）：填完就得知道「认出来了没有」。
            // 判定与文案来自共享包；与上面的保存路径同一份解析。
            OpsChartRecognitionBlock(recognition: priceChartRecognition,
                                     isInputEmpty: isPriceChartInputEmpty)
            Picker("价格表原图（首图即 `sourceImage`）", selection: $chartSourceImage) {
                Text("不指定").tag("")
                ForEach(workspace.catalog.assets) { asset in
                    Text(assetLabel(asset)).tag(asset.id)
                }
            }
            if let chartError {
                Label(chartError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button {
                    savePriceChart()
                } label: {
                    Label("保存价格表", systemImage: "tablecells")
                }
                .controlSize(.small)
                Button("清空价格表") {
                    guard workspace.clearSeriesPriceChart(seriesID: seriesID),
                          workspace.saveCatalogEditorChanges(seriesID: seriesID, fields: [.priceChart]) else {
                        chartError = workspace.statusText; return
                    }
                    chartUnit = CatalogChartKind.price.defaultUnit
                    chartColumnsText = ""
                    chartRowsText = ""
                    chartSourceImage = ""
                }
                .controlSize(.small)
                .disabled(series?.priceChart == nil)
            }
        }
        .confirmationDialog("用标准模板填入价格表？",
                            isPresented: $confirmsTemplateFill) {
            Button("覆盖当前的单位 / 列名 / 数据行", role: .destructive) {
                applyTemplate()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前的列名与数据行会被模板替换掉，这一步不能撤销。")
        }
    }

    private func savePriceChart() {
        chartError = nil
        // 解析口径与「识别结果」板块**共用同一份**（`OpsChartTextParsing`）——
        // 预览即落库结果，不存在「卡片说成功、保存说不行」。
        let (parsed, issue) = OpsChartTextParsing.parse(columnsText: chartColumnsText,
                                                        rowsText: chartRowsText)
        guard let parsed else {
            chartError = issue ?? "价格表至少要有列名与一行数据。"
            return
        }
        let images = chartSourceImage.isEmpty ? [] : [chartSourceImage]
        let ok = workspace.updateSeriesPriceChart(
            seriesID: seriesID,
            unit: chartUnit,
            columns: parsed.columns,
            rows: parsed.rows,
            sourceImages: images) && workspace.saveCatalogEditorChanges(seriesID: seriesID, fields: [.priceChart])
        if !ok { chartError = workspace.statusText ?? "保存失败，请看上方的提示。" }
    }

    // MARK: 标准模板

    /// 点「用标准模板填入」：空的就直接填，非空先确认（不静默覆盖运营手打的内容）。
    private func requestTemplateFill() {
        if isPriceChartInputEmpty {
            applyTemplate()
        } else {
            confirmsTemplateFill = true
        }
    }

    /// 模板内容**只从共享包读**（`CatalogChartTemplate.PriceChart`）——
    /// 界面不自己拼一份，所以「模板内容」与「模板还能不能过识别」永远只有一个答案。
    /// （那份常量由 `swift test` 的 `CatalogChartTemplateTests` 锁着。）
    private func applyTemplate() {
        chartUnit = CatalogChartTemplate.PriceChart.unit
        chartColumnsText = CatalogChartTemplate.PriceChart.columnsText
        chartRowsText = CatalogChartTemplate.PriceChart.rowsText
    }

    // MARK: 识别结果（2026-10-01 需求）

    /// 两个价格表输入框是否都为空（为空不显示结论卡片）
    private var isPriceChartInputEmpty: Bool {
        chartColumnsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && chartRowsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 价格表识别结论。结构与落库同一份解析，判定与文案交给共享包，
    /// 本视图不许自己拼「识别成功 / 识别失败」。
    private var priceChartRecognition: CatalogChartRecognition? {
        let (parsed, issue) = OpsChartTextParsing.parse(columnsText: chartColumnsText,
                                                        rowsText: chartRowsText)
        return OpsChartRecognition.make(kind: .price,
                                        columns: parsed?.columns ?? [],
                                        rows: parsed?.rows ?? [],
                                        issue: issue)
    }

    private func assetLabel(_ asset: CatalogAsset) -> String {
        workspace.previewFileURL(forReference: asset.originalURL)?.lastPathComponent
            ?? asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }

    // MARK: 装载

    private func load() {
        guard !didLoad, let series else { return }
        didLoad = true

        if series.salePhase != nil {
            declaresPhase = true
            phase = series.salePhase ?? .reservationActive
        }
        if let start = series.reservationStartAt {
            hasReservationStart = true
            reservationStartAt = start
        } else {
            hasReservationStart = false
        }
        if let end = series.reservationEndAt {
            hasReservationEnd = true
            reservationEndAt = end
        } else {
            hasReservationEnd = false
        }
        balanceDueKind = series.balanceDueKind ?? .approximate
        balanceDueText = series.balanceDueText ?? ""
        reservationBatches = series.reservationBatches ?? []
        coverAssetID = series.cover
        if let at = series.balanceDueAt {
            hasBalanceDueAt = true
            balanceDueAt = at
        }
        if let end = series.balanceDueEndAt {
            hasBalanceDueEndAt = true
            balanceDueEndAt = end
        }

        if let chart = series.priceChart {
            chartUnit = CatalogChartKind.price.unitForEditing(chart.unit)
            chartColumnsText = chart.columns.joined(separator: ", ")
            chartRowsText = chart.rows
                .map { row in row.label + " = " + row.values.map { $0 ?? "" }.joined(separator: ", ") }
                .joined(separator: "\n")
            chartSourceImage = chart.sourceImage ?? ""
        }
    }
}
