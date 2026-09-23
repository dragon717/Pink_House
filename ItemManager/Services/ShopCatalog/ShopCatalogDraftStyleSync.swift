//
//  ShopCatalogDraftStyleSync.swift
//  ItemManager
//
//  录入端「同款不同色」一键同步（2026-09-23，nonisolated 可单测）。
//
//  背景：批次录入时同一款式的多个颜色是**多条独立草稿**（每条草稿 = 一个颜色单品，
//  发布后各自成为独立商品 —— 与已落地的 SPU/SKU 结构一致，见
//  `ShopCatalogStyleProfileSharing` / `ShopCatalogSizeChartSharing`）。
//  「应用到整批」原本只同步店家 + 系列，于是价格 / 尺码表 / 面料 / 描述 只能逐条重录，
//  既费时又容易漏填。
//
//  本文件给出草稿侧的款式口径与同步产物，回答两个问题：
//    1. **哪些草稿是同一个款式**（分组键与商品侧 `styleKey` 同源：系列 + 品类 + 款式名）；
//    2. **从一条草稿同步到同款其他颜色时，哪些字段该动、哪些绝不能动**。
//
//  ⚠️ 字段分层（本文件是唯一定义处）：
//    · **款式公共（SPU）**：价格组、尺码表、面料、款式描述 —— 同款共用，可整块复制；
//    · **颜色私有（SKU）**：商品名（含颜色词）、配色图、配色尺码 —— **永不复制**，
//      复制它们等于把粉色改名成生成色、把三个颜色压成一张图。
//
//  价格为什么必须**整组**复制：预约价 / 现货价 / 定金 / 尾款 / 档期 / 币种是同一套
//  销售条件。只复制预约价而漏掉定金尾款，会直接产出
//  `depositBalanceIssue`（定金 + 尾款 ≠ 总价）的草稿，发布前被拦下。
//

import Foundation

nonisolated enum ShopCatalogDraftStyleSync {

    // MARK: - 款式身份

    /// 款式名：显式 `designName` 优先；未填按商品名剥离颜色词派生。
    /// 与商品侧 `ShopCatalogSameDesignGrouper.designName(of:)` 同一口径 ——
    /// 草稿分期与发布后的款式归组必须落在同一个款式上，否则「同步时是同一款、
    /// 发布后列表里却分成两卡」。
    static func designName(of draft: CatalogProductDraft) -> String {
        if let explicit = draft.designName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        return ShopCatalogSameDesignGrouper.baseName(for: draft.name)
    }

    /// 草稿自报的系列标签：系列 id（能解析出名则用名）优先，否则新建系列名；都没有 → nil
    static func ownSeriesLabel(of draft: CatalogProductDraft,
                               resolveSeriesName: (String) -> String? = { _ in nil }) -> String? {
        if let seriesID = draft.seriesID {
            return resolveSeriesName(seriesID) ?? seriesID
        }
        let name = draft.newSeriesName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// 款式键：系列标签 + 品类 + 款式名。
    ///
    /// 系列口径与批次页面展示分组**同源**（`CatalogBatchGrouping.groupKey`）：
    /// 草稿自报系列优先，未自报则继承整批归属当前选定的系列，都没有 → 「未指定系列」。
    /// 这样「用户看到的同系列分组」与「可一键同步的颜色组」永远是同一批人。
    ///
    /// - Parameter inheritedSeriesLabel: 整批归属当前选定系列的展示名（批次页选中项）；
    ///   非批次场景传 nil。
    static func styleKey(of draft: CatalogProductDraft,
                         inheritedSeriesLabel: String? = nil,
                         resolveSeriesName: (String) -> String? = { _ in nil }) -> String {
        let series = CatalogBatchGrouping.groupKey(
            draftOwnSeriesName: ownSeriesLabel(of: draft, resolveSeriesName: resolveSeriesName),
            batchSeriesName: inheritedSeriesLabel)
        return "\(series)|\(draft.category)|\(designName(of: draft))"
    }

    // MARK: - 分组

    /// 一个款式组：同一款式键下的若干颜色草稿
    struct StyleGroup: Identifiable, Equatable {
        let key: String
        /// 款式展示名
        let designName: String
        /// 组内草稿，保持传入顺序（= 录入顺序，不排序）
        let drafts: [CatalogProductDraft]

        var id: String { key }
        var colorCount: Int { drafts.count }
        /// 多色款式才值得「一键同步」
        var isMultiColor: Bool { drafts.count > 1 }
    }

    /// 按款式分组（保持首次出现顺序）。单颜色的款式也会成组（colorCount == 1），
    /// 由调用方决定是否展示同步入口。
    static func groups(_ drafts: [CatalogProductDraft],
                       inheritedSeriesLabel: String? = nil,
                       resolveSeriesName: (String) -> String? = { _ in nil }) -> [StyleGroup] {
        var order: [String] = []
        var buckets: [String: [CatalogProductDraft]] = [:]
        for draft in drafts {
            let key = styleKey(of: draft,
                              inheritedSeriesLabel: inheritedSeriesLabel,
                              resolveSeriesName: resolveSeriesName)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(draft)
        }
        return order.map { key in
            let members = buckets[key] ?? []
            return StyleGroup(key: key,
                              designName: members.first.map(designName(of:)) ?? key,
                              drafts: members)
        }
    }

    /// 同款其他颜色（**排除自己**），保持传入顺序。
    static func siblings(of draft: CatalogProductDraft,
                         in drafts: [CatalogProductDraft],
                         inheritedSeriesLabel: String? = nil,
                         resolveSeriesName: (String) -> String? = { _ in nil }) -> [CatalogProductDraft] {
        let key = styleKey(of: draft,
                          inheritedSeriesLabel: inheritedSeriesLabel,
                          resolveSeriesName: resolveSeriesName)
        return drafts.filter {
            $0.id != draft.id
                && styleKey(of: $0,
                            inheritedSeriesLabel: inheritedSeriesLabel,
                            resolveSeriesName: resolveSeriesName) == key
        }
    }

    // MARK: - 同步字段

    /// 可同步的字段。刻意**只列款式公共属性**：颜色私有属性（名称/配色图/配色尺码）
    /// 不提供开关，从接口上就没有被覆盖的可能。
    enum Field: String, CaseIterable, Identifiable, Hashable {
        /// 价格组：预约价 / 现货价 / 定金 / 尾款 / 档期 / 币种（整组，不可拆）
        case price
        case sizeChart
        case fabric
        case styleDescription

        var id: String { rawValue }

        var title: String {
            switch self {
            case .price: return "价格"
            case .sizeChart: return "尺码表"
            case .fabric: return "面料成分"
            case .styleDescription: return "款式描述"
            }
        }

        var subtitle: String {
            switch self {
            case .price: return "预约价、现货价、定金、尾款、档期、币种（整组同步）"
            case .sizeChart: return "列名、数据行、原图"
            case .fabric: return "款式级公共资料"
            case .styleDescription: return "款式级公共资料"
            }
        }
    }

    /// 默认勾选：全选（用户期望「一次把所有公共资料带过去」）
    static let defaultFields: Set<Field> = Set(Field.allCases)

    /// 同步产物：目标草稿 id → 更新后的草稿
    ///
    /// 语义与项目里其它「整快照提交」一致：**勾选即整块覆盖**，源为空即清除该字段
    /// （不是「跳过不修改」）。这样才能用「再同步一次」把改错的值纠正回去。
    ///
    /// 绝不触碰的字段：`id` / `batchID` / `name` / `designName` / `category` /
    /// `images` / `variants` / 店家与系列归属 / `status` / `createdAt` /
    /// `publishedResult` / `rejectReason`。
    /// 其中 `designName` 与 `category` 参与款式键，源与目标本来就相等，写入无意义；
    /// 归属字段由「应用到整批」负责，同步不该越权改归属。
    static func syncPlan(from source: CatalogProductDraft,
                         to targets: [CatalogProductDraft],
                         fields: Set<Field>) -> [String: CatalogProductDraft] {
        guard !fields.isEmpty else { return [:] }
        var plan: [String: CatalogProductDraft] = [:]
        for target in targets where target.id != source.id {
            var updated = target

            if fields.contains(.price) {
                // 整组一起搬：只搬价格会留下对不上的定金 / 尾款
                updated.saleKind = source.saleKind
                updated.price = source.price
                updated.stockPrice = source.stockPrice
                updated.deposit = source.deposit
                updated.balance = source.balance
                updated.startAt = source.startAt
                updated.endAt = source.endAt
                updated.currency = source.currency
            }

            if fields.contains(.sizeChart) {
                // 尺码表整块复制，但 **id 逐条重编**：草稿各自持有自己的那一行，
                // 共用 id 会让两条草稿在发布时互相覆盖（发布按 id 落到覆盖层）。
                updated.sizeChart = source.sizeChart.map { chart in
                    var copy = chart
                    copy.id = "sizechart-draft-\(target.id.prefix(6))"
                    copy.productID = ""
                    return copy
                }
            }

            if fields.contains(.fabric) {
                updated.fabric = source.fabric
            }
            if fields.contains(.styleDescription) {
                updated.styleDescription = source.styleDescription
            }

            plan[target.id] = updated
        }
        return plan
    }

    // MARK: - 展示辅助

    /// 该草稿是否携带款式公共资料（面料 / 描述）。发布时据此决定要不要写款式档案 ——
    /// 纯补价的草稿**不得**把已有档案清掉。
    static func hasStyleContent(_ draft: CatalogProductDraft) -> Bool {
        ShopCatalogStyleProfileSharing.clean(draft.fabric) != nil
            || ShopCatalogStyleProfileSharing.clean(draft.styleDescription) != nil
    }

    /// 勾选字段的人话清单（toast 用），按固定顺序
    static func describe(_ fields: Set<Field>) -> String {
        let names = Field.allCases.filter { fields.contains($0) }.map(\.title)
        return names.isEmpty ? "（未选择任何字段）" : names.joined(separator: "、")
    }
}
