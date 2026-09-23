//
//  ShopCatalogSizeChartSharing.swift
//  ItemManager
//
//  尺码表「款式共享」口径（2026-09-23，nonisolated 可单测）。
//
//  需求原文：以「大蝴蝶结背心裙」为例，只要为其中任意一个颜色（比如红色）填写了尺码表，
//  同款其它所有颜色（比如粉色）都必须自动共享同一套尺码数据；不只是后台数据本身，
//  前台商品页外侧显示的尺码信息也要同步 —— 无需重复填写。
//
//  收口结论：**尺码表属于款式，不属于颜色。**
//
//    1. 款式范围 = 同系列 + 同品类 + 同款式名（`ShopCatalogSameDesignGrouper.designKey`），
//       与商品详情页轮播的「同款兄弟」判定**完全一致** —— 轮播里能滑出几个颜色，
//       尺码表就覆盖几个颜色，不会出现「图里有粉色、表里没粉色」。
//
//    2. 读（`canonicalChart`）：款式范围内**结构化内容优先**——取最后一条有 columns/rows
//       的记录；整款都没有结构化内容时才退回最后一条「仅原图」的记录；原图再单独兜底合并。
//       合并后的数组顺序 = Bundle 基底 + 覆盖层追加，所以「最后一条」就是最后写入的那一份
//       （与 `ShopCatalogStore` 合并规则里的「后写胜出」同一口径）。
//       于是：只要同款任意一个颜色填过表，全款立刻可见；存量里「只有红色填过」的数据
//       无需迁移即可生效。而「粉色只传了原图、没填表格」也不会把红色的表格遮蔽掉。
//
//    3. 写（`writePlan`）：把内容**扇出**到款式下每个颜色各一行，内容逐字相同。
//       无论从哪个颜色填写，结果都是「整款一套」；`chart == nil` 同样作用于整款（整款清空）。
//
//    4. 尺码维度（`sizeLabels`）**不硬编码朝向**：项目数据里两种朝向都真实存在 ——
//       Bundle 种子是 `columns = [S,M,L]`，而手填 / OCR 口径（角落标签「尺码」）
//       是 `rows.label = [S,M,L]`。所以取「哪条轴像尺码就用哪条」。
//       旧实现写死 `rows.map(\.label)`，在种子数据上会把「胸围 / 腰围 / 裙长」当尺码显示。
//
//  已知限制：Bundle 种子里的尺码表行**删不掉**（种子只读，覆盖层只能同 id 替换）。
//  因此对「种子商品 + 种子尺码表」这一组合，「清空」写不进覆盖层；运营侧自建的商品
//  尺码表全部住在覆盖层，清空正常生效。编辑（非清空）不受影响：写入时复用既有行 id，
//  同 id 替换即可覆盖种子行。
//

import Foundation

nonisolated enum ShopCatalogSizeChartSharing {

    // MARK: - 款式范围

    /// 是否同款：同系列 + 品类与款式名都相同。
    /// `includeArchived == false`（写入口径）时还要求双方**都未归档** —— 不给已归档的颜色
    /// 写尺码表行；`true`（读口径）时归档颜色也算数 —— 某个颜色归档不该把整款的尺码表带走。
    /// 系列已经隐含店家（`CatalogSeries.shopID`），所以不必再比 `shopID`。
    static func isSameDesign(_ a: CatalogProduct, _ b: CatalogProduct,
                             includeArchived: Bool = false) -> Bool {
        guard a.id != b.id, a.seriesID == b.seriesID else { return false }
        guard ShopCatalogSameDesignGrouper.designKey(of: a)
            == ShopCatalogSameDesignGrouper.designKey(of: b) else { return false }
        if includeArchived { return true }
        return a.archivedAt == nil && b.archivedAt == nil
    }

    /// 款式共享范围：自己（恒在第 1 位）+ 同款其它颜色。
    /// 读范围含归档（`includeArchived: true`，见 `canonicalChart`），
    /// 写范围排除归档（`writePlan`）。
    static func designScope(of product: CatalogProduct,
                            among products: [CatalogProduct],
                            includeArchived: Bool = false) -> [CatalogProduct] {
        [product] + products.filter { isSameDesign(product, $0, includeArchived: includeArchived) }
    }

    // MARK: - 读取

    /// 尺码表是否算「有内容」：结构表或原图任一非空。
    /// 只有原图也算有内容（模型契约 `CatalogSizeChart.hasStructuredContent` 注释同款口径）。
    static func isMeaningful(_ chart: CatalogSizeChart) -> Bool {
        !chart.columns.isEmpty
            || !chart.rows.isEmpty
            || !(chart.sourceImage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 款式尺码表（**唯一读取入口**）：款式范围内「结构化内容优先，原图兜底合并」的一条。
    ///
    ///   ① 内容（`columns` / `rows`）取范围内**最后一条有结构化内容**的记录；
    ///      整款都没有结构化内容时，才退回最后一条「仅原图」的记录。
    ///   ② 原图 = 内容来源那条自带的图；它没有图时，取范围内最后一条带图记录的图。
    ///
    /// 为什么不能简单地「取最后一条有内容的」：粉色可能有一条**只上传了原图、
    /// 没填结构化行列**的记录（在录入端很容易发生：先把图传了，表格回头再补）。
    /// 它会遮蔽红色已经填好的完整表格 —— 于是**两个颜色都只剩「查看尺码表原图」**，
    /// 看起来就像「粉色把红色的表弄丢了」。表格的信息量严格大于单张图，所以结构化
    /// 内容永远优先；原图再单独兜底合并，避免内容来源那条恰好没图时把图一起丢掉。
    ///
    /// 同款各颜色因此拿到**同一份内容**，不会各看各的。
    /// 读范围**含归档颜色**：某个颜色归档不该把整款的尺码表一起带走。
    static func canonicalChart(for product: CatalogProduct,
                               among products: [CatalogProduct],
                               charts: [CatalogSizeChart]) -> CatalogSizeChart? {
        let scopeIDs = Set(designScope(of: product, among: products,
                                       includeArchived: true).map(\.id))
        let inScope = charts.filter { scopeIDs.contains($0.productID) && isMeaningful($0) }
        guard let contentSource = inScope.last(where: \.hasStructuredContent) ?? inScope.last else {
            return nil
        }
        var result = contentSource
        if !hasImage(result), let imageSource = inScope.last(where: hasImage) {
            result.sourceImage = imageSource.sourceImage
        }
        return result
    }

    /// 是否带尺码表原图（空白串按没有处理）
    static func hasImage(_ chart: CatalogSizeChart) -> Bool {
        !(chart.sourceImage ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 尺码维度（S / M / L）。
    ///
    /// ⚠️ 项目里两种朝向**都真实存在**，不能硬编码其中一条：
    ///   · Bundle 种子数据：`columns = [S, M, L]`，`rows.label = 胸围 / 腰围 / 裙长`；
    ///   · 手填与 OCR 口径：角落标签是「尺码」（`structuredTable(cornerLabel: "尺码")`、
    ///     深度编辑页占位「尺码,胸围,衣长」、OCR 注释「首个词元是左上角标签」），
    ///     即 `rows.label = 尺码`，`columns` 才是部位。
    /// 于是判定规则是「哪条轴**像尺码**就用哪条」：先看列、再看行标签；
    /// 两条都不像时按主流口径取行标签（空则退回列）。旧实现直接 `rows.map(\.label)`，
    /// 在种子数据上会把「胸围 / 腰围 / 裙长」当成尺码显示出来。
    /// 走 `CatalogManualChartText.normalized` 是为了兼容旧数据里混进列头的「尺码」标签列。
    static func sizeLabels(of chart: CatalogSizeChart?) -> [String] {
        guard let chart else { return [] }
        let normalized = CatalogManualChartText.normalized(columns: chart.columns, rows: chart.rows)
        let columns = normalized.columns.filter { !$0.isEmpty }
        let rowLabels = normalized.rows.map(\.label).filter { !$0.isEmpty }

        if looksLikeSizeRun(columns) { return columns }
        if looksLikeSizeRun(rowLabels) { return rowLabels }
        return rowLabels.isEmpty ? columns : rowLabels
    }

    /// 一整条轴是否「像尺码序列」：要求**全部**词元都是尺码词，避免把
    /// 「胸围 / 腰围 / 裙长」这种部位轴误判进来。
    static func looksLikeSizeRun(_ tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        return tokens.allSatisfy(isSizeToken)
    }

    /// 单个词元是否尺码：S / M / L / XS / XXL / 均码 / 90 / 100 …
    static func isSizeToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let upper = trimmed.uppercased()
        if ["均码", "均", "一码", "FREE", "F", "ONE SIZE", "OS"].contains(upper) { return true }
        if trimmed.contains("码"), trimmed.count <= 4 { return true }

        // 字母码：只由 X / S / M / L 组成（XS / S / M / L / XL / XXL / XXXL…）
        let letterBody = upper.replacingOccurrences(of: "号", with: "")
        let sizeLetters = CharacterSet(charactersIn: "XSML")
        if !letterBody.isEmpty, letterBody.count <= 5,
           letterBody.unicodeScalars.allSatisfy({ sizeLetters.contains($0) }) {
            return true
        }
        // 数字码：90 / 100（「80-84」这种区间含连字符，不算）
        if (2...3).contains(letterBody.count), letterBody.allSatisfy(\.isNumber) { return true }
        return false
    }

    /// 前台尺码列（展示 / 选择共用，唯一口径）：
    ///   ① 款式共享尺码表的尺码维度（同款任一颜色填过就生效）
    ///   ② 本商品规格尺码（variants）
    ///   ③ 同款其它颜色的规格尺码
    /// `sizesByProduct` 用闭包**惰性**求值：命中 ① 时不会去算整份规格尺码表。
    static func sizeRun(for product: CatalogProduct,
                        among products: [CatalogProduct],
                        charts: [CatalogSizeChart],
                        sizesByProduct: () -> [String: [String]]) -> [String] {
        let fromChart = sizeLabels(of: canonicalChart(for: product, among: products, charts: charts))
        if !fromChart.isEmpty { return fromChart }

        let sizes = sizesByProduct()
        let own = (sizes[product.id] ?? []).filter { !$0.isEmpty }
        if !own.isEmpty { return own }

        for sibling in designScope(of: product, among: products,
                                   includeArchived: true).dropFirst() {
            let inherited = (sizes[sibling.id] ?? []).filter { !$0.isEmpty }
            if !inherited.isEmpty { return inherited }
        }
        return []
    }

    /// 规格尺码索引（variants → 按出现顺序去重）。纯函数，供 Store 直接调用。
    static func variantSizesByProduct(_ catalog: ShopCatalog) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for variant in catalog.variants {
            guard let size = variant.size?
                .trimmingCharacters(in: .whitespacesAndNewlines), !size.isEmpty else { continue }
            var list = result[variant.productID] ?? []
            if !list.contains(size) { list.append(size) }
            result[variant.productID] = list
        }
        return result
    }

    // MARK: - 写入

    /// 扇出产物：要删除的 productID（整款）+ 要写入的行（每色一行，内容相同）
    struct WritePlan: Equatable {
        var removals: [String] = []
        var upserts: [CatalogSizeChart] = []
    }

    /// 写入产物（唯一口径）：无论从哪个颜色填写，都归一化到**整款**。
    ///   · `chart == nil` → 只删不写：清空整款（不是只清当前颜色）。
    ///   · `chart != nil` → 先删整款旧行，再为款式下每个颜色写一行内容完全相同的表。
    ///     id 优先复用该颜色**既有行**的 id（含 Bundle 种子 id —— 同 id 替换才真正生效），
    ///     没有则用确定性 id `sizechart-<productID>`，保证不会留下重复行。
    static func writePlan(chart: CatalogSizeChart?,
                          for product: CatalogProduct,
                          among products: [CatalogProduct],
                          charts: [CatalogSizeChart]) -> WritePlan {
        let scope = designScope(of: product, among: products)
        var plan = WritePlan(removals: scope.map(\.id))
        guard let chart else { return plan }

        for target in scope {
            var row = chart
            row.id = existingChartID(forProduct: target.id, charts: charts)
                ?? deterministicChartID(forProduct: target.id)
            row.productID = target.id
            plan.upserts.append(row)
        }
        return plan
    }

    /// 该商品当前尺码表行的 id（后写胜出 = 覆盖层优先）；用于写入时同 id 替换。
    static func existingChartID(forProduct productID: String,
                                charts: [CatalogSizeChart]) -> String? {
        charts.last { $0.productID == productID }?.id
    }

    /// 稳定 id：同一商品重复扇出永远得到同一个 id（幂等，不会堆重复行）
    static func deterministicChartID(forProduct productID: String) -> String {
        "sizechart-\(productID)"
    }
}
