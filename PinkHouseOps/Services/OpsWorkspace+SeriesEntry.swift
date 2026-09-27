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

    var blocked: Bool { !blockedByValidation.isEmpty }
    var allOK: Bool {
        !blocked && !entryResults.isEmpty && entryResults.allSatisfy(\.ok) && draftSaved
    }
}

// MARK: - 向导草稿持久化

extension OpsWorkspace {

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
            seriesEntry = decoded
        } else {
            // 解不开就重新开始：向导是短期工作副本，不值得为它做隔离态；
            // 但旧字节留在记录里不覆盖（与 R03 同一个「不毁证据」原则）
            seriesEntry = OpsSeriesEntryDraft()
        }
    }

    /// 重定向：系列级提交成功后重开一个空白向导（旧状态已全部落进目录）
    func resetSeriesEntry() {
        seriesEntry = OpsSeriesEntryDraft(shopID: seriesEntry.shopID)
        persistSeriesEntryState()
    }
}

// MARK: - 单图导入（封面 / 颜色图 / 尺码表原图）

extension OpsWorkspace {

    /// 导入一张图并返回 CatalogAsset id（失败返回 nil，原因在 `lastError`）。
    /// 复用与既有导入完全相同的规范化 + staging 路径（不另写第二套）。
    @discardableResult
    func importSingleImage(from url: URL) -> String? {
        guard canMutate() else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let raw = try Data(contentsOf: url)
            let staged = try ShopCatalogMediaStaging.stage(raw)
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let target = stagingDirectory.appendingPathComponent(staged.fileName)
            if !fileManager.fileExists(atPath: target.path) {
                try staged.data.write(to: target, options: .atomic)
            }
            upsertAsset(for: staged)
            let assetID = "asset-\(String(staged.mediaKey.prefix(12)))"
            let saved = saveDraft()
            if !saved {
                lastError = "图片已导入，但草稿落盘失败：" + (lastError ?? "未知原因")
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
        applySeriesPhaseFromWizard(seriesID: seriesID)
        if let coverID = seriesEntry.coverAssetID {
            _ = updateSeriesCover(seriesID: seriesID, assetID: coverID)
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
    private func applySeriesPhaseFromWizard(seriesID: String) {
        guard let series = catalog.series.first(where: { $0.id == seriesID }) else { return }
        let phase = seriesEntry.phase

        // 尾款区间：向导填了具体时间 → exact；一个都没填 → 保留系列已有值
        let declaresBalance = seriesEntry.hasBalanceStart || seriesEntry.hasBalanceEnd
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

        _ = updateSeriesSalePhase(
            id: seriesID,
            phase: phase,
            // S2 不收集预约开始时间：保留已有值
            reservationStartAt: series.reservationStartAt,
            reservationEndAt: seriesEntry.hasReservationEnd ? seriesEntry.reservationEndAt : nil,
            balanceDueKind: balanceKind,
            balanceDueText: balanceText,
            balanceDueAt: balanceAt,
            balanceDueEndAt: balanceEndAt)
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
