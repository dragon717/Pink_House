//
//  ShopCatalogDraftStyleForm.swift
//  ItemManager
//
//  「款式（SPU）+ 多颜色（SKU）」一体化录表单纯逻辑（2026-09-23，nonisolated 可单测）。
//
//  需求原文：
//    「现在的表单结构不够合理，请实现在当前页面内添加多颜色 SKU 的功能。不需要让用户
//      通过『新建单品』来建颜色。把 designName（款式名）和多个 product（颜色）的录入
//      整合在同一个表单里，让公共资料实现跨颜色复用，图片单独上传。」
//    「请在颜色 SKU 添加区，将图片上传组件与颜色字段直接绑定。让用户点颜色的同时就能
//      直接传图，实现图片与 SKU 的强关联。不要单独弄一个图片上传区让用户去对应。」
//
//  于是本文件定义表单的**中间表示**：一个表单 = 一个款式 + N 个颜色行。
//
//    款式层（填一次，全色复用）：款式名 / 分类 / 面料 / 款式描述 / 尺码表 / 价格组 / 归属
//    颜色层（每色一行）        ：颜色名 + 配色图（行内上传）+ 尺码勾选
//
//  ⚠️ 与 `ShopCatalogDraftStyleSync` 的分工（两者互补，不重复定义字段分层）：
//    · 那个管**跨草稿复制**（以一条为模板同步给同款其他颜色，用于「已经录成多条」的场景）；
//    · 本文件管**一个表单内同时录入/编辑整款**（从源头就不产生「要同步」这件事）。
//    字段分层只有一份口径，本文件直接复用它的 `designName(of:)`。
//
//  商品名的组合口径（本文件的幂等关键）：
//      商品名 = 颜色名 + 款式名
//    存量草稿 `name` 本来就是「颜色 + 款式」的形式（如「生成色一字领OP」），
//    而款式名未显式填写时由 `name` 剥离颜色词派生 —— 于是「派生款式名 → 再组合回
//    商品名」得到的就是原值，对存量数据**零改动**，不会因为打开一次表单就把名字改掉。
//

import Foundation

nonisolated enum ShopCatalogDraftStyleForm {

    // MARK: - 同款判定（**唯一口径**）

    /// 同款身份：品类 + 款式名（硬条件），外加「双方都自报时的系列令牌」。
    ///
    /// 刻意**不**把系列做成硬条件：批次里草稿的系列常常是「继承整批归属」而来
    /// （`seriesID` / `newSeriesName` 仍为空，靠批次会话兜底），拿空令牌去比会误判成
    /// 不同款，把本该同款的草稿拆开。
    static func identity(of draft: CatalogProductDraft)
        -> (design: String, category: String, seriesToken: String?) {
        let seriesName = draft.newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        let token: String?
        if let seriesID = draft.seriesID {
            token = "id:\(seriesID)"
        } else if !seriesName.isEmpty {
            token = "name:\(seriesName)"
        } else {
            token = nil
        }
        return (styleName(of: draft), draft.category, token)
    }

    static func isSameStyle(_ lhs: CatalogProductDraft, _ rhs: CatalogProductDraft) -> Bool {
        isSameIdentity(identity(of: lhs), identity(of: rhs))
    }

    static func isSameIdentity(_ lhs: (design: String, category: String, seriesToken: String?),
                               _ rhs: (design: String, category: String, seriesToken: String?)) -> Bool {
        guard lhs.design == rhs.design, lhs.category == rhs.category else { return false }
        if let a = lhs.seriesToken, let b = rhs.seriesToken { return a == b }
        return true
    }

    /// 与源草稿同款的**全部**草稿（含已发布 / 已归档），保持传入顺序。
    ///
    /// 表单展示与仓库落盘必须用这同一个函数取家族：如果两处口径不一致，
    /// 「表单没显示、仓库却认为该移除」的草稿会被当成「用户删掉了这个颜色」而**误删**。
    /// 所以这里不是便利方法，而是防止误删的防线。
    static func sameStyleFamily(of source: CatalogProductDraft,
                                in drafts: [CatalogProductDraft]) -> [CatalogProductDraft] {
        let sourceIdentity = identity(of: source)
        return drafts.filter { isSameIdentity(sourceIdentity, identity(of: $0)) }
    }

    // MARK: - 颜色行（表单 ↔ 草稿的中间表示）

    /// 一个颜色行 = 一个颜色 SKU。
    ///
    /// 行与草稿的对应关系用 `draftID` 表达：已有草稿 = 草稿 id；表单里新加的颜色 = nil，
    /// 保存时才创建草稿实体。`id` 只用于 SwiftUI 的列表身份，保证「新加的空行」在保存前
    /// 也有稳定身份（否则每敲一个字列表就重建，输入框会失焦）。
    struct ColorRow: Identifiable, Equatable {
        /// 列表身份：已有草稿 = 草稿 id；新增 = 表单生成的临时 id
        var id: String
        /// 对应草稿 id；nil = 本次表单新增的颜色
        var draftID: String?
        /// 颜色名（如「生成色」）。必填 —— 它是商品名与款式名分离的锚点
        var colorName: String
        /// 配色图引用（`local:` / Bundle 名 / URL）。
        /// 顺序 = 详情页轮播顺序，第一张 = 该颜色主图（前端切色时读的就是它）
        var imageRefs: [String]
        /// 该颜色提供的尺码（候选项来自款式尺码表，不重复填表）
        var sizes: [String]
        /// 已发布 / 已归档：产物已在覆盖层，改草稿不生效 → 表单里只读
        var isSettled: Bool

        var isNew: Bool { draftID == nil }

        init(id: String = "new-\(UUID().uuidString)",
             draftID: String? = nil,
             colorName: String = "",
             imageRefs: [String] = [],
             sizes: [String] = [],
             isSettled: Bool = false) {
            self.id = id
            self.draftID = draftID
            self.colorName = colorName
            self.imageRefs = imageRefs
            self.sizes = sizes
            self.isSettled = isSettled
        }
    }

    // MARK: - 款式层输入

    /// 款式（SPU）公共资料的整快照 —— 与 `ShopCatalogDraftStyleSync.Field` 同一分层：
    /// 这里列的每一项都是「同款共用」，会写到**每一条**颜色草稿上（每条草稿发布时
    /// 各自落库，款式档案在发布环节按款式键合并成一份）。
    struct StyleInput: Equatable {
        /// 款式名。空串 = 未填（按商品名剥离颜色词派生）—— 多颜色时由 `validate` 拦下
        var designName: String = ""
        /// 款式名兜底值：用户没填款式名时，用**源草稿派生出来的款名**给所有颜色组名。
        ///
        /// 为什么必须有它：新加的颜色草稿没有历史商品名可派生（`name` 还是空的），
        /// 若让它各自派生，新色的款名会是空串 → 商品名退化成只有颜色词 → 新色掉出同款组，
        /// 「在这个表单里加一个颜色」反而变成两个款式。款式名是整款一份，必须**一处决议**。
        /// 注意它只参与商品名组合，**不写进 `designName` 字段**（没填就是没填，
        /// 不替用户伪造显式款式名）。
        var styleNameFallback: String = ""
        var category: String = "其他"
        var fabric: String = ""
        var styleDescription: String = ""
        var sizeChart: CatalogSizeChart? = nil

        // 价格组：整组一起写，绝不出现「预约价 498、定金还是 0」的对账失败态
        var reservationPrice: Double? = nil
        var stockPrice: Double? = nil
        var deposit: Double? = nil
        var balance: Double? = nil
        var startAt: Date? = nil
        var endAt: Date? = nil
        var currency: CatalogCurrency? = nil

        // 归属（店家 / 系列 / 批次）——由「应用到整批」管，这里只透传，不改语义
        var shopID: String? = nil
        var newShopName: String = ""
        var newShopAliases: String = ""
        var seriesID: String? = nil
        var newSeriesName: String = ""
        var newSeriesYear: Int? = nil
        var newSeriesSeason: String = ""
        var batchID: String? = nil
    }

    // MARK: - 派生口径

    /// 款式名：显式 `designName` 优先，缺省按商品名剥离颜色词派生。
    /// 直接复用草稿侧唯一口径，草稿期分组与发布后归组必然落在同一款式上。
    static func styleName(of draft: CatalogProductDraft) -> String {
        ShopCatalogDraftStyleSync.designName(of: draft)
    }

    /// 颜色名：显式规格色优先 → 商品名里的颜色词 → 空串（**不把整名当颜色**）。
    /// 与商品侧的 `ShopCatalogColorPresentation` 同一份取值口径 ——
    /// 否则「表单里显示的颜色」与「详情页颜色胶囊」会各说各话。
    static func colorName(of draft: CatalogProductDraft) -> String {
        let explicit = draft.variants
            .compactMap { $0.color?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let explicit { return explicit }
        return ShopCatalogColorPresentation.derivedLabel(forName: draft.name) ?? ""
    }

    /// 商品名 = 颜色名 + 款式名。
    ///
    /// 两个都空 → 空串（校验会拦下）；只剩一个 → 就是那一个（单色、款式名待派生时的
    /// 过渡状态，发布校验仍要求非空）。
    static func productName(colorName: String, styleName: String) -> String {
        colorName.trimmingCharacters(in: .whitespacesAndNewlines)
            + styleName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 该颜色已选的尺码（按 variants 顺序去重）
    static func sizes(of draft: CatalogProductDraft) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for variant in draft.variants {
            guard let size = variant.size?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !size.isEmpty, seen.insert(size).inserted else { continue }
            result.append(size)
        }
        return result
    }

    /// 已发布 / 已归档 = 只读行
    static func isSettled(_ draft: CatalogProductDraft) -> Bool {
        draft.status == .published || draft.status == .archived
    }

    /// 草稿 → 颜色行。**源草稿（用户当前打开的那条）排第一位** ——
    /// 表单默认聚焦的那一色应当是用户点进来的那一色，而不是列表里碰巧排第一的。
    /// 其余保持传入顺序（= 录入顺序，不排序）。
    static func rows(of drafts: [CatalogProductDraft], sourceID: String) -> [ColorRow] {
        var ordered = drafts
        if let index = ordered.firstIndex(where: { $0.id == sourceID }), index != 0 {
            let source = ordered.remove(at: index)
            ordered.insert(source, at: 0)
        }
        return ordered.map { draft in
            ColorRow(id: draft.id,
                     draftID: draft.id,
                     colorName: colorName(of: draft),
                     imageRefs: draft.images.map(\.originalURL),
                     sizes: sizes(of: draft),
                     isSettled: isSettled(draft))
        }
    }

    // MARK: - 校验

    enum FormError: LocalizedError {
        case noColor
        case missingColorName(index: Int)
        case missingStyleNameForMultiColor

        var errorDescription: String? {
            switch self {
            case .noColor:
                return "至少需要一个颜色 —— 点「＋ 添加颜色」录入颜色名与图片"
            case .missingColorName(let index):
                return "第 \(index + 1) 个颜色还没有填颜色名"
            case .missingStyleNameForMultiColor:
                return "多颜色录入必须填款式名 —— 它是「同款共用一份公共资料」的归属键"
            }
        }
    }

    /// 保存前校验。**多颜色必须填款式名**：
    /// 款式名为空时商品名拿不到可分离的款名，款式键会退化成各自的颜色名，
    /// 于是「同款」被拆成三款 —— 公共资料复用与尺码表共享全部失效。
    static func validate(colors: [ColorRow], styleName: String) throws {
        guard !colors.isEmpty else { throw FormError.noColor }
        for (index, row) in colors.enumerated() {
            guard !row.colorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw FormError.missingColorName(index: index)
            }
        }
        if colors.count > 1,
           styleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FormError.missingStyleNameForMultiColor
        }
    }

    /// 款式名的**唯一决议点**：显式填写优先，缺省按源草稿的商品名派生。
    /// 表单展示（名字预览）与保存落库都必须调它，否则「看到的」与「存下的」会分叉。
    static func resolveStyleName(explicit: String, source: CatalogProductDraft) -> String {
        let typed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? styleName(of: source) : typed
    }

    // MARK: - 款式层应用

    /// 把款式公共资料整快照写到一条草稿上（含由「颜色名 + 款式名」重算商品名）。
    ///
    /// 只写款式层：**不碰** 图片 / 配色尺码（由 `applyColor` 负责）、状态、发布结果。
    /// 尺码表的 id **逐条重编**为 `sizechart-draft-<草稿 id 前 6 位>`：
    /// 多条草稿共用同一 id 会在发布时互相覆盖（发布按 id 落覆盖层），最后一个颜色赢家通吃。
    static func applyStyle(_ style: StyleInput,
                           to draft: CatalogProductDraft,
                           colorName: String) -> CatalogProductDraft {
        var updated = draft
        let design = style.designName.trimmingCharacters(in: .whitespacesAndNewlines)
        // 款名一处决议：显式填写优先，否则用调用方（仓库层）算好的兜底款名 ——
        // 绝不让每条草稿各自派生，新加的颜色会派生出空款名而掉出同款组。
        let styleName = design.isEmpty
            ? style.styleNameFallback.trimmingCharacters(in: .whitespacesAndNewlines)
            : design

        updated.name = productName(colorName: colorName, styleName: styleName)
        updated.designName = design.isEmpty ? nil : design
        updated.category = style.category

        // 价格整组（含 saleKind：统一按「预约价 = price、现货价 = stockPrice」的新口径，
        // 否则旧现货草稿的 price 会被 effectiveReservationPrice 重新解释成预约价）
        updated.saleKind = .reservation
        updated.price = style.reservationPrice ?? 0
        updated.stockPrice = style.stockPrice
        updated.deposit = style.deposit
        updated.balance = style.balance
        updated.startAt = style.startAt
        updated.endAt = style.endAt
        updated.currency = style.currency

        updated.fabric = ShopCatalogStyleProfileSharing.clean(style.fabric)
        updated.styleDescription = ShopCatalogStyleProfileSharing.clean(style.styleDescription)

        updated.sizeChart = style.sizeChart.map { chart in
            var copy = chart
            copy.id = "sizechart-draft-\(draft.id.prefix(6))"
            copy.productID = ""
            if let url = copy.sourceImage, url.trimmingCharacters(in: .whitespaces).isEmpty {
                copy.sourceImage = nil
            }
            return copy
        }

        updated.shopID = style.shopID
        updated.newShopName = style.newShopName
        updated.newShopAliases = style.newShopAliases
        updated.seriesID = style.seriesID
        updated.newSeriesName = style.newSeriesName
        updated.newSeriesYear = style.newSeriesYear
        updated.newSeriesSeason = style.newSeriesSeason
        if let batchID = style.batchID { updated.batchID = batchID }

        return updated
    }

    // MARK: - 颜色层应用

    /// 把颜色私有资料写到一条草稿上：图片 + 配色尺码（**图片与颜色强关联的落点**）。
    ///
    /// 图片 asset 的 id 由「草稿 id + 序号」确定性生成，因此同一份输入重复保存是幂等的，
    /// 也不会与别的颜色草稿撞 id。每个 variant 的 `imageAssetID` 都指向本颜色的主图 ——
    /// 前端详情页切色时读的就是这条链（商品图集 + 同款其他颜色主图）。
    ///
    /// - Parameter orderedSizes: 款式尺码表的尺码轴（决定输出顺序）。
    ///   顺序不能靠 Set 的遍历序 —— 详情页与点菜页的尺码顺序都直接读它，
    ///   顺序错乱会让同一个商品在两处显示不一致。
    static func applyColor(_ row: ColorRow,
                           to draft: CatalogProductDraft,
                           orderedSizes: [String]) -> CatalogProductDraft {
        var updated = draft
        let color = row.colorName.trimmingCharacters(in: .whitespacesAndNewlines)

        let refs = row.imageRefs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.images = refs.enumerated().map { index, ref in
            CatalogAsset(id: "asset-\(draft.id.prefix(8))-\(index)",
                         type: .productImage,
                         thumbnailURL: nil, previewURL: nil,
                         originalURL: ref, width: nil, height: nil)
        }
        // 主图 = 第一张（详情页默认展示当前颜色主图；轮播其余位置展示本色其余图）
        let primaryAssetID = updated.images.first?.id

        // 尺码顺序以款式尺码表为准；尺码表里没有的（历史数据 / 手误）追加在后面，
        // 不能直接丢弃 —— 那等于偷偷删掉用户已录的尺码
        var chosen = orderedSizes.filter { row.sizes.contains($0) }
        chosen.append(contentsOf: row.sizes.filter { !orderedSizes.contains($0) })

        let variantColor: String? = color.isEmpty ? nil : color
        if chosen.isEmpty {
            updated.variants = [CatalogProductVariant(id: "var-\(draft.id.prefix(8))-0",
                                                      productID: "",
                                                      color: variantColor,
                                                      size: nil,
                                                      imageAssetID: primaryAssetID)]
        } else {
            updated.variants = chosen.enumerated().map { index, size in
                CatalogProductVariant(id: "var-\(draft.id.prefix(8))-\(index)",
                                      productID: "",
                                      color: variantColor,
                                      size: size,
                                      imageAssetID: primaryAssetID)
            }
        }
        return updated
    }

    /// 新建一条颜色草稿：以源草稿为骨架继承归属 / 批次 / 状态，再套用款式层与颜色层。
    static func makeNewDraft(colorRow: ColorRow,
                             style: StyleInput,
                             basedOn source: CatalogProductDraft,
                             orderedSizes: [String],
                             id: String = UUID().uuidString) -> CatalogProductDraft {
        var draft = CatalogProductDraft()
        draft.id = id
        draft.batchID = source.batchID
        draft.status = .draft
        draft.createdAt = Date()
        let styled = applyStyle(style, to: draft, colorName: colorRow.colorName)
        return applyColor(colorRow, to: styled, orderedSizes: orderedSizes)
    }

    // MARK: - 展示辅助

    /// 「款式 → 将发布为」的人话预览（表单里给运营确认商品名用）
    static func namePreview(colorName: String, styleName: String) -> String {
        let name = productName(colorName: colorName, styleName: styleName)
        return name.isEmpty ? "（待填颜色名与款式名）" : name
    }
}
