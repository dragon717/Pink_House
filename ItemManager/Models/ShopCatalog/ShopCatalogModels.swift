//
//  ShopCatalogModels.swift
//  ItemManager
//
//  「店家上新 / 历年系列」公共 Catalog 领域模型（Phase 1：领域模型）。
//
//  需求来源：docs/少女心愿_店家上新_第一版落地计划.md 第二部分（§3–6）。
//  设计约束（计划 §34 强制开发约束）：
//    - 公共 Catalog 与用户私有状态分层；用户模型不重写，只加可选引用字段
//      （见 Clothing.catalogProductID / catalogVariantID / catalogSaleEventID）。
//    - Series 与 Product 分开；Product 必须支持多个 SaleEvent；
//      预约价不能被现货价覆盖（SaleEvent 为追加式记录，无覆盖接口）。
//    - 商品名称不能作为稳定 ID（所有实体以 id 为唯一标识）。
//    - CatalogAsset 必须保留 originalURL，用于保存原图。
//
//  命名说明：为避免与 TimeHall V3 画册 DTO（TimeHallItemDTO 等）及通用词冲突，
//  实体统一带 `Catalog` 前缀；字段名与计划 §4 模型表一一对应。
//

import Foundation

// MARK: - 枚举

/// SaleEvent 类型（计划 §6：预约价 / 现货价 / 再贩，追加式销售历史）
enum CatalogSaleEventType: String, Codable, CaseIterable, Identifiable {
    case reservation // 预约价
    case stock       // 现货价
    case rerelease   // 再贩

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reservation: return "预约价"
        case .stock: return "现货价"
        case .rerelease: return "再贩"
        }
    }
}

/// 金额币种（2026-09-22 第三版收口 R02 最小兼容设计）
///
/// 背景：旧迁移脚本把 `priceJPY / salePriceJPY / regularPriceJPY` 直接写进没有
/// 币种语义的 `price`，衣橱草稿又写死 CNY —— 于是「¥24800」在两处分别是
/// 24800 元人民币和 24800 日元，金额与币种脱钩，跨币种差价、合计、个人实付
/// 全是错的。
///
/// 口径（方案 §7.5）：
///   · 源金额 + 源币种 → Catalog 展示 → 用户选择 → 个人记录金额 + 同币种；
///   · 日元不得按人民币入库，来源不明标「币种待确认」；
///   · **不隐式换汇**：跨币种不直接比较、不直接合计；
///   · 旧 JSON 的无币种记录按可验证来源补齐，不做全局默认 CNY。
enum CatalogCurrency: String, Codable, CaseIterable, Identifiable, Sendable {
    case cny = "CNY"
    case jpy = "JPY"
    /// 来源未标注币种：展示「币种待确认」，不参与跨币种计算
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cny: return "人民币"
        case .jpy: return "日元"
        case .unknown: return "币种待确认"
        }
    }

    /// 金额符号。unknown 仍显示「¥」但配套文案必须提示币种待确认，
    /// 避免把「不知道是什么钱」呈现成「确定是人民币」。
    var symbol: String {
        switch self {
        case .cny: return "¥"
        case .jpy: return "JP¥"
        case .unknown: return "¥"
        }
    }

    var isUnknown: Bool { self == .unknown }

    /// 与衣橱既有口径（`ClothingPriceCurrency`）对齐的代码。
    /// unknown 回退到 CNY 只用于「必须给衣橱一个显示币种」的场合，
    /// 并会同时写入「币种待确认」备注，不作为换汇依据。
    var clothingCurrencyCode: String {
        switch self {
        case .cny: return "CNY"
        case .jpy: return "JPY"
        case .unknown: return "CNY"
        }
    }
}

/// 金额 + 币种的最小载体：跨币种比较 / 合计一律先过 `isSameCurrency(as:)`。
nonisolated struct CatalogMoney: Hashable, Sendable {
    var amount: Decimal
    var currency: CatalogCurrency

    func isSameCurrency(as other: CatalogMoney) -> Bool {
        currency == other.currency && !currency.isUnknown
    }

    /// 展示文本（币种待确认时不加符号前缀，改由配套文案说明）
    var displayText: String {
        guard !currency.isUnknown else { return "\(NSDecimalNumber(decimal: amount).stringValue)（币种待确认）" }
        return "\(currency.symbol)\(NSDecimalNumber(decimal: amount).stringValue)"
    }
}

/// CatalogAsset 图片资源类型（计划 §5）
enum CatalogAssetType: String, Codable, CaseIterable, Identifiable {
    case productImage    // 商品图
    case sizeChartImage  // 尺码表原图
    case seriesCover     // 系列主视觉
    case shopCover       // 店家封面 / Logo

    var id: String { rawValue }
}

/// 运营发布状态（计划 §31：draft → submitted → reviewed → published，必要时 archived）
enum CatalogPublicationStatus: String, Codable, CaseIterable, Identifiable {
    case draft     // 草稿
    case submitted // 提交
    case reviewed  // 审核
    case published // 发布
    case archived  // 归档

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .draft: return "草稿"
        case .submitted: return "提交"
        case .reviewed: return "审核"
        case .published: return "发布"
        case .archived: return "归档"
        }
    }
}

// MARK: - Shop 店家

/// 店家（计划 §4 模型表：id, name, aliases, logo, cover, description）
/// V1.1 §4.2 归档保护：被引用实体禁止物理删除，只能写 archivedAt（nil = 未归档）。
struct CatalogShop: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    /// 店家别名，用于搜索匹配与导入去重（计划 §29：根据店家名 / aliases 匹配）
    var aliases: [String] = []
    var logo: String? = nil
    var cover: String? = nil
    var description: String? = nil
    /// 归档标记（V1.1 §4.2）：nil = 未归档；非 nil = 归档时间。decodeIfPresent 兼容旧 JSON
    var archivedAt: Date? = nil

    /// 兼容旧格式：aliases 缺失时兜底为空数组（带默认值的非可选字段
    /// 不被合成 Decodable 自动兜底，需显式 decodeIfPresent）
    init(id: String, name: String, aliases: [String] = [],
         logo: String? = nil, cover: String? = nil, description: String? = nil,
         archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.logo = logo
        self.cover = cover
        self.description = description
        self.archivedAt = archivedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            aliases: try c.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            logo: try c.decodeIfPresent(String.self, forKey: .logo),
            cover: try c.decodeIfPresent(String.self, forKey: .cover),
            description: try c.decodeIfPresent(String.self, forKey: .description),
            archivedAt: try c.decodeIfPresent(Date.self, forKey: .archivedAt))
    }

    /// 名称或任一别名命中（大小写不敏感），供店家搜索与导入匹配复用
    func matches(nameOrAlias query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        if name.lowercased() == q { return true }
        return aliases.contains { $0.lowercased() == q }
    }
}

// MARK: - Series 系列

/// 系列（计划 §4：id, shopID, name, year, season, cover, description；与 Product 必须分开）
// MARK: - Series 系列发售阶段（2026-09-23 需求二）

/// 系列层面的「发售阶段」：明确区分该系列当前在**预约中**还是**预约已结束**，
/// 直接决定前端加购时能给什么模式（预约期可入定金 / 尾款，结束后引导全款）。
///
/// 与 `ShopCatalogPurchasePhase`（单品级、由销售事件档期推导）的分工：
///   · 本类型 = **运营在系列上显式声明**的口径，带「预约结束时间」与过期自动流转；
///   · 单品详情页**优先**消费它，未声明（nil）时才回退到档期推导 —— 旧数据行为不变。
nonisolated enum CatalogSeriesSalePhase: String, Codable, CaseIterable, Identifiable, Sendable {
    case reservationActive = "reservation_active"
    case reservationEnded = "reservation_ended"
    /// 尾款中（2026-09-24 需求三）：预约窗口结束后、**开始收尾款**的结算期。
    ///
    /// 与「预约已结束」的分工（这两个阶段必须能区分，否则运营无法表达
    /// 「预约收了定金，现在正在等大家补尾款」这条事实）：
    ///   · 预约已结束 = 预约（付定金）窗口关闭，尾款**还没开始收**；
    ///   · 尾款中     = 尾款支付进行中（已到「尾款时间」或运营显式声明）。
    ///
    /// rawValue 只追加、不改既有三个：已发布覆盖层里的阶段字符串必须继续可解码。
    case balancePending = "balance_pending"
    case inStock = "in_stock"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reservationActive: return "预约中"
        case .reservationEnded: return "预约已结束"
        case .balancePending: return "尾款中"
        case .inStock: return "现货"
        }
    }
}

/// 「尾款时间」的粒度（2026-09-24 需求四）：运营可能只能给出**大致时间**
/// （「大货到后」「2027 年春节前」），也可能给出**具体时间**（到分）。
///
/// 为什么要显式区分，而不是「能解析成日期就当具体时间」：
///   1. 自动流转只允许建立在**确定时刻**上 —— 大致时间是人的描述，不是时间点，
///      拿它做 `now > x` 判定就是把猜测当事实（与既有「缺依据就不猜」口径冲突）；
///   2. 展示口径不同：大致时间原样展示文本，具体时间按 locale 格式化。
nonisolated enum CatalogBalanceDueKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case approximate = "approximate"
    case exact = "exact"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .approximate: return "大致时间"
        case .exact: return "具体时间"
        }
    }
}

/// 系列（V1.1 §4.2：id / shopID / name / year / season / cover / description）
struct CatalogSeries: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var shopID: String
    var name: String
    var year: Int? = nil
    /// 年月（2026-09-24 需求）：与 `year` 配合表达「2026-10」这类年月粒度；
    /// nil = 只填了年份（旧数据形态）。录入/解析/展示统一走 `CatalogYearMonthText`。
    /// **必须 Optional**：合成 `Decodable` 对旧 JSON / 已发布覆盖层缺键自动置 nil，零迁移。
    var month: Int? = nil
    /// 季节（如「冬」），自由文本
    var season: String? = nil
    var cover: String? = nil
    var description: String? = nil
    /// 归档标记（V1.1 §4.2）：nil = 未归档，非 nil = 归档时间。
    /// Optional 字段由合成 Decodable 以 decodeIfPresent 处理，旧 JSON 缺键自动置 nil。
    var archivedAt: Date? = nil
    /// 系列级预约价格表（2026-09-22）：整个系列共用，旧 JSON 缺键自动置 nil
    var priceChart: CatalogPriceChart? = nil
    /// 发售阶段（2026-09-23 需求二）：nil = **未声明**（旧数据 / 运营还没填）
    /// → 前端沿用销售记录档期推导，行为与改动前完全一致。
    ///
    /// **必须 Optional**：合成 `Decodable` 对非 Optional 字段走 `decode`，
    /// 旧 JSON / 已发布的覆盖层缺这个键会直接抛错，整个系列列表都打不开。
    var salePhase: CatalogSeriesSalePhase? = nil

    // MARK: 预约期（2026-09-24 需求五：预约中必须同时有「开始 + 结束」）

    /// 预约开始时间。**选填**：预约期开口那天运营常常记不清，但结束时间必须有
    /// （它是自动流转的依据）。填了就必须不晚于 `reservationEndAt`（见
    /// `CatalogSeriesReservationWindow`）。
    ///
    /// **必须 Optional**（同 `salePhase` 的理由）：旧 JSON / 已发布覆盖层缺这个键，
    /// 非 Optional 会让合成 `Decodable` 直接抛错，整个系列列表都打不开。
    var reservationStartAt: Date? = nil
    /// 预约结束时间（仅在选择「预约中」时要求填写）。
    /// 当前时间越过它 → 生效阶段自动流转为「预约已结束」（`CatalogSeriesSalePhaseResolver`）。
    /// 切到其它阶段时**不清除**该值：它是「预约是什么时候结束的」这条事实本身。
    var reservationEndAt: Date? = nil

    // MARK: 尾款时间（2026-09-24 需求四）

    /// 尾款时间粒度：`approximate`（大致时间，自由文本）/ `exact`（具体时间，`balanceDueAt`）。
    ///
    /// **必须 Optional**（同 `salePhase` 的理由）：旧 JSON / 已发布覆盖层缺这三个键，
    /// 非 Optional 会让合成 `Decodable` 直接抛错，整个系列列表打不开。
    /// nil = 未填写 → 不参与任何自动流转、界面上不展示尾款时间。
    var balanceDueKind: CatalogBalanceDueKind? = nil
    /// 大致时间的**原文**（如「大货到后 1 个月」「2027 年春节前」）。
    /// 只在大致粒度下有意义；**故意不做日期解析** —— 它不是时间点，解析出来的
    /// 任何时刻都是猜的，会让自动流转说假话。上限与校验见 `CatalogSeriesBalanceDue`。
    var balanceDueText: String? = nil
    /// 具体时间（到分）。只在具体粒度下有意义，且是**唯一**允许驱动自动流转的字段。
    /// 切到其它阶段时**不清除**（与 `reservationEndAt` 同口径：事实保留，表单只是隐藏）。
    ///
    /// 语义 = **尾款期的开始**（「开始收尾款」的时刻），2026-09-24 需求五起与
    /// `balanceDueEndAt` 组成尾款区间。**key 不改**（改 key = 存量数据全丢）。
    var balanceDueAt: Date? = nil
    /// 大致时间下的**尾款结束描述**（如「大货到后 2 个月」）。
    /// 与 `balanceDueText` 成对：2026-09-24 需求五要求尾款期同时给出开始与结束。
    var balanceDueEndText: String? = nil
    /// 尾款结束时间（到分）。**选填**：不填 = 未声明结束，参与展示但不参与任何流转判定
    /// （「尾款是否收齐」在数据模型里没有依据，出口只能是运营声明 —— 见
    /// `CatalogSeriesSalePhaseResolver.balancePhaseExitsByDeclarationOnly`）。
    var balanceDueEndAt: Date? = nil
}

// MARK: - PriceCorrection 价格修正（2026-09-22：与 append-only 销售历史分离）

/// 价格修正结果：**对当前商品属性的更正**，不是业务事件。
///
/// 与 `CatalogSaleEvent` 的边界（双流程硬约束）：
///   · 本结构**只有一份最新状态**——再次修正直接整体覆盖，不产生历史记录；
///   · `CatalogSaleEvent` 是**追加式**业务事件（往年款再贩 / 补货），永不覆盖；
///   · 两者存储位置、写入接口、校验规则全部独立，不得互相写入。
///
/// 字段全部可选：nil = 该项未修正，展示时回退到 SaleEvent 推导值。
struct CatalogPriceCorrection: Codable, Hashable, Sendable {
    var reservationPrice: Decimal? = nil
    var stockPrice: Decimal? = nil
    var deposit: Decimal? = nil
    var balance: Decimal? = nil
    /// 最后一次修正时间（审计用；不是业务批次时间）
    var correctedAt: Date? = nil
    /// 修正快照的币种（R02）。nil = 沿用销售记录的币种；
    /// 修正价格时必须与商品既有币种一致——修价不是换币种，跨币种修正会被拒绝。
    var currency: CatalogCurrency? = nil
}

// MARK: - Product 商品

/// 商品（计划 §4：id, shopID, seriesID, name, category, images, description）
struct CatalogProduct: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var shopID: String
    var seriesID: String
    var name: String
    /// 商品类型（JSK / OP / SK / KC / 小物…），对齐系列详情分类筛选（计划 §11）
    var category: String
    /// 商品图（CatalogAsset 的 id 列表；原图一律经 CatalogAsset.originalURL 取）
    var images: [String] = []
    var description: String? = nil
    /// 归档标记（V1.1 §4.2）：nil = 未归档，非 nil = 归档时间。
    /// Optional 字段由合成 Decodable 以 decodeIfPresent 处理，旧 JSON 缺键自动置 nil。
    var archivedAt: Date? = nil
    /// 价格修正后的**当前价格状态**（2026-09-22）：由「价格修正」流程覆盖写入，
    /// 与 append-only 的 SaleEvent 历史互不相干。nil = 从未修正过。
    /// Optional 字段由合成 Decodable 以 decodeIfPresent 处理，旧 JSON 缺键自动置 nil。
    var priceCorrection: CatalogPriceCorrection? = nil
    /// 款式名（2026-09-22「同款不同色」归类）：同款式不同颜色的商品共享同一款式名，
    /// 列表按款式合并展示、卡片内颜色子项切换。nil = 未显式指定（按商品名剥离颜色词派生）。
    /// Optional 字段由合成 Decodable 以 decodeIfPresent 处理，旧 JSON 缺键自动置 nil。
    var designName: String? = nil

    /// 兼容旧格式：images 缺失时兜底为空数组（理由同 CatalogShop.init(from:)）
    init(id: String, shopID: String, seriesID: String, name: String,
         category: String, images: [String] = [], description: String? = nil,
         archivedAt: Date? = nil, priceCorrection: CatalogPriceCorrection? = nil,
         designName: String? = nil) {
        self.id = id
        self.shopID = shopID
        self.seriesID = seriesID
        self.name = name
        self.category = category
        self.images = images
        self.description = description
        self.archivedAt = archivedAt
        self.priceCorrection = priceCorrection
        self.designName = designName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            shopID: try c.decode(String.self, forKey: .shopID),
            seriesID: try c.decode(String.self, forKey: .seriesID),
            name: try c.decode(String.self, forKey: .name),
            category: try c.decode(String.self, forKey: .category),
            images: try c.decodeIfPresent([String].self, forKey: .images) ?? [],
            description: try c.decodeIfPresent(String.self, forKey: .description),
            archivedAt: try c.decodeIfPresent(Date.self, forKey: .archivedAt),
            priceCorrection: try c.decodeIfPresent(CatalogPriceCorrection.self, forKey: .priceCorrection),
            designName: try c.decodeIfPresent(String.self, forKey: .designName))
    }
}

// MARK: - ProductVariant 配色 / 尺码

/// 商品规格（计划 §4：id, productID, color, size）
/// 注：一条 Variant 表示一个「配色 + 尺码」组合；允许 color 或 size 为空表示“未区分”。
struct CatalogProductVariant: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var productID: String
    var color: String? = nil
    var size: String? = nil
    /// 规格图绑定（图文联动，V1.2 点菜式选购）：CatalogAsset id；
    /// 选中该规格时展示区同步切换为其对应照片。nil = 未绑定（沿用商品首图）。
    var imageAssetID: String? = nil
}

// MARK: - SizeChart 尺码表

/// 尺码表行（如「胸围 80-84 84-88 88-92」）
struct CatalogSizeRow: Codable, Hashable, Sendable {
    var label: String
    /// 与 columns 一一对应；缺测量的列为 nil
    var values: [String?]
}

/// 结构化尺码表（计划 §4：productID, columns, rows, sourceImage）
/// 计划 §12：同时保存结构化尺码表与原始尺码表图片，两者缺一不可。
struct CatalogSizeChart: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var productID: String
    var unit: String? = nil
    var columns: [String] = []
    var rows: [CatalogSizeRow] = []
    /// 原始尺码表图片（CatalogAsset id，type = sizeChartImage）
    var sourceImage: String? = nil

    /// 是否存在结构化内容（只有原图时为 false，此时商品详情仅展示原图）
    var hasStructuredContent: Bool {
        !columns.isEmpty && !rows.isEmpty
    }
}

// MARK: - StyleProfile 款式（SPU）公共档案

/// 款式公共档案（2026-09-23 录入端重构：SPU / SKU 分层）。
///
/// 分层口径（需求原文）：
///   · **款式（SPU）公共属性** —— 尺码表、面料、款式描述：录商品的第一步填，**只填一次**；
///   · **颜色（SKU）差异属性** —— 颜色图片、颜色尺码选择：添加每个颜色时独立填。
///
/// 本结构承载其中的「面料 / 款式描述」。**尺码表不放在这里**，它已经是款式级实体
/// （`CatalogSizeChart` 的读写都按款式归一化，见 `ShopCatalogSizeChartSharing`），
/// 再搬一次家只会多出第二个真相来源；新旧两处口径统一由 `ShopCatalogStyleProfileSharing`
/// 对外暴露，调用方不必知道数据住在哪。
///
/// `id` 就是款式键（`ShopCatalogStyleProfileSharing.styleKey`），因此
/// **一个款式天然只有一份档案**——写入口径是整体替换，不存在「红色一份、粉色一份」。
struct CatalogStyleProfile: Codable, Identifiable, Hashable, Sendable {
    /// 款式键：`seriesID|category|designName`（与 `ShopCatalogSameDesignGrouper.designKey` 同源）
    var id: String
    var seriesID: String
    var category: String
    var designName: String
    /// 面料（如「雪花提花布 + 蕾丝拼接」）
    var fabric: String? = nil
    /// 款式描述（款式级共用文案）
    var styleDescription: String? = nil
    var updatedAt: Date? = nil

    /// 是否有任何公共内容（全空 = 不该落库）
    var isEmpty: Bool {
        (fabric ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (styleDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - PriceChart 系列级预约价格表

/// 预约价格表（2026-09-22：与尺码表拆分为两个独立素材）：
///   · 归属**系列**而非单品：一张价格表整个系列共用，在系列维度配置处上传维护，
///     单品编辑页不再上传；单品详情页自动读取所属系列的价格表
///   · columns / rows 由上传图片 OCR 自动解析生成，允许人工修正
///   · sourceImage 保留原图引用（「local:」运营上传图或 Bundle 文件名）
///   · sourceImages（2026-09-24 需求）：价格表**多图**引用列表；
///     sourceImage 恒等于首图（单一展示口径继续成立），其余图供详情页补充展示。
///     Optional 字段由合成 Decodable 以 decodeIfPresent 处理，旧 JSON 缺键自动置 nil。
struct CatalogPriceChart: Codable, Hashable, Sendable {
    var id: String
    var seriesID: String
    var unit: String? = nil
    var columns: [String] = []
    var rows: [CatalogSizeRow] = []
    var sourceImage: String? = nil
    var sourceImages: [String]? = nil

    /// 是否存在结构化内容（只有原图时为 false，此时详情页给出明确提示）
    var hasStructuredContent: Bool { !columns.isEmpty && !rows.isEmpty }
}

// MARK: - SaleEvent 销售记录

/// 单次销售记录（计划 §4：id, productID, type, price, deposit, balance, startAt, endAt）
/// 价格属于商品历史，不是商城售价（计划 §6）。
struct CatalogSaleEvent: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var productID: String
    var type: CatalogSaleEventType
    var price: Decimal
    /// 定金 / 尾款（预约类记录常用；现货记录可为 nil）
    var deposit: Decimal? = nil
    var balance: Decimal? = nil
    /// 业务时间（预约/现货档期；再贩场景下即**再贩日期 / 批次时间**，必填）
    var startAt: Date? = nil
    var endAt: Date? = nil
    /// 批次标识（2026-09-22 再贩场景）：如「2025 再贩第二批」，可空
    var batchLabel: String? = nil
    /// 记录写入时间（append-only 审计用，与 startAt 业务时间区分）
    var recordedAt: Date? = nil
    /// 金额币种（R02）。nil = 旧数据未标注 → 按 `effectiveCurrency` 视为「待确认」。
    /// Optional 字段由合成 Decodable 以 decodeIfPresent 处理，旧 JSON 缺键自动置 nil。
    var currency: CatalogCurrency? = nil
    /// 价格分档区间（R05）：同一档期内按尺码 / SKU 分档的真实区间。
    /// 只有来源明确给出分档时才写；单一价格时两者均为 nil。
    var priceTierMin: Decimal? = nil
    var priceTierMax: Decimal? = nil

    /// 生效币种：nil（旧数据）按「待确认」处理，**不做全局默认 CNY**。
    var effectiveCurrency: CatalogCurrency { currency ?? .unknown }

    /// 是否为分档价格（有多个真实档位）
    var hasPriceTier: Bool {
        guard let min = priceTierMin, let max = priceTierMax else { return false }
        return max > min
    }

    /// 校验定金 + 尾款与总价的一致性（允许缺省字段，不做强约束）
    var isDepositBalanceConsistent: Bool {
        guard let deposit, let balance else { return true }
        return (deposit + balance) == price
    }

    /// 追加记录指纹：**重复提交防护**用。
    /// 业务维度完全一致（同商品 / 同类型 / 同价格 / 同定金尾款 / 同批次日）
    /// 即视为同一条记录的重复提交，不区分写入时间 `recordedAt`——重复提交
    /// 只是「再次点了保存」，不是一条新的再贩记录。
    var appendFingerprint: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let day: String
        if let startAt {
            let c = calendar.dateComponents([.year, .month, .day], from: startAt)
            day = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        } else {
            day = "nodate"
        }
        let d = deposit.map { NSDecimalNumber(decimal: $0).stringValue } ?? "-"
        let b = balance.map { NSDecimalNumber(decimal: $0).stringValue } ?? "-"
        // 币种参与去重（R02）：同一天、同价格但币种不同是两条不同的销售记录，
        // 不能因为数值相同就判定为重复提交。
        return [productID, type.rawValue, NSDecimalNumber(decimal: price).stringValue,
                d, b, day, effectiveCurrency.rawValue]
            .joined(separator: "|")
    }

    /// 展示用批次描述：有批次名显示批次名，否则显示日期
    var batchDisplay: String {
        if let batchLabel, !batchLabel.trimmingCharacters(in: .whitespaces).isEmpty {
            return batchLabel
        }
        guard let startAt else { return "未标注批次" }
        return startAt.formatted(.dateTime.year().month().day())
    }
}

// MARK: - CatalogAsset 图片资源

/// 图片资源（计划 §5：id, type, thumbnailURL, previewURL, originalURL, width, height）
/// 不允许只存缩略图：originalURL 必须保留，用于保存原图。
struct CatalogAsset: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var type: CatalogAssetType
    var thumbnailURL: String? = nil
    var previewURL: String? = nil
    var originalURL: String
    var width: Int? = nil
    var height: Int? = nil
    /// 公共库远端媒体的稳定关联键（公共数据库字段配置方案 §2.2）。
    ///
    /// 取值 = **图片字节的 SHA-256**（64 位小写 hex），用来推导 THMedia 记录名
    /// `th.media.<mediaKey>`；**不是** CloudKit 返回的临时下载 URL。
    /// 它位于 `THDataPack.asset` 内的 JSON，不是 CloudKit 记录的字段，
    /// 因此不需要为每个商品新建公共 Record Type。
    ///
    /// · 可选、非必填：没有它的旧包继续按 `http(s)` / Bundle / `local:` 旧逻辑读取；
    /// · `originalURL` 保留来源信息与旧版本兼容，不再承担「公共图片已上传」的语义；
    /// · 第一版只有一个 canonical `mediaKey`，需要多分辨率时再补
    ///   `thumbnailMediaKey` / `previewMediaKey`，或发布多条 `CatalogAsset`。
    var mediaKey: String? = nil
}

// MARK: - Catalog 根（第一版整包结构）

/// 公共 Catalog 整包。Phase 1 仅定义传输/存储结构；
/// 加载与去重匹配（Shop → Series → Product，计划 §29）在后续 Phase 落地。
struct ShopCatalog: Codable, Hashable, Sendable {
    var version: Int = 1
    var shops: [CatalogShop] = []
    var series: [CatalogSeries] = []
    var products: [CatalogProduct] = []
    var variants: [CatalogProductVariant] = []
    var sizeCharts: [CatalogSizeChart] = []
    var saleEvents: [CatalogSaleEvent] = []
    var assets: [CatalogAsset] = []
    /// 款式（SPU）公共档案（2026-09-23）：面料 / 款式描述，一个款式一份。
    /// Optional 缺键容错：合成解码对带默认值字段走 decodeIfPresent（见下方 init(from:)）
    var styleProfiles: [CatalogStyleProfile] = []
    /// 删除墓碑（2026-09-24 强制删除）：种子实体物理删不掉（Bundle 只读），
    /// 运营「强制删除」把 id 记进这里，合并层据此排除（含种子与覆盖层副本）。
    /// Optional 缺键容错：旧覆盖层 JSON 没有这些键也能解码。
    var removedShopIDs: [String] = []
    var removedSeriesIDs: [String] = []
    var removedProductIDs: [String] = []

    /// 兼容旧格式：任何集合字段缺失时兜底为空数组（理由同 CatalogShop.init(from:)）
    init(version: Int = 1, shops: [CatalogShop] = [], series: [CatalogSeries] = [],
         products: [CatalogProduct] = [], variants: [CatalogProductVariant] = [],
         sizeCharts: [CatalogSizeChart] = [], saleEvents: [CatalogSaleEvent] = [],
         assets: [CatalogAsset] = [], styleProfiles: [CatalogStyleProfile] = [],
         removedShopIDs: [String] = [], removedSeriesIDs: [String] = [],
         removedProductIDs: [String] = []) {
        self.version = version
        self.shops = shops
        self.series = series
        self.products = products
        self.variants = variants
        self.sizeCharts = sizeCharts
        self.saleEvents = saleEvents
        self.assets = assets
        self.styleProfiles = styleProfiles
        self.removedShopIDs = removedShopIDs
        self.removedSeriesIDs = removedSeriesIDs
        self.removedProductIDs = removedProductIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try c.decodeIfPresent(Int.self, forKey: .version) ?? 1,
            shops: try c.decodeIfPresent([CatalogShop].self, forKey: .shops) ?? [],
            series: try c.decodeIfPresent([CatalogSeries].self, forKey: .series) ?? [],
            products: try c.decodeIfPresent([CatalogProduct].self, forKey: .products) ?? [],
            variants: try c.decodeIfPresent([CatalogProductVariant].self, forKey: .variants) ?? [],
            sizeCharts: try c.decodeIfPresent([CatalogSizeChart].self, forKey: .sizeCharts) ?? [],
            saleEvents: try c.decodeIfPresent([CatalogSaleEvent].self, forKey: .saleEvents) ?? [],
            assets: try c.decodeIfPresent([CatalogAsset].self, forKey: .assets) ?? [],
            styleProfiles: try c.decodeIfPresent([CatalogStyleProfile].self, forKey: .styleProfiles) ?? [],
            removedShopIDs: try c.decodeIfPresent([String].self, forKey: .removedShopIDs) ?? [],
            removedSeriesIDs: try c.decodeIfPresent([String].self, forKey: .removedSeriesIDs) ?? [],
            removedProductIDs: try c.decodeIfPresent([String].self, forKey: .removedProductIDs) ?? [])
    }
}

// MARK: - 价格档案（计划 §6 用户端展示口径）

/// 价格档案汇总：从商品的 SaleEvent 列表推导「历史预约价 / 当前现货价 / 差价」。
/// 口径：同类取「时间最近」的一条；startAt 相同（都为空或同一时刻）时，
/// 取**数组中更靠后**的那条，即后追加的补录记录胜出。
/// 原因：补录上新追加的记录通常不带 startAt（全部落到 distantPast），而
/// `Sequence.max(by:)` 在并列时保留先出现的元素，会导致新补的价格被旧记录
/// 盖住——商品页无论怎么补录都不变。这里显式用下标做 tie-break 保证确定性。
/// 预约 / 现货记录本身仍只追加、不覆盖（本结构是只读推导，写入一律生成新 SaleEvent）。
struct CatalogPriceArchive: Hashable, Sendable {
    /// 最近一次预约记录（**未修正**，来自 append-only 历史）
    let reservation: CatalogSaleEvent?
    /// 最近一次现货记录（**未修正**，来自 append-only 历史）
    let stock: CatalogSaleEvent?
    /// 价格修正结果（nil = 从未修正 → 下面所有「当前值」回退到历史推导）
    let correction: CatalogPriceCorrection?

    init(events: [CatalogSaleEvent], correction: CatalogPriceCorrection? = nil) {
        func latest(_ type: CatalogSaleEventType) -> CatalogSaleEvent? {
            events.enumerated()
                .filter { $0.element.type == type }
                .max { lhs, rhs in
                    let l = lhs.element.startAt ?? .distantPast
                    let r = rhs.element.startAt ?? .distantPast
                    if l != r { return l < r }
                    return lhs.offset < rhs.offset
                }?
                .element
        }
        self.reservation = latest(.reservation)
        self.stock = latest(.stock)
        // 全 nil 的修正 = 「全部价格已清除」的有效状态，必须原样保留，
        // 不能按空值吞掉（否则清除操作永远不生效）
        self.correction = correction
    }

    /// 是否存在价格修正
    var isCorrected: Bool { correction != nil }

    // 「当前生效值」口径（2026-09-22 调整）：
    // 一旦存在价格修正，四个当前值**以修正值为准、逐字段对号入座**——
    // 修正值 nil = 该价格已被清除（展示「暂无」），**不回退**到历史推导；
    // 只有从未修正过（correction == nil）时才回退到最近一次销售记录推导。
    // 原因：修正弹窗按「留空 = 清除」提交完整快照，若 nil 还回退历史，
    // 用户清掉的价格会「清不掉」。

    /// 当前现货价
    var currentStockPrice: Decimal? {
        if let correction { return correction.stockPrice }
        return stock?.price
    }

    /// 当前预约价
    var currentReservationPrice: Decimal? {
        if let correction { return correction.reservationPrice }
        return reservation?.price
    }

    /// 历史预约价（计划 §6 用户页「历史预约价」）：保留旧命名，语义 = 当前生效预约价
    var historicalReservationPrice: Decimal? { currentReservationPrice }

    /// 当前定金
    var currentDeposit: Decimal? {
        if let correction { return correction.deposit }
        return reservation?.deposit
    }

    /// 当前尾款
    var currentBalance: Decimal? {
        if let correction { return correction.balance }
        return reservation?.balance
    }

    // MARK: 币种（R02）

    /// 预约记录的生效币种（无预约记录时为 nil）
    var reservationCurrency: CatalogCurrency? { reservation?.effectiveCurrency }

    /// 现货记录的生效币种（无现货记录时为 nil）
    var stockCurrency: CatalogCurrency? { stock?.effectiveCurrency }

    /// 修正快照声明的币种
    var correctionCurrency: CatalogCurrency? { correction?.currency }

    /// 当前生效币种：修正声明 > 最近一次销售记录；都没有则 nil（未知）。
    /// 预约与现货币种不一致时取**预约**（定金尾款口径以预约为准）。
    var currentCurrency: CatalogCurrency? {
        correctionCurrency ?? reservationCurrency ?? stockCurrency
    }

    /// 预约与现货**币种不同**（§7.5：跨币种不直接比较、不直接合计）。
    /// 币种待确认（unknown）时不算「不同」，但也不参与差价计算
    /// （见 `stockOverReservationDelta`）。
    var isCrossCurrency: Bool {
        guard let r = reservationCurrency, let s = stockCurrency else { return false }
        return r != s
    }

    /// 只有一侧标了币种、另一侧是「待确认」：不能假定它们同币种，也不做隐式换汇。
    ///
    /// 两侧**都没标**（存量旧数据的常态）不算混币种——那是同一份历史来源，
    /// 若一并拒绝，V1.1 的「预约‑现货差价」对所有存量商品会整体失效。
    /// 差别在于：两侧都未标注时我们只是**不声明币种**，仍然回答差价；
    /// 一侧明确、一侧不明时才是真的不知道该按哪种钱算。
    var isMixedKnownUnknownCurrency: Bool {
        guard let r = reservationCurrency, let s = stockCurrency else { return false }
        return r.isUnknown != s.isUnknown
    }

    /// 差价（现货 − 预约）；任一侧缺失、**币种不一致或一侧币种不明**时为 nil。
    ///
    /// 旧实现直接做减法，遇到「预约 24800 JPY / 现货 1580 CNY」会算出一个
    /// 既不是日元也不是人民币的数。这里显式拦掉：跨币种没有差价可言。
    var stockOverReservationDelta: Decimal? {
        guard let r = currentReservationPrice, let s = currentStockPrice else { return nil }
        guard isCrossCurrency == false, isMixedKnownUnknownCurrency == false else { return nil }
        return s - r
    }

    /// 差价百分比（相对预约价，含符号的浮点百分数，如 20 / -12.5 表示 +20% / −12.5%）；
    /// 预约价为 0 / 缺失 / 跨币种时为 nil（V1.1 §1 P0：展示预约‑现货差价及百分比）
    var stockOverReservationDeltaPercent: Double? {
        guard let r = currentReservationPrice, let delta = stockOverReservationDelta, r != 0 else { return nil }
        return NSDecimalNumber(decimal: delta / r * 100).doubleValue
    }

    /// 差价不可算的原因（供详情页给明确提示，而不是留一个空白或错误数字）
    var deltaUnavailableReason: String? {
        if currentReservationPrice == nil || currentStockPrice == nil { return nil }
        if isCrossCurrency { return "预约与现货币种不同，不计算差价" }
        if isMixedKnownUnknownCurrency { return "只有一侧标注了币种，另一侧为「币种待确认」，不计算差价" }
        return nil
    }
}
