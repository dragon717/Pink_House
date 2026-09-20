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
            .alert("无法应用", isPresented: Binding(
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
                        Text(series.year.map { "\($0) · \(series.name)" } ?? series.name)
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
        let count = draftStore.applyBatchAttribution(
            batchID: batch.id,
            shopID: shopID.isEmpty ? nil : shopID,
            newShopName: trimmedShopName,
            newShopAliases: newShopAliases,
            seriesID: seriesID.isEmpty ? nil : seriesID,
            newSeriesName: trimmedSeriesName,
            newSeriesYear: year,
            newSeriesSeason: newSeriesSeason.trimmingCharacters(in: .whitespacesAndNewlines))
        toast = "已将 \(count) 条单品归入「\(attributionSummary)」"
        onApplied?(count)
    }

    private var attributionSummary: String {
        let shop = shopID.isEmpty ? newShopName : (store.shop(id: shopID)?.name ?? "？")
        let series = seriesID.isEmpty ? newSeriesName : (store.series(id: seriesID)?.name ?? "？")
        return "\(shop) · \(series)"
    }

    // MARK: 本批单品（按系列分组展示）

    private var draftsSection: some View {
        Section {
            ForEach(groupedKeys, id: \.self) { key in
                let items = groupedDrafts[key] ?? []
                ForEach(Array(items.enumerated()), id: \.element.id) { index, draft in
                    if index == 0 {
                        groupHeader(key: key, count: items.count)
                    }
                    draftSummaryRow(draft)
                }
            }
            if batchDrafts.isEmpty {
                Text("本批单品已全部提交/发布/归档")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("本批单品（\(batchDrafts.count) 条，按系列分组）")
        }
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

    private func groupKey(for draft: CatalogProductDraft) -> String {
        if let sid = draft.seriesID, let name = store.series(id: sid)?.name { return name }
        if let sid = draft.seriesID { return sid }
        let name = draft.newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未指定系列" : name
    }

    private func groupHeader(key: String, count: Int) -> some View {
        HStack {
            Text("系列：\(key)")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(count) 个单品")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private func draftSummaryRow(_ draft: CatalogProductDraft) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(draft.name.isEmpty ? "（未命名单品）" : draft.name)
                .font(.system(size: 13))
            Text("\(draft.category) · \(draft.saleKind.displayName) · \(draft.status.displayName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
