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
struct CatalogSeries: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var shopID: String
    var name: String
    var year: Int? = nil
    /// 季节（如「冬」），自由文本
    var season: String? = nil
    var cover: String? = nil
    var description: String? = nil
    /// 归档标记（V1.1 §4.2）：nil = 未归档，非 nil = 归档时间。
    /// Optional 字段由合成 Decodable 以 decodeIfPresent 处理，旧 JSON 缺键自动置 nil。
    var archivedAt: Date? = nil
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

    /// 兼容旧格式：images 缺失时兜底为空数组（理由同 CatalogShop.init(from:)）
    init(id: String, shopID: String, seriesID: String, name: String,
         category: String, images: [String] = [], description: String? = nil,
         archivedAt: Date? = nil) {
        self.id = id
        self.shopID = shopID
        self.seriesID = seriesID
        self.name = name
        self.category = category
        self.images = images
        self.description = description
        self.archivedAt = archivedAt
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
            archivedAt: try c.decodeIfPresent(Date.self, forKey: .archivedAt))
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
    var startAt: Date? = nil
    var endAt: Date? = nil

    /// 校验定金 + 尾款与总价的一致性（允许缺省字段，不做强约束）
    var isDepositBalanceConsistent: Bool {
        guard let deposit, let balance else { return true }
        return (deposit + balance) == price
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

    /// 兼容旧格式：任何集合字段缺失时兜底为空数组（理由同 CatalogShop.init(from:)）
    init(version: Int = 1, shops: [CatalogShop] = [], series: [CatalogSeries] = [],
         products: [CatalogProduct] = [], variants: [CatalogProductVariant] = [],
         sizeCharts: [CatalogSizeChart] = [], saleEvents: [CatalogSaleEvent] = [],
         assets: [CatalogAsset] = []) {
        self.version = version
        self.shops = shops
        self.series = series
        self.products = products
        self.variants = variants
        self.sizeCharts = sizeCharts
        self.saleEvents = saleEvents
        self.assets = assets
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
            assets: try c.decodeIfPresent([CatalogAsset].self, forKey: .assets) ?? [])
    }
}

// MARK: - 价格档案（计划 §6 用户端展示口径）

/// 价格档案汇总：从商品的 SaleEvent 列表推导「历史预约价 / 当前现货价 / 差价」。
/// 口径：同类取时间最近的一条；预约记录只追加、永不覆盖（由模型层保证——
/// 本结构为只读推导，任何写入都生成新 SaleEvent）。
struct CatalogPriceArchive: Hashable, Sendable {
    /// 最近一次预约记录
    let reservation: CatalogSaleEvent?
    /// 最近一次现货记录
    let stock: CatalogSaleEvent?

    init(events: [CatalogSaleEvent]) {
        func latest(_ type: CatalogSaleEventType) -> CatalogSaleEvent? {
            events
                .filter { $0.type == type }
                .max { ($0.startAt ?? .distantPast) < ($1.startAt ?? .distantPast) }
        }
        self.reservation = latest(.reservation)
        self.stock = latest(.stock)
    }

    /// 当前现货价（计划 §6 用户页「当前现货价」）
    var currentStockPrice: Decimal? { stock?.price }

    /// 历史预约价（计划 §6 用户页「历史预约价」）
    var historicalReservationPrice: Decimal? { reservation?.price }

    /// 差价（现货 − 预约）；任一侧缺失则为 nil
    var stockOverReservationDelta: Decimal? {
        guard let r = reservation?.price, let s = stock?.price else { return nil }
        return s - r
    }

    /// 差价百分比（相对预约价，含符号的浮点百分数，如 20 / -12.5 表示 +20% / −12.5%）；
    /// 预约价为 0 或缺失时为 nil（V1.1 §1 P0：展示预约‑现货差价及百分比）
    var stockOverReservationDeltaPercent: Double? {
        guard let r = reservation?.price, let delta = stockOverReservationDelta, r != 0 else { return nil }
        return NSDecimalNumber(decimal: delta / r * 100).doubleValue
    }
}
