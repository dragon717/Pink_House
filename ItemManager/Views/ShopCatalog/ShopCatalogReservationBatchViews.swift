import SwiftUI

/// 系列编辑与整批配置共用团次表单，团数由运营按实际增减。
struct ShopCatalogReservationBatchEditor: View {
    @Binding var batches: [CatalogReservationBatch]
    var reservationEndAt: Date? = nil

    var body: some View {
        ForEach($batches) { $batch in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("批次名称（如一团、二团、1P、2P）", text: $batch.name)
                    Button("删除", role: .destructive) {
                        batches.removeAll { $0.id == batch.id }
                    }
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
                        Text("预计尾款日期：\(CatalogSeriesBalanceDue.shortDateText(window.start))（估算）")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(window.basis).font(.footnote).foregroundStyle(.secondary)
                        if window.end != window.start {
                            Text("预计结束日期：\(CatalogSeriesBalanceDue.shortDateText(window.end))（估算）")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text("结束可填十天、十五天、一个月，从预计尾款开始日推算；一个月按日历月计算。月份和旬取中间日：上旬5日、中旬15日、下旬25日。节日前按节日当天提前6天估算；省略年份按录入时间固定，也可写明年份。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if batch.balanceDueKind == .exact {
                    DatePicker("尾款开始", selection: Binding(
                        get: { batch.balanceDueAt ?? Date() }, set: { batch.balanceDueAt = $0 }))
                    Toggle("已公布尾款结束时间", isOn: Binding(
                        get: { batch.balanceDueEndAt != nil },
                        set: { batch.balanceDueEndAt = $0 ? batch.balanceDueAt : nil }))
                    if batch.balanceDueEndAt != nil {
                        DatePicker("尾款结束", selection: Binding(
                            get: { batch.balanceDueEndAt ?? Date() }, set: { batch.balanceDueEndAt = $0 }))
                    }
                }
                Toggle("该团预约结束时间（选填）", isOn: Binding(
                    get: { batch.reservationEndAt != nil },
                    set: { batch.reservationEndAt = $0 ? Date() : nil }))
                if batch.reservationEndAt != nil {
                    DatePicker("该团预约结束", selection: Binding(
                        get: { batch.reservationEndAt ?? Date() },
                        set: { batch.reservationEndAt = $0 }))
                }
            }
            .padding(.vertical, 6)
        }
        Button("添加团次", systemImage: "plus") {
            batches.append(CatalogReservationBatch(name: "", balanceDueKind: .approximate,
                balanceDueReferenceAt: Date()))
        }
    }
}

/// 入橱确认页内直接选择，选项只展示运营配置的名称。
struct ShopCatalogPurchaseBatchPicker: View {
    let series: CatalogSeries
    @Binding var selectedID: String?

    private var validSelection: Binding<String?> {
        Binding(get: {
            guard let selectedID, series.reservationBatches?.contains(where: { $0.id == selectedID }) == true else { return nil }
            return selectedID
        }, set: { selectedID = $0 })
    }

    var body: some View {
        Picker("购买批次", selection: validSelection) {
            Text("请选择团次或批次").tag(Optional<String>.none)
            ForEach(series.reservationBatches ?? []) { batch in
                Text(batch.name).tag(Optional(batch.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("catalog.purchaseBatch.\(series.id)")
    }
}

/// 系列与每件商品共用：默认只占一行，按需展开完整档期。
struct ShopCatalogSeriesScheduleDisclosure: View {
    let series: CatalogSeries
    var anchor: Date? = nil
    @State private var isExpanded = false

    private var batches: [CatalogReservationBatch] { series.reservationBatches ?? [] }

    var body: some View {
        if !batches.isEmpty || CatalogSeriesBalanceDue.valueText(of: series) != nil {
            DisclosureGroup(isExpanded: $isExpanded) {
                ShopCatalogSeriesScheduleDetails(series: series, anchor: anchor)
                    .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Label("团次与尾款", systemImage: "calendar")
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 0)
                    Text(batches.isEmpty ? "查看时间" : "\(batches.count) 个批次")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .themeSkinSectionCard(cornerRadius: 16)
            .accessibilityIdentifier("catalog.schedule.\(series.id)")
        }
    }
}

struct ShopCatalogSeriesScheduleDetails: View {
    let series: CatalogSeries
    var anchor: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let batches = series.reservationBatches, !batches.isEmpty {
                ForEach(batches) { batch in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(batch.name).font(.subheadline.weight(.semibold))
                        if let schedule = series.paymentSchedule(batchID: batch.id) {
                            ShopCatalogReservationBatchTiming(schedule: schedule, anchor: anchor)
                        }
                    }
                }
            } else {
                ShopCatalogReservationBatchTiming(schedule: series, anchor: anchor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ShopCatalogReservationBatchTiming: View {
    let schedule: CatalogSeries
    let anchor: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("尾款时间：\(CatalogSeriesBalanceDue.valueText(of: schedule) ?? "待公布")")
            if let window = CatalogBalanceDueApproximation.declaredWindow(
                of: schedule, anchor: schedule.reservationEndAt ?? anchor),
               schedule.balanceDueKind == .approximate {
                Text("预计尾款日期：\(CatalogSeriesBalanceDue.shortDateText(window.start))（估算）")
                if window.end != window.start {
                    Text("预计结束日期：\(CatalogSeriesBalanceDue.shortDateText(window.end))（估算）")
                }
                Text(window.basis)
            }
        }
        .font(.footnote).foregroundStyle(.secondary)
    }
}
