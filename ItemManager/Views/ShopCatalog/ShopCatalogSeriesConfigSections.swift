//
//  ShopCatalogSeriesConfigSections.swift
//  ItemManager
//
//  系列级三项配置的**唯一实现**（2026-09-24 需求：批次详情页「一站式配置」）：
//    ① 发售阶段（含「尾款中」与「尾款时间」）
//    ② 视觉与简介（图文）
//    ③ 预约价格表（整个系列共用）
//
//  ── 为什么必须抽成一份 ──
//
//  这三项配置在**两个入口**都要能改：批次详情页（一站式配置，本次需求）与系列编辑页
//  （存量系列没有活跃批次时的唯一入口）。如果两边各写一套 Section，
//  迟早出现「在批次页填的尾款时间在系列页保存后就没了」这类互相覆盖 ——
//  它们写的是**同一份 `CatalogSeries`**，任何一处少写一个字段就是一次静默数据丢失。
//  所以：回填 / 组装 / 校验全在 `ShopCatalogSeriesConfigForm`，
//  两处只消费同一个表单类型与同一个 Section 组件。
//
//  ── 与 `apply` 的边界 ──
//
//  `apply(to:)` **只写这三项配置涉及到的字段**（salePhase / reservationEndAt /
//  balanceDue* / cover / description / priceChart）。名称、年月、季节属于
//  「系列基础信息」，归系列编辑页，不在这里写 —— 否则批次详情页保存配置会把
//  运营在系列页填的年月一起覆盖成这里没有的默认值。
//

import SwiftUI

// MARK: - 表单状态（回填 / 组装 / 校验的唯一口径）

/// `Codable` 是为了整份表单能被「编辑中快照」原样落盘（见
/// `ShopCatalogFormSnapshotStore`）：切后台 / 相册选图 / 切应用后视图被重建时，
/// 十余个 `@State` 字段（含封面图与价格表图片引用）靠它一起恢复出来。
nonisolated struct ShopCatalogSeriesConfigForm: Equatable, Codable {

    // ① 发售阶段
    var salePhase: CatalogSeriesSalePhase?
    /// 预约期 = 开始（选填，开关控制）+ 结束（预约中必填）。
    /// 2026-09-24 需求五：两个都要有，不能只给结束。
    var reservationHasStart: Bool
    var reservationStartAt: Date
    var reservationEndAt: Date
    // 尾款期（需求四 + 需求五）：粒度 + 两种载体各自的「开始 / 结束」
    var balanceDueKind: CatalogBalanceDueKind?
    var balanceDueText: String
    var balanceDueEndText: String
    var balanceDueAt: Date
    var balanceDueHasEnd: Bool
    var balanceDueEndAt: Date

    // ② 视觉与简介
    var cover: String
    var descriptionText: String

    // ③ 预约价格表
    var priceChartImageText: String
    var priceChartColumnsText: String
    var priceChartRowsText: String
    var priceChartUnitText: String

    // MARK: 回填

    /// 由既有系列回填（唯一回填实现，两个入口共用）。
    init(series: CatalogSeries, now: Date = Date()) {
        salePhase = series.salePhase
        reservationEndAt = series.reservationEndAt ?? now
        // 开始时间：存量系列没有 → 开关关闭（**不预填一个假日期**），
        // 打开时给一个可编辑的起点（与 `reservationEndAt` 的既有写法同口径）
        reservationHasStart = series.reservationStartAt != nil
        reservationStartAt = series.reservationStartAt ?? series.reservationEndAt ?? now
        let due = CatalogSeriesBalanceDue.formValues(kind: series.balanceDueKind,
                                                    text: series.balanceDueText,
                                                    endText: series.balanceDueEndText,
                                                    at: series.balanceDueAt,
                                                    endAt: series.balanceDueEndAt,
                                                    fallbackExactAt: series.reservationEndAt ?? now)
        balanceDueKind = due.kind
        balanceDueText = due.text
        balanceDueEndText = due.endText
        balanceDueAt = due.exactAt
        balanceDueHasEnd = due.hasEnd
        balanceDueEndAt = due.endAt
        cover = series.cover ?? ""
        descriptionText = series.description ?? ""
        if let chart = series.priceChart {
            // 多图优先：`sourceImages` 是 2026-09-24 起的完整口径；
            // 旧数据只有 sourceImage，按原值回填，保存时归一化为单元素列表
            if let images = chart.sourceImages, !images.isEmpty {
                priceChartImageText = images.joined(separator: "\n")
            } else {
                priceChartImageText = chart.sourceImage ?? ""
            }
            priceChartColumnsText = chart.columns.joined(separator: ",")
            priceChartRowsText = chart.rows.map { row in
                "\(row.label):" + row.values.map { $0 ?? "" }.joined(separator: ",")
            }.joined(separator: "\n")
            priceChartUnitText = chart.unit ?? ""
        } else {
            priceChartImageText = ""
            priceChartColumnsText = ""
            priceChartRowsText = ""
            priceChartUnitText = ""
        }
    }

    // MARK: 校验

    /// 预约期校验（需求五）：开始时间不得晚于结束时间。
    /// 只在**预约中**校验 —— 那是这两个字段同时录入、结束时间就在眼前可改的唯一阶段。
    func reservationValidationErrorText() -> String? {
        guard salePhase == .reservationActive else { return nil }
        return CatalogSeriesReservationWindow.validationErrorText(
            start: reservationHasStart ? reservationStartAt : nil,
            end: reservationEndAt)
    }

    /// 尾款期校验（需求四 + 需求五）。返回 `nil` = 通过；否则为可直接显示的文案。
    ///
    /// 「具体时间必须晚于预约结束时间」只在**预约中**做比对：那是两个字段同时录入、
    /// 且预约结束时间就在眼前可改的唯一阶段；其余阶段表单里没有可比对的基准，
    /// 就不猜（与 `CatalogSeriesBalanceDue` 的口径一致）。
    func balanceDueValidationErrorText() -> String? {
        CatalogSeriesBalanceDue.validationErrorText(
            kind: balanceDueKind,
            text: balanceDueText,
            endText: balanceDueEndText,
            exactAt: balanceDueAt,
            endAt: balanceDueEndAt,
            endDeclared: balanceDueHasEnd,
            reservationEndAt: salePhase == .reservationActive ? reservationEndAt : nil)
    }

    // MARK: 组装（唯一落库形态）

    /// 把表单写回系列：**只写这三项配置的字段**（见文件头边界说明）。
    ///
    /// 两条「不清空」口径与既有实现一致：
    ///   · 切到非「预约中」阶段**不清除** `reservationEndAt`（那是「预约什么时候结束的」事实）；
    ///   · 尾款期同理，只在用户明确选「未填写」时清空。
    ///
    /// 预约**开始**时间是个例外：它的开关是显式的（「已设置预约开始时间」），
    /// 关掉就是「不声明」→ 写 nil。这是唯一一条「显式清除」路径，因为
    /// 存量系列本来就没有开始时间，不给一条撤下的路就没法回到原状。
    func apply(to series: CatalogSeries) -> CatalogSeries {
        var updated = series
        updated.salePhase = salePhase
        if salePhase == .reservationActive {
            updated.reservationEndAt = reservationEndAt
            updated.reservationStartAt = reservationHasStart ? reservationStartAt : nil
        }
        let due = CatalogSeriesBalanceDue.stored(kind: balanceDueKind,
                                                text: balanceDueText,
                                                endText: balanceDueEndText,
                                                exactAt: balanceDueAt,
                                                endAt: balanceDueEndAt,
                                                endDeclared: balanceDueHasEnd)
        updated.balanceDueKind = due.kind
        updated.balanceDueText = due.text
        updated.balanceDueEndText = due.endText
        updated.balanceDueAt = due.at
        updated.balanceDueEndAt = due.endAt
        updated.cover = Self.trimmedOrNil(cover)
        updated.description = Self.trimmedOrNil(descriptionText)
        updated.priceChart = makePriceChart(keeping: series)
        return updated
    }

    /// 由表单内容组装系列价格表（与系列编辑页原实现逐字同口径）。
    ///
    /// 多图：`priceChartImageText` 按行拆为引用列表写 `sourceImages`；
    /// `sourceImage` 同步写首图 —— 既有的单图展示 / 门禁口径
    /// （`ShopCatalogChartPresentation`）继续以 `sourceImage` 为唯一入口。
    private func makePriceChart(keeping series: CatalogSeries) -> CatalogPriceChart? {
        let imageReferences = CatalogPriceChartImageText.references(fromText: priceChartImageText)
        let sourceImage = imageReferences.first
        let parsedChart = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(priceChartColumnsText),
            rows: CatalogManualChartText.parseRows(priceChartRowsText))
        let columns = parsedChart.columns
        let rows = parsedChart.rows
        guard sourceImage != nil || !columns.isEmpty || !rows.isEmpty else { return nil }
        var chart = series.priceChart ?? CatalogPriceChart(
            id: "pricechart-\(series.id.prefix(8))", seriesID: series.id)
        chart.sourceImages = imageReferences.isEmpty ? nil : imageReferences
        chart.sourceImage = sourceImage
        chart.columns = columns
        chart.rows = rows
        chart.unit = Self.trimmedOrNil(priceChartUnitText)
        return chart
    }

    private static func trimmedOrNil(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 「同系列共用」提示（需求二：避免误操作）

/// 系列级配置区块的标题行：标题 + 「同系列共用」徽标。
///
/// 需求二要求「在 UI 上对用户给出明确的『同系列共用』提示，避免误操作」。
/// 提示分两层落地：
///   1. **徽标**（本视图）常驻在区块标题处 —— 用户不必展开说明就知道这不是单品字段；
///   2. **说明**（footer 首行）写清共用范围与影响面（哪些批次 / 哪些商品）。
struct ShopCatalogSeriesSharedHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer(minLength: 8)
            Text("同系列共用")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.15)))
        }
    }
}

/// 共用范围说明（footer 首行）。`scope` 由调用方给出具体影响面（如「本批次 6 条单品」），
/// 没有具体数字时退回通用说明。
struct ShopCatalogSeriesSharedScopeNote: View {
    let scope: String?

    var body: some View {
        Text(scope.map { "该配置属于**系列**，同系列的全部批次与单品共用；修改后立即对 \($0) 以及已发布的同系列商品详情页生效。"
        } ?? "该配置属于**系列**，不是单个批次或单品：同系列的全部批次与商品详情页共用这一份，改一次全系列同步生效。")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}

// MARK: - 三个 Section（批次详情页 / 系列编辑页共用）

struct ShopCatalogSeriesConfigSections: View {
    @Binding var form: ShopCatalogSeriesConfigForm
    /// 影响面文案（如「本批次 6 条单品」）；nil = 通用说明
    var sharedScope: String?

    var body: some View {
        salePhaseSection
        visualSection
        priceChartSection
    }

    // MARK: ① 发售阶段（需求二 §二.1/§二.2 + 需求三「尾款中」+ 需求四「尾款时间」）

    private var salePhaseSection: some View {
        Section {
            Picker("发售阶段", selection: $form.salePhase) {
                Text("未设置（沿用销售记录）").tag(Optional<CatalogSeriesSalePhase>.none)
                ForEach(CatalogSeriesSalePhase.allCases) { phase in
                    Text(phase.displayName).tag(Optional(phase))
                }
            }
            if CatalogSeriesSalePhaseResolver.requiresReservationEndAt(form.salePhase) {
                reservationInputs
            }
            if CatalogSeriesSalePhaseResolver.showsBalanceDueInput(form.salePhase) {
                balanceDueInputs
            }
            if let note = autoFlowNote {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            if showsBalanceDueEndedNote {
                Text("尾款期已过声明的结束时间。若尾款已收齐，可把发售阶段改为「现货」——系统不会自动改。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            if let error = form.reservationValidationErrorText() {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            if let error = form.balanceDueValidationErrorText() {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        } header: {
            ShopCatalogSeriesSharedHeader(title: "发售阶段")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                ShopCatalogSeriesSharedScopeNote(scope: sharedScope)
                Text(salePhaseFooter)
            }
        }
    }

    /// 预约期录入（需求五）：开始（开关 + 日期）+ 结束。
    ///
    /// 结束时间是**自动流转的唯一依据**（预约中 → 预约已结束），所以它没有开关、始终可见；
    /// 开始时间用开关显式声明 —— 存量系列没有它，硬给一个非可选 `DatePicker` 就会
    /// 在保存时写进一个运营没选过的日期（等于替运营编数据）。
    @ViewBuilder
    private var reservationInputs: some View {
        Toggle("已设置预约开始时间", isOn: $form.reservationHasStart.animation())
        if form.reservationHasStart {
            DatePicker("预约开始时间",
                       selection: $form.reservationStartAt,
                       displayedComponents: [.date, .hourAndMinute])
        }
        DatePicker("预约结束时间",
                   selection: $form.reservationEndAt,
                   displayedComponents: [.date, .hourAndMinute])
    }

    /// 尾款期录入（需求四 + 需求五）：粒度三选一（未填写 / 大致时间 / 具体时间）
    /// + 每种粒度各自的「开始 / 结束」。
    ///
    /// 「未填写」是**显式选项**而不是空字符串判定：运营需要一条「我要清掉之前填的尾款期」
    /// 的路径，否则只能改不能撤。结束时间同样用开关显式声明（理由同预约开始时间）。
    @ViewBuilder
    private var balanceDueInputs: some View {
        Picker("尾款期", selection: $form.balanceDueKind) {
            Text("未填写").tag(Optional<CatalogBalanceDueKind>.none)
            ForEach(CatalogBalanceDueKind.allCases) { kind in
                Text(kind.displayName).tag(Optional(kind))
            }
        }
        switch form.balanceDueKind {
        case .approximate:
            TextField("尾款开始（大致，如：大货到后 1 个月）", text: $form.balanceDueText)
            TextField("尾款结束（大致，选填，如：大货到后 2 个月）", text: $form.balanceDueEndText)
            Text("大致时间只作展示，不参与自动流转——它不是确定时刻，系统不拿它做判断。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .exact:
            DatePicker("尾款开始时间",
                       selection: $form.balanceDueAt,
                       displayedComponents: [.date, .hourAndMinute])
            Toggle("已设置尾款结束时间", isOn: $form.balanceDueHasEnd.animation())
            if form.balanceDueHasEnd {
                DatePicker("尾款结束时间",
                           selection: $form.balanceDueEndAt,
                           displayedComponents: [.date, .hourAndMinute])
            }
            Text("到「尾款开始时间」后，若系列仍是「预约中 / 预约已结束」，生效阶段自动显示为「尾款中」（读取时判定，不改动你声明的值）。结束时间只用于展示与提醒，不会自动把系列改成「现货」。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .none:
            EmptyView()
        }
    }

    /// 尾款期已过声明结束时间（只提示，不自动改阶段）
    private var showsBalanceDueEndedNote: Bool {
        guard form.balanceDueKind == .exact, form.balanceDueHasEnd else { return false }
        guard CatalogSeriesSalePhaseResolver.showsBalanceDueInput(form.salePhase) else { return false }
        return CatalogSeriesBalanceDue.isEnded(kind: .exact, at: form.balanceDueEndAt, now: Date())
    }

    /// 自动流转提示：说明保存后**生效阶段**会与所选声明不同（只提示，不拦保存）
    private var autoFlowNote: String? {
        guard CatalogSeriesSalePhaseResolver.hasAutoFlowed(
            declared: form.salePhase,
            reservationEndAt: form.reservationEndAt,
            balanceDueKind: form.balanceDueKind,
            balanceDueAt: form.balanceDueAt,
            now: Date()) else { return nil }
        let effective = CatalogSeriesSalePhaseResolver.effectivePhase(
            declared: form.salePhase,
            reservationEndAt: form.reservationEndAt,
            balanceDueKind: form.balanceDueKind,
            balanceDueAt: form.balanceDueAt,
            now: Date())
        return "按当前填写，保存后本系列的**生效阶段**会显示为「\(effective?.displayName ?? "?")」"
            + "（声明值仍保留，价格数据不变）。"
    }

    private var salePhaseFooter: String {
        switch form.salePhase {
        case .none:
            return "未设置时，商品详情页按销售记录（预约 / 现货档期）自动判断，与以往行为一致。"
        case .reservationActive:
            return "预约中：可填完整的预约期（开始 / 结束）。到「预约结束时间」后自动流转为「预约已结束」；若填了**具体**尾款开始时间，到点后再自动流转为「尾款中」。开始时间只作展示，不参与流转。无论哪个阶段，预约价 / 定金 / 尾款 / 现货价都会完整保留，不会清空或隐藏。"
        case .reservationEnded:
            return "预约已结束：预约（收定金）窗口已关闭、尾款还没开始收。填过具体尾款开始时间的系列到点会自动变「尾款中」；加购默认引导全款入橱，「定金 + 尾款」仍可选。"
        case .balancePending:
            return "尾款中：正在收尾款（已到尾款开始时间，或运营手动声明）。可填完整的尾款期（开始 / 结束）。加购默认引导「定金 + 尾款」（补尾款），也可切换为预约价全款。本阶段**不按时间自动结束**——尾款是否收齐在数据里没有可判定依据，即使过了尾款结束时间也只是提示，改「现货」由运营声明。"
        case .inStock:
            return "现货：加购直接按现货价计入衣橱，不走定金 / 尾款。"
        }
    }

    // MARK: ② 视觉与简介

    private var visualSection: some View {
        Section {
            TextField("封面（Bundle 文件名/URL，可空）", text: $form.cover)
            ShopCatalogImagePickerButton(mode: .replace, text: $form.cover, label: "添加封面图片")
            TextField("简介", text: $form.descriptionText)
        } header: {
            ShopCatalogSeriesSharedHeader(title: "视觉与简介")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                ShopCatalogSeriesSharedScopeNote(scope: sharedScope)
                Text("封面与简介是系列的门面：系列页、系列详情页与商品详情页的系列区块都读这一份。")
            }
        }
    }

    // MARK: ③ 预约价格表（整个系列共用）

    private var priceChartSection: some View {
        Section {
            ShopCatalogImagePickerButton(mode: .append,
                                         text: $form.priceChartImageText,
                                         label: "上传价格表图片（可多选）")
            ShopCatalogChartPasteButton(kind: .priceChart,
                                        columnsText: $form.priceChartColumnsText,
                                        rowsText: $form.priceChartRowsText)
            TextField("列名（逗号分隔，如：款式,预约价,定金,尾款）", text: $form.priceChartColumnsText)
                .font(.system(size: 13))
            TextEditor(text: $form.priceChartRowsText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
            Text("价格表行：每行「标签:值,值,…」与列一一对应（如「大蝴蝶结背心裙:318,91,227」）；可在「粘贴文本录入」里整段贴入，或在此手动修正后保存")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("单位（可空，如 元）", text: $form.priceChartUnitText)
                .font(.system(size: 13))
            if !form.priceChartImageText.isEmpty
                || !form.priceChartColumnsText.isEmpty
                || !form.priceChartRowsText.isEmpty {
                Button("清除价格表", role: .destructive) {
                    form.priceChartImageText = ""
                    form.priceChartColumnsText = ""
                    form.priceChartRowsText = ""
                    form.priceChartUnitText = ""
                }
                .font(.system(size: 13))
            }
        } header: {
            ShopCatalogSeriesSharedHeader(title: "预约价格表（整个系列共用）")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                ShopCatalogSeriesSharedScopeNote(scope: sharedScope)
                Text("在此录入一次，该系列全部商品详情页自动展示；无需在单品编辑页上传。用「粘贴文本录入」把整段表格文本贴进来最省事。")
            }
        }
    }
}
