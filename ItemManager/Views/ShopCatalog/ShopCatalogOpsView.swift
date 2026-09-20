//
//  ShopCatalogOpsView.swift
//  ItemManager
//
//  运营中心（计划 §26-31，入口：设置 → 运营工具 → 店家商品库，Catalog Editor 白名单）：
//    · 看板：今日更新 / 草稿 / 待审核 / 待补充 + ＋补录上新（§26）
//    · 补录：从淘宝内容导入（推荐）/ 手动录入（§27）
//    · 淘宝分享文本 / URL → 自动解析生成草稿（§28，禁止直接发布）
//    · 草稿流转：draft → submitted → reviewed → published（+archived，§31）
//    · 发布校验与 Shop / Series / Product 去重（§29）；整包 JSON 导出
//

import SwiftUI

struct ShopCatalogOpsView: View {
    @ObservedObject private var creatorAccess = CreatorAccess.shared
    @ObservedObject private var draftStore = ShopCatalogDraftStore.shared
    @ObservedObject private var store = ShopCatalogStore.shared

    /// 补录入口：nil=关闭；.taobao=淘宝导入；.manual=手动录入
    @State private var showsTaobaoImport = false
    @State private var showsManualDraft = false
    @State private var toast: String?
    @State private var actionError: String?

    var body: some View {
        Group {
            if creatorAccess.isCreator {
                content
            } else {
                ContentUnavailableView("仅限运营白名单", systemImage: "lock.shield",
                                       description: Text(CreatorAccess.shared.deniedGuidance))
            }
        }
        .navigationTitle("店家商品库")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.loadFromBundleIfNeeded() }
    }

    private var content: some View {
        Form {
            dashboardSection
            importSection
            batchSection
            draftSection
            manageSection
            exportSection
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 16)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        await MainActor.run { self.toast = nil }
                    }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: 运营中心看板（§26）

    private var dashboardSection: some View {
        Section {
            HStack(spacing: 0) {
                dashboardStat(title: "今日更新", value: draftStore.todayUpdatedCount)
                dashboardStat(title: "草稿", value: draftStore.draftCount)
                dashboardStat(title: "待审核", value: draftStore.pendingReviewCount)
                dashboardStat(title: "待补充", value: draftStore.needsSupplementCount)
            }
            // ＋ 补录上新（§27：淘宝导入推荐 / 手动录入兜底）
            Menu {
                Button {
                    showsTaobaoImport = true
                } label: {
                    Label("从淘宝内容导入（推荐）", systemImage: "wand.and.stars")
                }
                Button {
                    draftStore.upsert(CatalogProductDraft())
                    showsManualDraft = true
                } label: {
                    Label("手动录入", systemImage: "square.and.pencil")
                }
            } label: {
                Text("＋ 补录上新".appLocalized)
                    .frame(maxWidth: .infinity)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
        } header: {
            Text("运营中心")
        } footer: {
            Text("覆盖层：\(overlaySummary)")
        }
    }

    private var overlaySummary: String {
        guard let overlay = ShopCatalogDraftStore.loadOverlay() else { return "无（未发布过）" }
        return "店家 \(overlay.shops.count) · 系列 \(overlay.series.count) · 商品 \(overlay.products.count) · 记录 \(overlay.saleEvents.count)"
    }

    private func dashboardStat(title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
            Text(title.appLocalized)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 淘宝导入（§28：部分解析 → 草稿，禁止直接发布）

    private var importSection: some View {
        Section("淘宝导入（分享文本 / 链接）") {
            TextEditor(text: $importText)
                .frame(minHeight: 72)
                .font(.system(size: 13))
            Button {
                let parsed = ShopCatalogTaobaoParser.parse(importText)
                let draft = ShopCatalogTaobaoParser.makeDraft(from: parsed)
                draftStore.upsert(draft)
                importText = ""
                showsTaobaoImport = false
                // §28 三态：已识别 / 请确认 / 待补充
                toast = "已生成草稿（\(parsed.notes.joined(separator: "，"))），请补录店家与系列后提交"
            } label: {
                Label("解析并生成草稿", systemImage: "wand.and.stars")
            }
            .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("能拆多少拆多少，剩下人工补：自动识别链接 / 标题 / 价格 / 定金尾款；店家、系列、分类由人工补录。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @State private var importText = ""
    @State private var batchImportText = ""
    @State private var selectedBatch: CatalogBatchEntrySession?

    private var importProxy: Binding<String> {
        Binding(get: { importText }, set: { importText = $0 })
    }

    // MARK: 批量录入会话（V1.1 §4.1）

    private var batchSection: some View {
        Section("批次录入（多链接多单品）") {
            TextEditor(text: $batchImportText)
                .frame(minHeight: 88)
                .font(.system(size: 13))
            Button {
                importBatch()
            } label: {
                Label("批量解析并生成草稿（每条链接一个单品）", systemImage: "square.stack.3d.up")
            }
            .disabled(batchImportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ForEach(ShopCatalogDraftStore.loadBatches().reversed()) { batch in
                batchRow(batch)
            }
        }
    }

    /// 批次解析：先选归属（沿用首个草稿缺省 = 新建店家/系列由人工补），再批量生成
    private func importBatch() {
        let outcome = ShopCatalogTaobaoParser.parseBatch(batchImportText)
        guard !outcome.drafts.isEmpty || !outcome.failures.isEmpty else { return }
        var session = CatalogBatchEntrySession()
        // 若解析内容可识别出统一店家/系列名，预填第一条（人工可改）
        if let first = outcome.drafts.first {
            session.newShopName = first.newShopName
            session.newSeriesName = first.newSeriesName
        }
        // 回填原文（仅运营侧留存）
        for draft in outcome.drafts {
            if let url = draft.sourceURL {
                session.sourceTexts[draft.id] = url
            }
        }
        let summary = draftStore.createBatch(session, drafts: outcome.drafts, failures: outcome.failures)
        batchImportText = ""
        toast = summary
    }

    private func batchRow(_ batch: CatalogBatchEntrySession) -> some View {
        let batchDrafts = draftStore.drafts.filter { $0.batchID == batch.id }
        let draftable = batchDrafts.filter { $0.status == .draft }.count
        let assigned = batch.shopID != nil || !batch.newShopName.isEmpty
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(batchTitle(batch))
                    .font(.system(size: 13, weight: .medium))
                Text("共 \(batchDrafts.count) 条 · 待提交 \(draftable) 条\(assigned ? "" : " · 未指定归属")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if draftable > 0 {
                Button("批量提交") {
                    do {
                        let count = try draftStore.submitBatch(batch.id)
                        toast = "已批量提交 \(count) 条单品草稿"
                    } catch { actionError = error.localizedDescription }
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedBatch = batch }
        .sheet(item: $selectedBatch) { batch in
            ShopCatalogBatchDetailView(draftStore: draftStore, store: store, batch: batch)
        }
    }

    private func batchTitle(_ batch: CatalogBatchEntrySession) -> String {
        let shop = batch.shopID.flatMap { store.shop(id: $0)?.name } ?? batch.newShopName
        let series = batch.seriesID.flatMap { store.series(id: $0)?.name } ?? batch.newSeriesName
        let head = [shop, series].filter { !$0.isEmpty }.joined(separator: " · ")
        return head.isEmpty ? "批次 \(batch.id)" : head
    }

    // MARK: 草稿箱（§30 人工补录 / §31 状态流转）

    private var draftSection: some View {
        Section {
            ForEach(draftStore.drafts) { draft in
                ShopCatalogDraftEditorRow(
                    draft: draft,
                    draftStore: draftStore,
                    store: store,
                    toast: $toast,
                    actionError: $actionError
                )
            }
            if draftStore.drafts.isEmpty {
                Text("暂无草稿。点上方「＋ 补录上新」开始。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("草稿箱")
        } footer: {
            Text("发布 = 草稿 → 提交 → 审核通过后写入覆盖层并对用户可见（§31）；同名商品的现货记录会追加到既有商品（§29 去重 / 现货价格补录）。")
        }
    }

    // MARK: 实体管理（V1.1 §4.2：编辑 / 归档 / 引用保护删除）

    private var manageSection: some View {
        Section {
            NavigationLink {
                ShopCatalogOpsManageView()
            } label: {
                Label("店家 / 系列 / 商品管理（编辑、归档、删除）", systemImage: "square.and.pencil.circle")
            }
        } footer: {
            Text("被用户心愿/尾款/衣橱引用过的条目只能归档，不能删除（引用保护）。")
        }
    }

    // MARK: 导出

    private var exportSection: some View {
        Section("导出") {
            Button {
                if let json = draftStore.exportJSON(store: store) {
                    UIPasteboard.general.string = json
                    toast = "整包 JSON 已复制到剪贴板"
                }
            } label: {
                Label("复制整包 JSON（含覆盖层）", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - 草稿编辑行（§31 状态机操作）

private struct ShopCatalogDraftEditorRow: View {
    let draft: CatalogProductDraft
    @ObservedObject var draftStore: ShopCatalogDraftStore
    @ObservedObject var store: ShopCatalogStore
    @Binding var toast: String?
    @Binding var actionError: String?

    @State private var showsEditor = false
    @State private var showsRejectPrompt = false
    @State private var rejectReasonText = ""

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.name.isEmpty ? "（未命名草稿）" : draft.name)
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 6) {
                    statusBadge
                    Text("\(draft.saleKind.displayName) · \(ShopCatalogFormat.price(Decimal(draft.price)))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                // 驳回原因（V1.1 §4.1）：退回草稿后保留展示，重新提交时清空
                if let reason = draft.rejectReason, !reason.isEmpty {
                    Text("驳回：\(reason)")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
            if draft.status == .submitted {
                // 单品粒度审核（§4.1）：通过发布 / 驳回退回草稿（保留原因）
                Button("驳回", role: .destructive) {
                    rejectReasonText = ""
                    showsRejectPrompt = true
                }
                .font(.system(size: 13))
                .buttonStyle(.bordered)
                .tint(.red)
            }
            nextActionButton
        }
        .contentShape(Rectangle())
        .onTapGesture { showsEditor = true }
        .sheet(isPresented: $showsEditor) {
            ShopCatalogDraftDetailEditor(draft: draft, draftStore: draftStore, store: store)
        }
        .alert("驳回原因", isPresented: $showsRejectPrompt) {
            TextField("选填，将展示给补录人", text: $rejectReasonText)
            Button("确认驳回", role: .destructive) {
                do {
                    try draftStore.review(draft, approve: false, reason: rejectReasonText)
                    toast = "已驳回，退回草稿"
                } catch { actionError = error.localizedDescription }
                rejectReasonText = ""
            }
            Button("取消", role: .cancel) { rejectReasonText = "" }
        } message: {
            Text("草稿将退回草稿箱并保留原因（V1.1 §4.1）")
        }
    }

    private var statusBadge: some View {
        Text(draft.status.displayName)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(badgeColor))
    }

    private var badgeColor: Color {
        switch draft.status {
        case .draft: return .gray
        case .submitted: return .orange
        case .reviewed: return .blue
        case .published: return .green
        case .archived: return .brown
        }
    }

    /// §31 流转主操作：草稿→提交 / 已提交→审核通过 / 已审核→发布
    @ViewBuilder
    private var nextActionButton: some View {
        switch draft.status {
        case .draft:
            Button("提交") { advance(to: .submitted) }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(.orange)
        case .submitted:
            Button("审核通过") { advance(to: .reviewed) }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.bordered)
                .tint(.blue)
        case .reviewed:
            Button("发布") { publishNow() }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderedProminent)
                .tint(.pink)
        case .published, .archived:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private func advance(to status: CatalogPublicationStatus) {
        do {
            try draftStore.advance(draft, to: status)
            toast = "已\(status.displayName)"
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func publishNow() {
        do {
            let summary = try draftStore.publish(draft, store: store)
            toast = summary
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - 草稿详情编辑（人工补录，§30 兜底：手动可完整全流程）

private struct ShopCatalogDraftDetailEditor: View {
    @Binding private var draftBox: CatalogProductDraft
    @ObservedObject private var draftStore: ShopCatalogDraftStore
    @ObservedObject private var store: ShopCatalogStore
    @Environment(\.dismiss) private var dismiss

    init(draft: CatalogProductDraft, draftStore: ShopCatalogDraftStore, store: ShopCatalogStore) {
        _draftBox = Binding(
            get: { draftStore.drafts.first { $0.id == draft.id } ?? draft },
            set: { draftStore.upsert($0) }
        )
        self.draftStore = draftStore
        self.store = store
    }

    private let categories = ShopCatalogStore.canonicalCategoryOrder

    // MARK: 完整商品资料（G5：手动录入可完成全部业务；文本行式录入）
    @State private var imagesText = ""       // 每行一个 Bundle 文件名或 URL
    @State private var variantsText = ""     // 每行「颜色,尺码」（可留空一侧）
    @State private var chartColumnsText = "" // 列名，逗号分隔
    @State private var chartRowsText = ""    // 每行「label:值,值,…」
    @State private var chartUnit = ""
    @State private var chartImageText = ""   // 尺码表原图（Bundle 文件名/URL）

    var body: some View {
        NavigationStack {
            Form {
                Section("商品") {
                    TextField("商品名称", text: $draftBox.name)
                    Picker("分类", selection: $draftBox.category) {
                        ForEach(categories.filter { $0 != "其他" }, id: \.self) { Text($0).tag($0) }
                        Text("其他").tag("其他")
                    }
                }
                productInfoSection
                Section("销售记录") {
                    Picker("类型", selection: $draftBox.saleKind) {
                        Text("预约价").tag(CatalogSaleEventType.reservation)
                        Text("现货价").tag(CatalogSaleEventType.stock)
                    }
                    HStack {
                        Text("价格")
                        Spacer()
                        TextField("0", value: $draftBox.price, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    if draftBox.saleKind == .reservation {
                        HStack {
                            Text("定金")
                            Spacer()
                            TextField("可空", value: $draftBox.deposit, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                        HStack {
                            Text("尾款")
                            Spacer()
                            TextField("可空", value: $draftBox.balance, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 110)
                        }
                        if let issue = draftBox.depositBalanceIssue {
                            Text(issue)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section("店家") {
                    Picker("关联店家", selection: $draftBox.shopID) {
                        Text("新建店家").tag(String?.none)
                        ForEach(store.catalog?.shops ?? []) { shop in
                            Text(shop.name).tag(String?.some(shop.id))
                        }
                    }
                    if draftBox.shopID == nil {
                        TextField("新店家名称", text: $draftBox.newShopName)
                        TextField("别名（逗号分隔）", text: $draftBox.newShopAliases)
                    }
                }
                Section("系列") {
                    Picker("关联系列", selection: $draftBox.seriesID) {
                        Text("新建系列").tag(String?.none)
                        ForEach(store.catalog?.series ?? []) { series in
                            Text(series.name).tag(String?.some(series.id))
                        }
                    }
                    if draftBox.seriesID == nil {
                        TextField("新系列名称", text: $draftBox.newSeriesName)
                        HStack {
                            TextField("年份", value: $draftBox.newSeriesYear, format: .number.grouping(.never))
                                .keyboardType(.numberPad)
                            TextField("季节（如 冬）", text: $draftBox.newSeriesSeason)
                        }
                    }
                }
                Section("来源") {
                    TextField("淘宝链接（可空）", text: Binding(
                        get: { draftBox.sourceURL ?? "" },
                        set: { draftBox.sourceURL = $0.isEmpty ? nil : $0 }
                    ))
                }
            }
            .navigationTitle("补录草稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        applyProductInfo()
                        dismiss()
                    }
                }
            }
            .onAppear {
                store.loadFromBundleIfNeeded()
                loadProductInfo()
            }
        }
    }

    // MARK: 完整商品资料（图片/规格/尺码表）

    private var productInfoSection: some View {
        Section {
            TextEditor(text: $imagesText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
            Text("图片：每行一个 Bundle 文件名或 http(s) 链接（originalURL 必留原图）")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextEditor(text: $variantsText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
            Text("配色尺码：每行「颜色,尺码[,图片]」，一侧可留空（如「夜空蓝,M,night.png」）；第三段填图片行同一文件名/URL 即完成图文绑定（选中该配色时展示其照片）")
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
            TextField("尺码表原图（文件名/URL）", text: $chartImageText)
        } header: {
            Text("图片 / 配色尺码 / 尺码表")
        }
    }

    private func loadProductInfo() {
        let draft = draftBox
        imagesText = draft.images.map { $0.originalURL }.joined(separator: "\n")
        let idToRef = Dictionary(uniqueKeysWithValues: draft.images.map { ($0.id, $0.originalURL) })
        variantsText = draft.variants.map {
            let base = "\($0.color ?? ""),\($0.size ?? "")"
            guard let ref = $0.imageAssetID.flatMap({ idToRef[$0] }) else { return base }
            return "\(base),\(ref)"
        }.joined(separator: "\n")
        if let chart = draft.sizeChart {
            chartColumnsText = chart.columns.joined(separator: ",")
            chartRowsText = chart.rows.map { row in
                "\(row.label):" + row.values.map { $0 ?? "" }.joined(separator: ",")
            }.joined(separator: "\n")
            chartUnit = chart.unit ?? ""
            chartImageText = chart.sourceImage ?? ""
        }
    }

    private func applyProductInfo() {
        var draft = draftBox
        // 图片：非空行 → CatalogAsset（originalURL 必留）
        draft.images = imagesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .enumerated()
            .map { index, ref in
                CatalogAsset(id: "asset-draft-\(draft.id.prefix(6))-\(index)",
                             type: .productImage,
                             thumbnailURL: nil, previewURL: nil,
                             originalURL: ref, width: nil, height: nil)
            }
        // 配色尺码：每行「颜色,尺码[,图片]」——第三段为图片引用（与图片行相同的
        // 文件名/URL），图文联动（V1.2 点菜式选购）；匹配不到图片行则忽略绑定
        let imageRefs = imagesText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        draft.variants = variantsText
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
                if parts.count > 2, !parts[2].isEmpty,
                   let asset = draft.images.first(where: { $0.originalURL == parts[2] }) {
                    imageAssetID = asset.id
                }
                return CatalogProductVariant(id: "var-draft-\(draft.id.prefix(6))-\(index)",
                                             productID: "",
                                             color: color, size: size,
                                             imageAssetID: imageAssetID)
            }
        // 尺码表：列 + 行（label:值,…）+ 原图
        let columns = chartColumnsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let rows = chartRowsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line -> CatalogSizeRow? in
                let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                guard let label = pair.first else { return nil }
                let values = (pair.count > 1 ? String(pair[1]) : "")
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .map { $0.isEmpty ? nil : $0 }
                return CatalogSizeRow(label: String(label), values: values)
            }
        let sourceImage = chartImageText.trimmingCharacters(in: .whitespaces)
        if !columns.isEmpty || !rows.isEmpty || !sourceImage.isEmpty {
            var chart = CatalogSizeChart(id: "sizechart-draft-\(draft.id.prefix(6))",
                                         productID: "")
            chart.unit = chartUnit.isEmpty ? nil : chartUnit
            chart.columns = columns
            chart.rows = rows
            chart.sourceImage = sourceImage.isEmpty ? nil : sourceImage
            draft.sizeChart = chart
        } else {
            draft.sizeChart = nil
        }
        draftBox = draft
    }
}
