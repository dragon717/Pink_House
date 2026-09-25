import SwiftUI
import Combine
import SwiftData

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
    @Environment(\.scenePhase) private var scenePhase
    /// 尾款阶段同步需要显式传入 context（内部不默认拿生产容器）
    @Environment(\.modelContext) private var modelContext

    @State private var shopID = ""          // "" = 新建店家
    @State private var newShopName = ""
    @State private var newShopAliases = ""
    @State private var seriesID = ""        // "" = 新建系列
    @State private var newSeriesName = ""
    @State private var newSeriesYearMonthText = ""
    @State private var newSeriesSeason = ""
    @State private var loaded = false
    @State private var toast: String?
    @State private var errorText: String?
    /// 同一处 alert 兼作「无法应用」与「同步失败」，标题随之切换
    @State private var alertTitle = "无法应用"

    // 系列级三项配置（2026-09-24 需求「一站式配置」）：发售阶段 / 图文 / 预约价格表。
    // 表单类型与 Section 组件与**系列编辑页共用同一份**（`ShopCatalogSeriesConfigSections`），
    // 否则「批次页填的尾款时间被系列页保存覆盖」这类互相吃掉字段的问题迟早出现。
    @State private var configForm = ShopCatalogSeriesConfigForm(series: CatalogSeries(id: "", shopID: "", name: ""))
    /// 已加载配置的系列 id（nil = 尚未加载）：用于「系列变了要重新回填」的判定
    @State private var configFormSeriesID: String?

    /// 编辑中快照管家（2026-09-24 状态丢失**根源**修复）。
    ///
    /// 上一轮用 `loaded` 守卫挡「切后台 / 相册 / 切应用会重新触发 onAppear」，
    /// 但 `loaded` 本身就是 `@State`：**视图被重建时它跟着归零，守卫直接失效**，
    /// 表单被存储值重新回填 —— 用户看到的就是「内容全没了」。
    /// 真正的兜底只能是不依赖视图生命周期：把未提交的输入落盘，重建后自动恢复。
    /// scope 在 `onAppear` 里按批次 id 定下来（属性初始化式读不到 `batch`）。
    @State private var snapshotKeeper = ShopCatalogFormSnapshotKeeper<ShopCatalogBatchConfigSnapshot>(scope: "")

    private var batchDrafts: [CatalogProductDraft] {
        draftStore.drafts.filter { $0.batchID == batch.id && $0.status != .published && $0.status != .archived }
    }

    var body: some View {
        NavigationStack {
            Form {
                snapshotNoticeSection
                attributionSection
                seriesConfigBlock
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
                snapshotKeeper.scope = Self.snapshotScope(batchID: batch.id)
                loadInitialState()
            }
            // ── 编辑中快照（2026-09-24 状态丢失根源修复）─────────────────────────
            // 三处「页面即将离开」的时机各立即落盘一次；再叠一层「改一下就存一下」
            // 的防抖落盘，兜住跳系统相册这一路 —— 相册返回不会走 onDisappear。
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                snapshotKeeper.flush(makeSnapshot())
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                snapshotKeeper.flush(makeSnapshot())
            }
            .onChange(of: makeSnapshot()) { _, snapshot in
                snapshotKeeper.schedule(snapshot)
            }
            .onDisappear {
                snapshotKeeper.flush(makeSnapshot())
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
                Picker("系列", selection: seriesSelection) {
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
            if seriesID.isEmpty || selectedSeriesNeedsYearMonth {
                // 年月一起填（2026-09-24 需求五）：原先只收年份，导致经批次建出来的系列
                // 在列表里只有「2026」，而其它经系列编辑页录入的显示「2026-10」。
                TextField("年月（选填，如 2026-10 或 2026年10月）", text: $newSeriesYearMonthText)
                if selectedSeriesNeedsYearMonth {
                    Text("该系列还没有年月，在这里补上即可（只补空缺，不会覆盖已有值）。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if let error = CatalogYearMonthText.validationErrorText(for: newSeriesYearMonthText) {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
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
        if let error = CatalogYearMonthText.validationErrorText(for: newSeriesYearMonthText) {
            errorText = error
            return
        }
        let parsedYearMonth = CatalogYearMonthText.parse(newSeriesYearMonthText)
        let count: Int
        do {
            count = try draftStore.applyBatchAttribution(
                batchID: batch.id,
                shopID: shopID.isEmpty ? nil : shopID,
                newShopName: trimmedShopName,
                newShopAliases: newShopAliases,
                seriesID: seriesID.isEmpty ? nil : seriesID,
                newSeriesName: trimmedSeriesName,
                newSeriesYear: parsedYearMonth?.year,
                newSeriesMonth: parsedYearMonth?.month,
                newSeriesSeason: newSeriesSeason.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            // R01：写盘失败可见，列表与磁盘均未变化，可原样重试
            errorText = error.localizedDescription
            return
        }
        toast = "已将 \(count) 条单品归入「\(attributionSummary)」"
        // 选中的是既有系列且它缺年月 → 顺带补齐（只填空不覆盖，2026-09-24 需求五）。
        // `applyBatchAttribution` 只写批次与草稿、不碰实体，所以补全要走这条明确入口。
        if !seriesID.isEmpty, let parsedYearMonth {
            do {
                if try draftStore.completeSeriesYearMonth(seriesID: seriesID,
                                                          year: parsedYearMonth.year,
                                                          month: parsedYearMonth.month) {
                    toast = "已将 \(count) 条单品归入「\(attributionSummary)」，并补齐该系列的年月"
                }
            } catch {
                // 归属已经成功，补年月失败**不翻案**，如实说明是哪一步没成
                toast = "已将 \(count) 条单品归入「\(attributionSummary)」（系列年月补全失败：\(error.localizedDescription)）"
            }
        }
        // 归属变了 → 下方系列配置段跟着换系列（只在新系列 id 与已加载的不同时才重建表单，
        // 免得把用户正在编辑的配置覆盖成存储值）
        reloadConfigForm()
        onApplied?(count)
    }

    /// 选中的**既有系列**是否缺年月：缺 → 上方给出补全输入框，
    /// 「应用到整批」时顺带把缺失的那一项补上（2026-09-24 需求五的存量修复路径）。
    private var selectedSeriesNeedsYearMonth: Bool {
        guard !seriesID.isEmpty, let series = store.series(id: seriesID) else { return false }
        return series.year == nil || series.month == nil
    }

    /// 系列选择器的绑定：**只有用户改选**才把年月框换成该系列的值。
    ///
    /// 原先靠 `.onChange(of: seriesID)` 回填，但那对**程序化赋值**（首次回填 /
    /// 快照恢复 / 创建系列后回填）同样会触发 —— 恢复出来的年月会被「按系列重新推导」
    /// 立刻抹掉，用户看到的就是「恢复了但年月没了」。
    /// 改成挂在 Picker 自己的 setter 上，「谁改的」一目了然，不再依赖变化来源的猜测。
    private var seriesSelection: Binding<String> {
        Binding(
            get: { seriesID },
            set: { newValue in
                seriesID = newValue
                // 不加这一条会残留上一段输入（例如先在「新建系列」里填了 2026-10，
                // 再切到一条缺月份的既有系列），一点应用就把月份写到另一个系列上。
                newSeriesYearMonthText = selectedSeriesYearMonthText(for: newValue)
            })
    }

    /// 选中系列的年月回填文本（新建系列 / 查不到 → 空串）。
    /// 用 `displayText` 统一口径，所以输入框里看到的就是列表里显示的那串。
    private func selectedSeriesYearMonthText(for id: String) -> String {
        guard !id.isEmpty, let series = store.series(id: id) else { return "" }
        return CatalogYearMonthText.displayText(year: series.year, month: series.month) ?? ""
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

    // MARK: 系列配置（发售阶段 / 图文 / 价格表）——一站式配置的第二段

    /// 批次会话的**落库值**（不是上方 Picker 的本地选择）。
    /// 配置段只认已经「应用到整批」的归属，避免「上方刚选了别的系列、还没点应用，
    /// 下方配置就换了系列」这种错配。
    private var appliedBatchSession: CatalogBatchEntrySession? {
        draftStore.batches.first { $0.id == batch.id }
    }

    /// 该批已归属的系列实体。nil = 还没归属到既有系列 → 配置段给出创建入口。
    private var configSeries: CatalogSeries? {
        guard let sid = appliedBatchSession?.seriesID ?? batch.seriesID, !sid.isEmpty,
              let series = store.series(id: sid) else { return nil }
        return series
    }

    /// 共用影响面文案（需求二：让用户一眼知道改一次会影响谁）
    private var sharedScopeText: String? {
        guard let series = configSeries else { return nil }
        return "本批次 \(batchDrafts.count) 条单品、该系列 \(store.products(inSeries: series.id).count) 个商品"
    }

    @ViewBuilder
    private var seriesConfigBlock: some View {
        if configSeries != nil {
            ShopCatalogSeriesConfigSections(form: $configForm, sharedScope: sharedScopeText)
            Section {
                Button {
                    saveSeriesConfig()
                } label: {
                    Label("保存系列配置（发售阶段 / 图文 / 价格表）", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13))
                }
            } footer: {
                Text("保存即写回系列实体：同系列的全部批次与商品详情页同步生效，不需要逐条单品再改一次。")
            }
        } else {
            Section {
                Button {
                    ensureSeriesForConfig()
                } label: {
                    Label("创建 / 确认系列并开始配置", systemImage: "rectangle.stack.badge.plus")
                        .font(.system(size: 13))
                }
            } header: {
                ShopCatalogSeriesSharedHeader(title: "系列配置（发售阶段 / 图文 / 价格表）")
            } footer: {
                Text("这三项配置属于**系列**，不属于单个批次：先在「整批归属」里选定或填写系列并点「应用于整批」，这里才会出现配置项。"
                    + "若系列还没建，点上方按钮按**发布同款去重口径**创建（同名系列不会建出第二条）。")
            }
        }
    }

    /// 回填配置表单。只在「系列 id 变了」时重建 —— 否则每次列表刷新都会把用户
    /// 正在编辑的内容覆盖成存储值（与 2026-09-24「编辑系列页状态丢失」同源的坑）。
    private func reloadConfigForm() {
        guard let series = configSeries else {
            configFormSeriesID = nil
            return
        }
        guard configFormSeriesID != series.id else { return }
        configForm = ShopCatalogSeriesConfigForm(series: series)
        configFormSeriesID = series.id
    }

    // MARK: 编辑中快照（切后台 / 相册选图 / 切应用返回后不丢内容）

    /// 快照作用域：**一个批次一份**。带上批次 id 才不会把 A 批次填的店家 / 系列
    /// 恢复进 B 批次。
    private static func snapshotScope(batchID: String) -> String {
        "batch-config-\(batchID)"
    }

    /// 把当前整页表单组装成快照（唯一组装口径 —— 落盘、比较、提交都读它）。
    private func makeSnapshot() -> ShopCatalogBatchConfigSnapshot {
        ShopCatalogBatchConfigSnapshot(
            batchID: batch.id,
            shopID: shopID,
            newShopName: newShopName,
            newShopAliases: newShopAliases,
            seriesID: seriesID,
            newSeriesName: newSeriesName,
            newSeriesYearMonthText: newSeriesYearMonthText,
            newSeriesSeason: newSeriesSeason,
            configFormSeriesID: configFormSeriesID,
            config: configForm)
    }

    /// 把快照写回表单（唯一恢复口径）。**直接赋值**，不走任何 onChange 派生 ——
    /// 恢复出来的就是用户离开前看到的那一份，不该被「按系列重新推导」覆盖掉。
    private func applySnapshot(_ snapshot: ShopCatalogBatchConfigSnapshot) {
        shopID = snapshot.shopID
        newShopName = snapshot.newShopName
        newShopAliases = snapshot.newShopAliases
        seriesID = snapshot.seriesID
        newSeriesName = snapshot.newSeriesName
        newSeriesYearMonthText = snapshot.newSeriesYearMonthText
        newSeriesSeason = snapshot.newSeriesSeason
        configFormSeriesID = snapshot.configFormSeriesID
        configForm = snapshot.config
    }

    /// 首次出现：先按存储值填「默认态」，再用快照覆盖成「用户离开前的未提交编辑」。
    ///
    /// 顺序不能颠倒：快照与默认态的比较需要一个正确的默认态作基准；
    /// 而「快照 == 默认态」说明上次其实没改什么，`restoreOrDiscard` 会直接丢掉它，
    /// 不会让用户白看到一条「已恢复」提示。
    private func loadInitialState() {
        shopID = batch.shopID ?? ""
        newShopName = batch.newShopName
        newShopAliases = batch.newShopAliases
        seriesID = batch.seriesID ?? ""
        newSeriesName = batch.newSeriesName
        newSeriesYearMonthText = CatalogYearMonthText.displayText(year: batch.newSeriesYear,
                                                                 month: batch.newSeriesMonth) ?? ""
        newSeriesSeason = batch.newSeriesSeason
        configFormSeriesID = nil
        reloadConfigForm()
        snapshotKeeper.restoreOrDiscard(defaults: makeSnapshot()) { applySnapshot($0) }
    }

    /// 用户主动放弃恢复出来的未提交编辑：清快照 + 回到存储值
    private func discardRestoredSnapshot() {
        snapshotKeeper.discard()
        configFormSeriesID = nil
        loadInitialState()
        toast = "已放弃上次未保存的编辑"
    }

    /// 「已恢复未保存编辑」提示条。
    ///
    /// 不静默恢复：用户上次可能只是临时切走，恢复是对的；也可能是主动关掉了页面，
    /// 那就得给他一条一眼可见的「这些是上次没保存的」+ 一键放弃的路，
    /// 否则他会以为「明明没保存，怎么自己变了」。
    @ViewBuilder
    private var snapshotNoticeSection: some View {
        if snapshotKeeper.didRestore {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已恢复上次未保存的编辑")
                        .font(.system(size: 13, weight: .semibold))
                    Text("离开页面时（切后台 / 去相册选图 / 切到其他应用）自动保留了这里的内容，包括已选的封面图。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("知道了") { snapshotKeeper.markRestoreAcknowledged() }
                            .font(.system(size: 13))
                        Button("放弃修改", role: .destructive) { discardRestoredSnapshot() }
                            .font(.system(size: 13))
                    }
                }
            } footer: {
                Text("「放弃修改」只清掉这份未保存的内容，不会动服务器 / 本机已保存的系列数据。")
            }
        }
    }

    /// 未归属时的一键入口：把批次归属**落成真实实体**（与 `publish` 同源的三档解析）
    private func ensureSeriesForConfig() {
        alertTitle = "无法创建系列"
        do {
            guard let resolved = try draftStore.ensureAttributionEntities(batchID: batch.id, store: store) else {
                errorText = "请先在「整批归属」里选择既有系列，或填写新系列名称"
                return
            }
            seriesID = resolved.series.id
            // 程序化赋值不再经过 Picker 的 setter，年月回填要显式做一次
            newSeriesYearMonthText = selectedSeriesYearMonthText(for: resolved.series.id)
            reloadConfigForm()
            toast = "已确认系列「\(resolved.series.name)」，可以开始配置"
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// 保存三项系列配置：单点写入系列实体 + 批次链接归一（需求一）
    private func saveSeriesConfig() {
        alertTitle = "保存失败"
        guard let series = configSeries else { return }
        if let error = configForm.balanceDueValidationErrorText() {
            // 非法输入**不落库**；表单内也有同一份红字（同源判定，不做两套）
            errorText = error
            return
        }
        let updated = configForm.apply(to: series)
        do {
            let linked = try draftStore.saveSeriesConfig(updated, batchID: batch.id)
            configForm = ShopCatalogSeriesConfigForm(series: updated)
            configFormSeriesID = updated.id
            // 保存成功 = 这一份内容已提交：清掉编辑中快照，避免下次进页面把刚保存的
            // 内容又当成「未保存的编辑」恢复出来（那一刻用户会以为保存没生效）。
            snapshotKeeper.commit(makeSnapshot())
            toast = linked > 0
                ? "已保存「\(updated.name)」的系列配置，并同步本批 \(linked) 条单品"
                : "已保存「\(updated.name)」的系列配置（同系列全部单品同步生效）"
            // 2026-09-25 需求二/三：发售阶段/尾款时间可能刚变化 —— 幂等同步用户
            // 衣橱条目的尾款窗口（大致时间按约一个月基准估算成固定具体日期）。
            let syncReport = ShopCatalogWardrobeBalanceSync.syncIfNeeded(
                store: store, modelContext: modelContext)
            if syncReport.updatedCount > 0 {
                toast = (toast ?? "") + "；已同步 \(syncReport.updatedCount) 条衣橱尾款时间"
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
