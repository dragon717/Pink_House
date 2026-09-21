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
    ///   · shops/series/products/variants/sizeCharts/assets：覆盖层**同 id 实体整体替换**
    ///     基底（后写胜出）——支撑运营「编辑已发布实体」与「归档」（写 archivedAt 后
    ///     同 id 替换即可生效）；新 id 实体追加。
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
        merged.saleEvents.append(contentsOf: overlay.saleEvents)
        catalog = merged
    }

    nonisolated static func bundleURL(in bundle: Bundle) -> URL? {
        // 与 TimeHall / Midsummer 相同的三级查找：子目录 → Resources/子目录 → 根
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

    /// 尺码去重（保持出现顺序）
    func sizes(forProduct productID: String) -> [String] {
        var seen = Set<String>()
        return variants(forProduct: productID).compactMap(\.size).filter { seen.insert($0).inserted }
    }

    func sizeChart(forProduct productID: String) -> CatalogSizeChart? {
        catalog?.sizeCharts.first { $0.productID == productID }
    }

    func priceArchive(forProduct productID: String) -> CatalogPriceArchive {
        CatalogPriceArchive(events: saleEvents(forProduct: productID))
    }

    func saleEvents(forProduct productID: String) -> [CatalogSaleEvent] {
        catalog?.saleEvents.filter { $0.productID == productID } ?? []
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
    static func url(for reference: String?, bundle: Bundle = .main) -> URL? {
        guard var name = reference?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        } else if let path = localPath {
            Image(uiImage: UIImage(contentsOfFile: path) ?? UIImage())
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
