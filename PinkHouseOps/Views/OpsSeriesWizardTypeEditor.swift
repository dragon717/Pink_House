//
//  OpsSeriesWizardTypeEditor.swift
//  PinkHouseOps
//
//  系列上新向导 S3：系列内多类型录入（需求 v1.2 的核心编辑页面）。
//
//  ## 页面结构
//
//      左列：类型条目列表（多选生成的条目，可增删、可切换）
//      右列：当前类型的完整编辑区
//            S3-A 公共资料（款式名；类型由多选结果确定）
//            S3-B 尺码表（结构化列/行 + 单位 + 原图；或「无尺码/均码」）
//            S3-C 价格（预约价/定金/尾款/现货价同屏；尾款自动计算，现货价独立）
//            S3-D 颜色 SKU（颜色名 + 颜色图 + 可售尺码勾选）
//
//  ## 从需求逐条落下的交互约束
//
//  · 类型选择是**多选**，不是单选下拉框（§S3）；每个已选类型都有一套独立编辑区；
//  · 删除一个类型只删它**尚未提交的草稿条目**，且有明确确认，
//    不影响同系列其他类型（§S3）；
//  · 切换类型不丢输入 —— 输入直接写进 `workspace.seriesEntry`（自动持久化）；
//  · 可售尺码勾选项**来自当前类型尺码表**并按其原始顺序（§S3-B/§S3-D）；
//  · 颜色 SKU 不填价格 / 任务名称 / 批次 / 独立尺码表 / 款式描述（§S3-D）；
//  · 全程没有「任务名称」「批次」「款式描述」输入框（§1 / §5 验收）。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - S3 主视图（条目列表 + 当前类型编辑区）

struct OpsSeriesWizardTypeEntriesView: View {
    @ObservedObject var workspace: OpsWorkspace

    @State private var selectedEntryID: String?
    @State private var customCategoryText = ""
    @State private var entryPendingRemoval: OpsSeriesTypeEntry?
    @State private var showCustomCategory = false

    private var draft: OpsSeriesEntryDraft { workspace.seriesEntry }

    // MARK: 派生

    private var issues: [OpsSeriesEntryIssue] {
        OpsSeriesEntryValidator.validate(draft, catalog: workspace.catalog)
            .filter { $0.area == .typeEntries }
    }

    private func issues(forEntry entryID: String) -> [OpsSeriesEntryIssue] {
        issues.filter { $0.entryID == entryID }
    }

    private var selectedEntry: OpsSeriesTypeEntry? {
        draft.typeEntries.first { $0.id == selectedEntryID }
    }

    private var selectedBinding: Binding<OpsSeriesTypeEntry> {
        Binding(
            get: {
                draft.typeEntries.first { $0.id == selectedEntryID }
                    ?? draft.typeEntries.first
                    ?? OpsSeriesTypeEntry(category: "")
            },
            set: { newValue in
                if let index = workspace.seriesEntry.typeEntries.firstIndex(where: { $0.id == newValue.id }) {
                    workspace.seriesEntry.typeEntries[index] = newValue
                }
            })
    }

    var body: some View {
        HSplitView {
            entryListColumn
                // 响应式硬约束：窗口最小 980 − 导航侧栏最大 260 → 详情区最窄 ~720。
                // 两列 minWidth 之和**不得超过** 720，否则 NavigationSplitView 布局被撑爆
                // （侧栏被顶出窗口、内容两侧裁切、底部「上一步/下一步」被挤出可视区），
                // 且每次「上一步/下一步」重建 S3 时按 ideal 宽度重排，必然复现。
                // 因此：左列 200 + 编辑器 460 = 660 ≤ 720；编辑器用 maxWidth: .infinity 吃掉余量。
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
            if let entry = selectedEntry ?? draft.typeEntries.first {
                OpsSeriesWizardTypeEditorView(workspace: workspace, entry: selectedBindingFor(entry))
                    // 每个条目拥有自己的编辑器状态；切到副本不会触发旧编辑器的
                    // 颜色数量/身份变化回调，把复制保留的尺码勾选重新补满。
                    .id(entry.id)
                    .frame(minWidth: 460, idealWidth: 480, maxWidth: .infinity)
            } else {
                emptyEditor
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity)
            }
        }
        .onAppear { clampSelection() }
        .onChange(of: draft.typeEntries.count) { _, _ in clampSelection() }
        .confirmationDialog(
            "删除类型「\(entryPendingRemoval?.displayName ?? "")」？",
            isPresented: Binding(
                get: { entryPendingRemoval != nil },
                set: { if !$0 { entryPendingRemoval = nil } }),
            titleVisibility: .visible) {
            Button("删除这个类型的草稿资料", role: .destructive) {
                if let target = entryPendingRemoval {
                    workspace.seriesEntry.typeEntries.removeAll { $0.id == target.id }
                }
                entryPendingRemoval = nil
            }
            Button("取消", role: .cancel) { entryPendingRemoval = nil }
        } message: {
            opsMarkdown("只删除该类型**尚未提交**的草稿资料，不影响同系列的其他类型，也不影响已写入目录的商品。")
                .font(.callout)
        }
    }

    private func selectedBindingFor(_ entry: OpsSeriesTypeEntry) -> Binding<OpsSeriesTypeEntry> {
        Binding(
            get: {
                workspace.seriesEntry.typeEntries.first { $0.id == entry.id } ?? entry
            },
            set: { newValue in
                if let index = workspace.seriesEntry.typeEntries.firstIndex(where: { $0.id == newValue.id }) {
                    workspace.seriesEntry.typeEntries[index] = newValue
                }
            })
    }

    private func clampSelection() {
        if !draft.typeEntries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = draft.typeEntries.first?.id
        }
    }

    private var emptyEditor: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(OpsFlowPalette.textSecondary)
            opsMarkdown("先在左上方**勾选类型**（如 JSK、OP、小物）——"
                        + "每个已选类型都会生成一套独立编辑区。")
                .font(.callout)
                .foregroundStyle(OpsFlowPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OpsFlowPalette.tileLilac, in: RoundedRectangle(cornerRadius: 16))
        .padding(12)
    }

    // MARK: 左列

    private var entryListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("本系列已选类型").font(.headline)
                    .foregroundStyle(OpsFlowPalette.textPrimary)
                Text("已选：\(draft.selectedCategorySummary)")
                    .font(.caption)
                    .foregroundStyle(OpsFlowPalette.textSecondary)
                categoryPicker
                Divider()
                Text("添加同类型另一款款式").font(.subheadline.weight(.semibold))
                    .foregroundStyle(OpsFlowPalette.textPrimary)
                addSameCategoryRow
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if draft.typeEntries.isEmpty {
                Text("还没有类型。至少选择一个类型才能继续。")
                    .font(.callout).foregroundStyle(OpsFlowPalette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
            } else {
                List(selection: $selectedEntryID) {
                    ForEach(draft.typeEntries) { entry in
                        entryRow(entry).tag(entry.id)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(OpsFlowPalette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(OpsFlowPalette.cardBorder, lineWidth: 1))
        .shadow(color: OpsFlowPalette.cardShadow, radius: 10, x: 0, y: 4)
        .padding(12)
        .frame(maxHeight: .infinity)
    }

    /// 类型多选区（需求：多选，不是单选下拉框；保留枚举 + 扩展入口）
    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(OpsSeriesEntryCategory.known, id: \.self) { category in
                Toggle(isOn: bindingForKnownCategory(category)) {
                    HStack {
                        Text(category).font(.callout)
                        Spacer()
                        Text("已选 \(entryCount(for: category))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            HStack(spacing: 6) {
                TextField("自定义类型（扩展入口）", text: $customCategoryText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button("添加") { addCustomCategory() }
                    .controlSize(.small)
                    .disabled(customCategoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var addSameCategoryRow: some View {
        Menu {
            ForEach(orderedCategoriesInUse, id: \.self) { category in
                Button("新增一条 \(category) 款式") {
                    appendEntry(category: category)
                }
            }
        } label: {
            Label("添加条目…", systemImage: "plus")
        }
        .controlSize(.small)
        .disabled(orderedCategoriesInUse.isEmpty)
    }

    private var orderedCategoriesInUse: [String] {
        var ordered: [String] = []
        for entry in draft.typeEntries {
            let category = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
            if !category.isEmpty, !ordered.contains(category) { ordered.append(category) }
        }
        return ordered
    }

    private func entryCount(for category: String) -> Int {
        draft.typeEntries.filter { $0.category == category }.count
    }

    /// 勾选 = 该类型至少有一条条目；勾上 → 建条目，取消 → 询问后删（走确认弹窗）
    private func bindingForKnownCategory(_ category: String) -> Binding<Bool> {
        Binding(
            get: { entryCount(for: category) > 0 },
            set: { isOn in
                if isOn {
                    appendEntry(category: category)
                } else if let first = draft.typeEntries.first(where: { $0.category == category }) {
                    entryPendingRemoval = first
                }
            })
    }

    private func addCustomCategory() {
        let category = customCategoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { return }
        appendEntry(category: category)
        customCategoryText = ""
    }

    private func appendEntry(category: String) {
        let entry = OpsSeriesTypeEntry(category: category)
        workspace.seriesEntry.typeEntries.append(entry)
        selectedEntryID = entry.id
    }

    private func entryRow(_ entry: OpsSeriesTypeEntry) -> some View {
        let entryIssues = issues(forEntry: entry.id)
        return OpsFlowTile(color: entry.id == selectedEntryID
            ? OpsFlowPalette.tilePink : OpsFlowPalette.tileLilac.opacity(0.55),
            selected: entry.id == selectedEntryID) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.displayName).lineLimit(1)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(OpsFlowPalette.textPrimary)
                    if entry.lastCommitOK == true {
                        OpsFlowChip(text: "已提交", tint: OpsFlowPalette.okGreen, filled: true)
                    } else if entry.lastCommitOK == false {
                        OpsFlowChip(text: "上次提交失败", tint: OpsFlowPalette.warnOrange)
                    }
                    Spacer(minLength: 2)
                    Button { duplicateEntry(entry.id) } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制款式（保留全部填写内容）")
                    .accessibilityLabel("复制款式「\(entry.displayName)」")
                }
                HStack(spacing: 8) {
                    Text("\(entry.colors.count) 颜色")
                    if entry.usesSizeChart {
                        Text("有尺码表")
                    } else {
                        Text("均码")
                    }
                    if entryIssues.isEmpty {
                        Text("校验通过").foregroundStyle(OpsFlowPalette.okGreen)
                    } else {
                        Text("\(entryIssues.count) 个问题").foregroundStyle(OpsFlowPalette.warnOrange)
                    }
                }
                .font(.caption)
                .foregroundStyle(OpsFlowPalette.textSecondary)
            }
        }
        .contextMenu {
            Button("复制款式", systemImage: "doc.on.doc") { duplicateEntry(entry.id) }
            Divider()
            Button("删除这个类型…", role: .destructive) { entryPendingRemoval = entry }
        }
    }

    private func duplicateEntry(_ id: String) {
        if let copiedID = workspace.duplicateSeriesTypeEntry(id: id) { selectedEntryID = copiedID }
    }
}

// MARK: - 单个类型条目的编辑区（S3-A/B/C/D）

struct OpsSeriesWizardTypeEditorView: View {
    @ObservedObject var workspace: OpsWorkspace
    @Binding var entry: OpsSeriesTypeEntry

    /// 图片导入的目标槽位（封面在 S2，这里只有尺码表原图与颜色图）
    private enum ImageSlot: Equatable {
        case chartSource
    }
    @State private var importSlot: ImageSlot?
    @State private var showsImporter = false
    @State private var batchImageTarget: BatchImageTarget?

    private struct BatchImageTarget: Identifiable {
        let id: String
        var colorID: String?
    }

    /// 「用标准模板填入」的确认弹窗：**已经填过内容时先问一句**。
    /// 这个按钮会一次覆盖三个字段（单位 / 列名 / 数据行），
    /// 悄悄吃掉用户手打的一整张尺码表是不能接受的（仓库对「覆盖用户内容」一贯要求先确认）。
    @State private var confirmsTemplateFill = false

    /// 点「用标准模板填入」：空的就直接填，非空先确认。
    private func requestTemplateFill() {
        if isChartInputEmpty {
            applyTemplate()
        } else {
            confirmsTemplateFill = true
        }
    }

    private func applyTemplate() {
        entry.chartUnit = CatalogChartTemplate.SizeChart.unit
        entry.chartColumnsText = CatalogChartTemplate.SizeChart.columnsText
        entry.chartRowsText = CatalogChartTemplate.SizeChart.rowsText
        // 触发点 ②：模板一定识别成功 → 此刻把可售尺码补齐（幂等，见 autoSelectSellableSizes）
        autoSelectSellableSizes()
    }

    // MARK: 自动勾选可售尺码（2026-10-07 需求）

    /// 把「可售尺码」补齐到当前尺码表。
    ///
    /// ⭐ **判定在共享包 `CatalogSizeSelectionPolicy`，写回在 `OpsWorkspace`**，
    /// 本视图只负责说「此刻该补了」。规则是**幂等**的：
    /// 只对「一个有效尺码都没勾」的颜色补齐，**手动取消过的一律不动**。
    ///
    /// ## 触发时机（只有这几个，全部是**人的明确动作**）
    ///
    /// | # | 时机 | 为什么是它 |
    /// |---|---|---|
    /// | ① | 尺码表**原图上传成功**后 | 用户原话：「尺码表识别**并上传**成功后自动勾选」 |
    /// | ② | 点「**用标准模板填入**」后 | 模板一定识别成功，等于用户声明「就按这张表」 |
    /// | ③ | 尺码表文本改动、且这次改动让它**第一次**变成有效 | 覆盖「先贴数据行、再写列名」这类顺序 |
    /// | ④ | 打开「**区分尺码**」开关后 | 此前是均码，可勾项刚出现 |
    /// | ⑤ | **新增一个颜色**后 / **切换当前类型**后 | 新颜色一个尺码都没勾，不补就要手点 5 次 |
    ///
    /// ## 刻意**不做**的事
    ///
    /// · **不在 body / `onAppear` 里对账**：body 里改 `@Published` 会无限刷新，
    ///   而且「为什么勾上了」变得无法解释；
    /// · **不在尺码表被改动时无条件补**：改表之后无法区分「这是新加的尺码」和
    ///   「用户故意不要这个尺码」—— 后者是显式意图，绝不能被自动改写。
    ///   这种情况界面只给一句**提示**（「还有 N 个尺码没勾」）+ 一个「全选」按钮。
    private func autoSelectSellableSizes() {
        _ = workspace.autoSelectSellableSizes(entryID: entry.id)
    }

    /// 尺码表文本的绑定：**写入之后再判断**「这次改动是不是让它第一次变成有效」。
    /// 直接绑 `$entry.chartColumnsText` 就只能在「写之前」判断，
    /// 而「有效性」恰恰是写完之后才知道的。
    private func chartTextBinding(
        _ keyPath: WritableKeyPath<OpsSeriesTypeEntry, String>
    ) -> Binding<String> {
        Binding(
            get: { entry[keyPath: keyPath] },
            set: { newValue in
                let wasValid = parsedChart != nil
                entry[keyPath: keyPath] = newValue
                // 触发点 ③
                if !wasValid, parsedChart != nil { autoSelectSellableSizes() }
            })
    }

    /// 「区分尺码」开关：打开时可能立刻就有了可勾项（尺码表文本早就填好了）。触发点 ④。
    private var usesSizeChartBinding: Binding<Bool> {
        Binding(
            get: { entry.usesSizeChart },
            set: { newValue in
                entry.usesSizeChart = newValue
                if newValue { autoSelectSellableSizes() }
            })
    }

    private var parsedChart: OpsSeriesParsedSizeChart? {
        OpsSeriesSizeChartParsing.parse(entry: entry).chart
    }

    /// 两个尺码表输入框是否都为空。为空时不显示识别结果卡片 ——
    /// 还没填就说「识别失败」看着像出错。
    private var isChartInputEmpty: Bool {
        entry.chartColumnsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && entry.chartRowsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 尺码表识别结论（2026-10-01 需求）。
    ///
    /// 结构与落库**同一份解析**（`OpsSeriesSizeChartParsing`），判定与文案交给共享包
    /// `OpsChartRecognition` —— 本视图不许自己拼「识别成功 / 识别失败」。
    private var chartRecognition: CatalogChartRecognition? {
        guard entry.usesSizeChart else { return nil }
        let parsed = OpsSeriesSizeChartParsing.parse(entry: entry)
        return OpsChartRecognition.make(kind: .size,
                                        columns: parsed.chart?.columns ?? [],
                                        rows: parsed.chart?.rows ?? [],
                                        issue: parsed.issue)
    }

    private var entryIssues: [OpsSeriesEntryIssue] {
        var issues: [OpsSeriesEntryIssue] = []
        OpsSeriesEntryValidator.validateEntry(entry, into: &issues)
        return issues
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                publicInfoCard
                sizeChartCard
                priceCard
                colorSKUCard
                issuesCard
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OpsFlowPageBackground())
        .sheet(item: $batchImageTarget) { target in
            if let targetEntry = workspace.seriesEntry.typeEntries.first(where: { $0.id == target.id }) {
                OpsColorImagesSheet(workspace: workspace, entry: targetEntry, initialColorID: target.colorID)
            } else {
                VStack(spacing: 12) {
                    Text("当前类型已不存在，请重新打开批量配图。")
                    Button("关闭") { batchImageTarget = nil }
                }
                .padding(20)
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false) { result in
            guard let slot = importSlot else { return }
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                if let assetID = workspace.importSingleImage(from: url) {
                    assignAsset(assetID, to: slot)
                }
            case .failure(let error):
                workspace.reportFailure("图片上传失败：\(error.localizedDescription)")
            }
            importSlot = nil
        }
        // 触发点 ⑤（切换类型）：换到另一个类型时，它可能本来就有一张有效尺码表
        // 而颜色还没勾过（例如草稿从别的会话恢复）。幂等规则在这儿也是安全的。
        .onChange(of: entry.id) { _, _ in autoSelectSellableSizes() }
        .confirmationDialog("用标准模板填入尺码表？",
                            isPresented: $confirmsTemplateFill) {
            Button("覆盖当前的单位 / 列名 / 数据行", role: .destructive) {
                applyTemplate()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前的列名与数据行会被模板替换掉，这一步不能撤销。")
        }
    }

    private func assignAsset(_ assetID: String, to slot: ImageSlot) {
        switch slot {
        case .chartSource:
            entry.chartSourceImageAssetID = assetID
            // 触发点 ①：用户原话就是「尺码表识别**并上传**成功后自动勾选」。
            // 尺码表现在还没识别成功（`parsedChart == nil`）也不打紧 ——
            // 文本那边一旦有效，触发点 ③ 会接手补上。
            autoSelectSellableSizes()
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            if !entry.category.isEmpty {
                OpsFlowChip(text: entry.category, tint: OpsFlowPalette.accentPink, filled: true)
            }
            Text("当前编辑").font(.headline)
                .foregroundStyle(OpsFlowPalette.textPrimary)
            Spacer(minLength: 4)
        }
    }

    // MARK: S3-A 公共资料

    private var publicInfoCard: some View {
        OpsCard(title: "款式公共资料（当前类型的所有颜色共享）", systemImage: "tag") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("类型", value: entry.category.isEmpty ? "（未选择）" : entry.category)
                VStack(alignment: .leading, spacing: 3) {
                    Text("款式名（必填）").font(.callout)
                    TextField("如「星月夜」", text: $entry.designName)
                        .textFieldStyle(.roundedBorder)
                }
                OpsFootnote(text: "本页面**没有**「款式描述」输入框（需求 §S3-A）；"
                            + "尺码表只包含结构化列/行、单位和原图。")
            }
        }
    }

    // MARK: S3-B 尺码表

    private var sizeChartCard: some View {
        OpsCard(title: "尺码表（归属当前类型，不与其他类型共用）", systemImage: "ruler") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: usesSizeChartBinding) {
                    opsMarkdown("这个类型区分尺码（关闭 = **无尺码/均码**，如小物）")
                }
                if entry.usesSizeChart {
                    TextField("单位（如 cm）", text: $entry.chartUnit)
                        .textFieldStyle(.roundedBorder)
                    // ⭐ 示例文本一律读共享包的标准模板：placeholder 与下面那句「每一行一条」
                    // **同源**。原先 placeholder 举例 3 列（后衣长, 胸围, 腰围）、
                    // 下面提示却只给 2 个值（`S = 80, 78-83`）—— 两句话互相矛盾，
                    // 用户照哪句填都可能失败（2026-10-01 价格表报障的同一种病）。
                    TextField("列名（只写数据列，逗号分隔，如：\(CatalogChartTemplate.SizeChart.columnsText)）",
                              text: chartTextBinding(\.chartColumnsText))
                        .textFieldStyle(.roundedBorder)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("每一行一条：`\(CatalogChartTemplate.SizeChart.sampleRowText)`")
                                .font(.caption)
                            Spacer(minLength: 8)
                            Button("用标准模板填入") { requestTemplateFill() }
                                .controlSize(.small)
                                .help("填入一份格式一定正确的尺码表（7 个数据列 × 5 行），照着改数字即可")
                        }
                        TextEditor(text: chartTextBinding(\.chartRowsText))
                            .font(.body.monospaced())
                            .frame(height: 110)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                    }
                    // 「尺码不要写进列名」这条规则光靠一句提示说不清，而写错的后果很重
                    // （Mac 按含标签列的列数放行 → iOS 渲染剔掉该列、值没剔 → **整列错位**），
                    // 所以这里把口径写成一句可执行的话：尺码在「=」左边，只占「列名」以外的位置。
                    OpsFootnote(text: "**尺码/款式写在「=」左边**，不写进列名（渲染时它单独占角落那一列）；"
                                + "「=」右边的**值个数要和列名一样多**。分隔符用半角逗号「,」。")
                    chartSourceRow
                    // 识别结果（2026-10-01 需求）：用户填完就得知道「认出来了没有」。
                    // 判定与文案来自共享包，Mac 只负责画；两种表各自的提示由此派生。
                    OpsChartRecognitionBlock(recognition: chartRecognition,
                                             isInputEmpty: isChartInputEmpty)
                    if let chart = parsedChart {
                        OpsFootnote(text: "可售尺码勾选项将从这些行按**原始顺序**生成："
                                    + chart.sizeLabels.joined(separator: "、"))
                    } else if isChartInputEmpty {
                        // 输入为空时不显示识别卡片（没有内容谈不上识别），
                        // 但仍要说明「两条同时填或同时空」这条口径，所以这句保留。
                        OpsFootnote(text: "还没有结构化内容：列和行**同时**填写或**同时**留空；"
                                    + "只有原图时可以都为空。")
                    }
                } else {
                    OpsFootnote(text: "均码模式：颜色 SKU 不勾尺码（规格不区分尺码）。"
                                + "**不能借用其他类型的尺码表**。")
                }
            }
        }
    }

    private var chartSourceRow: some View {
        HStack(spacing: 8) {
            OpsImageUploadThumbnail(
                url: entry.chartSourceImageAssetID.flatMap {
                    workspace.stagedFileURL(forReference: workspace.asset(for: $0)?.originalURL)
                }, size: 40, title: "点击上传或更换尺码表原图") {
                    importSlot = .chartSource
                    showsImporter = true
                }
            Picker("尺码表原图", selection: $entry.chartSourceImageAssetID) {
                Text("不指定").tag(String?.none)
                ForEach(workspace.catalog.assets) { asset in
                    Text(assetFileLabel(asset)).tag(String?.some(asset.id))
                }
            }
            .controlSize(.small)
        }
    }

    // MARK: S3-C 价格

    private var priceCard: some View {
        OpsCard(title: "价格（当前类型只填一次；不同类型互相独立）", systemImage: "yensign.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("币种", selection: $entry.currency) {
                    ForEach(CatalogCurrency.allCases.filter { !$0.isUnknown }) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                // 宽度够 → 一行四列；不够 → 两行各两列（窄列宽下不换行会横向撑爆容器）
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        priceField("预约价", $entry.reservationPriceText)
                        priceField("定金", $entry.depositText)
                        priceField("尾款", $entry.balanceText)
                        priceField("现货价", $entry.stockPriceText)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            priceField("预约价", $entry.reservationPriceText)
                            priceField("定金", $entry.depositText)
                        }
                        HStack(spacing: 10) {
                            priceField("尾款", $entry.balanceText)
                            priceField("现货价", $entry.stockPriceText)
                        }
                    }
                }
                priceSummary
                OpsFootnote(text: "预约价与现货价**至少填一项**且**互相独立**："
                            + "改现货价不清空、不覆盖、不重算预约价；改预约价不改现货价。"
                            + "填写预约价和定金后**自动计算尾款**，修改任一项会同步更新。"
                            + "三者全填时校验「定金 + 尾款 = 预约价」。"
                            + "颜色 SKU 页**不重复填写价格**。")
            }
        }
    }

    private func priceField(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 120)
        }
    }

    private var priceSummaryText: String {
        let parsed = OpsSeriesPriceParsing.parse(entry: entry)
        let currency = parsed.price.currency
        let symbol = currency.isUnknown ? "¥" : currency.symbol
        func amount(_ value: Decimal?) -> String {
            guard let value else { return "暂无" }
            return "\(symbol)\(value)"
        }
        if let reservation = parsed.price.reservation {
            var line = "预约价 " + amount(reservation)
            if let deposit = parsed.price.deposit, let balance = parsed.price.balance {
                let ok = deposit + balance == reservation
                line += " = 定金 " + amount(deposit) + " + 尾款 " + amount(balance)
                    + (ok ? " ✓" : "（不等，见下方校验）")
            }
            if let stock = parsed.price.stock {
                line += "；现货价 " + amount(stock) + "（独立）"
            }
            return line
        }
        if let stock = parsed.price.stock {
            return "现货价 " + amount(stock) + "（独立）"
        }
        return "预约价与现货价至少填一项。"
    }

    @ViewBuilder
    private var priceSummary: some View {
        let parsed = OpsSeriesPriceParsing.parse(entry: entry)
        if parsed.price.reservation != nil || parsed.price.stock != nil {
            opsMarkdown(priceSummaryText)
                .font(.callout.weight(.medium))
        } else {
            Text("预约价与现货价至少填一项。")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    // MARK: S3-D 颜色 SKU

    private var colorSKUCard: some View {
        OpsCard(title: "颜色 SKU（\(entry.colors.count)）", systemImage: "paintpalette") {
            VStack(alignment: .leading, spacing: 10) {
                if entry.colors.isEmpty {
                    Text("还没有颜色。至少填写一个颜色，名称不能为空。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach($entry.colors) { $color in
                        colorRow($color)
                        Divider()
                    }
                }
                HStack(spacing: 12) {
                    Button {
                        entry.colors.append(OpsSeriesColorSKU())
                    } label: {
                        Label("添加颜色", systemImage: "plus")
                    }
                    Button {
                        batchImageTarget = BatchImageTarget(id: entry.id)
                    } label: {
                        Label("批量配图…", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(entry.colors.isEmpty)
                }
                .controlSize(.small)
                OpsFootnote(text: "追加颜色时，本类型的公共资料、尺码表和价格**只读继承**，"
                            + "不会因为新增颜色被覆盖；颜色也不能追加到其他类型。"
                            + "颜色 SKU **不填**价格 / 任务名称 / 批次 / 独立尺码表 / 款式描述。")
                OpsFootnote(text: "**可售尺码**：尺码表识别成功的那一刻自动勾满"
                            + "（原图上传成功、点「用标准模板填入」、文本第一次变成有效、"
                            + "打开「区分尺码」、新增颜色 —— 只有这几种时机）。"
                            + "之后**手动取消的尺码不会被自动勾回**；"
                            + "如果尺码表后来新增了尺码，这里只提示「还有 N 个没勾」，"
                            + "想全要就点该颜色的「**全选**」。")
            }
        }
        // 触发点 ⑤（新增颜色）：新颜色的 selectedSizes 是空的，不补就得手点 N 次。
        // 幂等规则在这儿也安全 —— 已经勾过的颜色（含用户手动取消过的）一律不动；
        // 删除颜色同样会走到这里，同样不改动剩下的颜色。
        .onChange(of: entry.colors.count) { _, _ in autoSelectSellableSizes() }
    }

    private func colorRow(_ color: Binding<OpsSeriesColorSKU>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OpsImageUploadThumbnail(
                    url: color.wrappedValue.imageAssetID.flatMap {
                        workspace.stagedFileURL(forReference: workspace.asset(for: $0)?.originalURL)
                    }, size: 36, title: "点击打开颜色批量配图") {
                        batchImageTarget = BatchImageTarget(id: entry.id, colorID: color.wrappedValue.id)
                    }
                TextField("颜色名称（必填，如「绯红」）", text: color.name)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive) {
                    entry.colors.removeAll { $0.id == color.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("删除这个颜色（只影响当前类型）")
            }
            sizeChecklist(for: color)
        }
        .padding(.vertical, 2)
    }

    /// 可售尺码勾选：**只来自当前类型尺码表**，按尺码表原始顺序展示；
    /// 均码模式（无尺码表）不展示勾选。
    ///
    /// ## 勾选 vs 取消（2026-10-07 需求的「明确触发时机」）
    ///
    /// · **勾**：只有两个来源 —— ① 上面 `autoSelectSellableSizes()` 的**自动补齐**
    ///   （**仅**在这个颜色「一个有效尺码都没勾」时发生，见 `CatalogSizeSelectionPolicy`）；
    ///   ② 用户自己点某个尺码 / 点这里的「**全选**」。
    /// · **取消**：只有用户点得动（或点掉「全选」里的某一个）。
    ///   **自动补齐永远不会把取消过的尺码勾回来** —— 用户取消是显式意图。
    /// · 所以「尺码表后来新增了一个尺码、用户不想要它」这种情况，界面只**提示**
    ///   「还有 N 个没勾」+ 给一个「全选」按钮，绝不替用户决定。
    @ViewBuilder
    private func sizeChecklist(for color: Binding<OpsSeriesColorSKU>) -> some View {
        if entry.usesSizeChart, let chart = parsedChart {
            // 缺勾清单：判定在共享包，这里只负责显示（顺序 = 尺码表原始顺序）
            let missing = CatalogSizeSelectionPolicy.missing(
                color.wrappedValue.selectedSizes, allLabels: chart.sizeLabels)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("可售尺码（来自当前类型尺码表）").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    // 「全选」是**人的明确动作** → 唯一被允许覆盖手动取消的入口
                    //（与自动补齐恰好相反，别把两者合并成一个函数）
                    if !missing.isEmpty {
                        Text("还有 \(missing.count) 个没勾").font(.caption)
                            .foregroundStyle(OpsFlowPalette.warnOrange)
                        Button("全选") {
                            color.wrappedValue.selectedSizes =
                                CatalogSizeSelectionPolicy.selectAll(allLabels: chart.sizeLabels)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("把这张尺码表的 \(chart.sizeLabels.count) 个尺码全部勾上"
                              + "（取消过的尺码也会被重新勾上）")
                    }
                }
                // 勾选项顺序 = 尺码表原始顺序（绝不用无序集合遍历序）；
                // 尺码多时一行放不下 → 折成竖排（HStack 不换行会横向撑爆容器）
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach(chart.sizeLabels, id: \.self) { label in
                            sizeToggle(label, sizeLabels: chart.sizeLabels, for: color)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(chart.sizeLabels, id: \.self) { label in
                            sizeToggle(label, sizeLabels: chart.sizeLabels, for: color)
                        }
                    }
                }
            }
            .padding(.leading, 44)
        } else if entry.usesSizeChart {
            Text("尺码表还没有结构化内容：先在上方填写列与行，才能生成可售尺码勾选项。")
                .font(.caption).foregroundStyle(.orange)
                .padding(.leading, 44)
        } else {
            Text("无尺码/均码：不需要勾选尺码。")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 44)
        }
    }

    // MARK: 当前条目的校验结果（实时）

    @ViewBuilder
    private var issuesCard: some View {
        let issues = entryIssues
        if !issues.isEmpty {
            OpsCard(title: "这个类型还没有完成的部分", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues) { issue in
                        Label {
                            opsMarkdown(issue.message)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    // MARK: 小工具

    /// 单个可售尺码勾选项（保存时立即归一成尺码表原始顺序）
    private func sizeToggle(_ label: String,
                            sizeLabels: [String],
                            for color: Binding<OpsSeriesColorSKU>) -> some View {
        Toggle(label, isOn: Binding(
            get: { color.wrappedValue.selectedSizes.contains(label) },
            set: { isOn in
                var picked = color.wrappedValue.selectedSizes
                if isOn {
                    if !picked.contains(label) { picked.append(label) }
                } else {
                    picked.removeAll { $0 == label }
                }
                color.wrappedValue.selectedSizes = sizeLabels.filter { picked.contains($0) }
            }))
            .toggleStyle(.checkbox)
            .font(.callout)
    }

    private func assetFileLabel(_ asset: CatalogAsset) -> String {
        workspace.stagedFileURL(forReference: asset.originalURL)?.lastPathComponent
            ?? asset.originalURL.replacingOccurrences(of: "local:", with: "")
    }
}
