//
//  OpsSeriesEntryDraft.swift
//  PinkHouseOps
//
//  「系列级多类型录入」的领域模型与校验（需求《Pink_House Mac 商品发布流程实现需求说明》v1.2）。
//
//  ## 这组类型解决什么问题
//
//  旧的业务逻辑把「录入单位」当成单个商品：先 addProduct(名, 品类)，再逐个补
//  规格 / 尺码表 / 销售记录。需求 v1.2 的录入单位是**系列**：
//  一个系列同时勾选多个类型（JSK / OP / 小物…），每个类型独立填写
//  款式名、尺码表、价格（预约价/定金/尾款/现货价）与颜色 SKU，
//  最后一次系列级提交。这里定义的就是那份「向导工作副本」。
//
//  ## 与现有模型的映射（提交时发生，见 OpsWorkspace+SeriesEntry.swift）
//
//    · 一个类型条目 typeEntries[]  = 一个 CatalogProduct（designName = 款式名）
//    · 颜色 SKU                    = CatalogProductVariant（color × size）
//    · 尺码表                      = CatalogSizeChart（归属该商品，不跨类型共用）
//    · 预约价 + 定金 + 尾款         = reservation 型 CatalogSaleEvent
//    · 现货价                      = stock 型 CatalogSaleEvent（与预约价互相独立）
//
//  ## 硬边界（需求 §1，全部在类型设计上体现）
//
//    · 没有「任务名称」、没有「批次」 —— 类型上根本没有这两个字段；
//    · 没有「款式描述」输入 —— 不放字段（历史数据里的 description 不删除、不清空）；
//    · 颜色 SKU 不带价格、不带独立尺码表；
//    · 尺码勾选项来自当前类型尺码表行标签，**按原始顺序**（绝不用无序集合重排）。
//
//  ## 迁移安全（仓库规则「新增字段一律 Optional」的 Codable 版）
//
//  这份 JSON 会持久化在 `OpsCatalogDraftRecord.seriesEntryJSON` 里，随草稿长期存在。
//  所有字段都写了自定义 `init(from:)` + `decodeIfPresent` + 默认值：
//  以后加字段，旧 JSON 缺键自动落到默认值，不会让整份向导草稿解不开。
//

import Foundation

// MARK: - 类型枚举（保留现有分类 + 扩展入口）

/// 系列内可选的类型/分类。需求 §S3：「类型可以来自现有分类，保留现有分类枚举和后续扩展入口」。
/// 现有分类对齐 iOS 端品类（JSK / OP / SK / KC / 小物…）；`custom` 走自由输入，不进枚举。
enum OpsSeriesEntryCategory {
    static let known = ["JSK", "OP", "SK", "KC", "小物"]
}

// MARK: - 颜色 SKU

/// 一个颜色的 SKU 定义（需求 §S3-D）。**不填**价格 / 任务名称 / 批次 / 独立尺码表 / 款式描述。
struct OpsSeriesColorSKU: Codable, Equatable, Identifiable {
    var id: String
    /// 颜色名称（必填，不能为空）
    var name: String
    /// 颜色图片（CatalogAsset id，可空）
    var imageAssetID: String?
    /// 可售尺码：**当前类型尺码表行标签的子集，按尺码表原始顺序保存**。
    /// 均码模式（类型无尺码表）下恒为空（规格 size = nil）。
    var selectedSizes: [String]

    init(id: String = UUID().uuidString, name: String = "",
         imageAssetID: String? = nil, selectedSizes: [String] = []) {
        self.id = id
        self.name = name
        self.imageAssetID = imageAssetID
        self.selectedSizes = selectedSizes
    }
}

extension OpsSeriesColorSKU {
    private enum Keys: String, CodingKey {
        case id, name, imageAssetID, selectedSizes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
            imageAssetID: try c.decodeIfPresent(String.self, forKey: .imageAssetID),
            selectedSizes: try c.decodeIfPresent([String].self, forKey: .selectedSizes) ?? [])
    }
}

// MARK: - 类型条目

/// 系列内的一个类型/款式条目（需求 §3 的 `typeEntries[]`）。
/// 表单态字段保留**原文**（而不是解析后的 Decimal）：解析失败时用户的输入不能丢。
struct OpsSeriesTypeEntry: Codable, Equatable, Identifiable {
    var id: String
    /// 类型/分类（JSK / OP / 小物…）。由多选结果确定；同系列同类型可以有多个条目（不同款式）。
    var category: String
    /// 款式名（必填）。当前类型的所有颜色共享。
    var designName: String

    // MARK: 尺码表（S3-B：归属当前类型，不归属颜色，不与其他类型共用）

    /// false = 「无尺码/均码」模式（如小物）：不建结构化尺码表，规格 size = nil。
    /// **绝不借用其他类型的尺码表。**
    var usesSizeChart: Bool
    var chartUnit: String
    /// 列名原文（逗号/竖线分隔），如「尺码, 前裙长, 推荐胸围」
    var chartColumnsText: String
    /// 行原文（每行一条：`S = 80, 78-83`）
    var chartRowsText: String
    /// 尺码表原图（CatalogAsset id，可空）。只有原图时结构化列行可以都为空。
    var chartSourceImageAssetID: String?

    // MARK: 价格（S3-C：同屏填写，互相独立）

    var reservationPriceText: String
    var depositText: String
    var balanceText: String
    var stockPriceText: String
    /// 币种 rawValue（CatalogCurrency）。默认人民币。
    var currencyRawValue: String

    // MARK: 颜色 SKU（S3-D）

    var colors: [OpsSeriesColorSKU]

    // MARK: 向导内部状态

    /// 提交成功后对应的 CatalogProduct id（重复提交时据此更新而不是再建一个）。
    /// nil = 还没有提交成功过。
    var committedProductID: String?
    /// 上次系列级提交该条目的结果（nil = 还没提交过；false = 上次失败）。
    var lastCommitOK: Bool?

    init(
        id: String = UUID().uuidString,
        category: String,
        designName: String = "",
        usesSizeChart: Bool = true,
        chartUnit: String = "",
        chartColumnsText: String = "",
        chartRowsText: String = "",
        chartSourceImageAssetID: String? = nil,
        reservationPriceText: String = "",
        depositText: String = "",
        balanceText: String = "",
        stockPriceText: String = "",
        currencyRawValue: String = CatalogCurrency.cny.rawValue,
        colors: [OpsSeriesColorSKU] = [],
        committedProductID: String? = nil,
        lastCommitOK: Bool? = nil
    ) {
        self.id = id
        self.category = category
        self.designName = designName
        self.usesSizeChart = usesSizeChart
        self.chartUnit = chartUnit
        self.chartColumnsText = chartColumnsText
        self.chartRowsText = chartRowsText
        self.chartSourceImageAssetID = chartSourceImageAssetID
        self.reservationPriceText = reservationPriceText
        self.depositText = depositText
        self.balanceText = balanceText
        self.stockPriceText = stockPriceText
        self.currencyRawValue = currencyRawValue
        self.colors = colors
        self.committedProductID = committedProductID
        self.lastCommitOK = lastCommitOK
    }
}

extension OpsSeriesTypeEntry {
    private enum Keys: String, CodingKey {
        case id, category, designName, usesSizeChart, chartUnit
        case chartColumnsText, chartRowsText, chartSourceImageAssetID
        case reservationPriceText, depositText, balanceText, stockPriceText
        case currencyRawValue, colors, committedProductID, lastCommitOK
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            id: try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
            category: try c.decodeIfPresent(String.self, forKey: .category) ?? "",
            designName: try c.decodeIfPresent(String.self, forKey: .designName) ?? "",
            usesSizeChart: try c.decodeIfPresent(Bool.self, forKey: .usesSizeChart) ?? true,
            chartUnit: try c.decodeIfPresent(String.self, forKey: .chartUnit) ?? "",
            chartColumnsText: try c.decodeIfPresent(String.self, forKey: .chartColumnsText) ?? "",
            chartRowsText: try c.decodeIfPresent(String.self, forKey: .chartRowsText) ?? "",
            chartSourceImageAssetID: try c.decodeIfPresent(String.self, forKey: .chartSourceImageAssetID),
            reservationPriceText: try c.decodeIfPresent(String.self, forKey: .reservationPriceText) ?? "",
            depositText: try c.decodeIfPresent(String.self, forKey: .depositText) ?? "",
            balanceText: try c.decodeIfPresent(String.self, forKey: .balanceText) ?? "",
            stockPriceText: try c.decodeIfPresent(String.self, forKey: .stockPriceText) ?? "",
            currencyRawValue: try c.decodeIfPresent(String.self, forKey: .currencyRawValue)
                ?? CatalogCurrency.cny.rawValue,
            colors: try c.decodeIfPresent([OpsSeriesColorSKU].self, forKey: .colors) ?? [],
            committedProductID: try c.decodeIfPresent(String.self, forKey: .committedProductID),
            lastCommitOK: try c.decodeIfPresent(Bool.self, forKey: .lastCommitOK))
    }

    var currency: CatalogCurrency {
        get { CatalogCurrency(rawValue: currencyRawValue) ?? .cny }
        set { currencyRawValue = newValue.rawValue }
    }

    /// 条目在界面上的标识（校验错误定位用，需求 §S3-E：「OP：尺码表列和行未完成」）
    var displayName: String {
        let design = designName.trimmingCharacters(in: .whitespacesAndNewlines)
        if design.isEmpty { return category.isEmpty ? "未命名类型" : category }
        return category.isEmpty ? design : "\(category)·\(design)"
    }
}

// MARK: - 系列级草稿

/// 向导工作副本（S1–S5 全程共用一份）。**不包含**任务名称与批次（需求 §1 边界）。
struct OpsSeriesEntryDraft: Codable, Equatable {
    // S1：店家与系列
    var shopID: String
    /// 已有系列 id；空 = 新建系列
    var seriesID: String
    var newSeriesName: String
    var newSeriesYearText: String
    var newSeriesMonthText: String
    var newSeriesSeason: String

    // S2：系列资料与发售阶段
    /// 系列封面（CatalogAsset id，可空）
    var coverAssetID: String?
    /// 声明发售阶段；nil rawValue 表示「不声明」（由档期推导）
    var declaresPhase: Bool
    var phaseRawValue: String
    var hasReservationEnd: Bool
    var reservationEndAt: Date
    /// 尾款开始时间（可选）。填了就是「具体时间」粒度（驱动自动流转）。
    var hasBalanceStart: Bool
    var balanceStartAt: Date
    /// 尾款结束时间（可选，**仅展示与提醒，不自动切换为现货**）
    var hasBalanceEnd: Bool
    var balanceEndAt: Date

    // S3：类型条目
    var typeEntries: [OpsSeriesTypeEntry]

    init(
        shopID: String = "",
        seriesID: String = "",
        newSeriesName: String = "",
        newSeriesYearText: String = "",
        newSeriesMonthText: String = "",
        newSeriesSeason: String = "",
        coverAssetID: String? = nil,
        declaresPhase: Bool = false,
        phaseRawValue: String = CatalogSeriesSalePhase.reservationActive.rawValue,
        hasReservationEnd: Bool = false,
        reservationEndAt: Date = Date(),
        hasBalanceStart: Bool = false,
        balanceStartAt: Date = Date(),
        hasBalanceEnd: Bool = false,
        balanceEndAt: Date = Date(),
        typeEntries: [OpsSeriesTypeEntry] = []
    ) {
        self.shopID = shopID
        self.seriesID = seriesID
        self.newSeriesName = newSeriesName
        self.newSeriesYearText = newSeriesYearText
        self.newSeriesMonthText = newSeriesMonthText
        self.newSeriesSeason = newSeriesSeason
        self.coverAssetID = coverAssetID
        self.declaresPhase = declaresPhase
        self.phaseRawValue = phaseRawValue
        self.hasReservationEnd = hasReservationEnd
        self.reservationEndAt = reservationEndAt
        self.hasBalanceStart = hasBalanceStart
        self.balanceStartAt = balanceStartAt
        self.hasBalanceEnd = hasBalanceEnd
        self.balanceEndAt = balanceEndAt
        self.typeEntries = typeEntries
    }
}

extension OpsSeriesEntryDraft {
    private enum Keys: String, CodingKey {
        case shopID, seriesID, newSeriesName, newSeriesYearText, newSeriesMonthText, newSeriesSeason
        case coverAssetID, declaresPhase, phaseRawValue
        case hasReservationEnd, reservationEndAt
        case hasBalanceStart, balanceStartAt, hasBalanceEnd, balanceEndAt
        case typeEntries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            shopID: try c.decodeIfPresent(String.self, forKey: .shopID) ?? "",
            seriesID: try c.decodeIfPresent(String.self, forKey: .seriesID) ?? "",
            newSeriesName: try c.decodeIfPresent(String.self, forKey: .newSeriesName) ?? "",
            newSeriesYearText: try c.decodeIfPresent(String.self, forKey: .newSeriesYearText) ?? "",
            newSeriesMonthText: try c.decodeIfPresent(String.self, forKey: .newSeriesMonthText) ?? "",
            newSeriesSeason: try c.decodeIfPresent(String.self, forKey: .newSeriesSeason) ?? "",
            coverAssetID: try c.decodeIfPresent(String.self, forKey: .coverAssetID),
            declaresPhase: try c.decodeIfPresent(Bool.self, forKey: .declaresPhase) ?? false,
            phaseRawValue: try c.decodeIfPresent(String.self, forKey: .phaseRawValue)
                ?? CatalogSeriesSalePhase.reservationActive.rawValue,
            hasReservationEnd: try c.decodeIfPresent(Bool.self, forKey: .hasReservationEnd) ?? false,
            reservationEndAt: try c.decodeIfPresent(Date.self, forKey: .reservationEndAt) ?? Date(),
            hasBalanceStart: try c.decodeIfPresent(Bool.self, forKey: .hasBalanceStart) ?? false,
            balanceStartAt: try c.decodeIfPresent(Date.self, forKey: .balanceStartAt) ?? Date(),
            hasBalanceEnd: try c.decodeIfPresent(Bool.self, forKey: .hasBalanceEnd) ?? false,
            balanceEndAt: try c.decodeIfPresent(Date.self, forKey: .balanceEndAt) ?? Date(),
            typeEntries: try c.decodeIfPresent([OpsSeriesTypeEntry].self, forKey: .typeEntries) ?? [])
    }

    var phase: CatalogSeriesSalePhase? {
        get { declaresPhase ? CatalogSeriesSalePhase(rawValue: phaseRawValue) : nil }
        set {
            declaresPhase = newValue != nil
            phaseRawValue = newValue?.rawValue ?? CatalogSeriesSalePhase.reservationActive.rawValue
        }
    }

    /// 已选类型清单摘要（S3 顶部 / S4 检查用），保持条目顺序
    var selectedCategorySummary: String {
        let seen = typeEntries.map(\.category).filter { !$0.isEmpty }
        var ordered: [String] = []
        for item in seen where !ordered.contains(item) { ordered.append(item) }
        return ordered.isEmpty ? "（未选择类型）" : ordered.joined(separator: " ✓　")
    }
}

// MARK: - 尺码表解析（条目文本 → 结构化）

/// 条目尺码表的解析结果。解析在**校验与提交时**发生，文本永远是用户原文。
struct OpsSeriesParsedSizeChart: Equatable {
    var unit: String?
    var columns: [String]
    var rows: [CatalogSizeRow]
    /// 行标签（**按原始顺序**）—— 颜色 SKU 的可售尺码勾选项从这里派生
    var sizeLabels: [String]

    /// 结构化内容是否存在（只有原图时为 false）
    var hasStructuredContent: Bool { !columns.isEmpty && !rows.isEmpty }
}

enum OpsSeriesSizeChartParsing {
    /// 解析条目里的尺码表文本。返回 nil = 完全没有结构化内容（列行都空）。
    /// 列行只填一半、行值个数不齐等**结构错误**通过 `issue` 返回，不静默兜底。
    static func parse(entry: OpsSeriesTypeEntry) -> (chart: OpsSeriesParsedSizeChart?, issue: String?) {
        guard entry.usesSizeChart else { return (nil, nil) }
        let columns = entry.chartColumnsText
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "|" || $0 == "｜" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var rows: [CatalogSizeRow] = []
        for rawLine in entry.chartRowsText.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let separatorIndex = line.firstIndex(of: "=") else {
                return (nil, "尺码表有一行没有「=」，格式应为 `S = 80, 78-83`：\(line)")
            }
            let label = String(line[line.startIndex..<separatorIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else {
                return (nil, "尺码表有一行没有写尺码标签：\(line)")
            }
            let valuesPart = String(line[line.index(after: separatorIndex)...])
            let values = valuesPart
                .split(separator: ",", omittingEmptySubsequences: false)
                .map { part -> String? in
                    let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            if !columns.isEmpty, values.count != columns.count {
                return (nil, "尺码表行「\(label)」有 \(values.count) 个值，而列名有 \(columns.count) 个 ——"
                    + "客户端会整列错位，请补齐或用逗号留空占位。")
            }
            rows.append(CatalogSizeRow(label: label, values: values))
        }
        // 需求 §S3-B 校验：列和行必须同时存在，不能只填写一半；只有原图时可以都为空。
        if columns.isEmpty != rows.isEmpty {
            return (nil, "尺码表的列与行必须同时填写，或同时留空（只有原图时可以都为空）。")
        }
        guard !columns.isEmpty, !rows.isEmpty else { return (nil, nil) }
        return (OpsSeriesParsedSizeChart(
            unit: normalized(entry.chartUnit),
            columns: columns,
            rows: rows,
            sizeLabels: rows.map(\.label)), nil)
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 价格解析（条目文本 → 金额）

/// 一个类型条目解析后的价格。四个字段互相独立（需求 §3：
/// 「不能通过当前阶段二选一存储」——这里的四项全部是独立 Optional）。
struct OpsSeriesParsedPrice: Equatable {
    var reservation: Decimal?
    var deposit: Decimal?
    var balance: Decimal?
    var stock: Decimal?
    var currency: CatalogCurrency
}

enum OpsSeriesPriceParsing {
    /// 解析条目价格文本。`issues` 非空 = 有解析失败或规则错误。
    static func parse(entry: OpsSeriesTypeEntry) -> (price: OpsSeriesParsedPrice, issues: [String]) {
        var issues: [String] = []
        func resolve(_ text: String, _ label: String) -> Decimal? {
            switch opsParseDecimal(text) {
            case .empty:
                return nil
            case .value(let value):
                return value
            case .invalid:
                issues.append("「\(label)」不是有效数字：\(text)（留空表示不填这一项）")
                return nil
            }
        }
        let reservation = resolve(entry.reservationPriceText, "预约价")
        let deposit = resolve(entry.depositText, "定金")
        let balance = resolve(entry.balanceText, "尾款")
        let stock = resolve(entry.stockPriceText, "现货价")

        let currency = entry.currency
        if currency.isUnknown {
            issues.append("请先确认币种再记录价格（「币种待确认」的金额无法参与差价与合计）。")
        }

        // 需求 §S3-C：预约价和现货价至少填写一项
        if reservation == nil && stock == nil {
            issues.append("预约价与现货价至少填一项。")
        }
        // 需求 §S3-C：三者全部填写时 定金 + 尾款 = 预约价
        if let reservation, let deposit, let balance,
           deposit + balance != reservation {
            issues.append("定金 + 尾款必须等于预约价（\(money(deposit, currency)) + "
                + "\(money(balance, currency)) ≠ \(money(reservation, currency))）。")
        }
        // 只填了定金/尾款其一却没有预约价 → 定金尾款没有归属，提示但不额外禁用
        if reservation == nil && (deposit != nil || balance != nil) {
            issues.append("填了定金或尾款就必须同时填预约价（它们是预约价的组成部分）。")
        }
        return (OpsSeriesParsedPrice(
            reservation: reservation, deposit: deposit,
            balance: balance, stock: stock, currency: currency), issues)
    }

    static func money(_ value: Decimal?, _ currency: CatalogCurrency) -> String {
        guard let value else { return "暂无" }
        return CatalogMoney(amount: value, currency: currency.isUnknown ? .cny : currency).displayText
    }
}

// MARK: - 校验（S4 / 系列级提交前）

/// 问题所属的向导步骤（界面据此把「下一步」拦在正确的页上）
enum OpsSeriesEntryArea: Equatable {
    case shopSeries     // S1
    case seriesProfile  // S2
    case typeEntries    // S3
}

/// 一条校验问题。`entryID` 定位到类型条目（nil = 系列级问题）。
struct OpsSeriesEntryIssue: Identifiable, Equatable {
    var id: String { message + (entryID ?? "-") }
    let entryID: String?
    let entryName: String
    let message: String
    /// 默认 S3：非校验器的调用点（提交阶段的拦截提示）可以省略
    var area: OpsSeriesEntryArea = .typeEntries
}

enum OpsSeriesEntryValidator {

    /// 全量校验。**错误必须定位到对应类型**（需求 §S3-E / §4），
    /// 所以每条问题都带 `entryID` / `entryName` 与所属步骤。
    static func validate(_ draft: OpsSeriesEntryDraft, catalog: ShopCatalog) -> [OpsSeriesEntryIssue] {
        var issues: [OpsSeriesEntryIssue] = []
        func add(_ message: String, area: OpsSeriesEntryArea, entry: OpsSeriesTypeEntry? = nil) {
            issues.append(OpsSeriesEntryIssue(
                entryID: entry?.id, entryName: entry?.displayName ?? "",
                message: message, area: area))
        }

        // S1：店家与系列（必填；不显示、不保存任务名称与批次）
        if draft.shopID.isEmpty || !catalog.shops.contains(where: { $0.id == draft.shopID }) {
            add("店家不能为空。", area: .shopSeries)
        }
        if draft.seriesID.isEmpty {
            if OpsSeriesSizeChartParsing.normalized(draft.newSeriesName) == nil {
                add("系列不能为空：请选择已有系列，或填写新系列名。", area: .shopSeries)
            }
        } else if !catalog.series.contains(where: { $0.id == draft.seriesID }) {
            add("所选系列不存在，请重新选择。", area: .shopSeries)
        }

        // S2：发售阶段（「预约中」必须有结束时间 —— 自动流转靠它）
        if let phase = draft.phase, phase == .reservationActive, !draft.hasReservationEnd {
            add("发售阶段是「预约中」时必须填预约结束时间 —— 缺了它系列会一直停在预约中。",
                area: .seriesProfile)
        }

        // S3：至少选择一个类型
        if draft.typeEntries.isEmpty {
            add("至少选择一个类型（如 JSK、OP、小物）。", area: .typeEntries)
        }

        for entry in draft.typeEntries {
            validateEntry(entry, into: &issues)
        }
        return issues
    }

    /// 单个类型条目的校验（S3 内嵌校验与系列级提交共用同一份口径）。
    static func validateEntry(_ entry: OpsSeriesTypeEntry, into issues: inout [OpsSeriesEntryIssue]) {
        func add(_ message: String) {
            issues.append(OpsSeriesEntryIssue(
                entryID: entry.id, entryName: entry.displayName,
                message: message, area: .typeEntries))
        }
        let prefix = entry.displayName

        // 款式名必填（S3-A）
        if OpsSeriesSizeChartParsing.normalized(entry.designName) == nil {
            add("\(prefix)：款式名不能为空。")
        }
        if entry.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            add("\(prefix)：类型不能为空。")
        }

        // 尺码表（S3-B）
        let parsed = OpsSeriesSizeChartParsing.parse(entry: entry)
        if let issue = parsed.issue { add("\(prefix)：\(issue)") }

        // 价格（S3-C）
        let price = OpsSeriesPriceParsing.parse(entry: entry)
        for message in price.issues { add("\(prefix)：\(message)") }

        // 颜色 SKU（S3-D）
        if entry.colors.isEmpty {
            add("\(prefix)：至少填写一个颜色。")
        }
        var seenColorNames: [String] = []
        for color in entry.colors {
            if OpsSeriesSizeChartParsing.normalized(color.name) == nil {
                add("\(prefix)：颜色名称不能为空。")
            } else if seenColorNames.contains(color.name) {
                add("\(prefix)：颜色名称「\(color.name)」重复 —— 两个同名颜色在客户端是两个"
                    + "长得一样的选项，请改名或合并。")
            } else {
                seenColorNames.append(color.name)
            }
            // 可售尺码：来自当前类型尺码表（按原始顺序）；尺码表不存在（均码）时不要求
            if let chart = parsed.chart {
                let valid = Set(chart.sizeLabels)
                let picked = color.selectedSizes.filter { valid.contains($0) }
                if picked.isEmpty {
                    add("\(prefix)：颜色「\(color.name.isEmpty ? "未命名" : color.name)」没有选择可售尺码。")
                }
            }
        }
    }

    /// 从结构化尺码表派生某颜色的规格行（color × size），**按尺码表原始顺序**。
    /// 均码模式（chart == nil）返回单个 (color, nil)。
    static func variantSizes(for color: OpsSeriesColorSKU,
                             chart: OpsSeriesParsedSizeChart?) -> [(color: String, size: String?)] {
        guard let chart else { return [(color.name, nil)] }
        // selectedSizes 顺序以**尺码表原始顺序**为准（不用勾选顺序、不用无序集合遍历序）
        return chart.sizeLabels
            .filter { color.selectedSizes.contains($0) }
            .map { (color.name, $0) }
    }
}
