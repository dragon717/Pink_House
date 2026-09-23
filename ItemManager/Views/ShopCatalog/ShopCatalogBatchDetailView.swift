import SwiftUI

// MARK: - 批次详情（V1.1 §4.1 整批归属整合）
//
//  一个批次 = 一条系列链路：运营在此一次性指定「店家 + 系列」，整批多单品
//  草稿统一归入该系列——发布后用户端从系列页（单一入口）查看并选择该系列
//  全部单品，各单品资料（图片/配色尺码/尺码表/销售事件）保持独立完整，
//  不再出现「一条链接 = 一个单品」的分散录入结构。
//  单品仍可进草稿编辑器单独覆盖归属（批次只是缺省归组）。

struct ShopCatalogBatchDetailView: View {
    @ObservedObject var draftStore: ShopCatalogDraftStore
    @ObservedObject var store: ShopCatalogStore
    let batch: CatalogBatchEntrySession
    var onApplied: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var shopID = ""          // "" = 新建店家
    @State private var newShopName = ""
    @State private var newShopAliases = ""
    @State private var seriesID = ""        // "" = 新建系列
    @State private var newSeriesName = ""
    @State private var newSeriesYearText = ""
    @State private var newSeriesSeason = ""
    @State private var loaded = false
    @State private var toast: String?
    @State private var errorText: String?
    /// 同一处 alert 兼作「无法应用」与「同步失败」，标题随之切换
    @State private var alertTitle = "无法应用"

    private var batchDrafts: [CatalogProductDraft] {
        draftStore.drafts.filter { $0.batchID == batch.id && $0.status != .published && $0.status != .archived }
    }

    var body: some View {
        NavigationStack {
            Form {
                attributionSection
                draftsSection
            }
            .navigationTitle("批次详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                shopID = batch.shopID ?? ""
                newShopName = batch.newShopName
                newShopAliases = batch.newShopAliases
                seriesID = batch.seriesID ?? ""
                newSeriesName = batch.newSeriesName
                newSeriesYearText = batch.newSeriesYear.map(String.init) ?? ""
                newSeriesSeason = batch.newSeriesSeason
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
            .alert(alertTitle, isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: 整批归属（店家 + 系列）

    private var attributionSection: some View {
        Section {
            Picker("店家", selection: $shopID) {
                Text("＋ 新建店家").tag("")
                ForEach(store.shopsSortedByActivity()) { shop in
                    Text(shop.name).tag(shop.id)
                }
            }
            if shopID.isEmpty {
                TextField("新店家名称（必填）", text: $newShopName)
                TextField("别名（逗号分隔，选填）", text: $newShopAliases)
            }

            if shopID.isEmpty {
                TextField("系列名称（必填，整批同系列）", text: $newSeriesName)
            } else {
                Picker("系列", selection: $seriesID) {
                    Text("＋ 新建系列").tag("")
                    ForEach(store.series(inShop: shopID)) { series in
                        Text(series.yearMonthText.map { "\($0) · \(series.name)" } ?? series.name)
                            .tag(series.id)
                    }
                }
                if seriesID.isEmpty {
                    TextField("新系列名称（必填，整批同系列）", text: $newSeriesName)
                }
            }
            if seriesID.isEmpty {
                TextField("年份（选填，如 2026）", text: $newSeriesYearText)
                    .keyboardType(.numberPad)
                TextField("季节（选填，如 冬）", text: $newSeriesSeason)
            }

            Button {
                applyAttribution()
            } label: {
                Label("应用到整批 \(batchDrafts.count) 条单品", systemImage: "rectangle.stack.badge.person.crop")
            }
            .disabled(batchDrafts.isEmpty)
        } header: {
            Text("整批归属（一次指定，全部单品同店同系列）")
        } footer: {
            Text("同一系列的多条链接整合到同一条系列链路：发布后用户从系列页即可查看并选择全部单品，单品资料各自保持完整。")
        }
    }

    private func applyAttribution() {
        alertTitle = "无法应用"
        let trimmedShopName = newShopName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSeriesName = newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        if shopID.isEmpty && trimmedShopName.isEmpty {
            errorText = "请选择既有店家，或填写新店家名称"
            return
        }
        if seriesID.isEmpty && trimmedSeriesName.isEmpty {
            errorText = "请选择既有系列，或填写新系列名称"
            return
        }
        let year = Int(newSeriesYearText.trimmingCharacters(in: .whitespaces))
        if newSeriesYearText.trimmingCharacters(in: .whitespaces).isEmpty == false && year == nil {
            errorText = "年份需为数字（如 2026）"
            return
        }
        let count: Int
        do {
            count = try draftStore.applyBatchAttribution(
                batchID: batch.id,
                shopID: shopID.isEmpty ? nil : shopID,
                newShopName: trimmedShopName,
                newShopAliases: newShopAliases,
                seriesID: seriesID.isEmpty ? nil : seriesID,
                newSeriesName: trimmedSeriesName,
                newSeriesYear: year,
                newSeriesSeason: newSeriesSeason.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            // R01：写盘失败可见，列表与磁盘均未变化，可原样重试
            errorText = error.localizedDescription
            return
        }
        toast = "已将 \(count) 条单品归入「\(attributionSummary)」"
        onApplied?(count)
    }

    private var attributionSummary: String {
        let shop = shopID.isEmpty ? newShopName : (store.shop(id: shopID)?.name ?? "？")
        let series = seriesID.isEmpty ? newSeriesName : (store.series(id: seriesID)?.name ?? "？")
        return "\(shop) · \(series)"
    }

    // MARK: 本批单品（系列 → 款式组 → 颜色 三级）

    private var draftsSection: some View {
        Section {
            ForEach(seriesGroups) { seriesGroup in
                seriesHeader(seriesGroup)
                ForEach(seriesGroup.styleGroups) { styleGroup in
                    ForEach(styleGroup.drafts) { draft in
                        NavigationLink {
                            ShopCatalogDraftDetailEditor(draft: draft, draftStore: draftStore, store: store)
                        } label: {
                            draftSummaryRow(draft)
                        }
                    }
                    if styleGroup.isMultiColor {
                        styleSyncRow(styleGroup)
                    }
                }
            }
            if batchDrafts.isEmpty {
                Text("本批单品已全部提交/发布/归档")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                addManualItem()
            } label: {
                Label("＋ 添加款式（一个表单录入整款，含多颜色）", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("本批单品（\(batchDrafts.count) 条，按系列分组）")
        } footer: {
            Text("一个款式只建一条：点进去就是「款式 + 多颜色」表单，款式公共资料填一次、每个颜色在行内直接传图和勾尺码，"
                + "不需要为每个颜色单独「新建单品」。若确实是分开录入的，可用款式组里的「同步款式资料」把价格、尺码表、面料、描述一次带给其余颜色。")
        }
    }

    /// 一个系列下的若干款式组（三级结构：系列 → 款式 → 颜色）
    private struct SeriesGroup: Identifiable {
        let key: String
        let styleGroups: [ShopCatalogDraftStyleSync.StyleGroup]
        var id: String { key }
        var draftCount: Int { styleGroups.reduce(0) { $0 + $1.colorCount } }
    }

    private var seriesGroups: [SeriesGroup] {
        groupedKeys.map { key in
            let members = groupedDrafts[key] ?? []
            return SeriesGroup(
                key: key,
                styleGroups: ShopCatalogDraftStyleSync.groups(
                    members,
                    // 已按系列分组，组内以系列键作继承标签：
                    // 让「未自报系列（继承整批）」与「自报同名系列」的草稿落在同一个款式组，
                    // 否则同一款式的颜色会被拆成两组、同步按钮点不到对方。
                    inheritedSeriesLabel: key,
                    resolveSeriesName: { store.series(id: $0)?.name }))
        }
    }

    /// 款式组内「同步款式资料」：以组内**第一条**为模板（= 用户先录入的那条颜色），
    /// 把款式公共资料整块覆盖到其余颜色。模板写进文案，避免「到底复制了谁的资料」含糊。
    private func styleSyncRow(_ group: ShopCatalogDraftStyleSync.StyleGroup) -> some View {
        let template = group.drafts.first
        let targetCount = max(group.colorCount - 1, 0)
        return Button {
            syncStyle(group)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("以「\(template?.name ?? group.designName)」同步到其余 \(targetCount) 个颜色",
                      systemImage: "doc.on.doc")
                    .font(.system(size: 13))
                Text("价格、尺码表、面料、款式描述（不含配色图与配色尺码）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(template == nil || targetCount == 0)
    }

    private func syncStyle(_ group: ShopCatalogDraftStyleSync.StyleGroup) {
        alertTitle = "同步失败"
        guard let template = group.drafts.first else { return }
        let targets = group.drafts.dropFirst().map(\.id)
        guard !targets.isEmpty else { return }
        do {
            let count = try draftStore.syncStyleInfo(
                sourceDraftID: template.id,
                targetDraftIDs: targets,
                fields: ShopCatalogDraftStyleSync.defaultFields)
            toast = count > 0
                ? "已以「\(template.name)」为模板同步 \(count) 个颜色"
                : "「\(group.designName)」其余颜色均已发布或不可写，未做修改"
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// 系列分组标题（第一级）
    private func seriesHeader(_ group: SeriesGroup) -> some View {
        HStack {
            Text("系列：\(group.key)")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(group.draftCount) 个单品")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    /// 手动会话加款式：新建空草稿挂入本批次，点进去就是「款式 + 多颜色」表单
    /// （整批归属 / 批量提交与其余款式同流程，V1.1 §4.1.2）
    private func addManualItem() {
        var draft = CatalogProductDraft()
        draft.batchID = batch.id
        do {
            try draftStore.upsert(draft)
        } catch {
            errorText = error.localizedDescription
            return
        }
        toast = "已添加款式（本批第 \(batchDrafts.count) 条），点入录入款式资料与各颜色"
    }

    /// 分组键：系列 id → 系列名；新建系列 → 名称；未指定 → 归入「未指定系列」
    private var groupedKeys: [String] {
        var order: [String] = []
        for draft in batchDrafts {
            let key = groupKey(for: draft)
            if !order.contains(key) { order.append(key) }
        }
        return order
    }

    private var groupedDrafts: [String: [CatalogProductDraft]] {
        Dictionary(grouping: batchDrafts, by: groupKey(for:))
    }

    /// 分组键（2026-09-22 默认继承整批系列）：
    ///   · 草稿自报系列（seriesID / newSeriesName）→ 用自己的，永不被整批覆盖；
    ///   · 未自报 → 继承整批归属当前选定的系列（上方选择一变，分组即时联动）；
    ///   · 整批也未选定 → 维持「未指定系列」（原有默认行为）。
    /// 纯逻辑在 `CatalogBatchGrouping.groupKey`，此处只负责名称解析。
    private func groupKey(for draft: CatalogProductDraft) -> String {
        let own: String?
        if let sid = draft.seriesID {
            own = store.series(id: sid)?.name ?? sid   // 系列查不到时用原始 id 兜底
        } else {
            let name = draft.newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
            own = name.isEmpty ? nil : name
        }
        return CatalogBatchGrouping.groupKey(draftOwnSeriesName: own,
                                             batchSeriesName: inheritedSeriesKey)
    }

    /// 整批归属当前选定系列的展示名（上方「系列」Picker 选中项，或正在填写的新系列名）；
    /// 上方未选定系列时为 nil → 分组回落「未指定系列」。
    /// 直接读 @State（seriesID / newSeriesName），所以上方一变，下方分组同步联动。
    private var inheritedSeriesKey: String? {
        // 本视图的 seriesID 是非可选 String（"" = 新建系列）
        if !seriesID.isEmpty {
            return store.series(id: seriesID)?.name ?? seriesID
        }
        let name = newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func draftSummaryRow(_ draft: CatalogProductDraft) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(draft.name.isEmpty ? "（未命名单品）" : draft.name)
                .font(.system(size: 13))
            Text("\(draft.category) · \(draft.priceSummary) · \(draft.status.displayName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
