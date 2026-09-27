//
//  OpsWorkspace+Editing.swift
//  PinkHouseOps
//
//  商品级编辑命令（方案 §4「操作单位是商品」）。
//
//  ## 为什么要单独一个文件
//
//  编排层（`OpsWorkspace.swift`）已经很长，而这里是一整组**录入语义**：
//  规格 / 尺码表 / 销售记录 / 价格修正 / 归档 / 复制。它们共享同一套契约
//  （R05：返回 Bool、失败只写 `lastError`、只读隔离态一律拒绝），
//  放一起看才看得出「口径是不是一致的」。
//
//  ## 三条贯穿全文件的硬规则
//
//  1. **修正 ≠ 追加**（价格双流程）：`appendSaleEvent` 只往历史里加，
//     永远不覆盖；`applyPriceCorrection` 只维护一份「当前状态」，
//     再次修正整体覆盖。两者不共用逻辑、不互相写入。
//  2. **删除靠归档**：被引用的实体不物理删（`archivedAt` 表达下架）。
//     归档条目在发布时会被剥离 —— 这正是「归档 ≠ 删除」的意义：
//     本机留着追溯，线上不再下发。
//  3. **不做款式级扇出**：同款归组（`ShopCatalogSameDesignGrouper`）、
//     尺码表款式级归一化（`ShopCatalogSizeChartSharing`）、商品改名扇出
//     （`ShopCatalogProductRename`）都只有 iOS 一处实现。Mac 端复制一份
//     就是第二套口径，两边迟早分叉（分叉的表现是「同款被拆成两款」）。
//     所以这里给的是**显式动作**（例如「把尺码表复制到指定商品」），
//     由运营点名，不需要一套归组谓词。
//

import Foundation

// MARK: - 商品详情

extension OpsWorkspace {

    /// 改商品的描述与款式名。
    ///
    /// 款式名（`designName`）是**款式级属性** —— 改它等于改整款的展示名。
    /// 已发布过的商品不给改（理由同 `renameGuard`），未发布的新录入内容可以改。
    @discardableResult
    func updateProductDetail(
        id: String, description: String?, designName: String?
    ) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.products.firstIndex(where: { $0.id == id }) else {
            lastError = "找不到商品 \(id)。"
            return false
        }
        let trimmedDescription = description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesign = designName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let newDesign = (trimmedDesign?.isEmpty ?? true) ? nil : trimmedDesign
        if newDesign != catalog.products[index].designName,
           isPublishedEntity(id) {
            lastError = "款式名是款式级属性，已发布过的商品不能在 Mac 端改（改名口径只有 iOS 一处实现）。"
            return false
        }

        catalog.products[index].description =
            (trimmedDescription?.isEmpty ?? true) ? nil : trimmedDescription
        catalog.products[index].designName = newDesign
        markDirty()
        return true
    }

    /// 这个实体是否已经存在于上次发布的基线快照里（= 线上有它）。
    func isPublishedEntity(_ id: String) -> Bool {
        guard let baseline = baselineCatalog else { return false }
        return baseline.products.contains { $0.id == id }
            || baseline.series.contains { $0.id == id }
            || baseline.shops.contains { $0.id == id }
    }
}

// MARK: - 规格（SKU：配色 + 尺码）

extension OpsWorkspace {

    /// 追加一个规格（配色 + 尺码组合，允许任一为空表示「未区分」）。
    ///
    /// 同一组合不允许重复：`color`/`size` 都相同算重复。重复项在客户端是
    /// 两个长得一样的选项，运营会以为是 App 的 bug。
    @discardableResult
    func addVariant(
        productID: String, color: String?, size: String?, imageAssetID: String?
    ) -> Bool {
        guard canMutate() else { return false }
        guard catalog.products.contains(where: { $0.id == productID }) else {
            lastError = "找不到商品 \(productID)。"
            return false
        }
        let trimmedColor = normalized(color)
        let trimmedSize = normalized(size)
        guard trimmedColor != nil || trimmedSize != nil else {
            lastError = "规格至少要填配色或尺码之一（两者都空等于「未区分」，那是商品本身的含义）。"
            return false
        }
        guard !hasVariant(productID: productID, color: trimmedColor, size: trimmedSize) else {
            lastError = "这个「\(variantLabel(color: trimmedColor, size: trimmedSize))」规格已经有了。"
            return false
        }
        if let assetID = normalized(imageAssetID), !catalog.assets.contains(where: { $0.id == assetID }) {
            lastError = "规格图绑定的图片资源 \(assetID) 不存在，请先在素材库里导入。"
            return false
        }
        catalog.variants.append(CatalogProductVariant(
            id: "variant-\(shortID())",
            productID: productID,
            color: trimmedColor,
            size: trimmedSize,
            imageAssetID: normalized(imageAssetID)))
        markDirty()
        return true
    }

    @discardableResult
    func updateVariant(
        id: String, color: String?, size: String?, imageAssetID: String?
    ) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.variants.firstIndex(where: { $0.id == id }) else {
            lastError = "找不到规格 \(id)。"
            return false
        }
        let productID = catalog.variants[index].productID
        let trimmedColor = normalized(color)
        let trimmedSize = normalized(size)
        guard trimmedColor != nil || trimmedSize != nil else {
            lastError = "规格至少要填配色或尺码之一。"
            return false
        }
        if hasVariant(productID: productID, color: trimmedColor, size: trimmedSize, excluding: id) {
            lastError = "这个「\(variantLabel(color: trimmedColor, size: trimmedSize))」规格已经有了。"
            return false
        }
        if let assetID = normalized(imageAssetID), !catalog.assets.contains(where: { $0.id == assetID }) {
            lastError = "规格图绑定的图片资源 \(assetID) 不存在。"
            return false
        }
        catalog.variants[index].color = trimmedColor
        catalog.variants[index].size = trimmedSize
        catalog.variants[index].imageAssetID = normalized(imageAssetID)
        markDirty()
        return true
    }

    @discardableResult
    func removeVariant(id: String) -> Bool {
        guard canMutate() else { return false }
        guard catalog.variants.contains(where: { $0.id == id }) else {
            lastError = "找不到规格 \(id)。"
            return false
        }
        catalog.variants.removeAll { $0.id == id }
        markDirty()
        return true
    }

    /// 规格的展示名（两处文案共用一份，避免「有的地方写配色、有的地方写颜色」）
    func variantLabel(color: String?, size: String?) -> String {
        switch (color, size) {
        case let (color?, size?): return "\(color) / \(size)"
        case let (color?, nil): return color
        case let (nil, size?): return "尺码 \(size)"
        case (nil, nil): return "未区分"
        }
    }

    private func hasVariant(
        productID: String, color: String?, size: String?, excluding: String? = nil
    ) -> Bool {
        catalog.variants.contains { variant in
            variant.productID == productID
                && variant.id != excluding
                && variant.color == color
                && variant.size == size
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 尺码表

extension OpsWorkspace {

    /// 写一个商品的尺码表（整体替换）。
    ///
    /// ⚠️ Mac 端按**商品**存尺码表，不做款式级归一化（见文件头第 3 条）。
    /// 同款多色要共用一张表，用 `copySizeChart(from:to:)` 显式指定目标。
    ///
    /// 校验口径（需求 v1.2 §S3-B）：
    ///   · 列与行必须**同时**填写或**同时**留空（只有原图时可以都为空）；
    ///   · 每行的数值个数必须等于列数（否则客户端整列错位）。
    ///
    /// - Parameters:
    ///   - allowShrinkingUsedSizes: 新表删掉了仍被现有规格（颜色）使用的尺码时是否放行。
    ///     手工编辑保持 false（先去处理受影响的颜色）；系列向导传 true ——
    ///     它写完尺码表后会**整体重建**该商品的规格，新表与规格必然一致。
    @discardableResult
    func setSizeChart(
        productID: String,
        unit: String?,
        columns: [String],
        rows: [CatalogSizeRow],
        sourceImage: String?,
        allowShrinkingUsedSizes: Bool = false
    ) -> Bool {
        guard canMutate() else { return false }
        guard catalog.products.contains(where: { $0.id == productID }) else {
            lastError = "找不到商品 \(productID)。"
            return false
        }
        let trimmedColumns = columns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // 需求 §S3-B：列和行必须同时存在，不能只填写一半；只有原图时可以都为空。
        guard trimmedColumns.isEmpty == rows.isEmpty else {
            lastError = "尺码表的列与行必须同时填写，或同时留空"
                + "（只有尺码表原图时，结构化列和行可以都为空）。"
            return false
        }
        // 行列不齐是尺码表最常见的脏数据：客户端会整列错位，看起来像「数据全错」。
        // 这里挡在录入端，而不是等发布端结构校验去报一句更含糊的话。
        guard rows.allSatisfy({ $0.values.count == trimmedColumns.count }) else {
            let bad = rows.first { $0.values.count != trimmedColumns.count }
            lastError = "尺码表有一行「\(bad?.label ?? "?")」的数值个数（\(bad?.values.count ?? 0)）"
                + "与列数（\(trimmedColumns.count)）不一致，客户端会整列错位，已拒绝。"
            return false
        }
        let assetID = normalized(sourceImage)
        if let assetID, !catalog.assets.contains(where: { $0.id == assetID }) {
            lastError = "尺码表原图绑定的图片资源 \(assetID) 不存在。"
            return false
        }
        let unitValue = normalized(unit)

        // 收缩保护（需求 §6.2）：新表删掉「正在被颜色使用」的尺码时，先列出受影响的
        // 颜色并要求处理 —— 静默删规格会让那些颜色变成没有可售尺码的空壳。
        if !allowShrinkingUsedSizes {
            let oldLabels = Set(catalog.sizeCharts
                .first(where: { $0.productID == productID })?.rows.map(\.label) ?? [])
            let newLabels = Set(rows.map(\.label))
            let removed = oldLabels.subtracting(newLabels)
            if !removed.isEmpty {
                let affected = catalog.variants
                    .filter { $0.productID == productID && $0.size.map { removed.contains($0) } == true }
                    .compactMap(\.color)
                if !affected.isEmpty {
                    var ordered: [String] = []
                    for color in affected where !ordered.contains(color) { ordered.append(color) }
                    lastError = "新尺码表删掉了仍被使用的尺码："
                        + removed.sorted().joined(separator: "、")
                        + "。受影响的颜色：" + ordered.joined(separator: "、")
                        + "。请先处理这些颜色的可售尺码（或走系列向导整体重建规格）。"
                    return false
                }
            }
        }

        if let index = catalog.sizeCharts.firstIndex(where: { $0.productID == productID }) {
            catalog.sizeCharts[index].unit = unitValue
            catalog.sizeCharts[index].columns = trimmedColumns
            catalog.sizeCharts[index].rows = rows
            catalog.sizeCharts[index].sourceImage = assetID
        } else {
            catalog.sizeCharts.append(CatalogSizeChart(
                id: "chart-\(shortID())",
                productID: productID,
                unit: unitValue,
                columns: trimmedColumns,
                rows: rows,
                sourceImage: assetID))
        }
        markDirty()
        return true
    }

    /// 删掉尺码表。**不动**原图资源（原图可能还被别处引用）。
    @discardableResult
    func clearSizeChart(productID: String) -> Bool {
        guard canMutate() else { return false }
        guard catalog.sizeCharts.contains(where: { $0.productID == productID }) else {
            lastError = "商品 \(productID) 没有尺码表。"
            return false
        }
        catalog.sizeCharts.removeAll { $0.productID == productID }
        markDirty()
        return true
    }

    /// 把一张尺码表复制到指定的其它商品（显式点名，不做款式级自动扇出）。
    @discardableResult
    func copySizeChart(from sourceProductID: String, to targetProductIDs: [String]) -> Bool {
        guard canMutate() else { return false }
        guard let source = catalog.sizeCharts.first(where: { $0.productID == sourceProductID }) else {
            lastError = "商品 \(sourceProductID) 没有尺码表，没有可复制的内容。"
            return false
        }
        let targets = targetProductIDs.filter { $0 != sourceProductID }
        guard !targets.isEmpty else {
            lastError = "请至少选择一个目标商品。"
            return false
        }
        var missing: [String] = []
        for target in targets {
            guard catalog.products.contains(where: { $0.id == target }) else {
                missing.append(target)
                continue
            }
            if let index = catalog.sizeCharts.firstIndex(where: { $0.productID == target }) {
                catalog.sizeCharts[index].unit = source.unit
                catalog.sizeCharts[index].columns = source.columns
                catalog.sizeCharts[index].rows = source.rows
                catalog.sizeCharts[index].sourceImage = source.sourceImage
            } else {
                catalog.sizeCharts.append(CatalogSizeChart(
                    id: "chart-\(shortID())",
                    productID: target,
                    unit: source.unit,
                    columns: source.columns,
                    rows: source.rows,
                    sourceImage: source.sourceImage))
            }
        }
        guard missing.isEmpty else {
            // 部分成功**绝不静默**：说清楚哪几个没做成
            markDirty()
            lastError = "有 \(missing.count) 个目标商品不存在，已跳过："
                + missing.prefix(5).joined(separator: "、")
            return false
        }
        markDirty()
        statusMessage = "已把尺码表复制到 \(targets.count) 个商品（未保存）。"
        return true
    }
}

// MARK: - 销售记录（追加）与价格修正（覆盖）

extension OpsWorkspace {

    /// 追加一条销售记录（预约价 / 现货价 / 再贩）。
    ///
    /// **只增不改**：这是价格的历史事实，任何「改价格」都必须走
    /// `applyPriceCorrection`（那是另一条流程，另一份存储）。把两者合起来写，
    /// 就会出现「改一次价格少一条历史」，而下一次发布还会把它同步出去。
    @discardableResult
    func appendSaleEvent(
        productID: String,
        type: CatalogSaleEventType,
        price: Decimal,
        deposit: Decimal?,
        balance: Decimal?,
        currency: CatalogCurrency,
        startAt: Date?,
        endAt: Date?,
        batchLabel: String?
    ) -> Bool {
        guard canMutate() else { return false }
        guard catalog.products.contains(where: { $0.id == productID }) else {
            lastError = "找不到商品 \(productID)。"
            return false
        }
        let trimmedBatch = normalized(batchLabel)
        // 再贩必须写清批次时间：再贩没有档期就不是一条可核对的记录
        if type == .rerelease, startAt == nil {
            lastError = "再贩记录必须填批次时间（它是这条再贩的档期），否则无法与其它批次区分。"
            return false
        }
        // 币种待确认时不允许落库：金额没有币种在跨币种合计里是错的
        guard !currency.isUnknown else {
            lastError = "请先确认币种再记录价格（「币种待确认」的金额无法参与差价与合计）。"
            return false
        }

        let event = CatalogSaleEvent(
            id: "sale-\(shortID())",
            productID: productID,
            type: type,
            price: price,
            deposit: deposit,
            balance: balance,
            startAt: startAt,
            endAt: endAt,
            batchLabel: trimmedBatch,
            recordedAt: Date(),
            currency: currency)
        // 指纹去重：同商品 / 同类型 / 同价格 / 同定金尾款 / 同批次日 = 同一条记录。
        // 挡住「保存按钮点两下」在追加式历史里变成两家不同的销售。
        guard !catalog.saleEvents.contains(where: { $0.appendFingerprint == event.appendFingerprint }) else {
            lastError = "已经有一条完全相同的\(type.displayName)记录（同商品、同金额、同批次），未重复追加。"
            return false
        }
        catalog.saleEvents.append(event)
        markDirty()
        return true
    }

    /// 应用价格修正（**覆盖**当前价格状态，不是追加历史）。
    ///
    /// 口径（与 iOS 端一致，别凭直觉改）：
    ///   · 这是**完整快照**：传 nil 表示**该项被清除**（展示「暂无」），
    ///     **不会**回退到历史推导 —— 否则「清除」这个动作永远做不成；
    ///   · 币种必须与既有记录一致：修价不是换币种，跨币种修正一律拒绝；
    ///   · 想要「撤销修正、回退到历史推导」用 `clearPriceCorrection`，
    ///     那是删除修正对象，与「把价格清空」是两件事。
    @discardableResult
    func applyPriceCorrection(
        productID: String,
        reservationPrice: Decimal?,
        stockPrice: Decimal?,
        deposit: Decimal?,
        balance: Decimal?,
        currency: CatalogCurrency?
    ) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.products.firstIndex(where: { $0.id == productID }) else {
            lastError = "找不到商品 \(productID)。"
            return false
        }
        let events = catalog.saleEvents.filter { $0.productID == productID }
        let archive = CatalogPriceArchive(
            events: events, correction: catalog.products[index].priceCorrection)

        if let currency {
            guard !currency.isUnknown else {
                lastError = "修正价格必须选定币种（「币种待确认」的修正会让合计整体失真）。"
                return false
            }
            // 跨币种修正：既有记录声明过币种，且与本次不同 → 拒绝
            if let existing = archive.currentCurrency, existing != currency, !existing.isUnknown {
                lastError = "这个商品既有价格记录是\(existing.displayName)，"
                    + "而本次修正选了\(currency.displayName)。修价不是换币种 —— "
                    + "跨币种修正会让差价与合计失去意义，已拒绝。"
                return false
            }
        }

        catalog.products[index].priceCorrection = CatalogPriceCorrection(
            reservationPrice: reservationPrice,
            stockPrice: stockPrice,
            deposit: deposit,
            balance: balance,
            correctedAt: Date(),
            currency: currency)
        markDirty()
        statusMessage = "已应用价格修正（未保存）。修正只改当前状态，销售历史一条都没动。"
        return true
    }

    /// 删除价格修正对象 → 当前价格回退到销售记录的历史推导。
    @discardableResult
    func clearPriceCorrection(productID: String) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.products.firstIndex(where: { $0.id == productID }) else {
            lastError = "找不到商品 \(productID)。"
            return false
        }
        guard catalog.products[index].priceCorrection != nil else {
            lastError = "这个商品没有价格修正，无需撤销。"
            return false
        }
        catalog.products[index].priceCorrection = nil
        markDirty()
        statusMessage = "已撤销价格修正（未保存）：当前价格回退到销售记录推导值。"
        return true
    }
}

// MARK: - 归档 / 恢复

extension OpsWorkspace {

    /// 归档（下线）或恢复一个店家 / 系列 / 商品。
    ///
    /// 为什么是归档而不是删除：被引用的实体物理删掉会让引用悬空，
    /// 客户端结构校验会整包拒绝；而归档是**显式事实**（何时下线的），
    /// 发布时会被剥离，本机还能追溯。
    @discardableResult
    func setArchived(_ archived: Bool, kind: ShopCatalogEntityKind, id: String) -> Bool {
        guard canMutate() else { return false }
        let stamp: Date? = archived ? Date() : nil
        switch kind {
        case .shop:
            guard let index = catalog.shops.firstIndex(where: { $0.id == id }) else {
                return missing(kind, id)
            }
            catalog.shops[index].archivedAt = stamp
        case .series:
            guard let index = catalog.series.firstIndex(where: { $0.id == id }) else {
                return missing(kind, id)
            }
            catalog.series[index].archivedAt = stamp
        case .product:
            guard let index = catalog.products.firstIndex(where: { $0.id == id }) else {
                return missing(kind, id)
            }
            catalog.products[index].archivedAt = stamp
        case .variant, .sizeChart, .saleEvent, .asset, .styleProfile:
            lastError = "\(kind.displayName)没有归档机制：只能删除或保留（归档只用于店家 / 系列 / 商品）。"
            return false
        }
        markDirty()
        if archived {
            var message = "已归档这\(kind.singularName)：发布时会从包里剔除，但本机仍保留可追溯。"
            if kind == .shop || kind == .series {
                message += "\n⚠️ 归档\(kind.singularName)会**连带剔除**它下面的子项"
                    + "（发布端会做干净，不让引用悬空）。如果只想下线一个商品，请归档那个商品本身。"
            }
            lastError = message
        } else {
            statusMessage = "已恢复这\(kind.singularName)（会重新进入发布包）。"
            lastError = nil
        }
        return true
    }

    private func missing(_ kind: ShopCatalogEntityKind, _ id: String) -> Bool {
        lastError = "找不到\(kind.singularName) \(id)。"
        return false
    }
}

// MARK: - 复制商品

extension OpsWorkspace {

    /// 复制一个商品到指定系列（含它的规格、尺码表与销售记录）。
    ///
    /// 为什么连历史一起复制：上新时「同款换个配色/换季再贩」是主流程，
    /// 让运营重新录一遍规格与尺码表是最容易出错的一步。
    /// 新商品的 id 全部重新生成 —— **绝不复用 id**（复用会让线上两件商品互相覆盖）。
    @discardableResult
    func duplicateProduct(id: String, intoSeries seriesID: String, nameSuffix: String = "（副本）") -> Bool {
        guard canMutate() else { return false }
        guard let source = catalog.products.first(where: { $0.id == id }) else {
            lastError = "找不到商品 \(id)。"
            return false
        }
        guard let series = catalog.series.first(where: { $0.id == seriesID }) else {
            lastError = "找不到目标系列 \(seriesID)。"
            return false
        }
        let newID = "product-\(shortID())"
        var copy = source
        copy.id = newID
        copy.shopID = series.shopID
        copy.seriesID = series.id
        copy.name = source.name + nameSuffix
        copy.archivedAt = nil
        catalog.products.append(copy)

        for variant in catalog.variants.filter({ $0.productID == id }) {
            let newVariantID = "variant-\(shortID())"
            catalog.variants.append(CatalogProductVariant(
                id: newVariantID,
                productID: newID,
                color: variant.color,
                size: variant.size,
                imageAssetID: variant.imageAssetID))
        }
        for chart in catalog.sizeCharts.filter({ $0.productID == id }) {
            catalog.sizeCharts.append(CatalogSizeChart(
                id: "chart-\(shortID())",
                productID: newID,
                unit: chart.unit,
                columns: chart.columns,
                rows: chart.rows,
                sourceImage: chart.sourceImage))
        }
        // 销售历史一并复制：它们是「这个款的历史价格」，新批次要以它们为参照。
        // 注意这是**新记录**（新 id、新 recordedAt），不是共享同一条记录 ——
        // 共享会让改一处影响两件商品。
        for event in catalog.saleEvents.filter({ $0.productID == id }) {
            var newEvent = event
            newEvent.id = "sale-\(shortID())"
            newEvent.productID = newID
            newEvent.recordedAt = Date()
            catalog.saleEvents.append(newEvent)
        }
        // 图片直接复用 asset id（同一张图天然只有一份资源，符合内容寻址口径）；
        // 价格修正随 `copy` 一起复制（它属于商品本身，不是历史）。
        markDirty()
        statusMessage = "已复制为「\(copy.name)」（含 "
            + "\(catalog.variants.filter { $0.productID == newID }.count) 个规格、"
            + "\(catalog.sizeCharts.filter { $0.productID == newID }.count) 张尺码表；未保存）"
        return true
    }
}

// MARK: - 素材引用检查

extension OpsWorkspace {

    /// 谁在引用这个图片资源。**用共享的字段清单**（`ShopCatalogMediaReferences`），
    /// 不自己列字段名 —— 自己列就会漏，而漏掉的那处会在删图之后变成悬空引用。
    func references(toAsset assetID: String) -> [ShopCatalogMediaReference] {
        guard let asset = catalog.assets.first(where: { $0.id == assetID }) else { return [] }
        let urls = [asset.originalURL, asset.thumbnailURL, asset.previewURL].compactMap { $0 }
        return ShopCatalogMediaReferences.all(in: catalog).filter { reference in
            // asset-id 字段里存的就是资源 id 本身
            if reference.allowsAssetID, reference.reference == assetID { return true }
            // URL 字段里存的是同一个文件名（内容寻址 → 同一张图同一串字节）
            if urls.contains(reference.reference) { return true }
            return false
        }
    }

    /// 从草稿里移除一个图片资源。**被引用时拒绝**并列出引用者。
    ///
    /// 为什么不做「连带解绑」：一次操作同时改掉商品、规格、系列、尺码表四个地方的
    /// 引用，是「部分成功/静默扩大影响」的典型。运营需要看到「谁在用这张图」，
    /// 自己决定先解绑哪一处。
    @discardableResult
    func removeAsset(id: String) -> Bool {
        guard canMutate() else { return false }
        guard catalog.assets.contains(where: { $0.id == id }) else {
            lastError = "找不到图片资源 \(id)。"
            return false
        }
        let users = references(toAsset: id)
        if !users.isEmpty {
            let owners = users.prefix(5).map { "\($0.owner)（\($0.field)）" }
            lastError = "这张图还被 \(users.count) 处引用，不能移除："
                + owners.joined(separator: "、")
                + (users.count > 5 ? " 等" : "")
                + "。请先在这些位置解绑，或者改为「归档」它所属的商品。"
            return false
        }
        catalog.assets.removeAll { $0.id == id }
        markDirty()
        statusMessage = "已移除图片资源（未保存）。注意：staging 里的文件没有删，"
            + "要释放磁盘请在素材库里单独处理。"
        return true
    }
}

// MARK: - 系列配置（发售阶段 / 图文 / 价格表）

extension OpsWorkspace {

    /// 写系列的发售阶段与两个区间。
    ///
    /// **只写这几个字段**（`form.apply(to:)` 口径）：系列配置只有一处存储
    /// （`CatalogSeries`），价格表、图文、档期各写各的字段，谁也不覆盖谁。
    ///
    /// 两个区间都是「开始必填、结束选填」，但**只有预约结束时间与尾款开始时间
    /// 驱动自动流转**（大致时间只展示、不驱动）。
    @discardableResult
    func updateSeriesSalePhase(
        id: String,
        phase: CatalogSeriesSalePhase?,
        reservationStartAt: Date?,
        reservationEndAt: Date?,
        balanceDueKind: CatalogBalanceDueKind?,
        balanceDueText: String?,
        balanceDueAt: Date?,
        balanceDueEndAt: Date?
    ) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.series.firstIndex(where: { $0.id == id }) else {
            lastError = "找不到系列 \(id)。"
            return false
        }
        if let start = reservationStartAt, let end = reservationEndAt, start > end {
            lastError = "预约开始时间不能晚于预约结束时间。"
            return false
        }
        if let start = balanceDueAt, let end = balanceDueEndAt, start > end {
            lastError = "尾款开始时间不能晚于尾款结束时间。"
            return false
        }
        // 「预约中」必须有结束时间：它是自动流转的唯一依据。
        // 没有它，系列会在预约期结束后一直显示「预约中」—— 用户端还能付定金。
        if phase == .reservationActive, reservationEndAt == nil {
            lastError = "声明「预约中」必须填预约结束时间 —— 自动流转靠它，"
                + "缺了它系列会一直停在预约中。"
            return false
        }
        if balanceDueKind == .exact, balanceDueAt == nil {
            lastError = "尾款时间选了「具体时间」，请填上时间（或改回「大致时间」）。"
            return false
        }
        if balanceDueKind == .approximate, (balanceDueText?.isEmpty ?? true) {
            lastError = "尾款时间选了「大致时间」，请写上描述（如「大货到后 1 个月」）。"
            return false
        }

        catalog.series[index].salePhase = phase
        catalog.series[index].reservationStartAt = reservationStartAt
        catalog.series[index].reservationEndAt = reservationEndAt
        // 切粒度时清掉另一种的载荷（否则「具体时间」页里会留着一句旧的描述文本）
        catalog.series[index].balanceDueKind = balanceDueKind
        catalog.series[index].balanceDueText =
            balanceDueKind == .approximate ? normalized(balanceDueText) : nil
        catalog.series[index].balanceDueAt = balanceDueKind == .exact ? balanceDueAt : nil
        catalog.series[index].balanceDueEndAt = balanceDueKind == .exact ? balanceDueEndAt : nil
        markDirty()
        statusMessage = "已更新系列发售阶段（草稿未保存）。注意：这里**不碰任何价格**。"
        return true
    }

    /// 写系列级价格表（整包系列共用，单品的详情页自动读它）。
    @discardableResult
    func updateSeriesPriceChart(
        seriesID: String,
        unit: String?,
        columns: [String],
        rows: [CatalogSizeRow],
        sourceImages: [String]
    ) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.series.firstIndex(where: { $0.id == seriesID }) else {
            lastError = "找不到系列 \(seriesID)。"
            return false
        }
        let trimmedColumns = columns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard rows.allSatisfy({ $0.values.count == trimmedColumns.count }) else {
            lastError = "价格表有行的数值个数与列数不一致，客户端会整列错位，已拒绝。"
            return false
        }
        let images = sourceImages.filter { !$0.isEmpty }
        guard images.allSatisfy({ reference in
            catalog.assets.contains { $0.id == reference }
                || reference.hasPrefix("local:")
                || reference.hasPrefix("thmedia:")
        }) else {
            lastError = "价格表引用了不存在的图片资源，请先在素材库里导入。"
            return false
        }
        // sourceImage 恒等于首图：单一展示口径继续成立，其余图供详情页补充展示
        let chart = CatalogPriceChart(
            id: catalog.series[index].priceChart?.id ?? "pricechart-\(shortID())",
            seriesID: seriesID,
            unit: normalized(unit),
            columns: trimmedColumns,
            rows: rows,
            sourceImage: images.first,
            sourceImages: images.isEmpty ? nil : images)
        catalog.series[index].priceChart = chart
        markDirty()
        statusMessage = "已保存系列价格表（\(images.count) 张图，未保存草稿）。"
        return true
    }

    /// 清空系列级价格表。
    @discardableResult
    func clearSeriesPriceChart(seriesID: String) -> Bool {
        guard canMutate() else { return false }
        guard let index = catalog.series.firstIndex(where: { $0.id == seriesID }) else {
            lastError = "找不到系列 \(seriesID)。"
            return false
        }
        guard catalog.series[index].priceChart != nil else {
            lastError = "这个系列没有价格表。"
            return false
        }
        catalog.series[index].priceChart = nil
        markDirty()
        return true
    }
}

// MARK: - 查询辅助（视图层不做口径判断）

extension OpsWorkspace {

    /// 某个商品的全部规格（按**录入顺序**，不是字典序）
    func variants(forProduct productID: String) -> [CatalogProductVariant] {
        catalog.variants.filter { $0.productID == productID }
    }

    func sizeChart(forProduct productID: String) -> CatalogSizeChart? {
        catalog.sizeCharts.first { $0.productID == productID }
    }

    /// 某个商品的销售记录（追加顺序）与价格档案
    func saleEvents(forProduct productID: String) -> [CatalogSaleEvent] {
        catalog.saleEvents.filter { $0.productID == productID }
    }

    func priceArchive(forProduct productID: String) -> CatalogPriceArchive? {
        guard let product = catalog.products.first(where: { $0.id == productID }) else { return nil }
        return CatalogPriceArchive(
            events: saleEvents(forProduct: productID),
            correction: product.priceCorrection)
    }

    /// 商品列表标签（**不合并两条状态轴**：编辑状态与发布状态各说各的）
    func publicationTags(forProduct productID: String) -> [String] {
        var tags: [String] = []
        if let product = catalog.products.first(where: { $0.id == productID }),
           product.archivedAt != nil {
            tags.append("已归档")
        }
        let delta = changeSet.delta(of: .product)
        if baselineCatalog == nil {
            // 没有基线快照 → 只敢说「本地内容」，不敢说「相对线上新增」
            tags.append("本地内容")
        } else if delta.addedIDs.contains(productID) {
            tags.append("新增")
        } else if delta.modifiedIDs.contains(productID) {
            tags.append("已修改")
        }
        if delta.removedIDs.contains(productID) { tags.append("本地已删") }
        if delta.tombstoneIDs.contains(productID) { tags.append("已下架") }
        return tags
    }
}
