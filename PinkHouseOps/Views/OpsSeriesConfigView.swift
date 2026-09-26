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

struct SeriesConfigSheet: View {
    @ObservedObject var workspace: OpsWorkspace
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
    @State private var phaseError: String?

    // 价格表
    @State private var chartUnit = ""
    @State private var chartColumnsText = ""
    @State private var chartRowsText = ""
    @State private var chartSourceImage = ""
    @State private var chartError: String?

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
                OpsFootnote(text: "这里是这一份系列配置的**唯一入口**。保存只写各自负责的字段："
                            + "第一阶段那组**不碰任何价格**，价格表那组**不碰阶段与区间**。")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    phaseSection
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
        if declaresPhase, phase == .reservationActive, !hasReservationEnd {
            phaseError = "声明「预约中」必须填预约结束时间 —— 自动流转靠它。"
            return
        }
        if declaresPhase, balanceDueKind == .exact, !hasBalanceDueAt {
            phaseError = "尾款时间选了「具体时间」，请填上时间。"
            return
        }
        if declaresPhase, balanceDueKind == .approximate,
           balanceDueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phaseError = "尾款时间选了「大致时间」，请写上描述。"
            return
        }
        let ok = workspace.updateSeriesSalePhase(
            id: seriesID,
            phase: declaresPhase ? phase : nil,
            reservationStartAt: declaresPhase && hasReservationStart ? reservationStartAt : nil,
            reservationEndAt: declaresPhase && hasReservationEnd ? reservationEndAt : nil,
            balanceDueKind: declaresPhase ? balanceDueKind : nil,
            balanceDueText: declaresPhase && balanceDueKind == .approximate ? balanceDueText : nil,
            balanceDueAt: declaresPhase && balanceDueKind == .exact && hasBalanceDueAt
                ? balanceDueAt : nil,
            balanceDueEndAt: declaresPhase && balanceDueKind == .exact && hasBalanceDueEndAt
                ? balanceDueEndAt : nil)
        if !ok { phaseError = workspace.statusText ?? "保存失败，请看上方的提示。" }
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
            TextField("单位（如 cm / inch）", text: $chartUnit)
            TextField("列名（逗号分隔，如：尺码, 胸围, 衣长）", text: $chartColumnsText)
            VStack(alignment: .leading, spacing: 4) {
                Text("每一行：`尺码 = 值1, 值2, …`").font(.callout)
                TextEditor(text: $chartRowsText)
                    .font(.body.monospaced())
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
            }
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
                    workspace.clearSeriesPriceChart(seriesID: seriesID)
                    chartUnit = ""
                    chartColumnsText = ""
                    chartRowsText = ""
                    chartSourceImage = ""
                }
                .controlSize(.small)
                .disabled(series?.priceChart == nil)
            }
        }
    }

    private func savePriceChart() {
        chartError = nil
        let columns = chartColumnsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "|" || $0 == "｜" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var rows: [CatalogSizeRow] = []
        for rawLine in chartRowsText.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let separatorIndex = line.firstIndex(of: "=") else {
                chartError = "这一行没有「=」，格式应为 `尺码 = 值1, 值2`：\(line)"
                return
            }
            let label = String(line[line.startIndex..<separatorIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                chartError = "有一行没有写尺码标签：\(line)"
                return
            }
            let valuesPart = String(line[line.index(after: separatorIndex)...])
            let values = valuesPart
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { part -> String? in
                    let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            if !columns.isEmpty, values.count != columns.count {
                chartError = "「\(label)」有 \(values.count) 个值，而列名有 \(columns.count) 个。"
                return
            }
            rows.append(CatalogSizeRow(label: label, values: values))
        }
        guard !columns.isEmpty, !rows.isEmpty else {
            chartError = "价格表至少要有列名与一行数据。"
            return
        }
        let images = chartSourceImage.isEmpty ? [] : [chartSourceImage]
        let ok = workspace.updateSeriesPriceChart(
            seriesID: seriesID,
            unit: chartUnit,
            columns: columns,
            rows: rows,
            sourceImages: images)
        if !ok { chartError = workspace.statusText ?? "保存失败，请看上方的提示。" }
    }

    private func assetLabel(_ asset: CatalogAsset) -> String {
        workspace.stagedFileURL(forReference: asset.originalURL)?.lastPathComponent
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
        if let at = series.balanceDueAt {
            hasBalanceDueAt = true
            balanceDueAt = at
        }
        if let end = series.balanceDueEndAt {
            hasBalanceDueEndAt = true
            balanceDueEndAt = end
        }

        if let chart = series.priceChart {
            chartUnit = chart.unit ?? ""
            chartColumnsText = chart.columns.joined(separator: ", ")
            chartRowsText = chart.rows
                .map { row in row.label + " = " + row.values.map { $0 ?? "" }.joined(separator: ", ") }
                .joined(separator: "\n")
            chartSourceImage = chart.sourceImage ?? ""
        }
    }
}
