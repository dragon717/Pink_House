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
import PhotosUI

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

    // 草稿箱删除 / 多选（2026-09-23）
    @State private var isSelectingDrafts = false             // 草稿箱多选模式开关
    @State private var selectedDraftIDs: Set<String> = []     // 多选已勾选
    @State private var pendingDeleteDraftIDs: Set<String> = [] // 待二次确认的删除目标
    @State private var showsDraftDeleteConfirm = false        // 删除二次确认弹窗

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
        // 草稿箱删除二次确认（单条 / 多选共用同一入口，同批次删除的口径）
        .confirmationDialog(draftDeleteConfirmTitle,
                            isPresented: $showsDraftDeleteConfirm,
                            titleVisibility: .visible) {
            Button("删除草稿", role: .destructive) {
                performDraftDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(draftDeleteImpactText)
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
        do {
            _ = try draftStore.createBatch(session, drafts: [draft])
            manualBatch = session
        } catch {
            // 保存失败可见、可重试（R01）：不静默成功，也不把用户带进一个没落盘的批次
            actionError = error.localizedDescription
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
    //
    // 删除（2026-09-23；与批次列表同一套交互，保持一致）：
    //   · 每条草稿行尾一个独立删除按钮（trash）
    //   · Section 标题右侧「选择」进入多选，批量删除
    //   · 删除前 confirmationDialog 二次确认，并说明影响范围（条数 + 状态构成）
    //   · 删除后 drafts 为 @Published → 列表实时刷新；结果走 toast 胶囊
    //   · 无硬拦截：草稿箱是运营自己的待处理记录，且批次删除的拦截文案本身就指引
    //     「在草稿箱中删除这些草稿」——这里再拦一道会让那条指引变成死路

    private var draftSection: some View {
        Section {
            ForEach(draftStore.drafts) { draft in
                ShopCatalogDraftEditorRow(
                    draft: draft,
                    draftStore: draftStore,
                    store: store,
                    toast: $toast,
                    actionError: $actionError,
                    isSelecting: isSelectingDrafts,
                    isSelected: selectedDraftIDs.contains(draft.id),
                    onToggleSelection: { toggleDraftSelection(draft.id) },
                    onRequestDelete: { beginDraftDelete([draft.id]) }
                )
            }
            if draftStore.drafts.isEmpty {
                Text("暂无草稿。点上方「＋ 补录上新」开始。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } header: {
            draftSectionHeader
        } footer: {
            if isSelectingDrafts {
                Text("已选 \(selectedDraftIDs.count) 条草稿。删除只移除草稿箱中的记录；已发布到覆盖层的商品数据与销售记录不受影响。")
                    .font(.system(size: 11))
            } else {
                Text("发布 = 草稿 → 提交 → 审核通过后写入覆盖层并对用户可见（§31）；同名商品的现货记录会追加到既有商品（§29 去重 / 现货价格补录）。")
            }
        }
    }

    /// Section 标题右侧：多选入口 / 删除 / 取消（与批次列表同款，视觉集中在列表内）
    private var draftSectionHeader: some View {
        HStack(spacing: 12) {
            Text("草稿箱")
            Spacer()
            if isSelectingDrafts {
                Button {
                    beginDraftDelete(selectedDraftIDs)
                } label: {
                    Text("删除(\(selectedDraftIDs.count))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedDraftIDs.isEmpty ? Color.secondary : Color.red)
                }
                .disabled(selectedDraftIDs.isEmpty)
                Button("取消") { exitDraftSelection() }
                    .font(.system(size: 12))
            } else if !draftStore.drafts.isEmpty {
                Button("选择") { isSelectingDrafts = true }
                    .font(.system(size: 12))
            }
        }
        .textCase(nil)
    }

    // MARK: 草稿删除（状态与回调）

    private func toggleDraftSelection(_ id: String) {
        if selectedDraftIDs.contains(id) {
            selectedDraftIDs.remove(id)
        } else {
            selectedDraftIDs.insert(id)
        }
    }

    private func exitDraftSelection() {
        isSelectingDrafts = false
        selectedDraftIDs = []
    }

    /// 删除入口（单条行内按钮 / 多选按钮共用）：先确认，再执行
    private func beginDraftDelete(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        pendingDeleteDraftIDs = ids
        showsDraftDeleteConfirm = true
    }

    private var pendingDeleteDraftNames: [String] {
        let ids = pendingDeleteDraftIDs
        return draftStore.drafts.filter { ids.contains($0.id) }.map {
            $0.name.isEmpty ? "（未命名草稿）" : $0.name
        }
    }

    private var draftDeleteConfirmTitle: String {
        let names = pendingDeleteDraftNames
        if names.count == 1, let only = names.first { return "删除「\(only)」？" }
        return "删除 \(names.count) 条草稿？"
    }

    /// 影响范围说明：与执行共用同一份判定（`previewDraftDeletion`），
    /// 所以这里说的条数、状态构成就是实际会删掉的
    private var draftDeleteImpactText: String {
        let plan = draftStore.previewDraftDeletion(ids: pendingDeleteDraftIDs)
        var lines: [String] = []
        let names = pendingDeleteDraftNames
        if names.count == 1, let only = names.first {
            lines.append("将删除草稿「\(only)」。")
        } else {
            lines.append("将删除 \(plan.targetCount) 条草稿。")
        }
        // 按状态逐项列出（固定 allCases 顺序，避免字典乱序）
        let breakdown = CatalogPublicationStatus.allCases.compactMap { status -> String? in
            guard let count = plan.countsByStatus[status], count > 0 else { return nil }
            return "\(status.displayName) \(count) 条"
        }
        if !breakdown.isEmpty {
            lines.append("构成：" + breakdown.joined(separator: "、") + "。")
        }
        lines.append("影响范围：仅移除草稿箱中的记录；已发布到覆盖层的商品资料与销售记录不受影响，批次分组记录也不受影响。")
        if plan.settledCount > 0 {
            lines.append("其中 \(plan.settledCount) 条已发布 / 已归档 —— 删除只去掉这份发布回执，线上数据不变。")
        }
        if plan.inFlightCount > 0 {
            lines.append("其中 \(plan.inFlightCount) 条仍在流转中，删除后将退出审核 / 发布流程。")
        }
        return lines.joined(separator: "\n")
    }

    /// 确认后执行：删除成功 → toast 结果提示 + 列表实时刷新（`drafts` 为 @Published）；
    /// 持久化失败 → 什么都没变，走通用「操作失败」弹窗，可原样重试
    private func performDraftDelete() {
        let ids = pendingDeleteDraftIDs
        pendingDeleteDraftIDs = []
        do {
            let plan = try draftStore.deleteDrafts(ids: ids)
            guard plan.targetCount > 0 else {
                // 选中项已经不在草稿箱（例如刚被别处删掉）：不谎报成功
                toast = "所选草稿已不在草稿箱，无需删除"
                selectedDraftIDs.subtract(ids)
                if selectedDraftIDs.isEmpty { exitDraftSelection() }
                return
            }
            toast = "已删除 \(plan.targetCount) 条草稿"
            selectedDraftIDs.subtract(Set(plan.targetIDs))
            if selectedDraftIDs.isEmpty || draftStore.drafts.isEmpty {
                exitDraftSelection()
            }
        } catch {
            actionError = error.localizedDescription
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

    /// 多选模式（草稿箱批量删除）：行首显示勾选框，整行点击 = 切换勾选，
    /// 同时隐藏行内流转 / 删除按钮，避免勾选时误触「提交 / 发布」
    var isSelecting: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)? = nil
    /// 单条删除回调（仅非多选模式）。nil = 不显示删除按钮
    var onRequestDelete: (() -> Void)? = nil

    @State private var showsEditor = false
    @State private var showsRejectPrompt = false
    @State private var rejectReasonText = ""

    var body: some View {
        HStack(spacing: 10) {
            // 多选模式：行首勾选框（非多选时不占位，保持视觉克制）
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.pink : Color.secondary)
            }
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
            if !isSelecting {
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
                // 单条删除按钮（需求：每条草稿一个独立删除按钮）。
                // 多选模式下不显示，统一走 Section 头部的「删除(N)」
                if let onRequestDelete {
                    Button(role: .destructive) {
                        onRequestDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel(Text("删除草稿"))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                onToggleSelection?()
            } else {
                showsEditor = true
            }
        }
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
            // Binding 的 set 无法抛错：失败落到 draftStore.lastPersistenceError，
            // 由下方横幅显式提示（R01：保存失败可见、可重试，不静默成功）
            set: { draftStore.upsertReportingError($0) }
        )
        self.draftStore = draftStore
        self.store = store
    }

    private let categories = ShopCatalogStore.canonicalCategoryOrder

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

    // MARK: 款式（SPU）层状态 —— 全色共用，只填一次

    @State private var designNameText = ""
    @State private var categoryText = "其他"
    @State private var fabricText = ""
    @State private var styleDescriptionText = ""
    @State private var chartColumnsText = ""
    @State private var chartRowsText = ""
    @State private var chartUnit = ""
    @State private var chartImageText = ""

    // 价格组（同款同价：按款式录一次，整组落到每条颜色草稿）
    @State private var reservationPrice: Double?
    @State private var stockPrice: Double?
    @State private var deposit: Double?
    @State private var balance: Double?
    @State private var currency: CatalogCurrency?

    // MARK: 颜色（SKU）层状态 —— 每色一行，图片与颜色行强绑定

    @State private var colors: [ShopCatalogDraftStyleForm.ColorRow] = []

    @State private var loaded = false
    @State private var toast: String?
    @State private var errorText: String?

    /// 款式名（唯一决议点）：显式填写优先，否则按源草稿商品名派生。
    /// 名字预览与保存落库都读它，避免「看到的」与「存下的」分叉。
    private var resolvedStyleName: String {
        ShopCatalogDraftStyleForm.resolveStyleName(explicit: designNameText, source: draftBox)
    }

    /// 款式尺码表（列 + 行 + 单位 + 原图；共享解析口径：首列「尺码」剔除、尾冒号清洗）
    private var composedChart: CatalogSizeChart? {
        let parsed = CatalogManualChartText.normalized(
            columns: CatalogManualChartText.parseColumns(chartColumnsText),
            rows: CatalogManualChartText.parseRows(chartRowsText))
        let image = chartImageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parsed.columns.isEmpty || !parsed.rows.isEmpty || !image.isEmpty else { return nil }
        var chart = CatalogSizeChart(id: "sizechart-draft-\(draftBox.id.prefix(6))", productID: "")
        chart.unit = chartUnit.trimmingCharacters(in: .whitespaces).isEmpty ? nil : chartUnit
        chart.columns = parsed.columns
        chart.rows = parsed.rows
        chart.sourceImage = image.isEmpty ? nil : image
        return chart
    }

    /// 尺码勾选候选 = 款式尺码表的尺码轴（每个颜色不再重复填表）
    private var availableSizes: [String] {
        ShopCatalogSizeChartSharing.sizeLabels(of: composedChart)
    }

    var body: some View {
        NavigationStack {
            Form {
                // R01：保存失败必须可见。写入失败时内存与磁盘都没变，
                // 用户原地再改一次即可重试，不能让用户以为已经存好了。
                if let failure = draftStore.lastPersistenceError {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("草稿未保存").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.red)
                            Text(failure).font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                // R01：草稿文件损坏时明确告知原文件已保留 + 备份位置，并给出恢复入口
                if draftStore.isBlockedByCorruptFile {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("草稿文件无法解析，已暂停写入").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                            Text(draftStore.lastLoadIssue ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button("我已处理，重新加载") {
                                draftStore.clearCorruptFileBlockAndReload()
                            }
                            .font(.system(size: 13))
                        }
                    }
                }
                Section {
                    TextField("款式名（同款共用，如：一字领 OP）", text: $designNameText)
                    Picker("分类", selection: $categoryText) {
                        ForEach(categories.filter { $0 != "其他" }, id: \.self) { Text($0).tag($0) }
                        Text("其他").tag("其他")
                    }
                } header: {
                    Text("商品（款式）")
                } footer: {
                    Text("商品名 = **颜色名 + 款式名**，由下方每个颜色行自动组合。款式名留空时按颜色行的商品名自动识别；多颜色录入必须填写。")
                }
                stylePublicInfoSection
                priceSection
                colorSection
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
                    Button("完成") { saveStyleForm() }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                store.loadFromBundleIfNeeded()
                migrateLegacySaleKindIfNeeded()
                loadStyleForm()
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
                            try? await Task.sleep(nanoseconds: 2_400_000_000)
                            await MainActor.run { self.toast = nil }
                        }
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: 款式层（SPU）：面料 / 款式描述 / 尺码表
    //
    //  2026-09-23 录入端分层：尺码表、面料、款式描述是**款式公共属性**（同款只填一次，
    //  发布时落到款式档案）；商品图片、配色尺码是**颜色差异属性**，在每个颜色行里独立填。
    //  分区展示不只是好看 —— 它把「哪些是整款一份、哪些是每色各自」摆在明面上，
    //  从结构上就不会再出现「把配色图当款式图复制到其他颜色」。

    /// 款式公共资料：面料 / 款式描述 / 尺码表 —— 同款共用一份，只填一次
    private var stylePublicInfoSection: some View {
        Section {
            TextField("面料成分（如：100% 聚酯纤维）", text: $fabricText)
                .font(.system(size: 13))
            TextEditor(text: $styleDescriptionText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
                .overlay(alignment: .topLeading) {
                    if styleDescriptionText.isEmpty {
                        Text("款式描述（同款所有颜色共用）")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            // 2026-09-23 需求 M：整段文本粘贴录入
            ShopCatalogChartPasteButton(kind: .sizeChart,
                                        columnsText: $chartColumnsText,
                                        rowsText: $chartRowsText)
            TextField("尺码表列名（逗号分隔，如：尺码,前裙长,胸围）", text: $chartColumnsText)
                .font(.system(size: 13))
            TextEditor(text: $chartRowsText)
                .frame(minHeight: 60)
                .font(.system(size: 13))
                .overlay(alignment: .topLeading) {
                    if chartRowsText.isEmpty {
                        Text("每行「标签:值,值,…」，如 S:80,78-83,60-66")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
            TextField("单位（cm）", text: $chartUnit)
            TextField("尺码表原图（文件名/URL）", text: $chartImageText)
            ShopCatalogImagePickerButton(mode: .replace, text: $chartImageText, label: "添加尺码表原图")
        } header: {
            Text("款式公共资料（同款共用，只需填一次）")
        } footer: {
            if availableSizes.isEmpty {
                Text("面料、款式描述、尺码表属于款式（SPU），本款全部颜色共用同一份。填了尺码表，下面每个颜色就能直接勾选尺码。")
                    .font(.system(size: 11))
            } else {
                Text("识别出的尺码：\(availableSizes.joined(separator: " / "))（下面每个颜色直接勾选，不再重复填表）")
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: 价格组（同款同价，按款式录一次）

    private var priceSection: some View {
        Section {
            // 预约价与现货价并存且不互斥（2026-09-22）：可同时填写、各自生成销售记录；
            // 现货价可空置后补录。任一项填写都不会禁用 / 清空 / 覆盖另一项。
            HStack {
                Text("预约价")
                Spacer()
                TextField("可空", value: $reservationPrice, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
            }
            if reservationPrice != nil {
                HStack {
                    Text("定金")
                    Spacer()
                    TextField("可空", value: $deposit, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
                HStack {
                    Text("尾款")
                    Spacer()
                    TextField("可空", value: $balance, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 110)
                }
                if let issue = depositBalanceIssue {
                    Text(issue)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            HStack {
                Text("现货价")
                Spacer()
                TextField("可空", value: $stockPrice, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
            }
            Picker("币种", selection: $currency) {
                Text("未标注").tag(CatalogCurrency?.none)
                ForEach(CatalogCurrency.allCases) { item in
                    Text(item.displayName).tag(CatalogCurrency?.some(item))
                }
            }
        } header: {
            Text("价格（同款同价，按款式录一次）")
        } footer: {
            Text("至少填写预约价或现货价之一；现货价可先空置，后续通过补录追加。价格整组写入本款每条颜色草稿。")
        }
    }

    private var depositBalanceIssue: String? {
        guard let r = reservationPrice, let d = deposit, let b = balance else { return nil }
        return Decimal(d) + Decimal(b) == Decimal(r)
            ? nil : "定金 \(Int(d)) + 尾款 \(Int(b)) ≠ 预约价 \(Int(r))"
    }

    // MARK: 颜色（SKU）—— 图片与颜色行强绑定

    /// 颜色 SKU 添加区。
    ///
    /// 需求原文的落点：「将图片上传组件与颜色字段直接绑定，让用户点颜色的同时就能直接传图」——
    /// 缩略图、选图按钮、删除按钮**都在同一个颜色行内**，
    /// 不再有「先在页面另一处传图、再回来自己对应文件名」这一步。
    private var colorSection: some View {
        Section {
            ForEach($colors) { row in
                colorRow(row)
            }
            Button {
                colors.append(ShopCatalogDraftStyleForm.ColorRow())
            } label: {
                Label("添加颜色", systemImage: "plus.circle")
                    .font(.system(size: 13))
            }
        } header: {
            Text("颜色（\(colors.count) 色，每色传图 + 勾尺码）")
        } footer: {
            Text("商品名 = 颜色名 + 款式名（每行都有预览）。配色图只属于该颜色：前端详情页切到这一色时读的就是它。"
                + "移除一个未上线的颜色会同时删掉它的草稿；已发布 / 已归档的颜色在这里只读。")
        }
    }

    @ViewBuilder
    private func colorRow(_ row: Binding<ShopCatalogDraftStyleForm.ColorRow>) -> some View {
        let settled = row.wrappedValue.isSettled
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if settled {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                }
                TextField("颜色名（如：生成色）", text: row.colorName)
                    .font(.system(size: 14))
                    .disabled(settled)
                if !settled && colors.count > 1 {
                    Button(role: .destructive) {
                        let id = row.wrappedValue.id
                        colors.removeAll { $0.id == id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .accessibilityLabel(Text("移除该颜色"))
                }
            }

            // 图片区：与颜色字段同处一个行视图内 —— 这就是「图片与 SKU 强关联」
            ShopCatalogColorImageRow(refs: row.imageRefs, isDisabled: settled)

            sizeChips(for: row)

            Text("将发布为：\(ShopCatalogDraftStyleForm.namePreview(colorName: row.wrappedValue.colorName, styleName: resolvedStyleName))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// 尺码勾选（候选 = 款式尺码表，每色不再重复填表）
    @ViewBuilder
    private func sizeChips(for row: Binding<ShopCatalogDraftStyleForm.ColorRow>) -> some View {
        if row.wrappedValue.isSettled {
            EmptyView()
        } else if availableSizes.isEmpty {
            Text("款式尺码表还没有尺码 —— 先填上方「款式公共资料」的尺码表，这里就能勾选")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("尺码")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 8) {
                    ForEach(availableSizes, id: \.self) { size in
                        let isOn = row.wrappedValue.sizes.contains(size)
                        Button {
                            if isOn {
                                row.wrappedValue.sizes.removeAll { $0 == size }
                            } else {
                                row.wrappedValue.sizes.append(size)
                            }
                        } label: {
                            Text(size)
                                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? Color.white : Color.pink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(isOn ? Color.pink : Color.pink.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: 加载 / 保存

    /// 读入表单：款式层取源草稿，颜色行取**本款全部草稿**（源草稿排第一位）。
    /// 家族口径与仓库落盘同源（`sameStyleFamily`）—— 两处不一致会导致误删。
    private func loadStyleForm() {
        let source = draftBox
        designNameText = source.designName ?? ""
        categoryText = source.category
        fabricText = source.fabric ?? ""
        styleDescriptionText = source.styleDescription ?? ""
        if let chart = source.sizeChart {
            chartColumnsText = chart.columns.joined(separator: ",")
            chartRowsText = chart.rows
                .map { "\($0.label):" + $0.values.map { $0 ?? "" }.joined(separator: ",") }
                .joined(separator: "\n")
            chartUnit = chart.unit ?? ""
            chartImageText = chart.sourceImage ?? ""
        }
        reservationPrice = source.effectiveReservationPrice
        stockPrice = source.effectiveStockPrice
        deposit = source.deposit
        balance = source.balance
        currency = source.currency
        let family = ShopCatalogDraftStyleForm.sameStyleFamily(of: source, in: draftStore.drafts)
        colors = ShopCatalogDraftStyleForm.rows(of: family, sourceID: source.id)
        if colors.isEmpty {
            // 兜底：源草稿已不在草稿箱（例如刚被别处删掉）时，至少保留它自己这一行
            colors = ShopCatalogDraftStyleForm.rows(of: [source], sourceID: source.id)
        }
    }

    /// 「完成」= 整款一次落盘（款式公共资料 + 全部颜色 SKU）
    private func saveStyleForm() {
        do {
            let result = try draftStore.applyStyleForm(sourceDraftID: draftBox.id,
                                                       style: styleInput(),
                                                       colors: colors)
            toast = summary(for: result)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func styleInput() -> ShopCatalogDraftStyleForm.StyleInput {
        var style = ShopCatalogDraftStyleForm.StyleInput()
        style.designName = designNameText
        style.category = categoryText
        style.fabric = fabricText
        style.styleDescription = styleDescriptionText
        style.sizeChart = composedChart
        style.reservationPrice = reservationPrice
        style.stockPrice = stockPrice
        style.deposit = deposit
        style.balance = balance
        // 档期本表单不编辑，原样透传 —— 避免保存一次就把已有档期抹掉
        style.startAt = draftBox.startAt
        style.endAt = draftBox.endAt
        style.currency = currency
        style.shopID = draftBox.shopID
        style.newShopName = draftBox.newShopName
        style.newShopAliases = draftBox.newShopAliases
        style.seriesID = draftBox.seriesID
        style.newSeriesName = draftBox.newSeriesName
        style.newSeriesYear = draftBox.newSeriesYear
        style.newSeriesSeason = draftBox.newSeriesSeason
        style.batchID = draftBox.batchID
        return style
    }

    private func summary(for result: ShopCatalogStyleFormResult) -> String {
        var parts: [String] = []
        if result.createdCount > 0 { parts.append("新增 \(result.createdCount) 色") }
        if result.updatedCount > 0 { parts.append("更新 \(result.updatedCount) 色") }
        if result.removedCount > 0 { parts.append("移除 \(result.removedCount) 色") }
        if result.skippedSettledCount > 0 { parts.append("跳过已上线 \(result.skippedSettledCount) 色") }
        return parts.isEmpty ? "款式资料已保存" : "已保存：" + parts.joined(separator: "、")
    }
}

// MARK: - 行内配色图选择器（图片与颜色 SKU 强绑定）

/// 颜色行内的图片组件：缩略图 + 相册选图 + 单张删除。
///
/// 需求原文：「请在颜色 SKU 添加区，将图片上传组件与颜色字段直接绑定。让用户点颜色的
/// 同时就能直接传图，实现图片与 SKU 的强关联。不要单独弄一个图片上传区让用户去对应。」
///
/// 所以它绑定的是**该颜色行自己的引用数组**（不是一整块多行文本），
/// 传完的图直接就是这一色的配色图 —— 不需要用户再去别处把文件名抄一遍。
/// 引用格式走 `ShopCatalogImageStore` 的 `local:<文件名>`，展示统一走
/// `ShopCatalogAssetImage`（读不到文件走占位图，不渲染空白）。
private struct ShopCatalogColorImageRow: View {
    @Binding var refs: [String]
    /// 已发布 / 已归档的颜色：只读展示，不给改图入口
    var isDisabled: Bool = false

    @State private var selection: PhotosPickerItem?
    @State private var errorText: String?

    private let thumbnailSide: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(refs.enumerated()), id: \.offset) { index, ref in
                        thumbnail(ref: ref, index: index)
                    }
                    if !isDisabled {
                        addButton
                    }
                }
                .padding(.vertical, 4)
                .padding(.trailing, 6)
            }
            if refs.isEmpty && isDisabled {
                Text("该颜色已上线，配色图请到商品编辑里修改")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            selection = nil
            Task { await handle(item) }
        }
    }

    private func thumbnail(ref: String, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            ShopCatalogAssetImage(reference: ref)
                .frame(width: thumbnailSide, height: thumbnailSide)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            if index == 0 {
                Text("主图")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .padding(3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            if !isDisabled {
                Button {
                    guard refs.indices.contains(index) else { return }
                    refs.remove(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .accessibilityLabel(Text("移除这张图片"))
            }
        }
    }

    private var addButton: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            VStack(spacing: 3) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 18))
                Text(refs.isEmpty ? "传配色图" : "加图")
                    .font(.system(size: 10))
            }
            .frame(width: thumbnailSide, height: thumbnailSide)
            .foregroundStyle(.pink)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.pink.opacity(0.45),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
    }

    private func handle(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let reference = ShopCatalogImageStore.save(data) else {
            await MainActor.run { errorText = "图片保存失败，请重试" }
            return
        }
        await MainActor.run {
            errorText = nil
            refs.append(reference)
        }
    }
}
