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

    /// 独立实例（单测 / 预览用）；App 内统一走 `shared`
    init() {}

    /// 测试 / 预览注入
    init(catalog: ShopCatalog) {
        self.catalog = catalog
        self.status = .loaded
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

    /// 合并规则（重构方案 §5.3）：
    ///   · shops/series/products/variants/sizeCharts/assets/styleProfiles：覆盖层**同 id
    ///     实体整体替换**基底（后写胜出）——支撑运营「编辑已发布实体」与「归档」
    ///     （写 archivedAt 后同 id 替换即可生效）；新 id 实体追加。
    ///   · saleEvents：**永远追加**，不做替换（硬约束：销售历史不可覆盖）。
    private func rebuildMergedCatalog() {
        guard let base = baseCatalog else {
            catalog = overlayCatalog
            return
        }
        guard let overlay = overlayCatalog else {
            catalog = base
            return
        }
        var merged = base
        func replaceOrAppend<T: Identifiable>(_ source: [T], into target: inout [T]) {
            for entity in source {
                if let index = target.firstIndex(where: { $0.id == entity.id }) {
                    target[index] = entity
                } else {
                    target.append(entity)
                }
            }
        }
        replaceOrAppend(overlay.shops, into: &merged.shops)
        replaceOrAppend(overlay.series, into: &merged.series)
        replaceOrAppend(overlay.products, into: &merged.products)
        replaceOrAppend(overlay.variants, into: &merged.variants)
        replaceOrAppend(overlay.sizeCharts, into: &merged.sizeCharts)
        replaceOrAppend(overlay.assets, into: &merged.assets)
        // 款式公共档案（SPU 面料 / 款式描述）：同款式键整体替换，后写胜出
        replaceOrAppend(overlay.styleProfiles, into: &merged.styleProfiles)
        merged.saleEvents.append(contentsOf: overlay.saleEvents)
        catalog = merged
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
        let productIDs = Set(catalog.products.filter { $0.shopID == shopID }.map(\.id))
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
        let productIDs = Set(catalog.products.filter { $0.seriesID == series.id }.map(\.id))
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

    func categories(inSeries seriesID: String) -> [String] {
        let present = Array(Set(products(inSeries: seriesID).map(\.category)))
        var ordered: [String] = []
        for c in Self.canonicalCategoryOrder where present.contains(c) && c != "其他" {
            ordered.append(c)
        }
        let known = Set(ordered)
        for c in present where !known.contains(c) {
            ordered.append(c)
        }
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
            let productIDs = Set(catalog.products.filter { $0.seriesID == s.id }.map(\.id))
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
        guard let url = url(for: trimmed) else { return true }
        if url.isFileURL { return !FileManager.default.fileExists(atPath: url.path) }
        return false
    }
}

// MARK: - 图片视图

/// CatalogAsset 引用的统一展示视图（Bundle 图 / 远程图 / 占位）
struct ShopCatalogAssetImage: View {
    let reference: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url = remoteURL {
            AsyncImage(url: url, content: { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: contentMode)
                default:
                    placeholder
                }
            })
        } else if let path = localPath, let loaded = UIImage(contentsOfFile: path) {
            // 文件存在且可解码才渲染；读失败（如沙盒重置后文件丢失）走占位图，
            // 不再渲染空白的 UIImage()（表现为整块空白/黑屏，用户无从判断原因）
            Image(uiImage: loaded)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            placeholder
        }
    }

    private var remoteURL: URL? {
        guard let reference, reference.lowercased().hasPrefix("http") else { return nil }
        return URL(string: reference)
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
}
