import Foundation

// MARK: - 仲夏物语（Midsummer Tale）· 数据模型
//
// 背景：仲夏物语是**国牌**，与时光馆已有五个日牌不同——没有官网 catalogue 管道，
// 公开信息散落在淘宝 / 微博 / 小红书，且天然不完整（见 docs/MIDSUMMER_TALE_BRAND_PAGE.md）。
//
// 因此本模块的数据有三个来源，按优先级合并：
//   1. CloudKit 公共库（创作者在上传入口补充的条目，始终优先）
//   2. Bundle 种子 `midsummer-series.json`（离线兜底与首屏）
//   3. 无（未登录 iCloud、断网、库里还没有数据 → 仍然显示 Bundle 内容，不白屏）
//
// 所有类型 `nonisolated`：与 TimeHall 侧一致，避免默认 MainActor 隔离带来的跨 actor 告警。

// MARK: - 上新阶段

/// 三坑「上新」不是单点上架，而是 3-6 个月的时间线（见 docs/品牌上新资讯功能方案.md §1）。
nonisolated enum MidsummerStage: String, Codable, CaseIterable, Sendable {
  case preview      // 图透
  case deposit      // 定金
  case balance      // 尾款
  case preorder     // 预约价（全款预约，2026-09-17 表单阶段收敛后新增）
  case shipping     // 出货
  case restock      // 再贩
  case inStock      // 现货

  var labelZH: String {
    switch self {
    case .preview: return "图透"
    case .deposit: return "定金"
    case .balance: return "尾款"
    case .preorder: return "预约价"
    case .shipping: return "出货"
    case .restock: return "再贩"
    case .inStock: return "现货"
    }
  }

  var symbolName: String {
    switch self {
    case .preview: return "sparkles"
    case .deposit: return "hand.raised.fill"
    case .balance: return "creditcard.fill"
    case .preorder: return "clock.arrow.circlepath"
    case .shipping: return "shippingbox.fill"
    case .restock: return "arrow.clockwise"
    case .inStock: return "bag.fill"
    }
  }
}

// MARK: - 单品分类（2026-09-17 三级术语体系）

/// 分类第一级 · 大类（用户 2026-09-17 指定的最简化三级标准）：
/// 一、连衣裙类；二、内搭类；三、小物类。
nonisolated enum MidsummerItemCategory: String, Codable, CaseIterable, Sendable {
  case dress    // 一、连衣裙类（OP / JSK / SK / 特殊版型 / FS 套装）
  case inner    // 二、内搭类（衬衫 / 泡泡袖 / 飞袖羊腿袖）
  case trinket  // 三、小物类（头饰 / 配件 / 鞋包 / 其他）

  var labelZH: String {
    switch self {
    case .dress: return "连衣裙类"
    case .inner: return "内搭类"
    case .trinket: return "小物类"
    }
  }
}

/// Lolita 的品类缩写（分类第二级 · 具体类型）。界面按大类分组展示，不要改成自由字符串。
///
/// 兼容性：`op / jsk / skirt / blouse / accessory / set` 是旧版六类的 raw，
/// 种子 JSON 与云端记录都在用，**不可改动**；新增类型的 raw 一经上线同样冻结。
nonisolated enum MidsummerItemKind: String, Codable, CaseIterable, Sendable {
  // 一、连衣裙类
  case op              // OP 有袖连衣裙
  case jsk             // JSK 无袖连衣裙
  case skirt           // SK 半裙
  case suspenderSkirt  // 背带裙
  case sp              // SP 特殊版型
  case ap              // AP 特殊版型
  case overdress       // 罩裙
  case set             // FS / 套装
  // 二、内搭类
  case blouse          // 衬衫
  case puffBlouse      // 泡泡袖内搭
  case gigotBlouse     // 飞袖 / 羊腿袖内搭
  // 三、小物类
  case hairItem        // 头饰（边夹 / 发带 / BNT / KC）
  case parts           // 配件（腰封 / 围裙 / 假领）
  case shoesBag        // 鞋包（lo鞋 / lo包）
  case accessory       // 其他小物（胸针 / 袜类 / 手套）

  /// 所属大类（分类第一级）。
  var category: MidsummerItemCategory {
    switch self {
    case .op, .jsk, .skirt, .suspenderSkirt, .sp, .ap, .overdress, .set:
      return .dress
    case .blouse, .puffBlouse, .gigotBlouse:
      return .inner
    case .hairItem, .parts, .shoesBag, .accessory:
      return .trinket
    }
  }

  /// 某大类下的具体类型（顺序即界面展示顺序）。
  static func kinds(in category: MidsummerItemCategory) -> [MidsummerItemKind] {
    allCases.filter { $0.category == category }
  }

  var labelZH: String {
    switch self {
    case .op: return "OP 有袖连衣裙"
    case .jsk: return "JSK 无袖连衣裙"
    case .skirt: return "SK 半裙"
    case .suspenderSkirt: return "背带裙"
    case .sp: return "SP 特殊版型"
    case .ap: return "AP 特殊版型"
    case .overdress: return "罩裙"
    case .set: return "FS / 套装"
    case .blouse: return "衬衫"
    case .puffBlouse: return "泡泡袖内搭"
    case .gigotBlouse: return "飞袖 / 羊腿袖内搭"
    case .hairItem: return "头饰（边夹 / 发带 / BNT / KC）"
    case .parts: return "配件（腰封 / 围裙 / 假领）"
    case .shoesBag: return "鞋包（lo鞋 / lo包）"
    case .accessory: return "其他小物（胸针 / 袜类 / 手套）"
    }
  }

  /// 卡片上的短标签，例如 `OP` / `JSK`。
  var shortLabel: String {
    switch self {
    case .op: return "OP"
    case .jsk: return "JSK"
    case .skirt: return "SK"
    case .suspenderSkirt: return "背带裙"
    case .sp: return "SP"
    case .ap: return "AP"
    case .overdress: return "罩裙"
    case .set: return "FS"
    case .blouse: return "衬衫"
    case .puffBlouse: return "泡泡袖"
    case .gigotBlouse: return "羊腿袖"
    case .hairItem: return "头饰"
    case .parts: return "配件"
    case .shoesBag: return "鞋包"
    case .accessory: return "其他"
    }
  }

  /// 从淘宝标题里的关键词推断类型；识别不到返回 nil，由调用方决定兜底。
  static func infer(fromName name: String) -> MidsummerItemKind? {
    let lowered = name.lowercased()
    // 先判组合词，避免「op罩裙jsk」这类混写被首个命中规则吃掉
    if lowered.contains("罩裙") { return .overdress }
    if lowered.contains("围裙") { return .parts }
    if lowered.contains("背带") { return .suspenderSkirt }
    if lowered.contains("jsk") { return .jsk }
    if lowered.contains("op") { return .op }
    if lowered.contains("sk") || lowered.contains("半裙") { return .skirt }
    if lowered.contains("泡泡袖") { return .puffBlouse }
    if lowered.contains("羊腿袖") || lowered.contains("飞袖") { return .gigotBlouse }
    if lowered.contains("衬衫") || lowered.contains("内搭") || lowered.contains("开衫") {
      return .blouse
    }
    if lowered.contains("边夹") || lowered.contains("发夹") || lowered.contains("发带")
      || lowered.contains("bnt") || lowered.contains("bonnet") || lowered.contains("kc")
      || lowered.contains("项链") || lowered.contains("帽")
    {
      return .hairItem
    }
    if lowered.contains("腰封") || lowered.contains("假领") { return .parts }
    if lowered.contains("lo鞋") || lowered.contains("鞋子") || lowered.contains("lo包")
      || lowered.contains("包包")
    {
      return .shoesBag
    }
    if lowered.contains("胸针") || lowered.contains("袜") || lowered.contains("手套") {
      return .accessory
    }
    return nil
  }
}

// MARK: - 规格（仿淘宝 SKU）

/// 规格组的**角色**：决定该组的选中值落到衣橱的哪个字段。
///
/// 之所以要显式声明而不是靠名字猜：创作者上传时可能写「配色」「颜色分类」「Colors」，
/// 靠关键词匹配会漏。字段缺省时才退化为关键词推断（见 `resolvedRole`）。
nonisolated enum MidsummerSpecRole: String, Codable, CaseIterable, Sendable {
  /// 款式 / 版型。一个淘宝链接里常有多款（印花SK / 段段JSK / 无腰OP / 内搭 …），
  /// 它们不是「颜色」也不是「尺码」，所以单独成一类：决定入库名称里的款名。
  case variant
  case color
  case size
  /// 其它规格（如「配件」），只进规格备注，不映射到配色/尺码字段
  case other
}

/// 一个规格组，例如「颜色分类」「尺码」。
nonisolated struct MidsummerSpecGroup: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  /// 缺省时按 `name` 关键词推断
  let role: MidsummerSpecRole?
  let options: [MidsummerSpecOption]

  var resolvedRole: MidsummerSpecRole {
    if let role { return role }
    let lowered = name.lowercased()
    if lowered.contains("尺码") || lowered.contains("尺寸") || lowered.contains("码")
      || lowered.contains("size")
    {
      return .size
    }
    if lowered.contains("款式") || lowered.contains("版型") || lowered.contains("款型") {
      return .variant
    }
    if lowered.contains("颜色") || lowered.contains("配色") || lowered.contains("色")
      || lowered.contains("color")
    {
      return .color
    }
    return .other
  }
}

/// 组内一个选项，例如「Sk粉色」。
nonisolated struct MidsummerSpecOption: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  /// 该选项自己的图。可以是 `Assets.xcassets` 里的名字，也可以是 `http(s)` 图链。
  /// `nil` / 空串 = 无图，界面按「SKU 组合图 → 其它已选选项的图 → 单品封面」的顺序回退。
  let image: String?
}

/// 一条具体可入库的规格组合。
///
/// 没有 SKU 表时（`item.skus` 为空），所有组合都视为合法——这覆盖了
/// 「只有规格组、还没整理出组合表」的常见中间状态。
nonisolated struct MidsummerSKU: Codable, Identifiable, Hashable, Sendable {
  let id: String
  /// `groupID -> optionID`
  let options: [String: String]
  /// 组合图。优先级**高于**单个选项的图，用于「内搭奶白色S1粉色」这类跨组组合的专属图。
  let image: String?
  /// 该组合的逐款价（元）。`nil` 表示沿用单品价格。
  let price: Int?
  /// 逐款价的**口径**。
  ///
  /// 归集商品（一个淘宝链接含多款）把逐款价全放在 SKU 表里，于是单品层的
  /// `priceKind` 覆盖不到它们——同一个「有价必须自报口径」的规则就漏了个口子。
  /// 以前只能靠 `priceNote` 用文字交代「这些数字其实是尾款」，
  /// 现在口径跟数字放在一起，界面也就能直接显示「尾款 ¥160–400」而不是裸区间。
  let priceKind: MidsummerPriceKind?

  init(
    id: String,
    options: [String: String],
    image: String? = nil,
    price: Int? = nil,
    priceKind: MidsummerPriceKind? = nil
  ) {
    self.id = id
    self.options = options
    self.image = image
    self.price = price
    self.priceKind = priceKind
  }
}

// MARK: - 价格口径
//
// 背景（这是价格问题的**根因**，不是补数据能解决的）：
// 以前只有一个 `price: Int?`，于是同一个字段被用来装现货价、第三方参考价、
// 甚至尾款——「同一个 ¥320 到底是定金还是全款」无法回答；系列层的价格区间还是
// **手写**的，与单品价格是两份数据，改一处忘一处。
//
// 现在两条硬规则：
//   1. 任何落到 `price` / `balance` / `deposit` 的数字，必须自报**口径**（本枚举）
//      与**采集日期**；出处复用已有的 `sourceURL`（合规必填）。
//   2. 系列 / 商品的价格区间一律**派生**，不再存储。
//      改一个单品价，上面的区间自动跟着走，不存在「忘了同步」。

/// 一个价格的来源口径。
nonisolated enum MidsummerPriceKind: String, Codable, CaseIterable, Sendable {
  /// 电商商品页直读（淘宝 / 天猫商品页本身）
  case shop
  /// 第三方图鉴 / 比价站 / 榜单给出的参考价
  case reference
  /// 尾款口径。
  ///
  /// 单独成一类的原因和「定金分列」一样：来源给的是**尾款**时，
  /// 把它塞进「现货价」会让使用者按全款估预算。归集商品的逐款价尤其常见——
  /// 一个系列里不同款的尾款本来就不同（¥160 / ¥400），只能逐款标注。
  case balance

  var labelZH: String {
    switch self {
    // 使用者口径：淘宝商品页直读的挂牌价就是「现货价」（用户 2026-09-16 定名）。
    case .shop: return "现货价"
    case .reference: return "参考价"
    case .balance: return "尾款"
    }
  }
}

// MARK: - 单品

nonisolated struct MidsummerItemDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let seriesID: String
  let name: String
  let kind: MidsummerItemKind
  /// 现货 / 参考价（元）。预售期一般为空，用 deposit / balance 表示。
  let price: Int?
  /// 预约价（全款预约，元）。
  ///
  /// 单独成档的原因：三坑上新常用三种购买方式并存——现货（即买即得）、
  /// 全款预约（一次付清）、定金尾款预约（付两次）。全款预约的金额既不是
  /// 现货价也不是定金，以前只能塞进 `deposit` 冒充「定金」，价格总表
  /// 「预约价 · 全款预约」分组因此只能靠「只有定金」猜出来。
  /// 旧记录没有此字段，解码自动为 nil（向后兼容）。
  var preorderPrice: Int? = nil
  /// 定金（元）
  let deposit: Int?
  /// 尾款（元）
  let balance: Int?
  /// `price` 的口径。填了 `price` 就必须填它——否则界面只能猜这个数字是什么。
  let priceKind: MidsummerPriceKind?
  /// 价格采集日期 `yyyy-MM-dd`。价格会变，没有采集日的价格无法判断是否过期。
  let priceCapturedOn: String?
  /// 价格口径说明 / 多来源冲突时的取舍理由。界面会如实展示。
  let priceNote: String?
  let sizes: [String]
  let colors: [String]
  /// 主图（本地文件名）。对齐千牛发布路径：每个单品的第一张图为**主图**，
  /// 列表行 / 详情页顶部 / 一键入库都以它为准。
  let coverImage: String?
  /// 附图（第 2–5 张，本地文件名，不含主图）。对齐千牛「主图 5 张」宫格：
  /// 主图存 `coverImage`，其余图按顺序存这里。
  /// 旧记录 / 旧种子没有此字段，解码自动为 nil（向后兼容）。
  var galleryImageNames: [String]? = nil
  let itemURL: String?
  /// 原文出处，合规必填（Apple 5.2）
  let sourceURL: String
  /// 资料存疑或待补时的说明，界面会如实展示
  let note: String?

  /// 尺码表图片的本地文件名（`ImageManager` Images 目录内）。
  /// `nil` / 空 = 尺码表待补充——界面如实标注，不虚构数据（docs/上新咨询双方案设计.md §四）。
  /// 旧 Bundle 种子与旧 CloudKit 记录没有此字段，解码时自动为 nil（向后兼容）；
  /// 用 `var` + 默认值是为了让成员初始化器带默认参数，既有构造点无需改动。
  var sizeChartImageName: String? = nil

  /// 款式尺码表条目：一个款式 + 它的尺码表图（数组保序，按分类顺序展示）。
  struct SizeChartEntry: Codable, Equatable, Hashable {
    let style: String
    let imageName: String
  }

  /// 款式尺码表：`款式 → 尺码表图`，一链接多款时每款各有一张（淘宝详情页按款式分列）。
  ///
  /// 与 `sizeChartImageName`（整条单品共用一张）是两个维度：归集型单品
  /// （如「樱花小羊」9 款）各款尺码不同，一张表讲不清楚，必须按款式给。
  /// 图多为 Bundle 种子静态素材（`seed-` 前缀，随包分发）；旧记录没有此字段，
  /// 解码自动为 nil（向后兼容）。
  var sizeChartImages: [SizeChartEntry]? = nil

  /// 款式对应图：`款式名 → 本地文件名`（每款一张主图，图2 的「粉色JSK / 粉色OP」样式）。
  ///
  /// 与整条单品共用的 5 格主图宫格（`coverImage` + `galleryImageNames`）是两个维度：
  /// 宫格是千牛「商品主图」，这里是**款式级**的对应图——补录时每款单独传、
  /// 单独替换，图和款式一一对应，而不是把所有图堆进同一个宫格。
  /// key 的取法：有「款式」规格组时用选项名（如「印花JSK」）；
  /// 没有规格组但有颜色分类时用「颜色 + 类型短标」（如「粉色OP」）。
  /// 旧记录没有此字段，解码自动为 nil（向后兼容）。
  var variantImageNames: [String: String]? = nil

  /// 规格组（颜色分类 / 尺码 / …）。`nil` 或空数组表示该单品没有可选规格，
  /// 此时详情页的「一键入库」不必让使用者做选择，直接按单品信息入库。
  let specGroups: [MidsummerSpecGroup]?
  /// SKU 组合表。为空表示不做组合约束（任意搭配都合法）。
  let skus: [MidsummerSKU]?

  /// 该商品包含的款式数。有 `variant` 规格组时 = 该组选项数；否则就是 1 款。
  /// 归集后的商品（如「樱花小羊」一个链接含 9 款）靠它把「几款」讲清楚。
  var variantCount: Int {
    let variantGroup = (specGroups ?? []).first { $0.resolvedRole == .variant }
    guard let variantGroup, !variantGroup.options.isEmpty else { return 1 }
    return variantGroup.options.count
  }

  /// 非定金口径的价格：优先参考价 / 现货价，其次尾款。
  ///
  /// 定金**不**参与，它是另一个维度（见 `depositRange`）——
  /// 把 388 的预约定金和 499 的现货价混成一个「¥388–499 区间」正是以前的口径错误。
  var primaryPrice: Int? { price ?? balance }

  /// 该单品全部可核验的「非定金」价格，含 SKU 表里的逐款价。
  ///
  /// 这是价格区间派生的**唯一数据源**：改一个单品价，商品与系列的区间一起变，
  /// 不存在两份数据要对齐。
  var effectivePrices: [Int] {
    let base = primaryPrice
    return ([base] + (skus ?? []).map { $0.price ?? base }).compactMap { $0 }
  }

  /// 逐款价的口径——只有当 SKU 表里的口径**完全一致**时才给出，否则返回 nil。
  ///
  /// 不一致（同一个链接里有参考价也有尾款）时不硬选一个：那正是「同一个区间
  /// 混了两种钱」的老问题。此时界面退回不带前缀的裸区间，细节交给 `priceNote`。
  var variantPriceKind: MidsummerPriceKind? {
    let kinds = Set((skus ?? []).compactMap { $0.priceKind })
    return kinds.count == 1 ? kinds.first : nil
  }

  /// 该单品自己有价吗（`price` / `deposit` / `balance` 任一非空）。
  /// 与 `hasPrice` 的区别：后者把 SKU 逐款价也算进来。
  var hasItemLevelPrice: Bool {
    price != nil || deposit != nil || balance != nil
  }

  /// 派生价格区间（元）。只有 SKU 表带价时也能得出区间。
  var priceRange: (min: Int, max: Int)? {
    let values = effectivePrices
    guard let low = values.min(), let high = values.max() else { return nil }
    return (low, high)
  }

  /// 该单品自己的定金（元）。定金与「参考价 / 现货价」是两个维度，分开统计。
  var effectiveDeposits: [Int] { deposit.map { [$0] } ?? [] }

  /// 价格展示：定金口径优先（预售期最常见），其次「参考价 / 现货价」区间。
  ///
  /// 归集商品（价格全在 SKU 表里，`price` 为 nil）会显示成 `¥199–699` 而不是
  /// 「价格待补充」——这是派生区间带来的直接收益。
  var priceText: String {
    if let deposit, let balance {
      return "定金 ¥\(deposit) · 尾款 ¥\(balance)"
    }
    if let deposit { return "定金 ¥\(deposit)" }
    // 全款预约价：独立于现货区间与定金的一档，明示「预约」口径。
    if let preorderPrice { return "预约价 ¥\(preorderPrice)" }
    if let range = priceRange {
      return range.min == range.max ? "¥\(range.min)" : "¥\(range.min)–\(range.max)"
    }
    if let balance { return "尾款 ¥\(balance)" }
    return "价格待补充"
  }

  /// 带口径前缀的价格文案，用于详情页（`参考价 ¥329`）。
  ///
  /// 只在展示的是「参考价 / 现货价 / 尾款」时才加前缀：定金 / 尾款 已经有自己的说法
  /// （`定金 ¥388`、`尾款 ¥400`），再加「参考价」就是第二重口径错误。
  ///
  /// 口径的取法：单品自己的 `priceKind` 优先；单品没有（价格全在 SKU 表的归集商品）
  /// 时退到 `variantPriceKind`——这样「尾款 ¥160–400」才说得出口，
  /// 而不是把一个尾款区间伪装成现货价。
  var priceTextWithKind: String {
    guard deposit == nil, balance == nil, let range = priceRange else { return priceText }
    let amount = range.min == range.max ? "¥\(range.min)" : "¥\(range.min)–\(range.max)"
    guard let kind = priceKind ?? variantPriceKind else { return amount }
    return "\(kind.labelZH) \(amount)"
  }

  /// 该单品是否已有任何可核验价格（含 SKU 逐款价）。
  /// 归集商品的 `price` 为 nil、价格全在 SKU 表里，用这个判断才不会误报「缺价格」。
  var hasPrice: Bool { !effectivePrices.isEmpty || deposit != nil }

  // MARK: 详情页四类价格口径（用户 2026-09-17）

  /// 详情页价格行。`label + value` 直接可读（如「定金」+「¥388」）。
  nonisolated struct DetailPriceRow: Equatable, Sendable {
    let label: String
    let value: String
  }

  /// 阶段是否属于预售线（图透 / 定金 / 尾款 / 预约价）：这几档里「预约价」优先于「现货价」。
  static func isPresaleStage(_ stage: MidsummerStage) -> Bool {
    stage == .preview || stage == .deposit || stage == .balance || stage == .preorder
  }

  /// 上新阶段（含预售）详情页价格：**只保留四类**——定金 / 尾款 / 现货价 / 预约价。
  ///
  /// 显示条件与互斥关系：
  ///   1. **定金 + 尾款成对**（预售定金模式）：有定金先给「定金 ¥x」；尾款**有数据才**
  ///      追加「尾款 ¥y」行（支付定金后还要付的钱）。缺尾款就少一行，不占位、不写
  ///      「待补充」——空行比缺数据更误导。
  ///   2. **归集商品的 SKU 尾款**：单品层无任何价、SKU 逐款价口径统一为 `balance`
  ///      时，派生区间整体按「尾款」展示（如「尾款 ¥160–400」）。
  ///   3. **预约价 vs 现货价互斥**，由系列阶段（`series.stage`，创作者上传第②步
  ///      选定，CloudKit / Bundle 种子下发）决定优先级：
  ///      预售线（图透/定金/尾款）优先展示预约价；出货 / 再贩 / 现货优先展示现货价。
  ///      只有当优先的那类没有数据时，才退回展示另一类——两者绝不同时出现。
  ///   4. **现货价**的取数：单品 `price` 且口径为 `shop`（或未标口径）；
  ///      归集商品退到 SKU 逐款价派生区间（口径统一 `shop` 或未标）。
  ///   5. **参考价（`reference`）及一切划线价 / 会员价 / 到手价 / 促销标签**：
  ///      不在四类之内，详情页一律不渲染；口径细节如需保留走 `priceNote` 文案。
  ///   6. 四类全空才显示「价格待补充」诚实态；某一类缺失只影响该行。
  ///
  /// - Parameter presaleEnded: 定金-尾款预售已结束（用户 2026-09-17 规则 4）。
  ///   此时预约期已了结、商品转入正常销售，**预约价与现货价同时展示**——
  ///   预约价在前（历史成交口径，付过定金尾款的人按它结算），现货价在后
  ///   （当前购买口径）。哪类缺数据就少哪行，两类全缺退回互斥逻辑兜底。
  func detailPriceRows(stage: MidsummerStage, presaleEnded: Bool = false) -> [DetailPriceRow] {
    var rows: [DetailPriceRow] = []

    // 1) 定金 + 尾款：成对展示，缺哪类就少哪行
    if let deposit {
      rows.append(DetailPriceRow(label: "定金", value: "¥\(deposit)"))
    }
    if let balance {
      rows.append(DetailPriceRow(label: "尾款", value: "¥\(balance)"))
    }
    // 2) 归集商品：单品层无价、SKU 口径统一为尾款 → 区间整体按尾款
    if deposit == nil, balance == nil, !hasItemLevelPrice,
      let range = priceRange,
      case .balance? = variantPriceKind
    {
      let amount =
        range.min == range.max ? "¥\(range.min)" : "¥\(range.min)–\(range.max)"
      rows.append(DetailPriceRow(label: "尾款", value: amount))
    }

    // 现货价候选（只有口径为 shop / 未标的价格才算现货价；reference / balance 不算）
    let spotRange: (min: Int, max: Int)? = {
      if let price, priceKind == nil || priceKind == .shop { return priceRange }
      // 价格全在 SKU 表：口径统一 shop 或完全未标 → 默认现货价；balance 已走上面；reference / 混合口径不展示
      guard price == nil, !hasItemLevelPrice, priceKind == nil,
        let range = priceRange
      else { return nil }
      let skuKinds = Set((skus ?? []).compactMap { $0.priceKind })
      guard skuKinds.isEmpty || skuKinds == [.shop] else { return nil }
      return range
    }()
    func spotRow() -> DetailPriceRow? {
      guard let range = spotRange else { return nil }
      let amount = range.min == range.max ? "¥\(range.min)" : "¥\(range.min)–\(range.max)"
      return DetailPriceRow(label: "现货价", value: amount)
    }
    func preorderRow() -> DetailPriceRow? {
      preorderPrice.map { DetailPriceRow(label: "预约价", value: "¥\($0)（全款预约）") }
    }

    // 3) 预约价与现货价：常规按阶段互斥（优先类缺数据才退另一类）；
    //    预售结束则两类同示（预约价在前、现货价在后），缺哪类少哪行。
    let presale = Self.isPresaleStage(stage)
    if presaleEnded {
      if let row = preorderRow() { rows.append(row) }
      if let row = spotRow() { rows.append(row) }
    } else if presale {
      if let row = preorderRow() ?? spotRow() { rows.append(row) }
    } else {
      if let row = spotRow() ?? preorderRow() { rows.append(row) }
    }

    return rows
  }

  /// 尺码从小到大展示排序（用户 2026-09-16 要求）：XS < S < M < L < XL < XXL < F，
  /// 认识不了的码（如「均码」「定制」）按原名排在后面、保持相对顺序。
  /// 三坑尺码基本都落在这张表里；排序是**展示层**行为，不改存储顺序。
  static func sortedSizeLabels(_ sizes: [String]) -> [String] {
    let rank = ["XXS": 0, "XS": 1, "S": 2, "M": 3, "L": 4, "XL": 5, "XXL": 6, "XXXL": 7, "F": 8]
    return sizes.enumerated().sorted { a, b in
      let ra = rank[a.element.uppercased()] ?? 99
      let rb = rank[b.element.uppercased()] ?? 99
      if ra != rb { return ra < rb }
      return a.offset < b.offset
    }
    .map(\.element)
  }

  var sizesText: String {
    sizes.isEmpty ? "尺码待补充" : Self.sortedSizeLabels(sizes).joined(separator: " / ")
  }
}

// MARK: - 系列

nonisolated struct MidsummerSeriesDTO: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let year: Int
  /// 上新日期，`yyyy-MM-dd`
  let launchedOn: String
  let stage: MidsummerStage
  let coverImage: String?
  /// ⚠️ 价格区间**不再存储**，一律由 `priceRange` 从单品（含 SKU 表）派生。
  ///
  /// 旧字段 `priceMin` / `priceMax` 已移除：它们与单品价格是两份数据，
  /// 改一处忘一处，是「价格数据缺失或错误」的直接来源。
  ///
  /// 定金是另一个维度：来源常以价格带形式给出（「定金 7-139 元」），
  /// 无法归到某一个单品上，所以这里保留一对**显式**的定金区间，
  /// 但必须同时写 `priceSource` 说明出处。
  let depositMin: Int?
  let depositMax: Int?
  /// 价格口径与出处说明（例如「定金牌榜价带；逐款参考价见图鉴条目」）
  let priceSource: String?
  /// 系列内可选的尺码并集
  let sizes: [String]
  let colors: [String]
  let summary: String?
  /// 该系列的原文出处（微博上新贴 / 淘宝新品页）
  let sourceURL: String
  /// `public` = 公开渠道整理；`editorial` = 创作者上传补充
  let sourceKind: String
  /// 是否来自可核验的公开来源。false 表示信息待创作者校正。
  let verified: Bool
  let items: [MidsummerItemDTO]

  /// 派生价格区间：取全系列单品（含每个 SKU 的逐款价）的「参考价 / 现货价」极值。
  var priceRange: (min: Int, max: Int)? {
    let values = items.flatMap(\.effectivePrices)
    guard let low = values.min(), let high = values.max() else { return nil }
    return (low, high)
  }

  /// 派生定金区间：显式标注的定金区间优先（来源价带口径），否则取单品定金极值。
  var depositRange: (min: Int, max: Int)? {
    if let low = depositMin, let high = depositMax {
      return (min(low, high), max(low, high))
    }
    let values = items.flatMap(\.effectiveDeposits)
    guard let low = values.min(), let high = values.max() else { return nil }
    return (low, high)
  }

  /// 价格区间文案：`¥119–699`，单值退化为 `¥119`，空缺返回待补充。
  var priceRangeText: String {
    guard let range = priceRange else { return "价格待补充" }
    return range.min == range.max ? "¥\(range.min)" : "¥\(range.min)–\(range.max)"
  }

  /// 定金文案：`定金 ¥7–139`；无定金口径时返回 nil。
  /// 与 `priceRangeText` **分列**——把定金和全款混成一个区间正是以前的口径错误。
  var depositRangeText: String? {
    guard let range = depositRange else { return nil }
    return range.min == range.max ? "定金 ¥\(range.min)" : "定金 ¥\(range.min)–\(range.max)"
  }

  var sizesText: String {
    sizes.isEmpty ? "尺码待补充" : MidsummerItemDTO.sortedSizeLabels(sizes).joined(separator: " / ")
  }

  /// `2024.02.09`
  var launchDateText: String {
    launchedOn.replacingOccurrences(of: "-", with: ".")
  }

  /// 该系列是否已有任何可核验价格（含 SKU 逐款价）。
  var hasPrice: Bool { priceRange != nil || depositRange != nil }

  /// 款式总数：每个单品按自身的款式数累加。
  /// 归集过的商品（一个淘宝链接含多款）在这里会贡献多款，而不是被算成 1 款。
  var variantCount: Int { items.reduce(0) { $0 + $1.variantCount } }

  /// `3 个商品 · 含 9 个款式`；没有多款商品时退化成 `3 款单品`。
  var itemCountText: String {
    let variants = variantCount
    if variants > items.count {
      return "\(items.count) 个商品 · 含 \(variants) 个款式"
    }
    return "\(items.count) 款单品"
  }
}

// MARK: - 品牌目录

nonisolated struct MidsummerCatalogDTO: Codable, Sendable {
  let brandID: String
  let brandName: String
  let brandNameEN: String
  /// 品牌实际成立时间。注意：用户口述为 2023 年，公开工商/百科资料为 2017-04-06，
  /// 这里以可核验来源为准，并在界面与文档中如实说明（见交付说明）。
  let foundedOn: String
  let company: String
  let positioning: String
  let officialShopURL: String
  let weiboURL: String
  /// 版权与资料完整性说明，界面顶部会展示。
  let disclaimer: String
  let series: [MidsummerSeriesDTO]

  /// 年份倒序（新的在前），与图一的年份导航一致。
  var years: [Int] {
    Array(Set(series.map(\.year))).sorted(by: >)
  }

  func series(inYear year: Int) -> [MidsummerSeriesDTO] {
    series
      .filter { $0.year == year }
      .sorted { $0.launchedOn > $1.launchedOn }
  }

  func series(withID id: String) -> MidsummerSeriesDTO? {
    series.first { $0.id == id }
  }

  /// 全部单品（跨系列），品牌页的商品卡片流用它。
  var allItems: [(series: MidsummerSeriesDTO, item: MidsummerItemDTO)] {
    series.flatMap { series in series.items.map { (series, $0) } }
  }
}

// MARK: - 年份导航条目（图一左侧）

nonisolated struct MidsummerYearEntry: Identifiable, Hashable, Sendable {
  let year: Int
  /// 该年份是否有「新品预约」，决定副标题（图一里 2026/2025/2024 写的是「新品预约」）
  let hasPreorder: Bool
  let seriesCount: Int

  var id: Int { year }

  /// 图一左栏文案：「2026年 新品预约」/「2023年 新品」
  var title: String { "\(year)年" }

  var subtitle: String { hasPreorder ? "新品预约" : "新品" }
}
