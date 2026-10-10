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
    /// 列名原文（逗号/竖线分隔），**只写数据列**，如「后衣长, 胸围, 腰围」。
    /// 首列若写成「尺码 / 款式」这类行标签列名会被自动忽略（见 `CatalogChartTextSyntax.dataColumns`）。
    var chartColumnsText: String
    /// 行原文（每行一条：`S = 80, 78-83`）
    var chartRowsText: String
    /// 尺码表原图（CatalogAsset id，可空）。只有原图时结构化列行可以都为空。
    var chartSourceImageAssetID: String?

    // MARK: 价格（S3-C：尾款随预约价 / 定金计算，现货价独立）

    var reservationPriceText: String {
        didSet { recalculateBalance() }
    }
    var depositText: String {
        didSet { recalculateBalance() }
    }
    var balanceText: String
    var stockPriceText: String
    /// 币种 rawValue（CatalogCurrency）。默认人民币。
    var currencyRawValue: String

    /// 在字段写入时同步更新，尾款与输入一起自动保存；不同类型只修改各自的草稿。
    /// 恢复旧草稿的 init 不触发观察器，保留其已保存金额，直到运营修改输入。
    private mutating func recalculateBalance() {
        guard case .value(let reservation) = opsParseDecimal(reservationPriceText),
              case .value(let deposit) = opsParseDecimal(depositText),
              reservation >= 0, deposit >= 0, deposit <= reservation else {
            balanceText = ""
            return
        }
        balanceText = NSDecimalNumber(decimal: reservation - deposit).stringValue
    }

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
    /// 只应用本次窗口管理的颜色图片，保留颜色名称、尺码及其他资料。
    /// 颜色已被删除时整批拒绝，避免部分写入或按行号串到另一个颜色。
    mutating func applyColorImages(colorIDs: Set<String>, assignments: [String: String]) -> Bool {
        guard colorIDs.isSubset(of: Set(colors.map(\.id))),
              Set(assignments.keys).isSubset(of: colorIDs) else { return false }
        for index in colors.indices where colorIDs.contains(colors[index].id) {
            colors[index].imageAssetID = assignments[colors[index].id]
        }
        return true
    }

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
    /// true = S1 选择「＋ 新建店家…」：忽略 shopID，提交时先建店家再建系列。
    /// 与系列的「空 seriesID = 新建」不同——店家需要显式开关，
    /// 因为 shopID == "" 同时承担「还没选」的含义，不能复用。
    var createsNewShop: Bool
    /// 新店家名（createsNewShop 时必填）
    var newShopName: String
    /// 新店家别名原文（英文逗号分隔，可空；提交时解析落库）
    var newShopAliasesText: String
    /// 未管理时保留店家已有 Logo；管理时 nil 表示清除。
    var managesShopLogo: Bool
    var shopLogoReference: String?
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

    // MARK: S2：系列价格表（可选）
    //
    // 价格表躺在 `CatalogSeries` 上（系列级唯一存储，单品不复制副本），
    // 所以向导这一页既可以**上传原图 + 录结构化列行**，也可以整块不管。
    //
    // ⚠️ `declaresPriceChart` 这个显式开关不是多余：与 `declaresPhase` 同一个理由。
    // 「这一项我没填」和「我要把它清空」在数据上长得一样（都是空字符串），
    // 没有开关的话，走一次向导就会把系列上已有的价格表**静默清掉** ——
    // 而运营在界面上看不到任何「被清空」的提示。
    /// true = 本次提交要把价格表写进系列；false = **完全不碰**系列已有的价格表。
    var declaresPriceChart: Bool
    /// 金额单位（如「元」「¥」）。注意：**不是**尺码表的长度单位。
    var priceChartUnit: String
    /// 列名原文（**只写数据列**，逗号分隔）
    var priceChartColumnsText: String
    /// 行原文（每行 `款式名 = 值1, 值2, …`）
    var priceChartRowsText: String
    /// 价格表原图（CatalogAsset id，**有序**：首图即 `sourceImage`）。
    /// 只有原图、没有结构化列行是**合法状态**（`CatalogPriceChart.hasStructuredContent`
    /// 为 false，客户端详情页会退化成展示原图）。
    var priceChartImageAssetIDs: [String]

    // S3：类型条目
    var typeEntries: [OpsSeriesTypeEntry]

    init(
        shopID: String = "",
        createsNewShop: Bool = false,
        newShopName: String = "",
        newShopAliasesText: String = "",
        managesShopLogo: Bool = false,
        shopLogoReference: String? = nil,
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
        declaresPriceChart: Bool = false,
        priceChartUnit: String = "",
        priceChartColumnsText: String = "",
        priceChartRowsText: String = "",
        priceChartImageAssetIDs: [String] = [],
        typeEntries: [OpsSeriesTypeEntry] = []
    ) {
        self.shopID = shopID
        self.createsNewShop = createsNewShop
        self.newShopName = newShopName
        self.newShopAliasesText = newShopAliasesText
        self.managesShopLogo = managesShopLogo
        self.shopLogoReference = shopLogoReference
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
        self.declaresPriceChart = declaresPriceChart
        self.priceChartUnit = priceChartUnit
        self.priceChartColumnsText = priceChartColumnsText
        self.priceChartRowsText = priceChartRowsText
        self.priceChartImageAssetIDs = priceChartImageAssetIDs
        self.typeEntries = typeEntries
    }
}

extension OpsSeriesEntryDraft {
    private enum Keys: String, CodingKey {
        case shopID, createsNewShop, newShopName, newShopAliasesText
        case managesShopLogo, shopLogoReference
        case seriesID, newSeriesName, newSeriesYearText, newSeriesMonthText, newSeriesSeason
        case coverAssetID, declaresPhase, phaseRawValue
        case hasReservationEnd, reservationEndAt
        case hasBalanceStart, balanceStartAt, hasBalanceEnd, balanceEndAt
        case declaresPriceChart, priceChartUnit, priceChartColumnsText, priceChartRowsText
        case priceChartImageAssetIDs
        case typeEntries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        self.init(
            shopID: try c.decodeIfPresent(String.self, forKey: .shopID) ?? "",
            createsNewShop: try c.decodeIfPresent(Bool.self, forKey: .createsNewShop) ?? false,
            newShopName: try c.decodeIfPresent(String.self, forKey: .newShopName) ?? "",
            newShopAliasesText: try c.decodeIfPresent(String.self, forKey: .newShopAliasesText) ?? "",
            managesShopLogo: try c.decodeIfPresent(Bool.self, forKey: .managesShopLogo) ?? false,
            shopLogoReference: try c.decodeIfPresent(String.self, forKey: .shopLogoReference),
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
            declaresPriceChart: try c.decodeIfPresent(Bool.self, forKey: .declaresPriceChart) ?? false,
            priceChartUnit: try c.decodeIfPresent(String.self, forKey: .priceChartUnit) ?? "",
            priceChartColumnsText: try c.decodeIfPresent(String.self, forKey: .priceChartColumnsText) ?? "",
            priceChartRowsText: try c.decodeIfPresent(String.self, forKey: .priceChartRowsText) ?? "",
            priceChartImageAssetIDs: try c.decodeIfPresent([String].self, forKey: .priceChartImageAssetIDs) ?? [],
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

    /// 价格表的两个文本输入框是否**都**为空。
    ///
    /// 用途是「还没填就别说识别失败」：一进 S2 就红一条「预约价格表识别失败」，
    /// 用户会以为系统出错了（其实只是还没填）。
    /// 口径与 `SeriesConfigSheet.isPriceChartInputEmpty` 逐字一致。
    var isPriceChartTextEmpty: Bool {
        priceChartColumnsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && priceChartRowsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    ///
    /// 切分、归一化、个数校验全部走共享包 `CatalogChartTextSyntax`（**唯一口径**，
    /// 本机可用 `swift test` 秒级验证）；本类型只负责把它翻译成尺码表这边的措辞。
    static func parse(entry: OpsSeriesTypeEntry) -> (chart: OpsSeriesParsedSizeChart?, issue: String?) {
        guard entry.usesSizeChart else { return (nil, nil) }

        // ⭐ 列口径与 iOS 完全一致：首列若是「尺码 / 款式」这类**行标签列名**，剔除。
        //
        // 这条不是宽容，是**防错**：不剔除就会出现「Mac 按 8 列校验放行 → iOS 渲染时剔成 7 列，
        // 而行的值仍是 8 个 → 整列错位」（2026-10-01 实测：胸围显示成后衣长的值）。
        // 校验与渲染必须看到同一份列，否则「识别成功」会变成静默的数据损坏。
        let rawColumns = CatalogChartTextSyntax.splitColumns(entry.chartColumnsText)
        let columns = CatalogChartTextSyntax.dataColumns(from: entry.chartColumnsText)
        // 用户在列名里写了行标签列 ⇒ 值列表里**不该**再为它留空位。报错时点明，
        // 否则「列名 8 个、值 7 个」会让人以为是自己数错了。
        let listedLabelColumn = rawColumns.first.flatMap {
            CatalogChartTextSyntax.isLabelColumn($0) ? $0 : nil
        }

        let rows: [CatalogSizeRow]
        switch CatalogChartTextSyntax.parseRowLines(entry.chartRowsText,
                                                   dataColumnCount: columns.count) {
        case .failure(let issue):
            return (nil, message(for: issue, listedLabelColumn: listedLabelColumn))
        case .success(let lines):
            rows = lines.map { CatalogSizeRow(label: $0.label, values: $0.values) }
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

    /// 共享层的事实 → 尺码表的措辞（**文案留在这里，规则不在这里**）。
    private static func message(for issue: CatalogChartTextSyntax.RowLineIssue,
                                listedLabelColumn: String?) -> String {
        switch issue {
        case .missingSeparator(let line):
            return "尺码表有一行没有「=」，格式应为 `S = 80, 78-83`：\(line)"
        case .emptyLabel(let line):
            return "尺码表有一行没有写尺码标签：\(line)"
        case .valueCountMismatch(let label, let actual, let expected):
            var hint = "请把这一行补齐到 \(expected) 个值"
                + "（值之间用半角逗号「,」分隔）。"
            if let listedLabelColumn {
                hint += "列名里的「\(listedLabelColumn)」是**行标签列**、不占数据列的名额，"
                    + "所以「=」后面直接写 \(expected) 个数即可，不要再为它留空位。"
            }
            return "尺码表行「\(label)」有 \(actual) 个值，而数据列有 \(expected) 个 —— " + hint
        }
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
        if let reservation, let deposit, deposit > reservation {
            issues.append("定金不能大于预约价，请修改预约价或定金后再计算尾款。")
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
        if draft.createsNewShop {
            // 新建店家路径：店名必填；shopID 此刻尚不存在，不按「未选择」拦
            if OpsSeriesSizeChartParsing.normalized(draft.newShopName) == nil {
                add("新店家名不能为空：请填写店名，或改选已有店家。", area: .shopSeries)
            }
        } else if draft.shopID.isEmpty || !catalog.shops.contains(where: { $0.id == draft.shopID }) {
            add("店家不能为空。", area: .shopSeries)
        }
        if draft.managesShopLogo, let reference = draft.shopLogoReference,
           !catalog.assets.contains(where: { $0.id == reference }),
           !reference.hasPrefix("thmedia:"), !reference.hasPrefix("local:"),
           !reference.hasPrefix("https://") {
            add("店家 Logo 图片不存在，请重新上传。", area: .shopSeries)
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

        // S2：系列价格表（开关关着时 `issues` 恒为空 —— 不碰就不校验）。
        // 规则在 Services（`OpsSeriesPriceChartValidation`），因为它必须问**同一个**
        // 文本解析器；这里只负责把它挂到 S2 这一页上。
        for message in OpsSeriesPriceChartValidation.issues(for: draft) {
            add(message, area: .seriesProfile)
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
