//
//  ShopCatalogPriceFlowViews.swift
//  ItemManager
//
//  价格双流程 UI（2026-09-22：深度编辑拆分，两条流程互不共用编辑/提交逻辑）：
//
//    ┌─────────────────────────┬──────────────────────────────┐
//    │ 价格修正                 │ 追加销售记录                  │
//    │ ShopCatalogPrice-        │ ShopCatalogSaleRecord-       │
//    │ CorrectionSheet          │ AppendSheet                  │
//    ├─────────────────────────┼──────────────────────────────┤
//    │ 「改当前价」             │ 「加一条再贩记录」             │
//    │ 覆盖 priceCorrection     │ append 一条 SaleEvent         │
//    │ 无日期、无批次、无历史    │ 必填再贩日期 + 可选批次名      │
//    │ 保存 = 覆盖              │ 保存 = 新增（重复提交被拦截）  │
//    └─────────────────────────┴──────────────────────────────┘
//
//  界面上的语义区分（避免用户在同一面板混淆两种操作）：
//    · 橙色「笔」标识 = 修正当前状态；绿色「时钟箭头」标识 = 追加历史；
//    · 各自独立表单 + 独立保存按钮，提交文案明确写出后果
//      （「覆盖当前价，不产生历史记录」/「新增一条记录，已有记录不变」）。
//

import SwiftUI

// MARK: - 共享：语义横幅 + 金额解析

/// 流程语义横幅：用颜色 + 图标 + 一句话后果说明，把两条流程在视觉上彻底分开
private struct PriceFlowBanner: View {
    enum Flow {
        case correction
        case append

        var tint: Color {
            switch self {
            case .correction: return Color.orange
            case .append: return Color.green
            }
        }
        var icon: String {
            switch self {
            case .correction: return "pencil.line"
            case .append: return "clock.arrow.circlepath"
            }
        }
    }

    let flow: Flow
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: flow.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(flow.tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(flow.tint)
            }
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

/// 金额文本 → Decimal（空白视为 nil，非法输入视为 nil 交由校验拦截）
private func priceDecimal(_ text: String) -> Decimal? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return Decimal(string: trimmed)
}

private func priceString(_ value: Decimal?) -> String {
    guard let value else { return "暂无" }
    return "¥\(NSDecimalNumber(decimal: value).stringValue)"
}

// MARK: - 流程一：价格修正（覆盖当前价，不产生历史记录）

struct ShopCatalogPriceCorrectionSheet: View {
    let product: CatalogProduct
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?
    @Environment(\.dismiss) private var dismiss

    @State private var reservationText = ""
    @State private var stockText = ""
    @State private var depositText = ""
    @State private var balanceText = ""
    @State private var loaded = false

    private var correction: CatalogPriceCorrection? { product.priceCorrection }
    private var archive: CatalogPriceArchive { store.priceArchive(forProduct: product.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PriceFlowBanner(
                        flow: .correction,
                        title: "价格修正 · 改当前价",
                        detail: "提交后直接覆盖本商品当前展示的预约价 / 现货价 / 定金 / 尾款，只保留最新状态，不会产生历史记录；字段留空 = 清除该价格。若要为往年款再贩、复刻、补货新增一条带时间的记录，请改用「追加销售记录」。")
                }

                Section {
                    TextField("现货价（留空 = 清除）", text: $stockText)
                        .keyboardType(.decimalPad)
                    TextField("预约价（留空 = 清除）", text: $reservationText)
                        .keyboardType(.decimalPad)
                    TextField("定金（留空 = 清除）", text: $depositText)
                        .keyboardType(.decimalPad)
                    TextField("尾款（留空 = 清除）", text: $balanceText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("修正为")
                } footer: {
                    Text("四个字段按当前生效值预填：留空 = 清除该价格（生效值变「暂无」），想保留的字段请保留预填数字。填了定金和尾款时必须与预约价对账一致。")
                }

                Section("当前生效值（修正后）") {
                    row("预约价", priceString(archive.currentReservationPrice))
                    row("定金", priceString(archive.currentDeposit))
                    row("尾款", priceString(archive.currentBalance))
                    row("现货价", priceString(archive.currentStockPrice))
                    if let at = correction?.correctedAt {
                        row("上次修正", at.formatted(.dateTime.year().month().day().hour().minute()))
                    }
                }

                if correction != nil {
                    Section {
                        Button(role: .destructive) {
                            do {
                                try ShopCatalogDraftStore.clearPriceCorrection(productID: product.id)
                                toast = "已撤销「\(product.name)」的价格修正，回退到历史记录推导值"
                                dismiss()
                            } catch { actionError = error.localizedDescription }
                        } label: {
                            Text("撤销价格修正（回退到历史记录推导）")
                        }
                    } footer: {
                        Text("撤销只清除修正值，已追加的销售记录一条都不会被删除或改动。")
                    }
                }
            }
            .navigationTitle("价格修正")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存修正") { submit() }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                // 按当前生效值（修正优先，否则历史推导）完整预填：
                // 提交 = 全量快照覆盖；用户删掉某字段再保存 = 明确清除该价格
                reservationText = archive.currentReservationPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                stockText = archive.currentStockPrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                depositText = archive.currentDeposit.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
                balanceText = archive.currentBalance.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium))
        }
        .font(.system(size: 13))
    }

    private func submit() {
        do {
            try ShopCatalogDraftStore.correctCurrentPrice(
                productID: product.id,
                reservationPrice: priceDecimal(reservationText),
                stockPrice: priceDecimal(stockText),
                deposit: priceDecimal(depositText),
                balance: priceDecimal(balanceText))
            toast = "已修正「\(product.name)」当前价格（覆盖最新状态，未产生历史记录）"
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - 流程二：追加销售记录（再贩 / 复刻 / 补货，append-only）

struct ShopCatalogSaleRecordAppendSheet: View {
    let product: CatalogProduct
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?
    @Environment(\.dismiss) private var dismiss

    @State private var type: CatalogSaleEventType = .rerelease
    @State private var priceText = ""
    @State private var depositText = ""
    @State private var balanceText = ""
    @State private var batchLabel = ""
    @State private var startAt = Date()
    @State private var hasEndAt = false
    @State private var endAt = Date()

    private var history: [CatalogSaleEvent] { store.saleHistory(forProduct: product.id) }

    /// 重复提交预检：与待写入记录业务维度完全一致的记录已存在 → 拦截
    private var isDuplicate: Bool {
        guard let price = priceDecimal(priceText), price > 0 else { return false }
        let probe = CatalogSaleEvent(
            id: "probe", productID: product.id, type: type, price: price,
            deposit: priceDecimal(depositText),
            balance: type == .reservation ? (priceDecimal(balanceText) ?? (price - (priceDecimal(depositText) ?? 0))) : nil,
            startAt: startAt, endAt: hasEndAt ? endAt : nil,
            batchLabel: nil, recordedAt: nil)
        let fingerprint = probe.appendFingerprint
        return history.contains { $0.appendFingerprint == fingerprint }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PriceFlowBanner(
                        flow: .append,
                        title: "追加销售记录 · 往年款再贩 / 复刻 / 补货",
                        detail: "这是新增一条业务事件：只追加、永不修改或覆盖已有记录。每条记录必须带上再贩日期（批次时间），同一商品可保留多条按时间排序的历史记录。若只是把当前价格填错了，请用「价格修正」。")
                }

                Section {
                    Picker("记录类型", selection: $type) {
                        Text("再贩").tag(CatalogSaleEventType.rerelease)
                        Text("预约价").tag(CatalogSaleEventType.reservation)
                        Text("现货价").tag(CatalogSaleEventType.stock)
                    }
                    DatePicker("再贩日期 / 批次时间", selection: $startAt, displayedComponents: .date)
                    TextField("批次（选填，如「2025 再贩第二批」）", text: $batchLabel)
                    Toggle("设置结束日期", isOn: $hasEndAt)
                    if hasEndAt {
                        DatePicker("结束日期", selection: $endAt, displayedComponents: .date)
                    }
                } header: {
                    Text("批次信息")
                } footer: {
                    Text("时间维度必填：没有再贩日期的记录无法区分批次，也不允许提交。")
                }

                Section {
                    TextField("价格", text: $priceText)
                        .keyboardType(.decimalPad)
                    if type == .reservation {
                        TextField("定金（可空）", text: $depositText)
                            .keyboardType(.decimalPad)
                        TextField("尾款（可空，缺省 = 价格 − 定金）", text: $balanceText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("本批次价格")
                }

                if isDuplicate {
                    Section {
                        Text("已存在一条业务维度完全相同的记录（同类型 / 同价格 / 同批次日），重复提交已被拦截。请修改价格或批次日期后再提交。")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    if history.isEmpty {
                        Text("暂无历史销售记录")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(history) { event in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(event.type.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(priceString(event.price))
                                        .font(.system(size: 13, weight: .medium))
                                    Text(event.batchDisplay + (event.deposit == nil ? "" : " · 定金 \(priceString(event.deposit))"))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("已有记录（只读 · 不可修改）")
                } footer: {
                    Text("🔒 已有记录一经写入即不可变：本次提交只会在末尾新增一条，不会改写上面任何一行。")
                }
            }
            .navigationTitle("追加销售记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加记录") { submit() }
                        .disabled(isDuplicate)
                }
            }
        }
    }

    private func submit() {
        guard let price = priceDecimal(priceText) else {
            actionError = "请填写本批次价格"
            return
        }
        do {
            let event = try ShopCatalogDraftStore.appendSaleRecord(
                productID: product.id,
                type: type,
                price: price,
                deposit: type == .reservation ? priceDecimal(depositText) : nil,
                balance: type == .reservation ? priceDecimal(balanceText) : nil,
                startAt: startAt,
                endAt: hasEndAt ? endAt : nil,
                batchLabel: batchLabel)
            toast = "已为「\(product.name)」追加\(type.displayName)记录（\(event.batchDisplay)），已有记录未改动"
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - 深度编辑页内的「价格与销售」入口区（只读总览 + 两个独立入口）

/// 在深度编辑页把两条流程并列呈现，但**不提供任何共用表单**：
/// 这里只展示只读总览与两个跳转按钮，真正的编辑分别在两个独立 sheet 里完成。
struct ShopCatalogPriceFlowEntrySection: View {
    let product: CatalogProduct
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?

    @State private var showsCorrection = false
    @State private var showsAppend = false

    private var archive: CatalogPriceArchive { store.priceArchive(forProduct: product.id) }
    private var history: [CatalogSaleEvent] { store.saleHistory(forProduct: product.id) }

    var body: some View {
        Section {
            // 当前生效价格（修正优先于历史推导）
            HStack {
                Text("当前现货价").foregroundStyle(.secondary)
                Spacer()
                Text(priceString(archive.currentStockPrice))
                    .font(.system(size: 14, weight: .medium))
            }
            .font(.system(size: 13))
            HStack {
                Text("当前预约价").foregroundStyle(.secondary)
                Spacer()
                Text(priceString(archive.currentReservationPrice))
                    .font(.system(size: 14, weight: .medium))
            }
            .font(.system(size: 13))
            if archive.isCorrected {
                Text("已存在价格修正：页面展示的是修正后的当前价，历史记录未被改动")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            Button {
                showsCorrection = true
            } label: {
                Label {
                    Text("价格修正（覆盖当前价 · 不产生历史）")
                } icon: {
                    Image(systemName: "pencil.line")
                }
                .foregroundStyle(Color.orange)
            }
            .font(.system(size: 13))

            Button {
                showsAppend = true
            } label: {
                Label {
                    Text("追加销售记录（再贩 · 带批次时间）")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .foregroundStyle(Color.green)
            }
            .font(.system(size: 13))

            if !history.isEmpty {
                NavigationLink {
                    ShopCatalogSaleHistoryView(product: product, store: store)
                } label: {
                    Text("查看历史销售记录（\(history.count) 条 · 只读）")
                        .font(.system(size: 13))
                }
            }
        } header: {
            Text("价格与销售（两条独立流程）")
        } footer: {
            Text("「改价格」用价格修正（覆盖当前状态）；「往年款再贩 / 补货」用追加销售记录（只新增、带批次时间）。两者不共用任何编辑与提交逻辑。")
        }
        .sheet(isPresented: $showsCorrection) {
            ShopCatalogPriceCorrectionSheet(product: product, store: store,
                                            toast: $toast, actionError: $actionError)
        }
        .sheet(isPresented: $showsAppend) {
            ShopCatalogSaleRecordAppendSheet(product: product, store: store,
                                             toast: $toast, actionError: $actionError)
        }
    }
}

// MARK: - 历史销售记录（只读）

struct ShopCatalogSaleHistoryView: View {
    let product: CatalogProduct
    @ObservedObject var store: ShopCatalogStore

    private var history: [CatalogSaleEvent] { store.saleHistory(forProduct: product.id) }

    var body: some View {
        List {
            Section {
                Text("历史记录按批次时间倒序排列，只可新增、不可修改或删除。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(history) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(event.type.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary))
                        Text(event.batchDisplay)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(priceString(event.price))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    if event.deposit != nil || event.balance != nil {
                        Text("定金 \(priceString(event.deposit)) · 尾款 \(priceString(event.balance))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("历史销售记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}
