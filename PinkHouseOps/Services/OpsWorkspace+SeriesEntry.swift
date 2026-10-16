//
//  OpsWorkspace+SeriesEntry.swift
//  PinkHouseOps
//
//  「系列级多类型录入」的服务层：向导草稿持久化、图片导入、系列级提交。
//
//  ## 提交语义（需求 §S3-E / §S5，与仓库既有口径逐条对齐）
//
//  · **系列级一次提交，逐类型校验**：任何一个类型缺必填项 → 整次提交被拦下
//    （「不能假装全部完成」），错误逐条带类型名展示；
//  · **提交 = 把通过校验的条目写入本地草稿目录**（复用现有编辑命令：
//    addProduct / updateProduct / setSizeChart / addVariant / appendSaleEvent …），
//    **不新增绕过校验的写入口**（需求 §S5）；真正的发布仍走受控发布链路（导出待发布包 → 受控发布器）；
//  · **修正 ≠ 追加**：首次提交追加预约/现货销售记录；再次提交时若价格变了，
//    走「价格修正」（完整快照），绝不再追加一条历史；
//  · **失败不丢输入**：向导工作副本独立持久化（`seriesEntryJSON`），
//    提交失败时所有已填内容原样保留。
//
//  ## 向导草稿为什么单独持久化
//
//  需求 §S3-E：「保存草稿」保存整个系列及其已选类型的当前状态，**包括未完成类型**。
//  未完成类型还不能映射成 CatalogProduct（会污染目录、发布门禁会拦），
//  所以它住在这份独立的 JSON 里，随 `OpsCatalogDraftRecord` 一起落盘。
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - 提交结果

/// 单个类型条目的提交结果（S5：每个类型的成功/失败状态必须分别可见）
struct OpsSeriesEntryCommitEntryResult: Identifiable, Equatable {
    let id: String
    let entryName: String
    let ok: Bool
    let message: String
}

/// 一次系列级提交的完整报告
struct OpsSeriesEntryCommitReport: Equatable {
    /// 校验拦下的全部问题（非空 = 一个字都没写进目录）
    var blockedByValidation: [OpsSeriesEntryIssue] = []
    /// 逐条目结果（写入口径阶段的成功/失败）
    var entryResults: [OpsSeriesEntryCommitEntryResult] = []
    /// 提交后确认的店家 id（S1「＋ 新建店家」落库后回填）
    var shopID: String?
    /// 提交后确认的系列 id
    var seriesID: String?
    /// 草稿是否落盘成功
    var draftSaved: Bool = true
    /// S2 系列价格表写回失败的原因（nil = 没写、或写成功）。
    /// 与逐条目结果**并列展示** —— 不能因为它挂在系列级就悄悄吞掉。
    var priceChartError: String?

    var blocked: Bool { !blockedByValidation.isEmpty }
    var allOK: Bool {
        !blocked && !entryResults.isEmpty && entryResults.allSatisfy(\.ok)
            && draftSaved && priceChartError == nil
    }
}

// MARK: - 向导草稿持久化

extension OpsWorkspace {

    /// 仅在运营切换系列时载入团次，恢复草稿或视图重建不覆盖未提交输入。
    func selectSeriesForEntry(_ seriesID: String) {
        let series = catalog.series.first { $0.id == seriesID }
        seriesEntry.seriesID = seriesID
        seriesEntry.reservationBatches = series?.reservationBatches
        seriesEntry.phase = series?.salePhase
        seriesEntry.hasReservationEnd = series?.reservationEndAt != nil
        if let end = series?.reservationEndAt { seriesEntry.reservationEndAt = end }
        seriesEntry.hasBalanceStart = series?.balanceDueKind == .exact && series?.balanceDueAt != nil
        if let start = series?.balanceDueAt { seriesEntry.balanceStartAt = start }
        seriesEntry.hasBalanceEnd = series?.balanceDueKind == .exact && series?.balanceDueEndAt != nil
        if let end = series?.balanceDueEndAt { seriesEntry.balanceEndAt = end }
    }

    /// 复制当前表单原文，不重新解析价格/尺码，也不复制已提交商品的身份。
    /// 先把原条目和副本一起保存，成功后才插入列表并交给界面选中。
    func duplicateSeriesTypeEntry(id: String) -> String? {
        guard canMutate(),
              let index = seriesEntry.typeEntries.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = seriesEntry.typeEntries[index]
        copy.id = UUID().uuidString
        for colorIndex in copy.colors.indices { copy.colors[colorIndex].id = UUID().uuidString }
        copy.committedProductID = nil
        copy.lastCommitOK = nil
        var updated = seriesEntry
        updated.typeEntries.insert(copy, at: index + 1)
        guard saveSeriesEntryEdit(updated, success: "已复制款式「\(copy.displayName)」，可直接修改副本。",
                                  failure: "复制款式保存失败，原内容已保留") else { return nil }
        return copy.id
    }

    /// 删除只按当前行的独立身份执行一次；同名、同类型及共用图片不参与匹配。
    @discardableResult
    func removeSeriesTypeEntry(id: String) -> Bool {
        guard canMutate(),
              let index = seriesEntry.typeEntries.firstIndex(where: { $0.id == id }) else { return false }
        var updated = seriesEntry
        let removed = updated.typeEntries.remove(at: index)
        return saveSeriesEntryEdit(updated, success: "已删除款式「\(removed.displayName)」的草稿条目。",
                                   failure: "删除款式保存失败，原条目已保留")
    }

    /// 对应 List.onMove 的插入位置语义。先持久化，保存失败时界面保持原顺序。
    @discardableResult
    func moveSeriesTypeEntries(fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
        guard canMutate(), !source.isEmpty,
              source.allSatisfy({ seriesEntry.typeEntries.indices.contains($0) }),
              (0...seriesEntry.typeEntries.count).contains(destination) else { return false }
        var updated = seriesEntry
        let moving = source.map { updated.typeEntries[$0] }
        for index in source.reversed() { updated.typeEntries.remove(at: index) }
        let insertionIndex = destination - source.filter { $0 < destination }.count
        updated.typeEntries.insert(contentsOf: moving, at: insertionIndex)
        guard updated != seriesEntry else { return true }
        return saveSeriesEntryEdit(updated, success: "款式顺序已保存。",
                                   failure: "排序保存失败，原顺序已保留")
    }

    /// 拖放使用独立行身份定位，插入位置由 List 的放置标记确定。
    @discardableResult
    func moveSeriesTypeEntry(id: String, toOffset destination: Int) -> Bool {
        guard let source = seriesEntry.typeEntries.firstIndex(where: { $0.id == id }) else { return false }
        return moveSeriesTypeEntries(fromOffsets: IndexSet(integer: source),
                                     toOffset: destination)
    }

    private func saveSeriesEntryEdit(_ updated: OpsSeriesEntryDraft, success: String, failure: String) -> Bool {
        guard let draft else { return false }
        let previousJSON = draft.seriesEntryJSON
        do {
            draft.seriesEntryJSON = try ShopCatalogJSONCoding.encoder().encode(updated)
            try saveCatalogContext(context)
        } catch {
            draft.seriesEntryJSON = previousJSON
            lastError = "\(failure)：\(error.localizedDescription)"
            return false
        }
        seriesEntry = updated
        lastError = nil
        statusMessage = success
        return true
    }

    /// 把向导工作副本写进当前草稿记录。**与目录内容分开保存**：
    /// 未完成类型不能进目录，但必须能恢复。
    func persistSeriesEntryState() {
        guard let draft, !draft.isCorrupted else { return }
        do {
            draft.seriesEntryJSON = try ShopCatalogJSONCoding.encoder().encode(seriesEntry)
            try context.save()
        } catch {
            // 持久化失败只报告，不清空内存副本 —— 输入绝不因为落盘失败而丢
            lastError = "向导草稿保存失败（界面上的内容仍在，不会丢）：\(error.localizedDescription)"
        }
    }

    /// 从草稿记录装载向导工作副本（nil / 解不开 = 空白向导，绝不报错打断启动）
    func loadSeriesEntryState() {
        guard let draft, let data = draft.seriesEntryJSON, !data.isEmpty else {
            seriesEntry = OpsSeriesEntryDraft()
            return
        }
        if let decoded = try? ShopCatalogJSONCoding.decoder()
            .decode(OpsSeriesEntryDraft.self, from: data) {
            // 「从 iOS 恢复」等整包导入会把目录整个换掉，持久化的店家/系列指针
            // 可能已经指向不存在的东西 —— 指着空气的 selection 会让 Picker
            // 每次刷新都报 "selection is invalid"，提交也会把内容挂到悬空 id 上。
            // 向导是短期工作副本：店家没了就整体重开；店家在、系列没了就保留
            // 店家清空系列级字段，不保留半截状态。
            let shopExists = catalog.shops.contains(where: { $0.id == decoded.shopID })
            let seriesExists = catalog.series.contains(where: { $0.id == decoded.seriesID })
            if decoded.createsNewShop || decoded.shopID.isEmpty {
                seriesEntry = decoded
            } else if !shopExists {
                seriesEntry = OpsSeriesEntryDraft()
            } else if !decoded.seriesID.isEmpty && !seriesExists {
                seriesEntry = OpsSeriesEntryDraft(shopID: decoded.shopID)
            } else {
                seriesEntry = decoded
            }
        } else {
            // 解不开就重新开始：向导是短期工作副本，不值得为它做隔离态；
            // 但旧字节留在记录里不覆盖（与 R03 同一个「不毁证据」原则）
            seriesEntry = OpsSeriesEntryDraft()
        }
    }

    /// 显式「写入草稿」完成后准备下一份系列。发布前的内部提交不能清空，
    /// 因为网络失败还要用原表单修正和重试。
    func saveSeriesEntryToDraft() -> OpsSeriesEntryCommitReport {
        var report = commitSeriesEntry()
        guard report.allOK else { return report }
        if !storeSubmittedSeriesDraft(report: report) {
            report.draftSaved = false
        } else {
            statusMessage = "系列已存入「发布草稿箱」，可在那里发布；已为下一份系列准备空白表单。"
        }
        return report
    }

    /// 先持久化空白表单，再改变界面。后台发布期间新填的内容及切换后的
    /// 其它草稿不属于这次完成操作，必须保留。
    @discardableResult
    func finishSeriesEntry(expected: OpsSeriesEntryDraft, draftID: String?) -> Bool {
        guard let draft, draft.id == draftID, !draft.isCorrupted,
              seriesEntry == expected else { return false }
        let previousJSON = draft.seriesEntryJSON
        let empty = OpsSeriesEntryDraft()
        do {
            draft.seriesEntryJSON = try ShopCatalogJSONCoding.encoder().encode(empty)
            try saveCatalogContext(context)
            seriesEntry = empty
            seriesEntryResetID = UUID()
            return true
        } catch {
            draft.seriesEntryJSON = previousJSON
            lastError = "系列已保存，但空白表单保存失败；已保留填写内容：\(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - S3：可售尺码的自动勾选（2026-10-07 用户需求）

extension OpsWorkspace {

    /// 把某个类型条目的「可售尺码」补齐到当前尺码表（**幂等**）。
    ///
    /// ## 规则（唯一一份，在共享包 `CatalogSizeSelectionPolicy`）
    ///
    /// · 该颜色**一个有效尺码都没勾** → 补齐为整张尺码表（按尺码表原始顺序）；
    /// · 已经勾了一部分 → **一个字都不动**（那是用户手动取消的结果）；
    /// · 顺带把「上一张尺码表留下的旧标签」归一掉。
    ///
    /// ## 为什么判定写在共享包、写回写在这里
    ///
    /// 判定要能被 `swift test` 秒级验证；写回要能被**视图层与快照 harness 共用** ——
    /// harness 在真 App 里调它、把结果拍成图，于是「自动勾选到底会不会发生」
    /// 有一份跑得起来、看得见的证据，而不是只写在视图的某个 `onChange` 里。
    ///
    /// ## 为什么不放在 body / onAppear 里「每次渲染对账」
    ///
    /// 两个理由：① 在 body 里改 `@Published` 会变成无限刷新；
    /// ② 幂等规则虽然不怕重复调用，但「什么时候该发生」必须**可解释** ——
    /// 运营问「为什么这几个尺码被勾上了」，答案得是一句话，不是一个渲染时机。
    /// 所以调用点全部是**明确的人的动作**（见 `OpsSeriesWizardTypeEditorView`）。
    ///
    /// - Returns: 本次**真的改动过**的颜色数（0 = 无需补齐）。
    @discardableResult
    func autoSelectSellableSizes(entryID: String) -> Int {
        guard let index = seriesEntry.typeEntries.firstIndex(where: { $0.id == entryID }) else {
            return 0
        }
        let entry = seriesEntry.typeEntries[index]
        guard entry.usesSizeChart, let chart = OpsSeriesSizeChartParsing.parse(entry: entry).chart else {
            return 0
        }
        var colors = entry.colors
        var changed = 0
        for colorIndex in colors.indices {
            let filled = CatalogSizeSelectionPolicy.autoFilled(
                colors[colorIndex].selectedSizes, allLabels: chart.sizeLabels)
            if filled != colors[colorIndex].selectedSizes {
                colors[colorIndex].selectedSizes = filled
                changed += 1
            }
        }
        // 一次写回：逐个写会触发 N 次草稿防抖持久化，且中途状态会被渲染出去
        if changed > 0 {
            seriesEntry.typeEntries[index].colors = colors
        }
        return changed
    }
}

// MARK: - 单图导入（封面 / 颜色图 / 尺码表原图）

extension OpsWorkspace {

    /// 导入一张图并返回 CatalogAsset id（失败返回 nil，原因在 `lastError`）。
    /// 复用与既有导入完全相同的规范化 + staging 路径（不另写第二套）。
    @discardableResult
    func importSingleImage(from url: URL) -> String? {
        guard canMutate() else { return nil }
        do {
            let assetID = try stageImageAsset(from: url)
            markDirty()
            let saved = saveImportedImageHistory([(assetID, url.lastPathComponent)])
            if !saved {
                lastError = "图片已导入，但上传历史落盘失败：" + (lastError ?? "未知原因")
                return nil
            } else {
                lastError = nil
                statusMessage = "已导入图片（\(url.lastPathComponent)）"
            }
            return assetID
        } catch let error as ShopCatalogMediaStagingError {
            lastError = "图片导入失败（\(url.lastPathComponent)）：\(error.errorDescription ?? "无法处理")"
            return nil
        } catch {
            lastError = "图片导入失败（\(url.lastPathComponent)）：\(error.localizedDescription)"
            return nil
        }
    }

    /// 更换原图必须把稳定款式 ID 的绑定立即保存，不能只保存素材、再依赖视图绑定和防抖写盘。
    @discardableResult
    func replaceSeriesSizeChartImage(entryID: String, from url: URL, expectedDraftID: String) -> Bool {
        guard canMutate() else { return false }
        guard draft?.id == expectedDraftID,
              seriesEntry.typeEntries.contains(where: { $0.id == entryID }) else {
            lastError = "草稿或款式已变化，原尺码表图片保留，请重新打开当前款式后更换。"
            return false
        }
        guard let assetID = importSingleImage(from: url) else { return false }
        return setSeriesSizeChartImage(entryID: entryID, assetID: assetID)
    }

    /// 上传与选择已有素材共用同一保存入口；失败保留原绑定、表格和尺码勾选。
    @discardableResult
    func setSeriesSizeChartImage(entryID: String, assetID: String?) -> Bool {
        guard canMutate() else { return false }
        guard let index = seriesEntry.typeEntries.firstIndex(where: { $0.id == entryID }) else {
            lastError = "当前款式已不存在，原尺码表图片未改动。"
            return false
        }
        if let assetID, asset(for: assetID) == nil {
            lastError = "所选尺码表图片已不存在，原图保留，请重新选择。"
            return false
        }
        var updated = seriesEntry
        updated.typeEntries[index].chartSourceImageAssetID = assetID
        // 复用可售尺码政策，仅补齐尚未选择有效尺码的颜色，手动取消结果保持原样。
        if assetID != nil, updated.typeEntries[index].usesSizeChart,
           let chart = OpsSeriesSizeChartParsing.parse(entry: updated.typeEntries[index]).chart {
            for colorIndex in updated.typeEntries[index].colors.indices {
                updated.typeEntries[index].colors[colorIndex].selectedSizes = CatalogSizeSelectionPolicy.autoFilled(
                    updated.typeEntries[index].colors[colorIndex].selectedSizes, allLabels: chart.sizeLabels)
            }
        }
        return saveSeriesEntryEdit(updated,
            success: assetID == nil ? "已清除当前款式的尺码表原图并保存。" : "已更换当前款式的尺码表原图并保存。",
            failure: "尺码表图片绑定保存失败，原图已保留")
    }

    /// 批量导入共用单图的规范化入口，整批保存一次；失败原因逐文件保留。
    func importColorImages(from urls: [URL]) async -> (assetIDs: [String], names: [String: String], failures: [String]) {
        guard canMutate() else { return ([], [:], [lastError ?? "草稿不可编辑。"]) }
        let directory = stagingDirectory
        let draftID = draft?.id
        var ids: [String] = []
        var names: [String: String] = [:]
        var failures: [String] = []
        for url in urls {
            do {
                let staged = try await Task.detached(priority: .userInitiated) {
                    try Self.stageImageMedia(from: url, directory: directory)
                }.value
                guard draft?.id == draftID, canEdit else {
                    failures.append("草稿已变化，停止导入，请重新打开批量配图。")
                    break
                }
                upsertAsset(for: staged)
                let id = "asset-\(String(staged.mediaKey.prefix(12)))"
                if !ids.contains(id) { ids.append(id) }
                names[id] = url.lastPathComponent
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        if !ids.isEmpty, draft?.id == draftID, canEdit {
            markDirty()
            if !saveImportedImageHistory(ids.map { ($0, names[$0] ?? $0) }) {
                failures.append(lastError ?? "图片已导入，但上传历史保存失败。")
            }
        }
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        statusMessage = "已导入 \(ids.count) 张图片，请为颜色分配图片后确认。"
        return (ids, names, failures)
    }

    private func stageImageAsset(from url: URL) throws -> String {
        let staged = try Self.stageImageMedia(from: url, directory: stagingDirectory)
        upsertAsset(for: staged)
        return "asset-\(String(staged.mediaKey.prefix(12)))"
    }

    private nonisolated static func stageImageMedia(
        from url: URL, directory: URL
    ) throws -> ShopCatalogMediaStaging.StagedMedia {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let staged = try ShopCatalogMediaStaging.stage(Data(contentsOf: url))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(staged.fileName)
        if !FileManager.default.fileExists(atPath: target.path) {
            try staged.data.write(to: target, options: .atomic)
        }
        return staged
    }

    @discardableResult
    func applyColorImages(entryID: String, colorIDs: Set<String>, assignments: [String: String]) -> Bool {
        guard canMutate() else { return false }
        guard let index = seriesEntry.typeEntries.firstIndex(where: { $0.id == entryID }),
              Set(assignments.values).isSubset(of: Set(catalog.assets.map(\.id))) else {
            lastError = "当前类型或所选图片已不存在，请重新打开批量配图。"
            return false
        }
        var updated = seriesEntry.typeEntries[index]
        guard updated.applyColorImages(colorIDs: colorIDs, assignments: assignments) else {
            lastError = "颜色列表已变化，请重新打开批量配图。"
            return false
        }
        seriesEntry.typeEntries[index] = updated
        lastError = nil
        persistSeriesEntryState()
        guard lastError == nil else { return false }
        statusMessage = "已保存「\(updated.displayName)」的颜色配图。"
        return true
    }
}

// MARK: - 价格表原图（S2）

extension OpsWorkspace {

    /// 价格表原图**允许**的文件类型。
    ///
    /// ⭐ 界面上的「支持 PNG / JPEG / …」提示、文件选择器的过滤器、
    /// 以及导入前的那道格式校验**共用这一份** —— 三处各写一遍就会出现
    /// 「说明里写了支持、实际却被拦」这种最让人上火的错。
    static let priceChartFileTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .bmp]

    /// 给用户看的格式清单（从 `priceChartFileTypes` 派生，不手打）
    static var priceChartFileFormatList: String {
        priceChartFileTypes.map(\.preferredFilenameExtension).compactMap { $0?.uppercased() }
            .joined(separator: " / ")
    }

    /// 文件选择器**允许选中**的类型。
    ///
    /// 刻意比 `priceChartFileTypes` 宽：把 PDF / 表格 / 文本也放进来，
    /// 是为了让「选错了」能得到一句**可执行的拒绝**，而不是在系统面板里灰掉一整片文件 ——
    /// 很多人是拿 Excel 排好价格表再导出的，灰掉只会让人以为「这个功能坏了」。
    /// 选中后由 `isSupportedPriceChartFile` 拦下，逐条说明「只能是图片，不支持文档」。
    static let priceChartPickerTypes: [UTType] =
        priceChartFileTypes + [.pdf, .spreadsheet, .commaSeparatedText, .plainText]

    /// 这个文件看起来是不是一张可用的价格表原图（**只看类型，不看内容**）。
    ///
    /// 为什么要有这一步：`ShopCatalogMediaStaging` 对非图片只会说
    /// 「不是 ImageIO 能解码的图片数据（N 字节）」—— 对着一张 `.pdf` 说这句，
    /// 用户读完不知道自己该换什么格式。先按类型拦一次，才能给出**可执行**的话。
    static func isSupportedPriceChartFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return priceChartFileTypes.contains { type.conforms(to: $0) }
    }

    /// 批量导入价格表原图（S2 的文件选择 / 拖入都走这里）。
    ///
    /// 口径（三条都是刻意的）：
    ///  · **逐张复用 `importSingleImage`** —— 规范化、内容寻址、写 staging、
    ///    落草稿、报错全部是同一条路径，不另写第二套导入；
    ///  · **一个文件失败不中断其余的** —— 选 5 张、坏 1 张，另外 4 张照样进；
    ///    这与「逐条目结果」是同一个口径（不能把部分失败折成一句「上传失败」）；
    ///  · **返回按选择顺序的 asset id** —— 价格表的 `sourceImage` 恒取首图，
    ///    顺序是有意义的，不许用集合重排。
    ///
    /// 失败原因取自 `lastError`（类型不符 / staging 报的原文），
    /// **不在这里另编一套措辞** —— 否则同一个原因在两张嘴上说两遍，早晚分叉。
    @discardableResult
    func importPriceChartImages(from urls: [URL]) -> (assetIDs: [String], failures: [String]) {
        var assetIDs: [String] = []
        var failures: [String] = []
        for url in urls {
            guard Self.isSupportedPriceChartFile(url) else {
                failures.append("\(url.lastPathComponent)：格式不支持。"
                    + "价格表原图只能是图片（\(Self.priceChartFileFormatList)），"
                    + "不支持 PDF、Excel、Word 等文档。")
                continue
            }
            // 上一张的失败原因必须先清掉，否则这一张成功时会误报上一张的错
            lastError = nil
            if let assetID = importSingleImage(from: url) {
                assetIDs.append(assetID)
            } else {
                failures.append("\(url.lastPathComponent)：\(lastError ?? "导入失败，原因未知。")")
            }
        }
        return (assetIDs, failures)
    }

    /// 把「选择 / 拖入」的图片追加进向导的价格表原图列表（**追加，不替换**）。
    ///
    /// 返回给界面的三类结果必须分开（仓库铁律：
    /// 「点了没反应」和「失败了」不是一回事，「全失败」和「部分失败」也不是）：
    ///   · 成功张数 + 是否有失败；
    ///   · 失败逐条原文（界面要逐条列出来，不许折成「上传失败」一句话）。
    @discardableResult
    func appendPriceChartImages(from urls: [URL])
        -> (addedCount: Int, failures: [String]) {
        let outcome = importPriceChartImages(from: urls)
        var ids = seriesEntry.priceChartImageAssetIDs
        for id in outcome.assetIDs where !ids.contains(id) {
            ids.append(id)
        }
        seriesEntry.priceChartImageAssetIDs = ids

        // 顶部横幅只说一句汇总；**逐条原因由界面就地列出来**
        //（那里才是用户点按钮的位置）。但「全部失败」必须升级成 lastError，
        // 否则横幅会显示上一张成功导入的绿字，看起来像成功。
        let added = outcome.assetIDs.count
        if added > 0, outcome.failures.isEmpty {
            lastError = nil
            statusMessage = "已上传 \(added) 张价格表原图（价格表原图共 "
                + "\(seriesEntry.priceChartImageAssetIDs.count) 张）。"
        } else if added > 0 {
            statusMessage = "已上传 \(added) 张价格表原图；"
                + "另有 \(outcome.failures.count) 个文件没上传成功（原因见价格表卡片）。"
            lastError = statusMessage
        } else if !outcome.failures.isEmpty {
            statusMessage = nil
            lastError = "价格表原图上传失败：" + outcome.failures.joined(separator: "；")
        }
        return (added, outcome.failures)
    }

    /// 从向导价格表原图列表里移除一张（**只解除关联，不删文件**）。
    ///
    /// 为什么不连文件一起删：同一张图可能被商品图、系列封面或别的草稿引用着，
    /// 「在这里取消勾选」的意思只能是「这张图不再是价格表原图」。
    /// 真正的孤儿文件清理另有入口（草稿孤立素材）。
    func removePriceChartImage(assetID: String) {
        seriesEntry.priceChartImageAssetIDs.removeAll { $0 == assetID }
    }

    // MARK: 提交写回

    /// S2 系列价格表 → 系列（提交的一部分）。
    ///
    /// ⚠️ 仅当 `declaresPriceChart` 打开时才动价格表；关着**一个字都不写**。
    /// 这是本仓库对「一次编辑只写它负责的字段」的既有口径：
    /// 合成一个「保存」，就会出现「我只是改了个档期，结果价格表被清空了」。
    ///
    /// 三种可提交形态（`OpsSeriesPriceChartValidation` 已经先拦掉了其它情况）：
    ///   · 结构化列行 +（可选）原图；
    ///   · 只有原图（`hasStructuredContent == false`，客户端退化成展示原图）；
    ///   · 只有结构化列行（纯表格，无图）。
    @discardableResult
    func applySeriesPriceChartFromWizard(seriesID: String) -> Bool {
        guard seriesEntry.declaresPriceChart else { return true }

        let parsed = seriesEntry.parsedPriceChart.parsed
        let images = seriesEntry.priceChartImageAssetIDs
        guard parsed != nil || !images.isEmpty else {
            // 上面那道校验会先拦下这种状态；这里再挡一次是为了「绝不用空表覆盖已有价格表」
            lastError = "系列价格表既没有结构化列行、也没有原图，已跳过（未改动系列上已有的价格表）。"
            return false
        }
        let ok = updateSeriesPriceChart(
            seriesID: seriesID,
            unit: seriesEntry.priceChartUnit,
            columns: parsed?.columns ?? [],
            rows: parsed?.rows ?? [],
            sourceImages: images)
        if !ok {
            lastError = "系列价格表写入失败：" + (lastError ?? "未知原因")
        }
        return ok
    }
}

// MARK: - 系列级提交

extension OpsWorkspace {

    /// 系列级提交（S5）。返回完整报告；**调用方必须展示逐条目结果**，
    /// 不能把它折成一句「成功」。
    @discardableResult
    func commitSeriesEntry() -> OpsSeriesEntryCommitReport {
        var report = OpsSeriesEntryCommitReport()

        // ── 第一关：全量校验（任何类型缺必填项 → 整次拦截，不写任何内容）──
        let issues = OpsSeriesEntryValidator.validate(seriesEntry, catalog: catalog)
        guard issues.isEmpty else {
            report.blockedByValidation = issues
            lastError = "系列级提交被校验拦下（\(issues.count) 条），没有写入任何内容。"
                + "逐条问题见下方列表；所有已填内容都保留在向导里。"
            return report
        }

        guard canMutate() else {
            report.blockedByValidation = [OpsSeriesEntryIssue(
                entryID: nil, entryName: "", message: "草稿处于只读隔离状态，不能提交。")]
            return report
        }

        // ── 店家：新建或沿用（S1「＋ 新建店家」的决议在这里落定）──
        // 店家必须先于系列存在（系列的 shopID 外键），所以它的落库排在最前。
        var shopID = seriesEntry.shopID
        if seriesEntry.createsNewShop {
            let aliases = seriesEntry.newShopAliasesText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard let newShopID = addShopReturningID(
                name: seriesEntry.newShopName, aliases: aliases) else {
                report.blockedByValidation = [OpsSeriesEntryIssue(
                    entryID: nil, entryName: "", message: "新建店家失败：" + (lastError ?? "未知原因"))]
                return report
            }
            shopID = newShopID
            // 回写决议结果：再点一次提交不会再建一个同名店家
            seriesEntry.shopID = newShopID
            seriesEntry.createsNewShop = false
        }
        report.shopID = shopID
        if seriesEntry.managesShopLogo,
           !updateShopLogo(id: shopID, reference: seriesEntry.shopLogoReference) {
            report.blockedByValidation = [OpsSeriesEntryIssue(
                entryID: nil, entryName: "", message: lastError ?? "店家 Logo 保存失败。")]
            return report
        }

        // ── 系列：新建或选用（S1 的决议在这里落定）──
        var seriesID = seriesEntry.seriesID
        if seriesID.isEmpty {
            let year = Int(seriesEntry.newSeriesYearText.trimmingCharacters(in: .whitespacesAndNewlines))
            let month = Int(seriesEntry.newSeriesMonthText.trimmingCharacters(in: .whitespacesAndNewlines))
            let season = seriesEntry.newSeriesSeason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let newID = addSeriesReturningID(
                shopID: shopID,
                name: seriesEntry.newSeriesName,
                year: year, month: month,
                season: season.isEmpty ? nil : season) else {
                report.blockedByValidation = [OpsSeriesEntryIssue(
                    entryID: nil, entryName: "", message: "新建系列失败：" + (lastError ?? "未知原因"))]
                return report
            }
            seriesID = newID
            seriesEntry.seriesID = newID
        }
        report.seriesID = seriesID

        // ── S2：系列资料（只写向导管理的字段，未管理的字段原样保留）──
        guard applySeriesPhaseFromWizard(seriesID: seriesID) else {
            report.blockedByValidation = [OpsSeriesEntryIssue(
                entryID: nil, entryName: "", message: lastError ?? "团次与尾款时间保存失败。",
                area: .seriesProfile)]
            return report
        }
        if let coverID = seriesEntry.coverAssetID {
            _ = updateSeriesCover(seriesID: seriesID, assetID: coverID)
        }
        // S2 价格表：开关关着时这个调用是空操作（一个字都不写）。
        // 失败原因**立刻取走**：后面的逐条目提交会覆盖 `lastError`。
        if !applySeriesPriceChartFromWizard(seriesID: seriesID) {
            report.priceChartError = lastError ?? "系列价格表写入失败。"
        }

        // ── 逐类型提交（每个类型复用同一条商品写入链路）──
        for index in seriesEntry.typeEntries.indices {
            let result = commitEntry(at: index, shopID: shopID, seriesID: seriesID)
            report.entryResults.append(result)
            seriesEntry.typeEntries[index].lastCommitOK = result.ok
        }

        // ── 落盘（R02：保存失败绝不报告成功）──
        let saved = saveDraft()
        report.draftSaved = saved
        persistSeriesEntryState()

        if report.allOK {
            let okCount = report.entryResults.count
            statusMessage = "系列级提交完成：\(okCount) 个类型已写入草稿（第 \(currentRevision) 版）。"
                + "发布请走受控发布链路——公共 CloudKit 上架状态以回读确认为准。"
            lastError = nil
        } else if !saved {
            lastError = "部分或全部类型已写入内存，但草稿落盘失败（内容仍在界面上）："
                + report.entryResults.filter { !$0.ok }.map(\.message).joined(separator: "；")
        } else if let priceChartError = report.priceChartError {
            // 价格表失败也要出声：条目全 OK 但价格表没写进去时，
            // 只报「系列级提交完成」就是谎报。
            lastError = priceChartError
        } else {
            let failed = report.entryResults.filter { !$0.ok }
            lastError = failed.map { "\($0.entryName)：\($0.message)" }.joined(separator: "\n")
        }
        return report
    }

    /// 提交一个类型条目。返回结果与定位信息；**单条失败不中断其他条目**。
    private func commitEntry(
        at index: Int, shopID: String, seriesID: String
    ) -> OpsSeriesEntryCommitEntryResult {
        let entry = seriesEntry.typeEntries[index]
        var messages: [String] = []

        // 1) 商品本体：已有（上次提交过）→ 更新；没有 → 新建
        var productID: String
        if let existingID = entry.committedProductID,
           catalog.products.contains(where: { $0.id == existingID }) {
            // 名称/归属：只在变化时写（updateProduct 的改名守卫仍会拦已上线的改名）
            if let existing = catalog.products.first(where: { $0.id == existingID }) {
                if existing.name != entry.designName || existing.category != entry.category
                    || existing.seriesID != seriesID || existing.shopID != shopID {
                    if !updateProduct(
                        id: existingID, shopID: shopID, seriesID: seriesID,
                        name: entry.designName, category: entry.category) {
                        messages.append("更新商品失败：" + (lastError ?? "未知原因"))
                    }
                }
            }
            productID = existingID
        } else {
            guard let newID = addProductReturningID(
                shopID: shopID, seriesID: seriesID,
                name: entry.designName, category: entry.category) else {
                return OpsSeriesEntryCommitEntryResult(
                    id: entry.id, entryName: entry.displayName,
                    ok: false, message: "新建商品失败：" + (lastError ?? "未知原因"))
            }
            productID = newID
        }

        // 2) 款式名（designName）。描述**不写**：本流程不新增「款式描述」，
        //    也不清空历史数据里已有的描述（需求 §S3-A 兼容边界）。
        if let pIndex = catalog.products.firstIndex(where: { $0.id == productID }) {
            let existingDescription = catalog.products[pIndex].description
            if catalog.products[pIndex].designName != entry.designName
                || catalog.products[pIndex].description != existingDescription {
                if !updateProductDetail(
                    id: productID, description: existingDescription, designName: entry.designName) {
                    messages.append("写款式名失败：" + (lastError ?? "未知原因"))
                }
            }
        }

        // 3) 尺码表（归属当前类型；不与其他类型共用）
        let parsedChart = OpsSeriesSizeChartParsing.parse(entry: entry)
        if entry.usesSizeChart, let chart = parsedChart.chart {
            if !setSizeChart(
                productID: productID,
                unit: chart.unit,
                columns: chart.columns,
                rows: chart.rows,
                sourceImage: entry.chartSourceImageAssetID,
                allowShrinkingUsedSizes: true) {
                messages.append("写尺码表失败：" + (lastError ?? "未知原因"))
            }
        }

        // 4) 颜色 SKU：整体重建（向导条目是这些规格的唯一管理者）。
        //    先删后加；尺码取自**当前类型尺码表**并按其原始顺序（校验已保证非空/合法）。
        catalog.variants.removeAll { $0.productID == productID }
        markDirty()
        var variantFailures: [String] = []
        for color in entry.colors.filter({ OpsSeriesSizeChartParsing.normalized($0.name) != nil }) {
            let sizes = OpsSeriesEntryValidator.variantSizes(for: color, chart: parsedChart.chart)
            for size in sizes {
                if !addVariant(
                    productID: productID,
                    color: size.color,
                    size: size.size,
                    imageAssetID: color.imageAssetID) {
                    variantFailures.append(size.color + (size.size.map { " / \($0)" } ?? "")
                        + "：" + (lastError ?? "未知原因"))
                }
            }
        }
        if !variantFailures.isEmpty {
            messages.append("部分规格写入失败：" + variantFailures.joined(separator: "；"))
        }

        // 5) 商品图 = 颜色图片（按颜色顺序去重）。没有颜色图时**不动**已有商品图。
        let colorImages = entry.colors.compactMap(\.imageAssetID)
        var seenImages: Set<String> = []
        let orderedImages = colorImages.filter { seenImages.insert($0).inserted }
        if !orderedImages.isEmpty {
            if !bindImages(orderedImages, toProduct: productID) {
                messages.append("绑定商品图失败：" + (lastError ?? "未知原因"))
            }
        }

        // 6) 价格：首次提交 → 追加预约/现货销售记录（append-only 口径）；
        //    再次提交且价格变化 → 价格修正（完整快照，修正 ≠ 追加）。
        let price = OpsSeriesPriceParsing.parse(entry: entry).price
        let hasAnySaleEvent = !catalog.saleEvents.filter { $0.productID == productID }.isEmpty
        if !hasAnySaleEvent {
            if let reservation = price.reservation {
                if !appendSaleEvent(
                    productID: productID, type: .reservation,
                    price: reservation, deposit: price.deposit, balance: price.balance,
                    currency: price.currency, startAt: nil, endAt: nil, batchLabel: nil) {
                    messages.append("写预约价失败：" + (lastError ?? "未知原因"))
                }
            }
            if let stock = price.stock {
                if !appendSaleEvent(
                    productID: productID, type: .stock,
                    price: stock, deposit: nil, balance: nil,
                    currency: price.currency, startAt: nil, endAt: nil, batchLabel: nil) {
                    messages.append("写现货价失败：" + (lastError ?? "未知原因"))
                }
            }
        } else {
            // 「有历史再改价走价格修正」的判定：任一当前值与本次录入不同，或既有
            // 记录币种不明（unknown）而本次声明了币种。既有记录币种明确且一致时不判变。
            let archive = priceArchive(forProduct: productID)
            let valuesChanged =
                archive?.currentReservationPrice != price.reservation
                || archive?.currentDeposit != price.deposit
                || archive?.currentBalance != price.balance
                || archive?.currentStockPrice != price.stock
            let currencyChanged: Bool = {
                guard let existing = archive?.currentCurrency else { return false }
                if existing.isUnknown { return price.currency != .unknown }
                return price.currency != .unknown && existing != price.currency
            }()
            if valuesChanged || currencyChanged {
                if !applyPriceCorrection(
                    productID: productID,
                    reservationPrice: price.reservation,
                    stockPrice: price.stock,
                    deposit: price.deposit,
                    balance: price.balance,
                    currency: price.currency.isUnknown ? nil : price.currency) {
                    messages.append("价格修正失败：" + (lastError ?? "未知原因"))
                }
            }
        }

        // 7) 记住映射：下次提交更新而不是再建一个
        seriesEntry.typeEntries[index].committedProductID = productID

        if messages.isEmpty {
            return OpsSeriesEntryCommitEntryResult(
                id: entry.id, entryName: entry.displayName, ok: true,
                message: "已写入草稿（商品 \(productID)）")
        }
        return OpsSeriesEntryCommitEntryResult(
            id: entry.id, entryName: entry.displayName, ok: false,
            message: messages.joined(separator: "；"))
    }

    // MARK: S2 系列资料

    /// 把向导 S2 的发售阶段写进系列。**只写向导管理的字段**：
    /// 预约开始时间、大致尾款描述等 S2 没有的字段，保留系列上已有值。
    private func applySeriesPhaseFromWizard(seriesID: String) -> Bool {
        guard let series = catalog.series.first(where: { $0.id == seriesID }) else { return false }
        let phase = seriesEntry.phase

        // 尾款区间：向导填了具体时间 → exact；一个都没填 → 保留系列已有值
        let batches = seriesEntry.reservationBatches ?? series.reservationBatches ?? []
        let declaresBalance = batches.isEmpty && (seriesEntry.hasBalanceStart || seriesEntry.hasBalanceEnd)
        let balanceKind: CatalogBalanceDueKind?
        let balanceText: String?
        let balanceAt: Date?
        let balanceEndAt: Date?
        if declaresBalance {
            balanceKind = .exact
            balanceText = nil
            balanceAt = seriesEntry.hasBalanceStart ? seriesEntry.balanceStartAt : nil
            balanceEndAt = seriesEntry.hasBalanceEnd ? seriesEntry.balanceEndAt : nil
        } else {
            balanceKind = series.balanceDueKind
            balanceText = series.balanceDueText
            balanceAt = series.balanceDueAt
            balanceEndAt = series.balanceDueEndAt
        }

        return updateSeriesSalePhase(
            id: seriesID,
            phase: phase,
            // S2 不收集预约开始时间：保留已有值
            reservationStartAt: series.reservationStartAt,
            reservationEndAt: seriesEntry.hasReservationEnd ? seriesEntry.reservationEndAt : nil,
            balanceDueKind: balanceKind,
            balanceDueText: balanceText,
            balanceDueAt: balanceAt,
            balanceDueEndAt: balanceEndAt,
            reservationBatches: seriesEntry.reservationBatches)
    }

    /// 写系列封面（CatalogAsset id）。返回是否成功。
    @discardableResult
    func updateSeriesCover(seriesID: String, assetID: String) -> Bool {
        guard canMutate() else { return false }
        guard catalog.assets.contains(where: { $0.id == assetID }) else {
            lastError = "封面引用的图片资源 \(assetID) 不存在，请先导入图片。"
            return false
        }
        guard let index = catalog.series.firstIndex(where: { $0.id == seriesID }) else {
            lastError = "找不到系列 \(seriesID)。"
            return false
        }
        catalog.series[index].cover = assetID
        markDirty()
        return true
    }
}
