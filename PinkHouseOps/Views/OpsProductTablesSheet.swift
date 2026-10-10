import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 从目录里的同一份系列价格表和商品尺码表读取；补录仍走既有编辑命令。
struct OpsProductTablesSheet: View {
    @ObservedObject var workspace: OpsWorkspace
    let productID: String
    @Environment(\.dismiss) private var dismiss
    @State private var editor: TableEditor?

    private var product: CatalogProduct? { workspace.catalog.products.first { $0.id == productID } }
    private var series: CatalogSeries? { workspace.catalog.series.first { $0.id == product?.seriesID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("价格表与尺码表").font(.headline)
            Text(product?.name ?? "商品已删除").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    prices
                    seriesPriceChart
                    sizeChart
                }
            }
            if let message = workspace.catalogEditSyncMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            HStack { Spacer(); Button("关闭") { dismiss() } }
        }
        .padding(20).frame(width: 680, height: 660)
        .sheet(item: $editor) { item in
            switch item {
            case .price:
                PriceCorrectionFormSheet(workspace: workspace, productID: productID, syncOnSave: true)
            case .size:
                SizeChartFormSheet(workspace: workspace, productID: productID, syncOnSave: true)
            case .seriesPrice(let id):
                OpsSeriesPriceChartEditor(workspace: workspace, seriesID: id)
            }
        }
    }

    private var prices: some View {
        let archive = workspace.priceArchive(forProduct: productID)
        return OpsCard(title: "商品价格", systemImage: "yensign.circle") {
            LabeledContent("预约价", value: money(archive?.currentReservationPrice, archive?.currentCurrency))
            LabeledContent("定金", value: money(archive?.currentDeposit, archive?.currentCurrency))
            LabeledContent("尾款", value: money(archive?.currentBalance, archive?.currentCurrency))
            LabeledContent("现货价", value: money(archive?.currentStockPrice, archive?.currentCurrency))
            Button("编辑 / 补录商品价格…") { editor = .price }
                .disabled(product == nil)
        }
    }

    private var seriesPriceChart: some View {
        OpsCard(title: "系列价格表", systemImage: "tablecells") {
            if let chart = series?.priceChart {
                Text("\(series?.name ?? "") · 系列内商品共用").font(.caption).foregroundStyle(.secondary)
                table(unit: chart.unit, columns: chart.columns, rows: chart.rows)
                if chartImageReferences(chart).isEmpty {
                    Text("尚未上传价格表原图，可补录。")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(Array(chartImageReferences(chart).enumerated()), id: \.offset) { _, reference in
                    OpsTableImage(workspace: workspace, reference: reference)
                }
            } else {
                Text("未录入系列价格表，可上传原图或填写表格。")
                    .foregroundStyle(.secondary)
            }
            if let series {
                Button("编辑 / 补录系列价格表…") { editor = .seriesPrice(series.id) }
            }
        }
    }

    private var sizeChart: some View {
        OpsCard(title: "商品尺码表", systemImage: "ruler") {
            if let chart = workspace.sizeChart(forProduct: productID) {
                table(unit: chart.unit, columns: chart.columns, rows: chart.rows)
                if let image = chart.sourceImage {
                    OpsTableImage(workspace: workspace, reference: image)
                } else {
                    Text("尚未上传尺码表原图，可补录。")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else {
                Text("未录入尺码表，可上传原图或填写表格。")
                    .foregroundStyle(.secondary)
            }
            Button("编辑 / 补录尺码表…") { editor = .size }
                .disabled(product == nil)
        }
    }

    private func table(unit: String?, columns: [String], rows: [CatalogSizeRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let unit { Text("单位：\(unit)").font(.caption).foregroundStyle(.secondary) }
            if !columns.isEmpty {
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("款式 / 尺码").bold()
                            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in Text(column).bold() }
                        }
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            GridRow {
                                Text(row.label)
                                ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in Text(value ?? "—") }
                            }
                        }
                    }.font(.callout).textSelection(.enabled)
                }
            }
        }
    }

    private func money(_ value: Decimal?, _ currency: CatalogCurrency?) -> String {
        value.map { CatalogMoney(amount: $0, currency: currency ?? .unknown).displayText } ?? "未录入"
    }

    private enum TableEditor: Identifiable {
        case price, size, seriesPrice(String)
        var id: String {
            switch self { case .price: return "price"; case .size: return "size"
            case .seriesPrice(let id): return "series-\(id)" }
        }
    }
}

private struct OpsTableImage: View {
    @ObservedObject var workspace: OpsWorkspace
    let reference: String

    var body: some View {
        if let url = workspace.stagedFileURL(forReference: workspace.asset(for: reference)?.originalURL ?? reference),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 300)
                .onTapGesture { NSWorkspace.shared.open(url) }
                .help("点击查看原图")
        } else {
            Label("已关联原图，本机尚未下载图片；同步完成后可查看。", systemImage: "photo")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 多图原样加载，新增、替换或移除后显式保存；不会只保留旧表的第一张图。
struct OpsSeriesPriceChartEditor: View {
    @ObservedObject var workspace: OpsWorkspace
    let seriesID: String
    @Environment(\.dismiss) private var dismiss
    @State private var unit = ""
    @State private var columns = ""
    @State private var rows = ""
    @State private var images: [String] = []
    @State private var importsImages = false
    @State private var error: String?
    @State private var didLoad = false

    var body: some View {
        OpsFormFrame(title: "编辑系列价格表", subtitle: "系列内商品共用这张表。可以只上传原图，也可以录入结构化表格。",
            width: 620, contentHeight: 440, content: {
                TextField("单位（如 元）", text: $unit)
                TextField("列名（逗号分隔）", text: $columns)
                Text("每行：款式 = 值1, 值2, …").font(.caption)
                TextEditor(text: $rows).font(.body.monospaced()).frame(height: 130)
                ForEach(Array(images.enumerated()), id: \.offset) { index, reference in
                    HStack(alignment: .top) {
                        OpsTableImage(workspace: workspace, reference: reference)
                        Button("移除") { images.remove(at: index) }.controlSize(.small)
                    }
                }
                Button { importsImages = true } label: {
                    Label("添加价格表图片（可多选）…", systemImage: "photo.badge.plus")
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }, onCancel: { dismiss() }, onConfirm: save)
        .onAppear {
            guard !didLoad else { return }; didLoad = true
            guard let chart = workspace.catalog.series.first(where: { $0.id == seriesID })?.priceChart else { return }
            unit = chart.unit ?? ""
            columns = chart.columns.joined(separator: ",")
            rows = chart.rows.map { $0.label + " = " + $0.values.map { $0 ?? "" }.joined(separator: ",") }.joined(separator: "\n")
            images = chartImageReferences(chart)
        }
        .fileImporter(isPresented: $importsImages, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            do {
                for url in try result.get() {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let id = workspace.importSingleImage(from: url), !images.contains(id) { images.append(id) }
                    if let failure = workspace.lastError { error = failure }
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func save() -> Bool {
        error = nil
        var parsedColumns: [String] = []
        var parsedRows: [CatalogSizeRow] = []
        if !columns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !rows.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let (parsed, issue) = OpsChartTextParsing.parse(columnsText: columns, rowsText: rows)
            guard let parsed else { error = issue; return false }
            parsedColumns = parsed.columns; parsedRows = parsed.rows
        }
        guard !images.isEmpty || !parsedRows.isEmpty else {
            error = "请上传价格表图片或填写表格。"; return false
        }
        guard workspace.updateSeriesPriceChart(seriesID: seriesID, unit: unit,
            columns: parsedColumns, rows: parsedRows, sourceImages: images), workspace.saveCatalogEditorChanges() else {
            error = workspace.lastError ?? "保存失败，请重试。"; return false
        }
        return true
    }
}

private func chartImageReferences(_ chart: CatalogPriceChart) -> [String] {
    var seen: Set<String> = []
    return ((chart.sourceImages ?? []) + [chart.sourceImage].compactMap { $0 })
        .filter { !$0.isEmpty && seen.insert($0).inserted }
}
