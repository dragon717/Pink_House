//
//  ShopCatalogProductDeepEditView.swift
//  ItemManager
//
//  已发布商品深度编辑（V1.1 §4.2 Product 修改，重構方案缺口①收口）：
//    · 名称 / 分类 / 图片 / 配色尺码（图文绑定）/ 尺码表 全字段可编辑
//    · id 永不改变，用户侧引用（心愿/尾款/衣橱）不受影响
//    · 录入格式与补录草稿编辑器一致（每行一张图 / 「颜色,尺码[,图片]」）
//
//  ⚠️ 2026-09-22 双流程拆分：本页**只负责商品资料**，「价格」相关的两种操作
//  已拆成两条互不共用的独立流程，仅在页面底部提供只读总览与两个独立入口：
//    · 价格修正（覆盖当前价，不产生历史）→ ShopCatalogPriceCorrectionSheet
//    · 追加销售记录（再贩，append-only 带批次时间）→ ShopCatalogSaleRecordAppendSheet
//  本页的「保存」按钮只提交商品资料，不再顺带写任何价格。
//

import SwiftUI

struct ShopCatalogProductDeepEditView: View {
    let product: CatalogProduct
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "其他"
    @State private var imagesText = ""       // 每行一个 Bundle 文件名或 URL
    @State private var variantsText = ""     // 每行「颜色,尺码[,图片]」
    @State private var chartColumnsText = "" // 列名，逗号分隔
    @State private var chartRowsText = ""    // 每行「label:值,值,…」
    @State private var chartUnit = ""
    @State private var chartImageText = ""   // 尺码表原图

    @State private var loaded = false

    private let categories = ShopCatalogStore.canonicalCategoryOrder

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    TextField("商品名称", text: $name)
                    Picker("分类", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                }
                productInfoSection
                ShopCatalogPriceFlowEntrySection(product: product, store: store,
                                                 toast: $toast, actionError: $actionError)
            }
            .navigationTitle("深度编辑商品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 文案明确：本按钮只保存商品资料，不含任何价格改动
                    Button("保存资料") { save() }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                loadExisting()
            }
        }
    }

    // MARK: 图片 / 配色尺码 / 尺码表（与补录草稿编辑器同格式）

    private var productInfoSection: some View {
        Section {
            TextEditor(text: $imagesText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
            ShopCatalogImagePickerButton(mode: .append, text: $imagesText, label: "添加商品图片")
            Text("图片：每行一个 Bundle 文件名或 http(s) 链接；originalURL 未变的行自动复用原图片资源（规格绑定与用户端缓存不断链）；也可点上方按钮从相册选图自动入库")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextEditor(text: $variantsText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
            Text("配色尺码：每行「颜色,尺码[,图片]」，一侧可留空；第三段填图片行同一文件名/URL 即完成图文绑定")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("尺码表列名（逗号分隔，如：尺码,胸围,衣长）", text: $chartColumnsText)
                .font(.system(size: 13))
            TextEditor(text: $chartRowsText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
            Text("尺码表行：每行「标签:值,值,…」与列一一对应（如「M:84,52」）")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("单位（cm）", text: $chartUnit)
            TextField("尺码表/价格表原图（文件名/URL）", text: $chartImageText)
            ShopCatalogImagePickerButton(mode: .replace, text: $chartImageText, label: "添加尺码表/价格表原图")
        } header: {
            Text("图片 / 配色尺码 / 尺码表")
        }
    }

    // MARK: 载入现值

    private func loadExisting() {
        name = product.name
        category = product.category
        // 图片行：asset id → originalURL（Bundle 内联文件名原样回显）
        let refs = product.images.map { store.asset(id: $0)?.originalURL ?? $0 }
        imagesText = refs.joined(separator: "\n")
        let refToID = Dictionary(uniqueKeysWithValues: zip(refs, product.images))
        let variants = store.variants(forProduct: product.id)
        variantsText = variants.map {
            let base = "\($0.color ?? ""),\($0.size ?? "")"
            guard let ref = $0.imageAssetID.flatMap({ id in refToID.first(where: { $0.value == id })?.key }) else {
                return base
            }
            return "\(base),\(ref)"
        }.joined(separator: "\n")
        if let chart = store.sizeChart(forProduct: product.id) {
            chartColumnsText = chart.columns.joined(separator: ",")
            chartRowsText = chart.rows.map { row in
                "\(row.label):" + row.values.map { $0 ?? "" }.joined(separator: ",")
            }.joined(separator: "\n")
            chartUnit = chart.unit ?? ""
            chartImageText = chart.sourceImage ?? ""
        }
    }

    // MARK: 保存

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            actionError = "商品名称不能为空"
            return
        }
        var updated = product
        updated.name = trimmedName
        updated.category = category

        // 图片：非空行 → CatalogAsset；originalURL 与原图一致的行复用原 asset id（断链保护）
        let rows = imagesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let originalRefs = product.images.map { store.asset(id: $0)?.originalURL ?? $0 }
        var assets: [CatalogAsset] = []
        var refToNewID: [String: String] = [:]
        for (index, ref) in rows.enumerated() {
            let id: String
            if index < originalRefs.count, originalRefs[index] == ref, index < product.images.count {
                id = product.images[index]          // 原图原位：复用原 asset id
            } else if let reused = refToNewID[ref] {
                id = reused                          // 同文件多行：共用同一 asset
            } else {
                id = "asset-edit-\(product.id.suffix(8))-\(index)"
            }
            refToNewID[ref] = id
            assets.append(CatalogAsset(id: id,
                                       type: .productImage,
                                       thumbnailURL: nil,
                                       previewURL: nil,
                                       originalURL: ref,
                                       width: nil,
                                       height: nil))
        }

        // 配色尺码：每行「颜色,尺码[,图片]」，第三段按 originalURL 匹配新图完成图文绑定
        let variants: [CatalogProductVariant] = variantsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, line in
                let parts = line.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let color = parts.first.flatMap { $0.isEmpty ? nil : $0 }
                let size = parts.count > 1 ? (parts[1].isEmpty ? nil : parts[1]) : nil
                var imageAssetID: String? = nil
                if parts.count > 2, !parts[2].isEmpty {
                    imageAssetID = refToNewID[parts[2]]
                }
                return CatalogProductVariant(id: "var-edit-\(product.id.suffix(8))-\(index)",
                                             productID: product.id,
                                             color: color,
                                             size: size,
                                             imageAssetID: imageAssetID)
            }

        // 尺码表：列 + 行 + 原图（全空则清除）；共享解析口径（首列「尺码」= 标签列剔除，
        // 值尾冒号清洗），避免与补录编辑器 / 详情页渲染出现重复「尺码」列错位
        let parsedColumns = CatalogManualChartText.parseColumns(chartColumnsText)
        let parsedRows = CatalogManualChartText.parseRows(chartRowsText)
        let normalizedChart = CatalogManualChartText.normalized(columns: parsedColumns, rows: parsedRows)
        let sourceImage = chartImageText.trimmingCharacters(in: .whitespaces)
        var sizeChart: CatalogSizeChart? = nil
        if !normalizedChart.columns.isEmpty || !normalizedChart.rows.isEmpty || !sourceImage.isEmpty {
            var chart = CatalogSizeChart(id: "sizechart-edit-\(product.id.suffix(8))",
                                         productID: product.id)
            chart.unit = chartUnit.isEmpty ? nil : chartUnit
            chart.columns = normalizedChart.columns
            chart.rows = normalizedChart.rows
            chart.sourceImage = sourceImage.isEmpty ? nil : sourceImage
            sizeChart = chart
        }

        do {
            // 只写商品资料：价格一律不走这里（修正 / 追加各走各的独立接口）
            try ShopCatalogDraftStore.updatePublishedProduct(
                updated, assets: assets, variants: variants, sizeChart: sizeChart)
            toast = "已更新商品资料「\(updated.name)」，id 不变，用户引用不受影响"
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}
