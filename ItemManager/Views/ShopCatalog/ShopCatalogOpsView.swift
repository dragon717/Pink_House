//
//  ShopCatalogOpsView.swift
//  ItemManager
//
//  运营中心（计划 §26-31，入口：设置 → 运营工具 → 店家商品库，Catalog Editor 白名单）：
//    · 看板：今日更新 / 草稿 / 待审核 / 待补充 + ＋补录上新（§26）
//    · 补录：手动录入（§27）
//    · 淘宝分享文本 / URL 导入与批量导入已下线（§28 Parser 及关联代码已删除）
//    · 草稿流转：draft → submitted → reviewed → published（+archived，§31）
//    · 发布校验与 Shop / Series / Product 去重（§29）；整包 JSON 导出
//

import SwiftUI

struct ShopCatalogOpsView: View {
    @ObservedObject private var creatorAccess = CreatorAccess.shared
    @ObservedObject private var draftStore = ShopCatalogDraftStore.shared
    @ObservedObject private var store = ShopCatalogStore.shared

    /// 手动录入批次会话（V1.1 §4.1.2：同一会话内连续添加多件单品）
    @State private var manualBatch: CatalogBatchEntrySession?
    @State private var toast: String?
    @State private var actionError: String?

    // 批次删除 / 多选（2026-09-22 批次列表治理）
    @State private var isSelectingBatches = false          // 多选模式开关
    @State private var selectedBatchIDs: Set<String> = []   // 多选已勾选
    @State private var pendingDeleteBatchIDs: Set<String> = [] // 待二次确认的删除目标
    @State private var showsBatchDeleteConfirm = false      // 删除二次确认弹窗
    @State private var blockedBatchDeletions: [CatalogBatchDeleteBlock] = [] // 被拦截条目（附原因）

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
            // 淘宝导入（§28）与批量导入（§4.1 多链接解析）已下线，仅保留既有批次列表
            if !draftStore.batches.isEmpty {
                batchListSection
            }
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
        .sheet(item: $manualBatch) { batch in
            ShopCatalogBatchDetailView(draftStore: draftStore, store: store, batch: batch)
        }
        .confirmationDialog(batchDeleteConfirmTitle,
                            isPresented: $showsBatchDeleteConfirm,
                            titleVisibility: .visible) {
            Button("删除批次（草稿与已发布数据保留）", role: .destructive) {
                performBatchDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(batchDeleteImpactText)
        }
        // 拦截反馈：被拦截的批次整体保留并逐条说明原因；处理后可对相同选择直接重试
        .alert("部分批次无法删除", isPresented: Binding(
            get: { !blockedBatchDeletions.isEmpty },
            set: { if !$0 { blockedBatchDeletions = [] } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(blockedBatchDeletionsText)
        }
    }

    /// 手动录入（V1.1 §4.1.2）：建一个批次会话 + 首条空草稿，
    /// 会话内可「＋添加单品」连续录入多件，整批归属 / 批量提交见批次列表
    private func startManualBatch() {
        let session = CatalogBatchEntrySession()
        var draft = CatalogProductDraft()
        draft.batchID = session.id
        _ = draftStore.createBatch(session, drafts: [draft])
        manualBatch = session
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
            // ＋ 补录上新（§27：手动录入会话；批次展示见下方批次列表）
            Menu {
                Button {
                    startManualBatch()
                } label: {
                    Label("手动录入（可连续添加多件）", systemImage: "square.and.pencil")
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

    @State private var selectedBatch: CatalogBatchEntrySession?

    // MARK: 批次列表（V1.1 §4.1；淘宝/批量导入入口已下线，仅保留既有批次的管理）
    //
    // 行内操作（2026-09-22 列表治理）：
    //   · 右侧「更多」菜单（ellipsis.circle，视觉克制）：删除批次…
    //   · Section 标题右侧「选择」进入多选，批量删除
    //   · 删除前 confirmationDialog 二次确认并说明影响范围
    //   · 批次下仍有未处理草稿（draft/submitted/reviewed）→ 拦截并说明原因，条目保留
    //   · 持久化失败 → actionError 反馈，条目保留，可用相同选择直接重试

    private var batchListSection: some View {
        Section {
            ForEach(draftStore.batches.reversed()) { batch in
                batchRow(batch)
            }
        } header: {
            batchSectionHeader
        } footer: {
            if isSelectingBatches {
                Text("已选 \(selectedBatchIDs.count) 个批次。删除只移除批次分组记录，单品草稿与已发布数据不受影响；仍有未处理草稿的批次会被拦截并说明原因。")
                    .font(.system(size: 11))
            }
        }
    }

    /// Section 标题右侧：多选入口 / 删除 / 取消（替代整页 toolbar，视觉集中在列表内）
    private var batchSectionHeader: some View {
        HStack(spacing: 12) {
            Text("批次")
            Spacer()
            if isSelectingBatches {
                Button {
                    beginBatchDelete(selectedBatchIDs)
                } label: {
                    Text("删除(\(selectedBatchIDs.count))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedBatchIDs.isEmpty ? Color.secondary : Color.red)
                }
                .disabled(selectedBatchIDs.isEmpty)
                Button("取消") { exitBatchSelection() }
                    .font(.system(size: 12))
            } else {
                Button("选择") { isSelectingBatches = true }
                    .font(.system(size: 12))
            }
        }
        .textCase(nil)
    }

    private func batchRow(_ batch: CatalogBatchEntrySession) -> some View {
        let batchDrafts = draftStore.drafts.filter { $0.batchID == batch.id }
        let draftable = batchDrafts.filter { $0.status == .draft }.count
        let assigned = batch.shopID != nil || !batch.newShopName.isEmpty
        let isSelected = selectedBatchIDs.contains(batch.id)
        return HStack(spacing: 10) {
            // 多选模式：行首勾选框（非多选时不占位，保持视觉克制）
            if isSelectingBatches {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.pink : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(batchTitle(batch))
                    .font(.system(size: 13, weight: .medium))
                Text("共 \(batchDrafts.count) 条 · 待提交 \(draftable) 条\(assigned ? "" : " · 未指定归属")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isSelectingBatches {
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
                // 「更多」下拉菜单：与实体管理商品行同一交互模式（ellipsis.circle）
                Menu {
                    Button(role: .destructive) {
                        beginBatchDelete([batch.id])
                    } label: {
                        Label("删除批次…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectingBatches {
                toggleBatchSelection(batch.id)
            } else {
                selectedBatch = batch
            }
        }
        .sheet(item: $selectedBatch) { batch in
            ShopCatalogBatchDetailView(draftStore: draftStore, store: store, batch: batch)
        }
    }

    // MARK: 批次删除（状态与回调）

    private func toggleBatchSelection(_ id: String) {
        if selectedBatchIDs.contains(id) {
            selectedBatchIDs.remove(id)
        } else {
            selectedBatchIDs.insert(id)
        }
    }

    private func exitBatchSelection() {
        isSelectingBatches = false
        selectedBatchIDs = []
    }

    /// 删除入口（单条菜单 / 多选按钮共用）：先确认，再执行
    private func beginBatchDelete(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        pendingDeleteBatchIDs = ids
        showsBatchDeleteConfirm = true
    }

    private var pendingDeleteTitles: [String] {
        pendingDeleteBatchIDs.compactMap { id in
            draftStore.batches.first(where: { $0.id == id }).map(batchTitle)
        }
    }

    private var batchDeleteConfirmTitle: String {
        let titles = pendingDeleteTitles
        if titles.count == 1, let only = titles.first { return "删除「\(only)」？" }
        return "删除 \(pendingDeleteBatchIDs.count) 个批次？"
    }

    /// 影响范围说明：删除只作用于批次归组记录；预告知将被拦截的批次
    private var batchDeleteImpactText: String {
        var lines: [String] = []
        let titles = pendingDeleteTitles
        if titles.count == 1, let only = titles.first {
            lines.append("将删除批次「\(only)」。")
        } else {
            lines.append("将删除 \(titles.count) 个批次。")
        }
        lines.append("影响范围：仅删除批次分组记录；草稿箱中的单品草稿与已发布到覆盖层的数据都不受影响。")
        let blockedCount = pendingDeleteBatchIDs.filter {
            ShopCatalogDraftStore.batchDeleteBlockReason(batchID: $0, drafts: draftStore.drafts) != nil
        }.count
        if blockedCount == 0 {
            lines.append("所选批次下均无未处理草稿，可以直接删除。")
        } else {
            lines.append("其中 \(blockedCount) 个批次仍有未处理草稿，将被拦截并说明原因。")
        }
        return lines.joined(separator: "\n")
    }

    private var blockedBatchDeletionsText: String {
        blockedBatchDeletions.map { block in
            let title = draftStore.batches.first(where: { $0.id == block.batchID })
                .map(batchTitle) ?? block.batchID
            return "「\(title)」\(block.reason)"
        }
        .joined(separator: "\n\n")
    }

    /// 确认后执行：删除成功的从选择中移除；被拦截的保留条目与选择，弹窗说明原因；
    /// 抛错（持久化失败）时什么都不变，走通用「操作失败」弹窗，可用相同选择重试
    private func performBatchDelete() {
        do {
            let result = try draftStore.deleteBatches(ids: pendingDeleteBatchIDs)
            pendingDeleteBatchIDs = []
            guard !result.deletedIDs.isEmpty else {
                blockedBatchDeletions = result.blocked
                return
            }
            toast = result.blocked.isEmpty
                ? "已删除 \(result.deletedIDs.count) 个批次"
                : "已删除 \(result.deletedIDs.count) 个批次，其余被拦截"
            selectedBatchIDs.subtract(result.deletedIDs)
            if !result.blocked.isEmpty {
                blockedBatchDeletions = result.blocked
            } else if selectedBatchIDs.isEmpty || draftStore.batches.isEmpty {
                exitBatchSelection()
            }
        } catch {
            pendingDeleteBatchIDs = []
            actionError = error.localizedDescription
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
                    Text(draft.priceSummary)
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

// MARK: - 草稿详情编辑（人工补录，§30 兜底：手动可完整全流程；批次详情页亦复用）

struct ShopCatalogDraftDetailEditor: View {
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

    /// 预约价输入绑定：0 显示为空（可空），输入即写回 price
    private var reservationPriceBinding: Binding<Double?> {
        Binding(
            get: { draftBox.effectiveReservationPrice },
            set: { draftBox.price = $0 ?? 0 }
        )
    }

    /// 款式名输入绑定（V1.4）：空串 = 清除显式款式，发布时按名称自动派生
    private var designNameBinding: Binding<String> {
        Binding(
            get: { draftBox.designName ?? "" },
            set: { draftBox.designName = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        )
    }

    /// 旧口径迁移：存量「现货草稿」（saleKind == .stock 且 price 承载现货价）
    /// 在新编辑器里打开时一次性搬到 stockPrice，price 让位给预约价 ——
    /// 之后预约 / 现货即可并存编辑，旧数据不丢。
    private func migrateLegacySaleKindIfNeeded() {
        guard draftBox.saleKind == .stock,
              draftBox.stockPrice == nil,
              draftBox.price > 0 else { return }
        draftBox.stockPrice = draftBox.price
        draftBox.price = 0
        draftBox.saleKind = .reservation
    }

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
                    // V1.4「同款不同色」：款式名可空 = 按商品名剥离颜色词自动派生；
                    // 同款不同色的补录填同一款式名，发布后列表自动归入同一款式
                    TextField("款式（可空，默认按名称自动识别）", text: designNameBinding)
                    Picker("分类", selection: $draftBox.category) {
                        ForEach(categories.filter { $0 != "其他" }, id: \.self) { Text($0).tag($0) }
                        Text("其他").tag("其他")
                    }
                }
                productInfoSection
                Section {
                    // 预约价与现货价并存且不互斥（2026-09-22）：
                    // 可同时填写、各自生成销售记录；现货价可空置，后续补录修改。
                    // 任一项填写都不会禁用 / 清空 / 覆盖另一项。
                    HStack {
                        Text("预约价")
                        Spacer()
                        TextField("可空", value: reservationPriceBinding, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                    if draftBox.effectiveReservationPrice != nil {
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
                    HStack {
                        Text("现货价")
                        Spacer()
                        TextField("可空", value: $draftBox.stockPrice, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                    }
                } header: {
                    Text("价格（预约与现货可并存）")
                } footer: {
                    Text("至少填写预约价或现货价之一；现货价可先空置，后续通过补录追加。")
                }
                Section("店家") {
                    Picker("关联店家", selection: $draftBox.shopID) {
                        Text("新建店家").tag(String?.none)
                        ForEach(store.shopsSortedByName()) { shop in
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
                        ForEach(store.seriesSortedByName()) { series in
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
                migrateLegacySaleKindIfNeeded()
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
            ShopCatalogImagePickerButton(mode: .append, text: $imagesText, label: "添加商品图片")
            Text("图片：每行一个 Bundle 文件名或 http(s) 链接（originalURL 必留原图）；也可点上方按钮从相册选图自动入库")
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
            ShopCatalogImagePickerButton(mode: .replace, text: $chartImageText, label: "添加尺码表原图")
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
        // 尺码表：列 + 行（label:值,…）+ 原图；共享解析口径（首列「尺码」= 标签列剔除、尾冒号清洗）
        let parsedChart = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(chartColumnsText),
            rows: CatalogManualChartText.parseRows(chartRowsText))
        let columns = parsedChart.columns
        let rows = parsedChart.rows
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
