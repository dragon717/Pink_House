//
//  ShopCatalogStore.swift
//  ItemManager
//
//  「店家上新 / 历年系列」只读浏览数据层（Phase 2：只读浏览）。
//
//  需求来源：docs/少女心愿_店家上新_第一版落地计划.md
//    - §8  时光馆内部入口：当前上新 / 历年系列 / 全部店家；搜索范围 = 店家名与别名
//    - §9  店家列表：最近上新时间 + 已收录系列数量
//    - §10 店家主页：当前上新 + 按年份翻阅历年系列
//    - §11 系列详情：分类筛选（JSK / OP / SK / …）
//    - §13 商品详情：价格档案（历史预约价 + 当前现货价 + 差价）
//
//  设计约束（计划 §34）：公共 Catalog 与用户私有状态分层——本 Store 只读
//  Catalog，不写任何用户状态；心愿 / 尾款 / 衣橱写入在 Phase 3/4 接入。
//

import Foundation
import SwiftUI
import Combine

// MARK: - 店家商品库 Store

@MainActor
final class ShopCatalogStore: ObservableObject {
    static let shared = ShopCatalogStore()

    enum LoadStatus: Equatable {
        case idle
        case loaded
        case failed(String)
    }

    /// Bundle 整包资源名（Resources/ShopCatalog/shop-catalog.json）
    static let bundleResourceName = "shop-catalog"

    @Published private(set) var catalog: ShopCatalog?
    @Published private(set) var status: LoadStatus = .idle

    /// 运营端发布的覆盖层（Phase 6）：发布后与 Bundle 种子合并展示
    private var baseCatalog: ShopCatalog?
    private var overlayCatalog: ShopCatalog?

    /// 云端发布的商店目录（消费通道只读拉取，见 `ShopCatalogCloudSyncService`）。
    /// 优先级低于本机覆盖层：覆盖层是运营**未发布**的最新编辑，必须赢过已发布快照；
    /// 又高于 Bundle 种子：远端整包是运营批准发布后的最新事实。
    private var remoteCatalog: ShopCatalog?

    /// 独立实例（单测 / 预览用）；App 内统一走 `shared`
    init() {}

    /// 测试 / 预览注入
    init(catalog: ShopCatalog) {
        self.catalog = catalog
        self.status = .loaded
    }

    /// 测试注入「合成种子」基底（Bundle 只读语义）：
    /// `isSeedShop/Series/Product` 等守卫据此判定；App 内一律走 `loadFromBundleIfNeeded`。
    /// 2026-09-24 种子连根清理后，原种子夹具由 `ShopCatalogSeedFixture` 提供。
    init(baseCatalog: ShopCatalog) {
        self.baseCatalog = baseCatalog
        rebuildMergedCatalog()
    }

    // MARK: 加载

    /// 从 Bundle 加载整包（同步、开销极小：JSON 反序列化 + 内存索引），
    /// 并合并运营覆盖层（如存在）。
    @discardableResult
    func loadFromBundleIfNeeded(bundle: Bundle = .main) -> ShopCatalog? {
        guard catalog == nil else { return catalog }
        guard let url = Self.bundleURL(in: bundle) else {
            status = .failed("Bundle 中未找到 \(Self.bundleResourceName).json")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            baseCatalog = try decoder.decode(ShopCatalog.self, from: data)
            status = .loaded
        } catch {
            status = .failed("Catalog 解析失败: \(error.localizedDescription)")
        }
        overlayCatalog = ShopCatalogDraftStore.loadOverlay()
        rebuildMergedCatalog()
        return catalog
    }

    /// 运营发布后重新合并覆盖层（Phase 6）
    func reloadWithOverlay() {
        overlayCatalog = ShopCatalogDraftStore.loadOverlay()
        rebuildMergedCatalog()
    }

    /// 云端同步服务安装已通过三层校验的远端目录（消费通道只读）。
    /// 传 nil = 公共库当前没有商店内容（清空远端层，回退到 base + overlay）。
    /// 只进内存、不落盘：下次冷启动由同步服务按缓存/节流策略重新拉取，
    /// 避免与包缓存（`ShopCatalogPackCache`）形成两份真相。
    func installRemoteCatalog(_ remote: ShopCatalog?) {
        remoteCatalog = remote
        rebuildMergedCatalog()
    }

    // MARK: 三层合并

    /// 把一层目录合并进已有结果：
    ///   · shops/series/products/variants/sizeCharts/assets/styleProfiles：
    ///     同 id 实体整体替换、新 id 追加（后写胜出，与覆盖层原规则一致）。
    ///   · saleEvents：**追加 + 按 id 去重**。远端整包携带全部历史事件，
    ///     与种子/既有层重叠的事件按 id 去重，不产生重复记录；
    ///     同 id 不同内容时保留先到的（append-only 硬约束：销售历史永不改写）。
    ///   · 墓碑：removed*IDs 求并集（任何一层声明删除即生效）。
    /// `accumulated` 为 nil 时直接以 `layer` 为起点（`ShopCatalog` 是 struct 值类型）。
    private static func merging(_ layer: ShopCatalog, into accumulated: ShopCatalog?) -> ShopCatalog {
        guard var merged = accumulated else { return layer }
        func replaceOrAppend<T: Identifiable>(_ source: [T], into target: inout [T]) {
            for entity in source {
                if let index = target.firstIndex(where: { $0.id == entity.id }) {
                    target[index] = entity
                } else {
                    target.append(entity)
                }
            }
        }
        replaceOrAppend(layer.shops, into: &merged.shops)
        replaceOrAppend(layer.series, into: &merged.series)
        replaceOrAppend(layer.products, into: &merged.products)
        replaceOrAppend(layer.variants, into: &merged.variants)
        replaceOrAppend(layer.sizeCharts, into: &merged.sizeCharts)
        replaceOrAppend(layer.assets, into: &merged.assets)
        replaceOrAppend(layer.styleProfiles, into: &merged.styleProfiles)
        var knownEventIDs = Set(merged.saleEvents.map(\.id))
        for event in layer.saleEvents where knownEventIDs.insert(event.id).inserted {
            merged.saleEvents.append(event)
        }
        for id in layer.removedShopIDs where !merged.removedShopIDs.contains(id) {
            merged.removedShopIDs.append(id)
        }
        for id in layer.removedSeriesIDs where !merged.removedSeriesIDs.contains(id) {
            merged.removedSeriesIDs.append(id)
        }
        for id in layer.removedProductIDs where !merged.removedProductIDs.contains(id) {
            merged.removedProductIDs.append(id)
        }
        return merged
    }

    /// 合并规则（重构方案 §5.3 + 云同步三层扩展）：合并优先级 **base → remote → overlay**，
    /// 后一层赢过前一层：
    ///   · Bundle 种子（base）是出厂事实；远端整包（remote）是运营批准发布后的最新事实；
    ///     本机覆盖层（overlay）是运营**未发布**的最新编辑，优先级最高。
    ///   · 各层实体合并规则见 `merging(into:)`（同 id 替换 / 新 id 追加 / saleEvents
    ///     按 id 去重追加 / 墓碑并集）；最后统一过 `applyTombstones` 排除已删除实体。
    private func rebuildMergedCatalog() {
        guard baseCatalog != nil || remoteCatalog != nil || overlayCatalog != nil else {
            // 三层全空 → catalog 保持 nil：
            // `.shared` 的懒加载靠 `catalog == nil` 判定，这里置空对象会让
            // `loadFromBundleIfNeeded` 永久短路、种子再也进不来（2026-09-24 踩到）。
            catalog = nil
            return
        }
        var merged: ShopCatalog? = baseCatalog
        if let remote = remoteCatalog {
            merged = Self.merging(remote, into: merged)
        }
        if let overlay = overlayCatalog {
            merged = Self.merging(overlay, into: merged)
        }
        catalog = merged.map(Self.applyTombstones)
    }

    /// 墓碑过滤（纯函数便于单测）：被强制删除的店家/系列/商品从生效目录排除，
    /// 已删商品的规格与尺码表连坐排除；**销售事件永不排除**（append-only 硬约束）。
    nonisolated static func applyTombstones(_ catalog: ShopCatalog) -> ShopCatalog {
        var result = catalog
        let removedShops = Set(catalog.removedShopIDs)
        let removedSeries = Set(catalog.removedSeriesIDs)
        let removedProducts = Set(catalog.removedProductIDs)
        guard !removedShops.isEmpty || !removedSeries.isEmpty || !removedProducts.isEmpty
        else { return result }
        if !removedShops.isEmpty { result.shops.removeAll { removedShops.contains($0.id) } }
        if !removedSeries.isEmpty { result.series.removeAll { removedSeries.contains($0.id) } }
        if !removedProducts.isEmpty {
            result.products.removeAll { removedProducts.contains($0.id) }
            result.variants.removeAll { removedProducts.contains($0.productID) }
            result.sizeCharts.removeAll { removedProducts.contains($0.productID) }
        }
        return result
    }

    nonisolated static func bundleURL(in bundle: Bundle) -> URL? {
        // 三级查找：子目录 → Resources/子目录 → 根（含 TimeHall/images 既有图片回退）
        bundle.url(forResource: bundleResourceName, withExtension: "json", subdirectory: "ShopCatalog")
            ?? bundle.url(forResource: bundleResourceName, withExtension: "json", subdirectory: "Resources/ShopCatalog")
            ?? bundle.url(forResource: bundleResourceName, withExtension: "json")
    }

    // MARK: 店家（计划 §9）

    /// 用户侧查询统一排除已归档实体（V1.1 §4.2：归档后用户端不再展示；
    /// 运营端绕过本层直接查 `catalog` 原始数组）。
    nonisolated static func isLive(_ archivedAt: Date?) -> Bool { archivedAt == nil }

    /// 实体是否来自 Bundle 种子（只读）：运营「物理删除」只对覆盖层产物有效，
    /// 种子实体只能归档（同 id 替换写 archivedAt）。
    func isSeedShop(id: String) -> Bool { baseCatalog?.shops.contains { $0.id == id } ?? false }
    func isSeedSeries(id: String) -> Bool { baseCatalog?.series.contains { $0.id == id } ?? false }
    func isSeedProduct(id: String) -> Bool { baseCatalog?.products.contains { $0.id == id } ?? false }

    func shop(id: String) -> CatalogShop? {
        catalog?.shops.first { $0.id == id && Self.isLive($0.archivedAt) }
    }

    /// 店家最近一次「上新」时间：取该店已开始（startAt ≤ now）的 SaleEvent 里最新的
    /// startAt；未来的排期（如未开始的现货档）不算「已上新」。
    /// 没有任何已开始销售记录时回退为最新系列年份的年初（保证卡片始终有时间可展示）。
    func latestActivityDate(shopID: String, now: Date = Date()) -> Date? {
        guard let catalog else { return nil }
        // 归档商品不计入「最近上新」：已发布到云端的旧包仍可能带着归档条目
        // （2026-09-25 起发布端构建时已剔除，存量包没有），展示口径必须自己再过滤一次。
        let productIDs = Set(catalog.products
            .filter { $0.shopID == shopID && Self.isLive($0.archivedAt) }.map(\.id))
        let dates = catalog.saleEvents
            .filter { productIDs.contains($0.productID) }
            .compactMap(\.startAt)
            .filter { $0 <= now }
        if let latest = dates.max() { return latest }
        let year = series(inShop: shopID).compactMap(\.year).max()
        return year.flatMap {
            Calendar(identifier: .gregorian).date(from: DateComponents(year: $0, month: 1, day: 1))
        }
    }

    /// 店家列表：按最近上新时间倒序（排除已归档店家）
    func shopsSortedByActivity() -> [CatalogShop] {
        guard let catalog else { return [] }
        return catalog.shops
            .filter { Self.isLive($0.archivedAt) }
            .sorted {
                (latestActivityDate(shopID: $0.id) ?? .distantPast)
                    > (latestActivityDate(shopID: $1.id) ?? .distantPast)
            }
    }

    // MARK: 字典序访问器（展示列表的唯一出口）

    /// 根因说明：catalog 里的数组是**录入顺序 / JSON 顺序**，不是字典序。
    /// 任何要按名称展示的列表（运营端实体管理、补录草稿的店家/系列选择器等）
    /// 都必须走这三个访问器或 `AZIndexGrouping.groups`，禁止直接遍历原始数组。
    /// 这里包含已归档实体（运营端需要看到并管理它们）。
    func shopsSortedByName() -> [CatalogShop] {
        AZIndexGrouping.sortedByName(catalog?.shops ?? []) { $0.name }
    }

    func seriesSortedByName() -> [CatalogSeries] {
        AZIndexGrouping.sortedByName(catalog?.series ?? []) { $0.name }
    }

    func productsSortedByName() -> [CatalogProduct] {
        AZIndexGrouping.sortedByName(catalog?.products ?? []) { $0.name }
    }

    /// 店家搜索：正式名包含命中或任一别名包含命中（计划 §8：第一版搜索范围 = 店家名称与别名）
    func searchShops(keyword: String) -> [CatalogShop] {
        let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return shopsSortedByActivity() }
        return shopsSortedByActivity().filter { shop in
            shop.name.lowercased().contains(q)
                || shop.aliases.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: 系列（计划 §10 / §11）

    func series(id: String) -> CatalogSeries? {
        catalog?.series.first { $0.id == id && Self.isLive($0.archivedAt) }
    }

    /// 店家的全部系列，按年份倒序（无年份的排最后；排除已归档系列）
    func series(inShop shopID: String) -> [CatalogSeries] {
        guard let catalog else { return [] }
        return catalog.series
            .filter { $0.shopID == shopID && Self.isLive($0.archivedAt) }
            .sorted {
                switch (($0.year ?? .min, $1.year ?? .min)) {
                case let (a, b) where a != b: return a > b
                default: return $0.id < $1.id
                }
            }
    }

    func years(inShop shopID: String) -> [Int] {
        Array(Set(series(inShop: shopID).compactMap(\.year))).sorted(by: >)
    }

    func productCount(inSeries seriesID: String) -> Int {
        catalog?.products.filter { $0.seriesID == seriesID && Self.isLive($0.archivedAt) }.count ?? 0
    }

    /// 系列卡上的「yyyy.MM 上新」：该系列下已开始的最新 SaleEvent 时间（参考图4）
    func latestSeriesActivity(_ series: CatalogSeries, now: Date = Date()) -> Date? {
        guard let catalog else { return nil }
        // 同上：归档商品不参与系列「上新时间」推导
        let productIDs = Set(catalog.products
            .filter { $0.seriesID == series.id && Self.isLive($0.archivedAt) }.map(\.id))
        return catalog.saleEvents
            .filter { productIDs.contains($0.productID) }
            .compactMap(\.startAt)
            .filter { $0 <= now }
            .max()
    }

    /// 系列下某分类的商品；`nil` = 全部分类（排除已归档商品）
    func products(inSeries seriesID: String, category: String? = nil) -> [CatalogProduct] {
        guard let catalog else { return [] }
        let all = catalog.products.filter { $0.seriesID == seriesID && Self.isLive($0.archivedAt) }
        guard let category else { return all }
        return all.filter { $0.category == category }
    }

    /// 系列详情分类筛选（计划 §11）：全部 / JSK / OP / SK / Blouse / KC / 小物 / 鞋 / 包 / 其他
    /// 固定顺序在前，其余分类追加在「其他」语义段之前，去重。
    static let canonicalCategoryOrder = [
        "JSK", "OP", "SK", "Blouse", "KC", "小物", "鞋", "包", "其他",
    ]

    // MARK: 自定义分类（2026-09-24 需求：运营可增删改分类）

    private static let customCategoriesKey = "shopcatalog.customCategories.v1"

    /// 运营自定义分类词表（UserDefaults 轻量存储；添加顺序即展示顺序）。
    /// 固定品类（canonicalCategoryOrder）是系统口径——品类参与加购主物判定
    /// （ShopCatalogWardrobeCategory）与类型分组，**禁止改名/删除**；
    /// 自定义分类由运营在「管理分类」页维护。
    static var customCategories: [String] {
        get { UserDefaults.standard.stringArray(forKey: customCategoriesKey) ?? [] }
        set {
            let cleaned = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            UserDefaults.standard.set(cleaned, forKey: customCategoriesKey)
        }
    }

    /// 分类候选**唯一口径**（所有分类 Picker / 类型分组共用）：
    /// 固定品类（除「其他」）→ 自定义分类（添加序）→ 「其他」兜底；去重。
    static var categoryCandidates: [String] {
        var result = canonicalCategoryOrder.filter { $0 != "其他" }
        for c in customCategories where !result.contains(c) {
            result.append(c)
        }
        result.append("其他")
        return result
    }

    /// 系列分区顺序（点菜页 / 系列详情共用口径）：
    /// 固定品类（canonicalCategoryOrder，除「其他」）在前；
    /// 其余分类按**商品录入顺序**（catalog 数组首次出现序）追加，去重。
    ///
    /// 2026-09-25 根因修复（点菜页分区乱跳）：之前非固定品类用
    /// `Array(Set(products.map(\.category)))` 派生顺序 —— Set 的遍历序取决于
    /// **进程级随机哈希种子**，每次冷启动都换一个排法，用户看到的就是
    /// 「商品列表不断重新排序、位置频繁变动」。与是否切换颜色无关，
    /// 只是乱序恰好在反复进出页面 / 重启调试时被观察到。
    /// 唯一确定性来源是 catalog 数组本身的录入顺序（持久化，跨启动稳定）。
    func categories(inSeries seriesID: String) -> [String] {
        var present: [String] = []
        var seen = Set<String>()
        for p in products(inSeries: seriesID) where seen.insert(p.category).inserted {
            present.append(p.category)
        }
        var ordered = Self.canonicalCategoryOrder.filter { $0 != "其他" && present.contains($0) }
        let known = Set(ordered)
        let tail = present.filter { !known.contains($0) }
        ordered.append(contentsOf: tail.filter { $0 != "其他" })
        if tail.contains("其他") { ordered.append("其他") }
        return ordered
    }

    // MARK: 商品与规格（计划 §13）

    func product(id: String) -> CatalogProduct? {
        catalog?.products.first { $0.id == id && Self.isLive($0.archivedAt) }
    }

    func variants(forProduct productID: String) -> [CatalogProductVariant] {
        catalog?.variants.filter { $0.productID == productID } ?? []
    }

    /// 配色去重（保持出现顺序）
    func colors(forProduct productID: String) -> [String] {
        var seen = Set<String>()
        return variants(forProduct: productID).compactMap(\.color).filter { seen.insert($0).inserted }
    }

    /// **同款颜色集合**（详情页「配色」行的唯一数据源，2026-09-23 系统性修复）。
    ///
    /// 与标题的「· N 色」**同源**：两者都由 `ShopCatalogDesignPalette` 的同款商品集合推导。
    /// 旧口径读的是「本商品自己的规格色」，在 SPU/SKU 结构下每个颜色是独立商品 →
    /// 本商品只有自己那一色，纯名称命名（没建规格）时一条都没有 →
    /// 「配色」行整行消失，而标题仍写着「· 3 色」。
    ///
    /// ⚠️ 加购弹窗里的「规格色选择」（挑本商品要买哪个色号）仍然用
    /// `colors(forProduct:)` —— 那个是**本商品规格**的选择器，不是「这款有哪几色」，
    /// 两者语义不同，不要合并。
    func designColors(forProduct productID: String) -> [String] {
        guard let catalog,
              let product = catalog.products.first(where: { $0.id == productID }) else {
            // 商品不在目录（脏引用）：退回本商品规格色，至少不空手
            return colors(forProduct: productID)
        }
        return ShopCatalogDesignPalette.colors(
            of: product,
            among: catalog.products,
            explicitColors: { self.colors(forProduct: $0.id) })
    }

    /// 尺码去重（保持出现顺序）
    func sizes(forProduct productID: String) -> [String] {
        var seen = Set<String>()
        return variants(forProduct: productID).compactMap(\.size).filter { seen.insert($0).inserted }
    }

    /// 尺码表（2026-09-23 **款式共享**）：表属于款式，不属于颜色 ——
    /// 只要同款任意一个颜色填过，全款都能拿到同一张表，无需逐个颜色重复填写。
    /// 解析口径唯一收口在 `ShopCatalogSizeChartSharing.canonicalChart`，
    /// 调用方不要再自己 `.first { productID == ... }`（那就又变成「只看自己」了）。
    func sizeChart(forProduct productID: String) -> CatalogSizeChart? {
        guard let catalog else { return nil }
        guard let product = catalog.products.first(where: { $0.id == productID }) else {
            // 商品已删 / 脏引用：退回该行自身的直查，至少不误共享到别的款
            return catalog.sizeCharts.last { $0.productID == productID }
        }
        return ShopCatalogSizeChartSharing.canonicalChart(for: product,
                                                          among: catalog.products,
                                                          charts: catalog.sizeCharts)
    }

    /// 前台尺码列（详情页「尺码」行、点菜页尺码 chips、预约尺码选择共用同一口径）：
    /// 款式共享尺码表的尺码维度 → 本商品规格尺码 → 同款其它颜色的规格尺码。
    /// 尺码维度的朝向消歧收在 `ShopCatalogSizeChartSharing.sizeLabels`。
    func sizeRun(forProduct productID: String) -> [String] {
        guard let catalog, let product = catalog.products.first(where: { $0.id == productID }) else {
            return sizes(forProduct: productID)
        }
        return ShopCatalogSizeChartSharing.sizeRun(
            for: product, among: catalog.products, charts: catalog.sizeCharts,
            sizesByProduct: { ShopCatalogSizeChartSharing.variantSizesByProduct(catalog) })
    }

    /// 款式公共档案（SPU 面料 / 款式描述，2026-09-23 录入端重构）。
    /// 尺码表不在这里 —— 它是独立的款式级实体，见 `sizeChart(forProduct:)`。
    func styleProfile(forProduct productID: String) -> CatalogStyleProfile? {
        guard let catalog, let product = catalog.products.first(where: { $0.id == productID }) else {
            return nil
        }
        return ShopCatalogStyleProfileSharing.profile(for: product,
                                                      among: catalog.products,
                                                      profiles: catalog.styleProfiles)
    }

    /// 款式面料（**款式级公共属性**：同款各颜色读到同一份，仅需录入一次）
    func fabric(forProduct productID: String) -> String? {
        guard let catalog, let product = catalog.products.first(where: { $0.id == productID }) else {
            return nil
        }
        return ShopCatalogStyleProfileSharing.fabric(for: product,
                                                     among: catalog.products,
                                                     profiles: catalog.styleProfiles)
    }

    /// 款式描述（**款式级公共属性**）：档案优先，回退商品自身 description（历史写法）
    func styleDescription(forProduct productID: String) -> String? {
        guard let catalog, let product = catalog.products.first(where: { $0.id == productID }) else {
            return nil
        }
        return ShopCatalogStyleProfileSharing.styleDescription(for: product,
                                                              among: catalog.products,
                                                              profiles: catalog.styleProfiles)
    }

    /// 价格档案 = append-only 历史推导值 + 价格修正覆盖值（修正优先）。
    /// 本方法只读：任何写入都必须走 `ShopCatalogDraftStore.correctCurrentPrice`
    ///（修正，覆盖当前状态）或 `appendSaleRecord`（追加，新增业务事件）。
    func priceArchive(forProduct productID: String) -> CatalogPriceArchive {
        let correction = catalog?.products.first { $0.id == productID }?.priceCorrection
        return CatalogPriceArchive(events: saleEvents(forProduct: productID), correction: correction)
    }

    func saleEvents(forProduct productID: String) -> [CatalogSaleEvent] {
        catalog?.saleEvents.filter { $0.productID == productID } ?? []
    }

    /// 追加式销售历史（按批次时间倒序：最近批次在前；并列时后追加的在前，
    /// 与 `CatalogPriceArchive` 的「最新」判定完全一致）。
    /// 只读视图：不支持任何改写接口，历史一经写入不可变。
    func saleHistory(forProduct productID: String) -> [CatalogSaleEvent] {
        saleEvents(forProduct: productID)
            .enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.startAt ?? .distantPast
                let r = rhs.element.startAt ?? .distantPast
                if l != r { return l > r }
                return lhs.offset > rhs.offset
            }
            .map(\.element)
    }

    func saleEvent(id: String) -> CatalogSaleEvent? {
        catalog?.saleEvents.first { $0.id == id }
    }

    func asset(id: String) -> CatalogAsset? {
        catalog?.assets.first { $0.id == id }
    }

    // MARK: 上新窗口状态（只读展示用；尾款状态机在 Phase 3 落地）

    enum SaleWindowStatus: Equatable {
        case upcoming   // 未开始
        case open       // 进行中
        case ended      // 已结束
        case ongoing    // 不设时间窗口（长期有效）
    }

    func windowStatus(of event: CatalogSaleEvent, now: Date = Date()) -> SaleWindowStatus {
        switch (event.startAt, event.endAt) {
        case let (start?, end?):
            if now < start { return .upcoming }
            if now > end { return .ended }
            return .open
        case let (start?, nil):
            return now < start ? .upcoming : .open
        case let (nil, end?):
            return now > end ? .ended : .open
        case (nil, nil):
            return .ongoing
        }
    }

    /// 店家主页「当前上新」：系列内任一商品存在「进行中或未开始」的预约 / 现货记录（计划 §10）。
    /// 无档期（startAt/endAt 均空）的记录视为长期在售（.ongoing）——运营发布时可以不填日期，
    /// 这类系列必须出现在「当前上新」，否则会同时掉出历年年份 chip（无年份）导致整体不可见。
    func currentSeries(inShop shopID: String, now: Date = Date()) -> [CatalogSeries] {
        guard let catalog else { return [] }
        return series(inShop: shopID).filter { s in
            // 同上：归档商品的档期不算「当前上新」，否则已归档系列会重新冒出来
            let productIDs = Set(catalog.products
                .filter { $0.seriesID == s.id && Self.isLive($0.archivedAt) }.map(\.id))
            let events = catalog.saleEvents.filter { productIDs.contains($0.productID) }
            return events.contains {
                switch windowStatus(of: $0, now: now) {
                case .open, .upcoming, .ongoing: return true
                default: return false
                }
            }
        }
    }

    /// 店家主页「历年系列」：不属于当前上新的其余系列
    func archiveSeries(inShop shopID: String, now: Date = Date()) -> [CatalogSeries] {
        let current = Set(currentSeries(inShop: shopID, now: now).map(\.id))
        return series(inShop: shopID).filter { !current.contains($0.id) }
    }
}

// MARK: - 图片解析（计划 §5：CatalogAsset 保留 originalURL）

/// 运营上传图片的落盘存储（V1.1 §4.2 图片入口配套）：
/// PhotosPicker 选图 → 压缩写入 Application Support/ShopCatalog/images/ →
/// 生成「local:<文件名>」引用随 CatalogAsset.originalURL / sizeChart.sourceImage 持久化。
nonisolated enum ShopCatalogImageStore {

    static var directory: URL {
        let dir = ShopCatalogStorage.directory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 保存图片数据 → 引用「local:<文件名>」；长边压到 1600px 控制 occupies。
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let scaled = scaledDown(image, maxDimension: 1600)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "img-\(UUID().uuidString.prefix(8)).jpg"
        do {
            try jpeg.write(to: directory.appendingPathComponent(name))
            return "local:\(name)"
        } catch {
            return nil
        }
    }

    /// 「local:」引用 → 文件 URL；非 local 引用返回 nil（交给 Bundle/远程解析）
    static func url(for reference: String) -> URL? {
        guard reference.lowercased().hasPrefix("local:") else { return nil }
        let name = String(reference.dropFirst(6))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/") else { return nil }
        return directory.appendingPathComponent(name)
    }

    private static func scaledDown(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: image.size.width * scale,
                             height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// CatalogAsset 引用解析：
///   · http(s) 开头 → 远程图（AsyncImage）
///   · local: 开头 → 运营上传图（Application Support/ShopCatalog/images/）
///   · 其余视为 Bundle 内文件名（兼容 "bundle:" 前缀），
///     依次在根目录 / images / TimeHall/images / ShopCatalog/images 中查找。
/// 第一版直接复用 Bundle 内已有的时光馆画册图作为演示素材，不复制资源。
nonisolated enum ShopCatalogImageResolver {
    static func url(for reference: String?, bundle: Bundle = .main) -> URL? {        guard var name = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        if name.lowercased().hasPrefix("http://") || name.lowercased().hasPrefix("https://") {
            return URL(string: name)
        }
        if name.lowercased().hasPrefix("local:") {
            return ShopCatalogImageStore.url(for: name)
        }
        // 远端媒体（THMedia）：本地解析不出路径，交给 `ShopCatalogMediaStore` 按需下载
        if name.lowercased().hasPrefix(ShopCatalogSyncProtocol.mediaReferencePrefix) {
            return nil
        }
        if name.lowercased().hasPrefix("bundle:") {
            name = String(name.dropFirst(7))
        }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard !stem.isEmpty else { return nil }
        return bundle.url(forResource: stem, withExtension: ext)
            ?? bundle.url(forResource: stem, withExtension: ext, subdirectory: "images")
            ?? bundle.url(forResource: stem, withExtension: ext, subdirectory: "TimeHall/images")
            ?? bundle.url(forResource: stem, withExtension: ext, subdirectory: "ShopCatalog/images")
    }

    /// 引用能否解析出「本地确实存在」的图片：
    ///   · 空引用 / 解析不出 URL → true（不可用）
    ///   · http(s) 引用 → false（可用性交给网络层，本地无法判断）
    ///   · local: / Bundle 引用 → 按解析出的文件是否存在判定
    /// 用于把「图片显示不出来」变成明确提示（如沙盒重置后 local: 文件丢失），
    /// 而不是渲染一张空白图。nonisolated 纯逻辑，可单测。
    static func isUnavailable(_ reference: String?) -> Bool {
        guard let trimmed = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return true }
        if trimmed.lowercased().hasPrefix("http") { return false }
        // 远端媒体：可用性取决于下载结果，本地无法判定 → 不算「不可用」
        if trimmed.lowercased().hasPrefix(ShopCatalogSyncProtocol.mediaReferencePrefix) { return false }
        guard let url = url(for: trimmed) else { return true }
        if url.isFileURL { return !FileManager.default.fileExists(atPath: url.path) }
        return false
    }
}

// MARK: - 图片视图

/// CatalogAsset 引用的统一展示视图（Bundle 图 / 运营上传图 / 远端媒体 / 占位）
struct ShopCatalogAssetImage: View {
    let reference: String?
    /// 公共库远端媒体的 canonical 键（`CatalogAsset.mediaKey`，公共数据库字段配置方案 §2.2）。
    /// 给了就优先按它取 THMedia；nil 时回退 `reference` 里的 `thmedia:` 旧写法
    /// （解析一律走 `ShopCatalogSyncProtocol.resolvedMediaKey`，调用方不自己拆字符串）。
    var mediaKey: String? = nil
    var contentMode: ContentMode = .fill

    /// 远端媒体（THMedia）下载后的本地文件 —— 按需下载，屏内才拉
    @State private var remoteMediaURL: URL?
    /// 下载过且失败：本次展示周期内不再重试（列表滚动会反复触发 task）
    @State private var remoteMediaFailed = false
    /// http(s) 老引用的重载令牌 —— 点按重试时换一个 identity，
    /// 逼 `AsyncImage` 重新发请求（同一个 URL 它不会自己重试）
    @State private var asyncImageReloadToken = UUID()

    var body: some View {
        content
            .task(id: reference) { await loadRemoteMediaIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if let url = remoteURL {
            AsyncImage(url: url, content: { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                case .failure:
                    // 网络图也要区分「拉失败」与「没有图」，否则用户以为商品图就是这样
                    failedPlaceholder
                default:
                    placeholder
                }
            })
            .id(asyncImageReloadToken)
        } else if let path = remoteMediaPath ?? localPath, let loaded = UIImage(contentsOfFile: path) {
            // 文件存在且可解码才渲染；读失败（如沙盒重置后文件丢失）走占位图，
            // 不再渲染空白的 UIImage()（表现为整块空白/黑屏，用户无从判断原因）
            Image(uiImage: loaded)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if remoteMediaFailed {
            // 本地兜底图也解不出来、远端又下失败 → 必须是「加载失败」而不是「没有图」（方案 §5）
            failedPlaceholder
        } else {
            placeholder
        }
    }

    private func loadRemoteMediaIfNeeded() async {
        let key = ShopCatalogSyncProtocol.resolvedMediaKey(mediaKey, fallbackReferences: [reference])
        guard key != nil else {
            remoteMediaURL = nil
            remoteMediaFailed = false
            return
        }
        guard !remoteMediaFailed else { return }
        if let url = await ShopCatalogMediaStore.shared.resolvedURL(mediaKey: key) {
            remoteMediaURL = url
        } else {
            remoteMediaFailed = true
        }
    }

    /// 点按重试（iOS 运营上传实施方案 §5 的「重试入口」）。
    ///
    /// 两件事都必须做，缺一不可：
    ///   1. 清掉 `ShopCatalogMediaStore` 里**本次会话失败记忆** —— 只把下面的
    ///      `remoteMediaFailed` 置回 false 是没用的，store 会直接返回 nil，
    ///      表现成「点了没反应」；
    ///   2. 换 `asyncImageReloadToken`，让 http(s) 老引用的 `AsyncImage` 重建。
    private func retryLoading() {
        if let key = ShopCatalogSyncProtocol.resolvedMediaKey(
            mediaKey, fallbackReferences: [reference]) {
            ShopCatalogMediaStore.shared.clearSessionFailure(mediaKey: key)
        }
        remoteMediaFailed = false
        asyncImageReloadToken = UUID()
        Task { await loadRemoteMediaIfNeeded() }
    }

    private var remoteURL: URL? {
        guard let reference, reference.lowercased().hasPrefix("http") else { return nil }
        return URL(string: reference)
    }

    private var remoteMediaPath: String? {
        remoteMediaURL?.path
    }

    private var localPath: String? {
        guard let url = ShopCatalogImageResolver.url(for: reference) else { return nil }
        return url.path
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color(red: 0.95, green: 0.93, blue: 0.95))
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(Color(red: 0.72, green: 0.70, blue: 0.74))
        }
    }

    /// 加载失败的明确占位 —— 与上面的「本来就没有图」在视觉与可操作性上都要区分开：
    /// 底色偏暖、图标是「重试」而不是「照片」，并且**可点按重试**。
    /// 依据：iOS 运营上传实施方案 §5「下载失败显示明确占位和重试入口，
    /// 不把图片当作没有图片」。
    private var failedPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color(red: 0.97, green: 0.93, blue: 0.90))
            VStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18))
                Text("加载失败，点按重试")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
            }
            .foregroundStyle(Color(red: 0.78, green: 0.52, blue: 0.40))
        }
        .contentShape(Rectangle())
        .onTapGesture { retryLoading() }
        .accessibilityElement()
        .accessibilityLabel("图片加载失败")
        .accessibilityHint("点按重试")
        .accessibilityAddTraits(.isButton)
    }
}
