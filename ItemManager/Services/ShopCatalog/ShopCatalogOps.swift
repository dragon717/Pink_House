//
//  ShopCatalogOps.swift
//  ItemManager
//
//  店家商品库运营端（Phase 6，计划 §26-31）：
//    · CatalogProductDraft  运营草稿（§27 手动录入草稿 → 人工补录）
//    · ShopCatalogDraftStore    草稿持久化 + 发布 → 覆盖层 JSON（§31 草稿/发布）
//    · 发布校验：必填项、价格、定金尾款对账、Shop/Series/Product 去重（§29）
//    · 淘宝导入（§28 ShopCatalogTaobaoParser）与批量导入已下线，代码已删除
//
//  简化说明（第一版）：审核态由白名单创作者一步完成——发布 = 校验通过后
//  写入覆盖层并对用户可见；CatalogPublicationStatus 枚举保留完整状态机。
//

import Foundation
import Combine
import SwiftData

// MARK: - 草稿流转错误（§31）

nonisolated enum ShopCatalogDraftStoreError: LocalizedError {
    case illegalTransition(from: CatalogPublicationStatus, to: CatalogPublicationStatus)
    case notReadyForPublish(CatalogPublicationStatus)
    /// 发布产物已写入覆盖层，但草稿状态/结果回执写盘失败（R09 半成功）。
    /// 产物是既成事实，不回滚；重试只会补回执，不会重复发布。
    case publishResultUnrecorded(summary: String, detail: String)
    /// 目标商品不存在（可能已被删除 / 脏引用）
    case productNotFound(String)
    /// 同款同步的模板草稿不存在（列表已刷新 / 脏引用）
    case sourceDraftNotFound(String)

    var errorDescription: String? {
        switch self {
        case .illegalTransition(let from, let to):
            return "状态不能从「\(from.displayName)」变更为「\(to.displayName)」"
        case .notReadyForPublish(let status):
            return "草稿当前为「\(status.displayName)」，需先提交并审核通过后才能发布"
        case .publishResultUnrecorded(let summary, let detail):
            return "已发布：\(summary)。但草稿状态未能保存（\(detail)）——请勿重复点击发布，"
                + "重新进入本条草稿再发布一次即可补齐回执，不会重复生成销售记录。"
        case .productNotFound(let id):
            return "未找到商品 \(id)，可能已被删除——请刷新后重试"
        case .sourceDraftNotFound(let id):
            return "未找到作为模板的草稿 \(id)，可能已被删除——请返回列表刷新后重试"
        }
    }
}

// MARK: - 价格双流程错误（2026-09-22）

/// 价格修正 / 追加销售记录两条流程各自的校验错误。
/// 分开定义而非复用 `ShopCatalogDraftValidator.ValidationError`：草稿发布校验
/// 与这两条运营流程语义不同（是否要求时间维度、是否需要去重都不一样）。
nonisolated enum ShopCatalogPriceEditError: LocalizedError {
    /// 价格非正数
    case invalidPrice
    /// 定金 + 尾款 ≠ 价格（或清了预约价却留着定金 / 尾款）
    case depositBalanceMismatch(String)
    /// 追加记录重复提交（业务指纹命中既有记录）
    case duplicateRecord
    /// 商品不存在（可能已被删除）
    case productNotFound(String)
    /// 修正 / 追加的币种与商品既有币种不一致（R02：修价不是换币种，也不隐式换汇）
    case crossCurrency(String)

    var errorDescription: String? {
        switch self {
        case .invalidPrice:
            return "价格必须大于 0"
        case .depositBalanceMismatch(let detail):
            return "定金尾款对账失败：\(detail)"
        case .duplicateRecord:
            return "该销售记录已存在（同商品 / 同类型 / 同价格 / 同批次日），请勿重复提交"
        case .productNotFound(let id):
            return "未找到商品 \(id)，可能已被删除"
        case .crossCurrency(let detail):
            return "币种不一致：\(detail)。修正价格不是更换币种，也不可隐式换汇；"
                + "请先用正确币种重新录入，或交由人工核对来源币种。"
        }
    }
}

// MARK: - 运营草稿

nonisolated struct CatalogProductDraft: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    /// 所属批次（V1.1 §4.1 批量录入：一次补录任务的多条单品互不耦合）；nil = 单条录入
    var batchID: String? = nil
    /// 关联既有店家；为 nil 时用 newShopName 新建
    var shopID: String?
    var newShopName: String = ""
    var newShopAliases: String = "" // 逗号分隔
    /// 关联既有系列；为 nil 时用 newSeriesName 新建
    var seriesID: String?
    var newSeriesName: String = ""
    var newSeriesYear: Int?
    var newSeriesSeason: String = ""

    var name: String = ""
    var category: String = "其他"
    /// 款式名（2026-09-22 V1.4「同款不同色」归类）：可空 = 按商品名剥离颜色词自动派生；
    /// 同款式不同颜色的补录填同一款式名，发布后列表自动归入同一款式展示。
    /// Optional + 默认 nil，合成解码对旧 JSON 自动兜底。
    var designName: String? = nil
    /// 本次销售记录类型：reservation / stock
    /// ⚠️ 2026-09-22 起仅作旧数据兼容：预约价与现货价**并存且不互斥**，
    /// 新录入一律用 price（预约价）+ stockPrice（现货价），不再用本字段切换互斥表单。
    var saleKind: CatalogSaleEventType = .reservation
    /// 预约价（可空 = 0；现货价可与之并存，也可两者都空置后补录）
    var price: Double = 0
    /// 现货价（可空，后续补录修改；与预约价并存，互不清空/覆盖）
    var stockPrice: Double? = nil
    var deposit: Double?
    var balance: Double?
    var startAt: Date? = nil
    var endAt: Date? = nil
    /// 金额币种（R02）。nil = 未标注 → 发布时按「币种待确认」入库，
    /// **不做全局默认 CNY**（§5.2 步骤 6：币种必须明确）。
    /// Optional + 默认 nil，合成解码对旧 JSON 自动兜底。
    var currency: CatalogCurrency? = nil

    /// 完整商品资料（V1.1 G5：手动录入必须能完成全部业务）
    /// 图片以 CatalogAsset 表达（originalURL 必填）；发布时一并写入覆盖层
    var images: [CatalogAsset] = []
    /// 配色尺码规格；发布时一并写入覆盖层
    var variants: [CatalogProductVariant] = []
    /// 结构化尺码表（含 sourceImage）；发布时一并写入覆盖层
    var sizeChart: CatalogSizeChart? = nil
    /// 款式（SPU）公共资料：面料成分 —— 同款所有颜色共用一份，发布时落到
    /// `CatalogStyleProfile`（款式档案）。Optional + 默认 nil，合成解码对旧 JSON 自动兜底。
    var fabric: String? = nil
    /// 款式（SPU）公共资料：款式描述 —— 同上，整款一份。
    /// 注意与 `CatalogProduct.description` 的关系：发布后以款式档案为准，
    /// 档案为空时读取侧回退商品自身的 description（历史写法兼容）。
    var styleDescription: String? = nil

    var status: CatalogPublicationStatus = .draft
    /// 审核驳回原因（V1.1 §4.1：驳回退回草稿并保留原因）；重新提交时清空。
    /// Optional + 默认 nil，合成解码对旧 JSON 自动兜底。
    var rejectReason: String? = nil
    var createdAt: Date = Date()
    /// 已发布结果（R09）：重复提交与半成功恢复的依据。
    /// Optional + 默认 nil，合成解码对旧 JSON 自动兜底（旧草稿 = 未记录，走首次发布）。
    var publishedResult: CatalogDraftPublishResult? = nil

    // MARK: 预约 / 现货并存口径（2026-09-22）

    /// 预约价口径：新口径下 price 即预约价；
    /// 唯一例外是**未经新编辑器迁移的旧现货草稿**（saleKind == .stock 且未单独填
    /// stockPrice）——它的 price 历史上就是现货价，不得重复解释为预约价。
    nonisolated var effectiveReservationPrice: Double? {
        if saleKind == .stock && stockPrice == nil { return nil }
        return price > 0 ? price : nil
    }

    /// 现货价口径：新口径取 stockPrice；
    /// 旧现货草稿（同上）回退解释 price，保证存量草稿发布行为不变。
    nonisolated var effectiveStockPrice: Double? {
        if saleKind == .stock && stockPrice == nil { return price > 0 ? price : nil }
        return stockPrice.flatMap { $0 > 0 ? $0 : nil }
    }

    /// 价格摘要：预约 / 现货并存展示（谁填了显示谁，都不填给引导文案）
    nonisolated var priceSummary: String {
        var parts: [String] = []
        if let r = effectiveReservationPrice { parts.append("预约 ¥\(Int(r))") }
        if let s = effectiveStockPrice { parts.append("现货 ¥\(Int(s))") }
        return parts.isEmpty ? "待填价格" : parts.joined(separator: " · ")
    }

    /// 预约草稿的定金尾款对账（允许缺省，缺省时发布前自动补齐）
    nonisolated var depositBalanceIssue: String? {
        guard effectiveReservationPrice != nil, let d = deposit, let b = balance else { return nil }
        return (Decimal(d) + Decimal(b)) == Decimal(price)
            ? nil : "定金 \(Int(d)) + 尾款 \(Int(b)) ≠ 总价 \(Int(price))"
    }
}

// MARK: - 发布结果记录（2026-09-22 第三版收口 R09：发布幂等与半成功恢复）

/// 一次成功发布的落库结果，随草稿持久化。
///
/// 用途有两个，都是 R09 点名要解决的失效形态：
///   1. **重复提交**：同一份草稿内容再次点发布（重复点击、或 UI 持有旧 reviewed 快照），
///      凭 `operationKey` 判定「这次内容和上次完全一样」→ 直接返回上次结果，
///      不再追加一组销售事件。
///   2. **半成功恢复**：覆盖层已写成功、但草稿状态/结果写回失败（写盘失败、进程被杀）。
///      下次发布时覆盖层里已有产物，凭确定性事件 id 反查命中 → 只补齐草稿状态，
///      **绝不重新生成一组事件**。
nonisolated struct CatalogDraftPublishResult: Codable, Hashable, Sendable {
    /// 发布产生的商品 ID（新建或复用的既有商品）
    var productID: String
    /// 本次发布写入的销售事件 ID（确定性生成，可反查）
    var saleEventIDs: [String]
    /// 发布完成时间
    var publishedAt: Date
    /// 发布时的内容指纹；内容没变就复用本次结果
    var operationKey: String
}

extension CatalogProductDraft {

    /// 发布操作键：**决定发布产物**的字段指纹（不含状态、不含写入时间）。
    ///
    /// 刻意排除 `status / rejectReason / createdAt / id`，因为同一份内容被驳回后
    /// 重新提交、或换个草稿 id 重录，都应复用已发布的产物而不是再发一遍。
    /// 反过来，任何会改变产物的字段（店家 / 系列 / 商品名 / 分类 / 价格 / 档期 /
    /// 款式名）变化都会让指纹改变，从而允许一次**真实的新发布**。
    nonisolated var publishOperationKey: String {
        func d(_ value: Double?) -> String {
            guard let value else { return "-" }
            return NSDecimalNumber(value: value).stringValue
        }
        func t(_ date: Date?) -> String {
            guard let date else { return "-" }
            return String(Int(date.timeIntervalSince1970))
        }
        let parts = [
            shopID ?? "new:\(newShopName)",
            newShopAliases,
            seriesID ?? "new:\(newSeriesName)",
            String(newSeriesYear.map(String.init) ?? "-"),
            newSeriesSeason,
            name,
            category,
            designName ?? "-",
            String(effectiveReservationPrice ?? -1),
            String(effectiveStockPrice ?? -1),
            d(deposit), d(balance),
            t(startAt), t(endAt),
            images.map(\.originalURL).joined(separator: ","),
            variants.map { "\($0.color ?? "-")/\($0.size ?? "-")" }.joined(separator: ","),
            sizeChart.map { "\($0.columns.joined(separator: ","))#\($0.rows.count)#\($0.sourceImage ?? "-")" } ?? "-",
            // 款式（SPU）公共资料参与指纹：改了面料/描述就是一份新内容，
            // 否则重新发布会被「已恢复发布结果」吞掉，面料改动永远落不了库。
            fabric ?? "-",
            styleDescription ?? "-",
            // 币种参与指纹（R02）：同价格不同币种是两条不同的销售记录。
            // 未标注（nil）与旧草稿口径一致地退化为 "-"，不会让存量已发布草稿换指纹。
            currency?.rawValue ?? "-",
        ]
        return parts.joined(separator: "|")
    }

    /// 决定「落到哪个商品」的归属指纹：店家 / 系列 / 商品名 / 品类 / 款式。
    /// 改归属 = 落到另一个商品，因此销售事件 ID 也必须跟着变。
    nonisolated var productIdentityKey: String {
        [shopID ?? "new:\(newShopName)",
         seriesID ?? "new:\(newSeriesName)",
         name, category, designName ?? "-"].joined(separator: "|")
    }

    /// 单条销售事件的确定性指纹（R09）：**只包含与该事件有关的字段**。
    ///
    /// 用整份草稿指纹会导致「只改了预约价，现货价被原样重发一次」——
    /// 现货事件 ID 变了，覆盖层里就多出一条内容完全相同的记录。
    /// 这里按类型收窄：预约事件只看预约三件套，现货事件只看现货价。
    nonisolated func saleEventKey(_ type: CatalogSaleEventType) -> String {
        let priceFields: [String]
        switch type {
        case .reservation:
            priceFields = [d(effectiveReservationPrice), d(deposit), d(balance)]
        case .stock:
            priceFields = [d(effectiveStockPrice)]
        case .rerelease:
            // 再贩记录不走发布流程（由「追加销售记录」入口写入），这里给空指纹占位
            priceFields = []
        }
        return ([productIdentityKey, type.rawValue] + priceFields
                + [t(startAt), t(endAt), currency?.rawValue ?? "-"])
            .joined(separator: "|")
    }

    private nonisolated func d(_ value: Double?) -> String {
        guard let value else { return "-" }
        return NSDecimalNumber(value: value).stringValue
    }

    private nonisolated func t(_ date: Date?) -> String {
        guard let date else { return "-" }
        return String(Int(date.timeIntervalSince1970))
    }
}

// MARK: - 批次录入会话（V1.1 §4.1：一次补录任务录入多个单品、多品类混合）

/// 批次会话：归属店家/系列（可新建）+ 若干独立单品草稿。
/// 状态互不耦合：批次内可部分发布、部分停留草稿、部分驳回（§4.3）。
nonisolated struct CatalogBatchEntrySession: Codable, Identifiable, Hashable, Sendable {
    var id: String = "batch-\(UUID().uuidString.prefix(8))"
    /// 归属店家；nil = 用 newShopName 新建（整批同店）
    var shopID: String?
    var newShopName: String = ""
    var newShopAliases: String = ""
    /// 归属系列；nil = 用 newSeriesName 新建（整批同系列）
    var seriesID: String?
    var newSeriesName: String = ""
    var newSeriesYear: Int?
    var newSeriesSeason: String = ""
    var createdAt: Date = Date()
}

// MARK: - 发布校验（§29 去重 + 基础校验）

nonisolated enum ShopCatalogDraftValidator {

    nonisolated enum ValidationError: LocalizedError {
        case missingName
        case invalidPrice
        case depositBalanceMismatch(String)
        case missingShop
        case missingSeries

        var errorDescription: String? {
            switch self {
            case .missingName: return "商品名称不能为空"
            case .invalidPrice: return "价格必须大于 0"
            case .depositBalanceMismatch(let detail): return "定金尾款对账失败：\(detail)"
            case .missingShop: return "未选择或填写店家"
            case .missingSeries: return "未选择或填写系列"
            }
        }
    }

    static func validate(_ draft: CatalogProductDraft, catalog: ShopCatalog?) throws {
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ValidationError.missingName }
        // 预约价与现货价并存且不互斥：至少填一项即可；现货价可空置后补录（2026-09-22）
        guard draft.effectiveReservationPrice != nil || draft.effectiveStockPrice != nil else {
            throw ValidationError.invalidPrice
        }
        if let issue = draft.depositBalanceIssue { throw ValidationError.depositBalanceMismatch(issue) }
        guard draft.shopID != nil || !draft.newShopName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.missingShop
        }
        guard draft.seriesID != nil || !draft.newSeriesName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError.missingSeries
        }
    }

    /// 店家去重（§29）：按名称或别名匹配既有店家；命中则应复用，不再新建
    static func findExistingShop(for draft: CatalogProductDraft, catalog: ShopCatalog?) -> CatalogShop? {
        guard let catalog else { return nil }
        let name = draft.newShopName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return catalog.shops.first { $0.matches(nameOrAlias: name) }
    }

    /// 系列去重：同店家下同名（不区分大小写）系列视为同一系列
    static func findExistingSeries(for draft: CatalogProductDraft, shopID: String, catalog: ShopCatalog?) -> CatalogSeries? {
        guard let catalog else { return nil }
        let name = draft.newSeriesName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }
        return catalog.series.first { $0.shopID == shopID && $0.name.lowercased() == name }
    }

    /// 商品去重 + 现货追加判定（§29/§30）：同系列同名商品已存在，
    /// 且草稿是现货记录 → 追加 SaleEvent 而不是新建商品。
    static func findExistingProduct(for draft: CatalogProductDraft, seriesID: String, catalog: ShopCatalog?) -> CatalogProduct? {
        guard let catalog else { return nil }
        let name = draft.name.trimmingCharacters(in: .whitespaces).lowercased()
        return catalog.products.first { $0.seriesID == seriesID && $0.name.lowercased() == name }
    }
}

// MARK: - 统一存储目录（测试隔离，2026-09-21 事故根源修复）

/// ShopCatalog 全部运营数据的统一根目录（草稿 / 批次 / 覆盖层 / 运营上传图片）。
///
/// 事故回顾：单元测试以主 App 为宿主运行，`FileManager.default` 指向用户真实沙盒。
/// 多个测试套件在 tearDown 里删除真实覆盖层/草稿文件，导致用户发布的系列在
/// 每轮回归测试后被清掉（表现为「发布的系列刷新后消失」）。
/// 根源修复：所有测试必须先 `useTemporaryForTesting()` 把读写重定向到独立临时
/// 目录，结束时 `restoreDefaultForTesting()` 还原并清理——测试从此无法触碰生产数据。
nonisolated enum ShopCatalogStorage {

    /// 测试注入的临时目录；nil = 生产路径（宿主 App 沙盒 Application Support/ShopCatalog）
    private nonisolated(unsafe) static var testOverride: URL?

    /// 当前生效的存储根目录（测试注入优先）
    static var directory: URL {
        if let testOverride { return testOverride }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 生产路径（永不受测试注入影响）：供回归测试断言「测试未污染生产数据」
    static var productionDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShopCatalog", isDirectory: true)
    }

    static var isTestOverridden: Bool { testOverride != nil }

    /// 测试专用：重定向到全新临时目录（每套测试独立，互不串扰）
    @discardableResult
    static func useTemporaryForTesting() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShopCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        testOverride = url
        return url
    }

    /// 测试专用：恢复生产路径并清掉临时目录
    static func restoreDefaultForTesting() {
        if let url = testOverride {
            try? FileManager.default.removeItem(at: url)
        }
        testOverride = nil
    }
}

// MARK: - 批次单品分组（2026-09-22：未指定系列默认继承整批归属）

/// 批次详情「本批单品（按系列分组）」的分组键纯逻辑（nonisolated 可单测）：
///   · 草稿**自报**了系列（关联系列 Picker 选中，或填了新系列名）→ 永远用自己的，
///     整批归属怎么变都不覆盖（用户手动修改不被覆盖）；
///   · 草稿未自报 → **继承**整批归属当前选定的系列（上方店家/系列选择联动，
///     上方一变，分组即时跟着变）；
///   · 整批也没选定系列 → 维持原有默认行为「未指定系列」。
/// 注意：这里只是**展示分组**口径；把继承值真正写进草稿数据仍走「应用到整批」按钮
/// （applyBatchAttribution），避免上方随便点一下就静默改数据。
nonisolated enum CatalogBatchGrouping {
    static let unspecified = "未指定系列"

    /// - Parameters:
    ///   - draftOwnSeriesName: 草稿自报系列的展示名（seriesID 解析成功 = 系列名，
    ///     解析失败 = 原始 id 兜底；填了新系列名 = 该名称）；nil = 草稿未自报系列
    ///   - batchSeriesName: 整批归属当前选定系列的展示名；nil = 上方未选定系列
    static func groupKey(draftOwnSeriesName: String?, batchSeriesName: String?) -> String {
        if let own = draftOwnSeriesName { return own }
        if let batch = batchSeriesName { return batch }
        return unspecified
    }
}

// MARK: - 批次删除（2026-09-22 批次列表治理）

/// 批量删除结果：成功删除的批次 + 被拦截的批次（条目保留，附原因，可处理后重试）
nonisolated struct CatalogBatchDeleteBlock: Identifiable, Hashable, Sendable {
    let batchID: String
    let reason: String
    var id: String { batchID }
}

nonisolated struct CatalogBatchDeleteResult: Sendable {
    let deletedIDs: Set<String>
    let blocked: [CatalogBatchDeleteBlock]
}

// MARK: - 商品批量删除（2026-09-23：多选 + 二次确认）

/// 商品被拦下的原因。文案与单项 `ShopCatalogEntityError` 保持同一口径，
/// 但这里用**枚举**而不是拼好的错误对象，方便弹窗逐条列出、也方便单测断言。
nonisolated enum CatalogProductDeleteReason: Hashable, Sendable {
    /// 已被用户心愿 / 尾款 / 衣橱引用（含软删除记录）→ 只能归档
    case referencedByUserData
    /// 来自随版本内置的种子档案（Bundle 只读）→ 无法物理删除，只能归档
    case seedImmutable

    var message: String {
        switch self {
        case .referencedByUserData:
            return "已被用户心愿/尾款/衣橱引用，禁止删除，仅可归档。"
        case .seedImmutable:
            return "来自随版本内置的种子档案，无法物理删除，仅可归档。"
        }
    }
}

/// 批量删除中被拦下的单个商品（条目保留并附原因，处理后可用同样的选择重试）
nonisolated struct CatalogProductDeleteBlock: Identifiable, Hashable, Sendable {
    let productID: String
    let name: String
    let reason: CatalogProductDeleteReason
    var id: String { productID }
}

/// 商品批量删除结果：成功物理删除的 id + 被拦截的条目。
/// 部分成功是允许的，但**绝不静默**——`blocked` 必须原样展示给操作者。
nonisolated struct CatalogProductDeleteResult: Sendable {
    let deletedIDs: Set<String>
    let blocked: [CatalogProductDeleteBlock]
}

/// 删除预检结果（只读）：供「二次确认」弹窗展示**真实**影响范围。
/// 与真正执行走同一个决策函数，所以弹窗说会删几件、实际就删几件。
nonisolated struct CatalogProductDeletePreview: Equatable, Sendable {
    let deletableNames: [String]
    let blocked: [CatalogProductDeleteBlock]

    var deletableCount: Int { deletableNames.count }
    var blockedCount: Int { blocked.count }
}

nonisolated enum ShopCatalogBatchStoreError: LocalizedError {
    /// 批次记录持久化失败：内存与磁盘都未变化，条目完整保留，可直接重试
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .persistenceFailed(let detail):
            return "批次记录写入失败：\(detail)。列表未发生任何变化，请重试。"
        }
    }
}

// MARK: - 草稿删除判定（2026-09-23：单条 + 多选批量）

/// 草稿删除的判定结果：**预检与执行同源**。
///
/// `ShopCatalogDraftStore.previewDraftDeletion`（只读，供确认弹窗）与
/// `deleteDrafts`（执行）都走 `ShopCatalogDraftDeletion.plan`，
/// 所以「弹窗说删 N 条」与「实际删 N 条」不可能对不上。
///
/// 与「批次删除」刻意不同，这里**没有任何硬拦截**。理由是批次删除的拦截文案本身
/// 就让运营「在草稿箱中删除这些草稿后再删除批次」——若草稿删除也再拦一道，
/// 那条指引就成了死路。可删范围覆盖全部状态（含已发布 / 已归档这份发布回执），
/// 因为删除只作用于草稿箱记录、不碰覆盖层产物，所以是安全的；
/// 状态构成只用来把影响范围讲清楚，不承担拦截职责。
///
/// 纯数据、无文案：影响范围文案由视图层拼（与 `batchDeleteImpactText` 同一分工），
/// 这样这个类型不必依赖 MainActor 隔离的本地化能力，可以留在 nonisolated 里单测。
nonisolated struct ShopCatalogDraftDeletionPlan: Equatable, Sendable {
    /// 选择中**真实存在**、会被删除的草稿 id（保持草稿箱原有顺序）
    var targetIDs: [String] = []
    /// 选择中已找不到的 id（例如已在别处删掉）→ 执行时静默跳过，不算删除数
    var staleIDs: [String] = []
    /// 目标按发布状态分组的条数（视图按 `CatalogPublicationStatus.allCases` 顺序展示）
    var countsByStatus: [CatalogPublicationStatus: Int] = [:]
    /// 仍在流转中的条数（草稿 / 待审核 / 待发布）
    var inFlightCount: Int = 0
    /// 已出终态的条数（已发布 / 已归档 —— 发布回执）
    var settledCount: Int = 0

    var isEmpty: Bool { targetIDs.isEmpty }
    var targetCount: Int { targetIDs.count }
}

// MARK: - 整款表单落盘结果（2026-09-23「款式 + 多颜色」录入）

/// 一次「整款表单」保存的落库结果（每条颜色草稿的去向都要能讲清楚）。
///
/// 之所以要区分「跳过」与「更新」：已发布 / 已归档的颜色行在表单里是只读的，
/// 保存时**静默跳过它们的草稿**，但绝不能假装「整款都存好了」——
/// 运营得知道哪几个颜色因为已经上线而没有被这次编辑改动。
nonisolated struct ShopCatalogStyleFormResult: Equatable, Sendable {
    /// 更新了资料的既有颜色草稿数
    var updatedCount: Int = 0
    /// 本次表单新加、刚建出来的颜色草稿数
    var createdCount: Int = 0
    /// 从表单里移除、并连带删掉的未发布颜色草稿数
    var removedCount: Int = 0
    /// 因为已发布 / 已归档而被跳过的颜色行数（产物在覆盖层，改草稿不生效）
    var skippedSettledCount: Int = 0

    var isEmpty: Bool { updatedCount == 0 && createdCount == 0 && removedCount == 0 }
    /// 实际写入的颜色草稿数（不含被移除的）
    var writtenCount: Int { updatedCount + createdCount }
}

nonisolated enum ShopCatalogDraftDeletion {

    /// 由「勾选的 id 集合 + 当前草稿箱」推导删除判定。
    ///
    /// - Parameters:
    ///   - ids: 勾选的草稿 id（单条删除时只放一条）
    ///   - drafts: 草稿箱当前内容（生产注入 `ShopCatalogDraftStore.drafts`）
    static func plan(ids: Set<String>,
                     drafts: [CatalogProductDraft]) -> ShopCatalogDraftDeletionPlan {
        guard !ids.isEmpty else { return ShopCatalogDraftDeletionPlan() }

        var plan = ShopCatalogDraftDeletionPlan()
        // 遍历 drafts 而不是 ids：保证 targetIDs 与草稿箱展示顺序一致，
        // 弹窗里「将删除「A」、「B」」才和用户看到的行序对得上
        for draft in drafts where ids.contains(draft.id) {
            plan.targetIDs.append(draft.id)
            plan.countsByStatus[draft.status, default: 0] += 1
            switch draft.status {
            case .draft, .submitted, .reviewed:
                plan.inFlightCount += 1
            case .published, .archived:
                plan.settledCount += 1
            }
        }
        plan.staleIDs = ids.subtracting(Set(plan.targetIDs)).sorted()
        return plan
    }
}

// MARK: - 草稿存储 + 发布（§31）

@MainActor
final class ShopCatalogDraftStore: ObservableObject {
    static let shared = ShopCatalogDraftStore()

    @Published private(set) var drafts: [CatalogProductDraft] = []
    /// 批次会话（发布式：createBatch / saveBatches / deleteBatches 统一维护，
    /// 视图请读 `batches` 而不是直接调 `loadBatches()`，否则删除后不会刷新）
    @Published private(set) var batches: [CatalogBatchEntrySession] = []

    private let fileManager = FileManager.default
    private var draftsURL: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-drafts.json")
    }

    private var batchesURL: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-batches.json")
    }

    /// 发布后的覆盖层：与 Bundle 种子合并后对用户可见
    nonisolated static var overlayURL: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-override.json")
    }

    private init() {
        loadDrafts()
        batches = Self.loadBatches()
    }

    // MARK: 草稿持久化（R01：编解码同源 + 坏文件保护 + 写盘失败可见）

    /// 最近一次加载的异常（文件损坏 / 解析失败），供运营 UI 显式提示。
    /// nil = 加载正常（含「文件不存在」这种合法的空草稿箱）。
    @Published private(set) var lastLoadIssue: String? = nil

    /// 最近一次写入失败原因（R01：写盘失败必须可见，不能静默成功）。
    /// SwiftUI Binding 的 set 闭包无法抛错，写入入口用 `upsertReportingError`
    /// 把错误落到这里，由 UI 显式提示；内存与磁盘都不变，可原样重试。
    @Published private(set) var lastPersistenceError: String? = nil

    /// 坏文件待处理状态：为 true 时**禁止任何写回**（R01 后半段风险：
    /// 「解码失败 → 当成空库 → 下一次保存覆盖掉还能抢救的旧文件」）。
    /// 只有人工处理完坏文件（移除或修复）并重新加载后才解除。
    private(set) var isBlockedByCorruptFile = false

    /// 坏文件备份路径（供 UI 指引运营去哪里找回原文件）
    private(set) var corruptFileBackupURL: URL? = nil

    func loadDrafts() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: draftsURL.path),
              let data = try? Data(contentsOf: draftsURL) else {
            // 文件不存在 = 合法的空草稿箱（首次启动），不是错误
            drafts = []
            lastLoadIssue = nil
            isBlockedByCorruptFile = false
            corruptFileBackupURL = nil
            return
        }
        do {
            drafts = try ShopCatalogJSONCoding.decoder()
                .decode([CatalogProductDraft].self, from: data)
            lastLoadIssue = nil
            isBlockedByCorruptFile = false
            corruptFileBackupURL = nil
        } catch {
            // 解码失败：**绝不**当作空库。原文件原地保留，另存一份带时间戳的副本，
            // 并进入「待处理」状态阻止后续写回。
            let backup = Self.backupURL(for: draftsURL)
            try? fm.copyItem(at: draftsURL, to: backup)
            corruptFileBackupURL = backup
            isBlockedByCorruptFile = true
            lastLoadIssue = Self.describeDecodingFailure(error)
            // drafts 保持进入本方法前的内存值（首次启动即为空数组），
            // 但 isBlockedByCorruptFile 会阻止把它写回磁盘。
        }
    }

    /// 人工处理完坏文件后调用：解除写入封锁并重新加载。
    /// （运营 UI 的「我已处理，重新加载」入口；不删除任何文件。）
    func clearCorruptFileBlockAndReload() {
        isBlockedByCorruptFile = false
        corruptFileBackupURL = nil
        lastLoadIssue = nil
        loadDrafts()
    }

    private static func backupURL(for url: URL) -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        return url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
    }

    private static func describeDecodingFailure(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, let context):
                return "缺少字段 \(key.stringValue)（路径 \(context.codingPath.map(\.stringValue).joined(separator: "."))）"
            case .typeMismatch(let type, let context):
                return "字段类型不符，期望 \(type)（路径 \(context.codingPath.map(\.stringValue).joined(separator: "."))）"
            case .valueNotFound(let type, let context):
                return "字段值为空，期望 \(type)（路径 \(context.codingPath.map(\.stringValue).joined(separator: "."))）"
            case .dataCorrupted(let context):
                return context.debugDescription
            @unknown default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }

    /// 写盘：**先写磁盘再提交内存**，失败时内存与磁盘都不变，可直接重试。
    private func persist(_ snapshot: [CatalogProductDraft]) throws {
        if isBlockedByCorruptFile {
            throw ShopCatalogDraftFileError.writeBlockedByCorruptFile(draftsURL)
        }
        let data: Data
        do {
            data = try ShopCatalogJSONCoding.encoder().encode(snapshot)
        } catch {
            throw ShopCatalogDraftFileError.writeFailed(error.localizedDescription)
        }
        do {
            try data.write(to: draftsURL, options: .atomic)
        } catch {
            throw ShopCatalogDraftFileError.writeFailed(error.localizedDescription)
        }
    }

    /// 绑定式写入（SwiftUI `Binding` 的 set 不能抛错）：失败时记到 `lastPersistenceError`。
    /// 语义与 `upsert(_:)` 完全一致（内存与磁盘都不变，可原样重试），只是错误出口不同。
    func upsertReportingError(_ draft: CatalogProductDraft) {
        do {
            try upsert(draft)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    /// 写入单条草稿。写盘失败抛错（内存不变、磁盘不变），调用方提示后可原样重试。
    func upsert(_ draft: CatalogProductDraft) throws {
        var snapshot = drafts
        if let index = snapshot.firstIndex(where: { $0.id == draft.id }) {
            snapshot[index] = draft
        } else {
            snapshot.append(draft)
        }
        try persist(snapshot)
        drafts = snapshot
    }

    /// 批量写入草稿（整批成功或整批失败，避免「写了一半」的半成品文件）。
    func upsert(_ drafts: [CatalogProductDraft]) throws {
        var snapshot = self.drafts
        for draft in drafts {
            if let index = snapshot.firstIndex(where: { $0.id == draft.id }) {
                snapshot[index] = draft
            } else {
                snapshot.append(draft)
            }
        }
        try persist(snapshot)
        self.drafts = snapshot
    }

    // MARK: 草稿删除（2026-09-23：单条 + 多选批量）

    /// 只读预检：确认弹窗据此说明「删几条、哪些状态、会不会影响线上数据」。
    /// 与 `deleteDrafts` 共用 `ShopCatalogDraftDeletion.plan`，因此与实际删除数恒等。
    func previewDraftDeletion(ids: Set<String>) -> ShopCatalogDraftDeletionPlan {
        ShopCatalogDraftDeletion.plan(ids: ids, drafts: drafts)
    }

    /// 删除草稿（单条删除同样走这里，`ids` 只放一条 —— **不存在第二条写入路径**）。
    ///
    /// 三条硬约束：
    ///   · **整批只写一次盘**：先在快照上删完再 `persist`，绝不循环调单条删除。
    ///     `persist` 是「先写磁盘、再提交内存」，失败时磁盘与内存都不变，可原样重试；
    ///   · **不连带改批次**：批次只是归组视图，草稿 `batchID` 引用随之失效即可，
    ///     `shop-catalog-batches.json` 一条不动（与「删批次不动草稿」互为镜像）；
    ///   · **不碰覆盖层**：已发布商品的资料与销售记录完全不受影响 ——
    ///     被删掉的只是草稿箱里的记录（含已发布草稿那份发布回执）。
    ///
    /// `drafts` 是 `@Published`，赋值即触发草稿箱列表实时刷新。
    /// - Returns: 实际命中的判定结果（视图直接拿它拼结果提示）。
    @discardableResult
    func deleteDrafts(ids: Set<String>) throws -> ShopCatalogDraftDeletionPlan {
        try CreatorAccess.requireCreator(.listingEdit)
        let plan = ShopCatalogDraftDeletion.plan(ids: ids, drafts: drafts)
        guard !plan.isEmpty else { return plan }

        let doomed = Set(plan.targetIDs)
        var snapshot = drafts
        snapshot.removeAll { doomed.contains($0.id) }
        try persist(snapshot)
        drafts = snapshot
        return plan
    }

    // MARK: 批次会话（V1.1 §4.1）

    /// 全部批次（草稿状态互不耦合，批次只是归组视图）
    /// 批次读取：与草稿同源的宽容解码器（R01）。文件损坏时**返回空并保留原文件**，
    /// 由 `lastLoadIssue` 报告——批次只是归组视图，不因解析失败阻断草稿箱。
    nonisolated static func loadBatches() -> [CatalogBatchEntrySession] {
        guard let data = try? Data(contentsOf: batchesURLStatic) else { return [] }
        return (try? ShopCatalogJSONCoding.decoder()
            .decode([CatalogBatchEntrySession].self, from: data)) ?? []
    }

    /// 批次落盘：**先写磁盘再提交内存**，失败抛错（内存与磁盘均不变，可原样重试）。
    func saveBatches(_ batches: [CatalogBatchEntrySession]) throws {
        let data: Data
        do {
            data = try ShopCatalogJSONCoding.encoder().encode(batches)
        } catch {
            throw ShopCatalogBatchStoreError.persistenceFailed(error.localizedDescription)
        }
        do {
            try data.write(to: batchesURL, options: .atomic)
        } catch {
            throw ShopCatalogBatchStoreError.persistenceFailed(error.localizedDescription)
        }
        self.batches = batches
    }

    nonisolated private static var batchesURLStatic: URL {
        ShopCatalogStorage.directory.appendingPathComponent("shop-catalog-batches.json")
    }

    // MARK: 批次删除（2026-09-22 批次列表治理）

    /// 批次删除拦截判定：批次下仍有**未处理**单品草稿（draft / submitted / reviewed）
    /// 时禁止删除，返回面向运营的可读原因；nil = 可删。
    /// 「已处理」口径：已发布（published）或已归档（archived）的草稿不算未处理——
    /// 批次只是归组记录，发布产物在覆盖层，删除批次不影响它们。
    nonisolated static func batchDeleteBlockReason(
        batchID: String, drafts: [CatalogProductDraft]
    ) -> String? {
        let unprocessed = drafts.filter {
            $0.batchID == batchID
                && ($0.status == .draft || $0.status == .submitted || $0.status == .reviewed)
        }
        guard !unprocessed.isEmpty else { return nil }
        var parts: [String] = []
        let draftCount = unprocessed.filter { $0.status == .draft }.count
        let submittedCount = unprocessed.filter { $0.status == .submitted }.count
        let reviewedCount = unprocessed.filter { $0.status == .reviewed }.count
        if draftCount > 0 { parts.append("草稿 \(draftCount) 条") }
        if submittedCount > 0 { parts.append("待审核 \(submittedCount) 条") }
        if reviewedCount > 0 { parts.append("待发布 \(reviewedCount) 条") }
        return "批次下仍有未处理数据（\(parts.joined(separator: "、"))），请先提交 / 发布，或在草稿箱中删除这些草稿后再删除批次。"
    }

    /// 批量删除批次会话。**只删归组记录，不动任何单品草稿**：
    ///   · 草稿箱中的草稿原样保留（batchID 引用随之失效，仅失去批次归组）；
    ///   · 已发布到覆盖层的数据完全不受影响；
    ///   · 未处理草稿命中拦截的批次**整体保留**（连同原因返回），可处理后重试；
    ///   · 持久化失败时抛错，磁盘与内存均不变化，调用方提示重试即可。
    @discardableResult
    func deleteBatches(ids: Set<String>) throws -> CatalogBatchDeleteResult {
        try CreatorAccess.requireCreator(.listingEdit)
        guard !ids.isEmpty else {
            return CatalogBatchDeleteResult(deletedIDs: [], blocked: [])
        }

        var blocked: [CatalogBatchDeleteBlock] = []
        var deletable = Set<String>()
        for id in ids {
            if let reason = Self.batchDeleteBlockReason(batchID: id, drafts: drafts) {
                blocked.append(CatalogBatchDeleteBlock(batchID: id, reason: reason))
            } else {
                deletable.insert(id)
            }
        }
        guard !deletable.isEmpty else {
            return CatalogBatchDeleteResult(deletedIDs: [], blocked: blocked)
        }

        var remaining = Self.loadBatches()
        remaining.removeAll { deletable.contains($0.id) }
        do {
            let data = try ShopCatalogJSONCoding.encoder().encode(remaining)
            try data.write(to: batchesURL, options: .atomic)
        } catch {
            throw ShopCatalogBatchStoreError.persistenceFailed(error.localizedDescription)
        }
        batches = remaining
        return CatalogBatchDeleteResult(deletedIDs: deletable, blocked: blocked)
    }

    /// 创建批次并把草稿写入草稿箱。
    /// 草稿写盘失败时抛错：批次记录已落盘但草稿未落盘的「半成功」由调用方提示重试
    /// （重试会把同一批草稿重新写入，批次记录按 id 去重不会重复）。
    @discardableResult
    func createBatch(
        _ session: CatalogBatchEntrySession,
        drafts: [CatalogProductDraft]
    ) throws -> String {
        var batches = Self.loadBatches()
        batches.append(session)
        try saveBatches(batches)

        var prepared: [CatalogProductDraft] = []
        for var draft in drafts {
            draft.batchID = session.id
            // 批次级归属：整批同店同系列（草稿可再单独改）
            draft.shopID = session.shopID
            draft.newShopName = session.newShopName
            draft.newShopAliases = session.newShopAliases
            draft.seriesID = session.seriesID
            draft.newSeriesName = session.newSeriesName
            draft.newSeriesYear = session.newSeriesYear
            draft.newSeriesSeason = session.newSeriesSeason
            prepared.append(draft)
        }
        try upsert(prepared)     // 整批成功或整批失败，不留半成品
        return "已生成 \(prepared.count) 条单品草稿"
    }

    /// 批量提交（§4.1）：本批次全部草稿态条目 → 提交；单品状态互不耦合
    func submitBatch(_ batchID: String) throws -> Int {
        try CreatorAccess.requireCreator(.listingStatus)
        var count = 0
        for draft in drafts where draft.batchID == batchID && draft.status == .draft {
            try advance(draft, to: .submitted)
            count += 1
        }
        return count
    }

    /// 整批归属整合（V1.1 §4.1）：一次指定「店家 + 系列」，写入批次会话并同步到
    /// 该批全部未发布草稿——同一系列的多单品归入同一条系列链路，用户端从系列页
    /// 查看并选择全部单品，避免单品与链接一一对应的分散结构。
    /// 已发布（.published）条目不回写（发布产物已写入覆盖层，改动请走实体编辑）。
    /// 返回更新的草稿数。
    @discardableResult
    func applyBatchAttribution(
        batchID: String,
        shopID: String?, newShopName: String, newShopAliases: String,
        seriesID: String?, newSeriesName: String, newSeriesYear: Int?, newSeriesSeason: String
    ) throws -> Int {
        var batches = Self.loadBatches()
        guard let idx = batches.firstIndex(where: { $0.id == batchID }) else { return 0 }
        batches[idx].shopID = shopID
        batches[idx].newShopName = newShopName
        batches[idx].newShopAliases = newShopAliases
        batches[idx].seriesID = seriesID
        batches[idx].newSeriesName = newSeriesName
        batches[idx].newSeriesYear = newSeriesYear
        batches[idx].newSeriesSeason = newSeriesSeason
        try saveBatches(batches)

        var updated: [CatalogProductDraft] = []
        for var draft in drafts
        where draft.batchID == batchID && draft.status != .published && draft.status != .archived {
            draft.shopID = shopID
            draft.newShopName = newShopName
            draft.newShopAliases = newShopAliases
            draft.seriesID = seriesID
            draft.newSeriesName = newSeriesName
            draft.newSeriesYear = newSeriesYear
            draft.newSeriesSeason = newSeriesSeason
            updated.append(draft)
        }
        try upsert(updated)      // 整批成功或整批失败
        return updated.count
    }

    // MARK: 同款不同色：款式公共资料一键同步（2026-09-23）

    /// 把一条草稿的**款式公共资料**同步到同款其他颜色草稿
    /// （即「复制信息到同款其他颜色」／批次页的「同步款式资料」）。
    ///
    /// 与 `applyBatchAttribution` 的分工，两者互不替代：
    ///   · 那个管**归属**（店家 / 系列），整批一刀切；
    ///   · 本方法管**款式公共资料**（价格组 / 尺码表 / 面料 / 款式描述），以某一条为模板。
    /// 两者都不碰颜色私有字段（商品名 / 配色图 / 配色尺码）——
    /// 复制名称会把粉色改叫生成色，复制图片会把三个颜色压成一张图。
    ///
    /// 约定：
    ///   · **模板草稿原样不动**，只写目标；
    ///   · 已发布 / 已归档的目标不回写（产物已在覆盖层，改草稿不影响线上）；
    ///   · 字段按「整快照覆盖」语义 —— 模板为空即清除目标该项，不是「跳过不修改」，
    ///     这样「再同步一次」能把改错的值纠正回来；
    ///   · **整批一次落盘**：要么全成功，要么磁盘上一条都没变。
    ///
    /// - Parameters:
    ///   - sourceDraftID: 模板草稿（用户当前录入并保存好的那一条，通常是有完整资料的颜色）
    ///   - targetDraftIDs: 目标草稿 id；非同款、或不可写的会被剔除而不是报错
    ///   - fields: 要同步的字段集合（空集合 = 无事发生）
    /// - Returns: 实际更新的草稿数（0 = 没有可写目标，UI 应提示而非假装成功）
    @discardableResult
    func syncStyleInfo(sourceDraftID: String,
                       targetDraftIDs: [String],
                       fields: Set<ShopCatalogDraftStyleSync.Field>) throws -> Int {
        try CreatorAccess.requireCreator(.listingStatus)
        guard let source = drafts.first(where: { $0.id == sourceDraftID }) else {
            throw ShopCatalogDraftStoreError.sourceDraftNotFound(sourceDraftID)
        }
        let wanted = Set(targetDraftIDs)
        // 防线：只认同款、且未发布/未归档的目标。调用方（视图）可能传进过期选择，
        // 这里按数据自己判一遍 —— 预检与执行同源，不靠 UI 自觉。
        let targets = drafts.filter { draft in
            guard wanted.contains(draft.id),
                  draft.status != .published, draft.status != .archived else { return false }
            return ShopCatalogDraftStyleForm.isSameStyle(source, draft)
        }
        guard !targets.isEmpty else { return 0 }

        let plan = ShopCatalogDraftStyleSync.syncPlan(from: source, to: targets, fields: fields)
        let updated = targets.compactMap { plan[$0.id] }
        guard !updated.isEmpty else { return 0 }
        try upsert(updated)
        return updated.count
    }

    /// 同款判定已上移到 `ShopCatalogDraftStyleForm.identity / isSameStyle / sameStyleFamily`：
    /// 表单展示的家族、跨草稿同步的目标、整款表单的落盘范围必须是**同一份判定**，
    /// 否则会出现「界面看不到、落盘却认为该改甚至该删」的颜色。
    /// （原先私有的 `syncStyleIdentity` / `isSameStyleForSync` 已随之删除，不留第二套口径。）

    // MARK: 整款录入：款式 + 多颜色一次性落盘（2026-09-23）

    /// 一次表单提交 = 整款（款式公共资料 + N 个颜色 SKU）一次落盘。
    ///
    /// 取代「先建单品、再逐色重录公共资料」的旧流程：颜色行在本表单内直接新增，
    /// 公共资料只写一遍。落盘是**一次 `persist`** —— 要么全成功，要么磁盘上一条都没变。
    ///
    /// 四条口径（与项目既有规则一致，不另开一套语义）：
    ///   · **预检与执行同源**：同款判定由服务层自己按数据判一遍，不靠 UI 传对 id；
    ///   · **款式名一处决议**：显式填写优先，否则按源草稿派生，再交给所有颜色共用。
    ///     绝不逐条派生 —— 新加的颜色没有历史商品名可派生，会派生出空款名而掉出同款组；
    ///   · **已发布 / 已归档只读跳过**：产物已在覆盖层，改草稿不影响线上，
    ///     但如实返回跳过条数，不假装整款都存好了；
    ///   · **移除颜色 = 删除其未发布草稿**：与「删批次不连带删草稿」不矛盾 ——
    ///     批次只是归组记录，而颜色行**就是**这份草稿本身，删掉它是用户的明确意图，
    ///     留着会变成草稿箱里的孤儿。已发布的草稿保留（那是发布回执）。
    @discardableResult
    func applyStyleForm(
        sourceDraftID: String,
        style: ShopCatalogDraftStyleForm.StyleInput,
        colors: [ShopCatalogDraftStyleForm.ColorRow]
    ) throws -> ShopCatalogStyleFormResult {
        try CreatorAccess.requireCreator(.listingEdit)

        guard let source = drafts.first(where: { $0.id == sourceDraftID }) else {
            throw ShopCatalogDraftStoreError.sourceDraftNotFound(sourceDraftID)
        }

        // 款名决议 + 校验（与表单展示同一份口径：`resolveStyleName` 是唯一决议点）
        var resolved = style
        resolved.styleNameFallback = ShopCatalogDraftStyleForm.resolveStyleName(
            explicit: style.designName, source: source)
        try ShopCatalogDraftStyleForm.validate(colors: colors, styleName: resolved.styleNameFallback)

        let orderedSizes = ShopCatalogSizeChartSharing.sizeLabels(of: style.sizeChart)
        // 家族口径与视图展示同源（`sameStyleFamily`）—— 两处不一致会把「表单没显示」
        // 的草稿当成「用户删掉了这个颜色」而误删
        let family = ShopCatalogDraftStyleForm.sameStyleFamily(of: source, in: drafts)

        var snapshot = drafts
        var result = ShopCatalogStyleFormResult()
        let represented = Set(colors.compactMap(\.draftID))

        // 1) 表单里已移除的同款颜色：未发布的连带删除，已发布的保留并计入跳过
        let removable = Set(family.filter {
            !represented.contains($0.id) && !ShopCatalogDraftStyleForm.isSettled($0)
        }.map(\.id))
        result.skippedSettledCount = family.filter {
            !represented.contains($0.id) && ShopCatalogDraftStyleForm.isSettled($0)
        }.count
        if !removable.isEmpty {
            snapshot.removeAll { removable.contains($0.id) }
            result.removedCount = removable.count
        }

        // 2) 逐行应用：命中的既有草稿更新，没有的按新增建出来
        for row in colors {
            if let draftID = row.draftID,
               let index = snapshot.firstIndex(where: { $0.id == draftID }) {
                let existing = snapshot[index]
                guard !ShopCatalogDraftStyleForm.isSettled(existing) else {
                    result.skippedSettledCount += 1
                    continue
                }
                let styled = ShopCatalogDraftStyleForm.applyStyle(resolved,
                                                                  to: existing,
                                                                  colorName: row.colorName)
                snapshot[index] = ShopCatalogDraftStyleForm.applyColor(row,
                                                                       to: styled,
                                                                       orderedSizes: orderedSizes)
                result.updatedCount += 1
            } else {
                snapshot.append(ShopCatalogDraftStyleForm.makeNewDraft(colorRow: row,
                                                                       style: resolved,
                                                                       basedOn: source,
                                                                       orderedSizes: orderedSizes))
                result.createdCount += 1
            }
        }

        try persist(snapshot)   // 单次落盘：失败时磁盘与内存都不变，可原样重试
        drafts = snapshot
        return result
    }

    /// 单品粒度审核（§4.1）：通过 → reviewed；驳回 → 退回草稿并保留原因
    func review(_ draft: CatalogProductDraft, approve: Bool, reason: String? = nil) throws {
        try CreatorAccess.requireCreator(.listingStatus)
        guard draft.status == .submitted else {
            throw ShopCatalogDraftStoreError.illegalTransition(from: draft.status, to: approve ? .reviewed : .draft)
        }
        if approve {
            try advance(draft, to: .reviewed)
            return
        }
        // 驳回：原因写入草稿（空白原因归一为 nil），状态退回 draft
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = draft
        updated.status = .draft
        updated.rejectReason = (trimmed?.isEmpty == false) ? trimmed : nil
        try upsert(updated)
    }

    // MARK: 发布状态机（计划 §31：draft → submitted → reviewed → published，任一态可 archived）

    /// 推进草稿状态。非法流转抛错。
    /// `submitted → draft` 为审核驳回（V1.1 §4.1：部分通过发布、部分驳回退回草稿）。
    func advance(_ draft: CatalogProductDraft, to newStatus: CatalogPublicationStatus) throws {
        let allowed: [CatalogPublicationStatus: Set<CatalogPublicationStatus>] = [
            .draft: [.submitted, .archived],
            .submitted: [.reviewed, .archived, .draft],
            .reviewed: [.published, .archived],
            .published: [.archived],
            .archived: [.draft],
        ]
        guard allowed[draft.status]?.contains(newStatus) == true else {
            throw ShopCatalogDraftStoreError.illegalTransition(from: draft.status, to: newStatus)
        }
        var updated = draft
        updated.status = newStatus
        // 重新提交即视为已回应驳回意见：清空驳回原因
        if newStatus == .submitted { updated.rejectReason = nil }
        try upsert(updated)
    }

    // MARK: 运营中心看板（计划 §26：今日更新 / 草稿 / 待审核 / 待补充）

    /// 今日更新：今天创建或推进过的草稿数
    var todayUpdatedCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return drafts.filter { $0.createdAt >= start }.count
    }

    var draftCount: Int { drafts.filter { $0.status == .draft }.count }

    /// 待审核：已提交、等待审核的草稿
    var pendingReviewCount: Int { drafts.filter { $0.status == .submitted }.count }

    /// 待补充：关键字段不全（缺名称 / 价格为 0 / 缺店家或系列）的草稿
    var needsSupplementCount: Int {
        drafts.filter { draft in
            draft.name.trimmingCharacters(in: .whitespaces).isEmpty
                || (draft.effectiveReservationPrice == nil && draft.effectiveStockPrice == nil)
                || (draft.shopID == nil && draft.newShopName.trimmingCharacters(in: .whitespaces).isEmpty)
                || (draft.seriesID == nil && draft.newSeriesName.trimmingCharacters(in: .whitespaces).isEmpty)
        }.count
    }

    // MARK: 发布幂等基元（R09）

    /// 确定性销售事件 ID：**同一份草稿内容 + 同一价格类型**永远得到同一个 ID。
    ///
    /// 这是重复发布的最后一道防线——即便调用方拿着一份状态仍是 `.reviewed` 的旧快照
    /// （内存里没有 publishedResult）再点一次，算出来的事件 ID 也和上次完全相同，
    /// 覆盖层里已有该 ID 时直接跳过追加，不会写出第二组事件。
    nonisolated static func publishEventID(
        draftID: String, type: CatalogSaleEventType, eventKey: String
    ) -> String {
        let seed = "\(draftID)|\(type.rawValue)|\(eventKey)"
        return "ev-ops-\(draftID.prefix(8))-\(type.rawValue)-\(stableHash(seed))"
    }

    /// 草稿本次发布要写的全部事件 ID（按类型逐个确定性生成）。
    /// 覆盖层里已存在同 ID 的事件会被跳过，因此「只改了其中一价」不会重发另一条。
    nonisolated static func publishEventIDs(
        for draft: CatalogProductDraft
    ) -> [CatalogSaleEventType: String] {
        var result: [CatalogSaleEventType: String] = [:]
        if draft.effectiveReservationPrice != nil {
            result[.reservation] = publishEventID(draftID: draft.id, type: .reservation,
                                                  eventKey: draft.saleEventKey(.reservation))
        }
        if draft.effectiveStockPrice != nil {
            result[.stock] = publishEventID(draftID: draft.id, type: .stock,
                                            eventKey: draft.saleEventKey(.stock))
        }
        return result
    }

    /// 64 位 FNV-1a（无依赖、跨进程稳定），输出 16 位十六进制。
    /// 只用于生成可反查的稳定 ID 后缀，不承担任何安全用途。
    nonisolated static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    /// 半成功恢复：覆盖层已写入、草稿状态/结果未写回时，凭确定性事件 ID 反查。
    ///
    /// - Returns: 命中返回恢复说明；未命中返回 nil（说明覆盖层里确实没有本次产物，
    ///   调用方按首次发布处理）。
    @discardableResult
    func recoverPendingPublish(
        _ draft: CatalogProductDraft, store: ShopCatalogStore
    ) throws -> String? {
        guard var overlay = Self.loadOverlay() else { return nil }
        let key = draft.publishOperationKey
        let candidateIDs = Set(Self.publishEventIDs(for: draft).values)
        guard !candidateIDs.isEmpty else { return nil }
        let hit = overlay.saleEvents.filter { candidateIDs.contains($0.id) }
        // ⚠️ 必须**全部命中**才算「这次发布已经发生过」。
        // 只命中一部分说明内容变了（例如只改了预约价）：现货事件 ID 不变所以还在，
        // 但新的预约事件还没写。此时若按恢复处理，本次真实变更就会被吞掉。
        guard hit.count == candidateIDs.count else { return nil }

        // 款式档案补齐：本方法等价于「产物已落、收尾没做完」，因此除了草稿回执，
        // 还要把草稿携带的款式面料/描述写进款式档案 —— 否则「只改了面料再发布」
        // 会停在入口①/② 而永远落不了库（事件 ID 不含面料，必然全部命中）。
        var styleProfileWritten = false
        if ShopCatalogDraftStyleSync.hasStyleContent(draft),
           let target = Self.mergedProduct(id: hit[0].productID, overlay: overlay) {
            var working = overlay
            Self.applyStyleProfile(fabric: draft.fabric,
                                   styleDescription: draft.styleDescription,
                                   for: target, overlay: &working)
            if working.styleProfiles != overlay.styleProfiles {
                overlay = working
                styleProfileWritten = true
            }
        }

        // 覆盖层里已有产物 → 只补齐草稿状态与结果记录，**不再写任何事件**
        var updated = draft
        updated.status = .published
        updated.publishedResult = CatalogDraftPublishResult(
            productID: hit[0].productID,
            saleEventIDs: hit.map(\.id),
            publishedAt: Date(),
            operationKey: key)
        if styleProfileWritten {
            try Self.saveOverlay(overlay)
        }
        try upsert(updated)
        store.reloadWithOverlay()
        return "已恢复发布结果（覆盖层已写入、草稿状态未落盘）：商品 \(hit[0].productID)，未重复生成销售记录"
    }

    /// 发布：白名单校验（§26 服务层入口）→ 状态校验（§31：仅 reviewed 可发布）→
    /// 校验 → 幂等 / 恢复判定 → 去重合并（复用既有店家/系列；同名商品追加记录）
    /// → 写覆盖层 → 写草稿状态。
    ///
    /// ⚠️ 顺序刻意是「先覆盖层、后草稿状态」：覆盖层是发布产物，草稿状态只是回执。
    /// 万一状态写失败，产物仍在，`recoverPendingPublish` 或再次调用本方法可以补齐，
    /// 且不会重新生成一组事件。
    func publish(_ draft: CatalogProductDraft, store: ShopCatalogStore) throws -> String {
        try CreatorAccess.requireCreator(.listingPublish)
        guard draft.status == .reviewed else {
            throw ShopCatalogDraftStoreError.notReadyForPublish(draft.status)
        }
        let catalog = store.catalog
        try ShopCatalogDraftValidator.validate(draft, catalog: catalog)

        // ── 幂等入口 ①：草稿已记录过同一份内容的发布结果 ────────────────────
        let operationKey = draft.publishOperationKey
        if let recorded = draft.publishedResult, recorded.operationKey == operationKey {
            store.reloadWithOverlay()
            if draft.status != .published {
                var settled = draft
                settled.status = .published
                try upsert(settled)
            }
            return "「\(draft.name)」此前已发布（同一内容重复提交，未重复生成销售记录）"
        }
        // ── 幂等入口 ②：覆盖层已有本次产物但草稿没记录（半成功 / 旧快照重放） ──
        if let recovered = try recoverPendingPublish(draft, store: store) {
            return recovered
        }

        var overlay = Self.loadOverlay() ?? ShopCatalog()

        // 店家：复用或新建（再按别名兜底去重一次）
        let shop: CatalogShop
        if let shopID = draft.shopID, let existing = catalog?.shops.first(where: { $0.id == shopID }) ?? overlay.shops.first(where: { $0.id == shopID }) {
            shop = existing
        } else if let hit = ShopCatalogDraftValidator.findExistingShop(for: draft, catalog: catalog ?? overlay) {
            shop = hit
        } else {
            let aliases = draft.newShopAliases
                .components(separatedBy: CharacterSet(charactersIn: "，,、"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            shop = CatalogShop(id: "shop-ops-\(UUID().uuidString.prefix(8))",
                               name: draft.newShopName.trimmingCharacters(in: .whitespaces),
                               aliases: aliases)
            overlay.shops.append(shop)
        }

        // 系列：复用或新建
        let series: CatalogSeries
        if let seriesID = draft.seriesID,
           let existing = catalog?.series.first(where: { $0.id == seriesID }) ?? overlay.series.first(where: { $0.id == seriesID }) {
            series = existing
        } else if let hit = ShopCatalogDraftValidator.findExistingSeries(for: draft, shopID: shop.id, catalog: catalog ?? overlay) {
            series = hit
        } else {
            series = CatalogSeries(id: "series-ops-\(UUID().uuidString.prefix(8))",
                                   shopID: shop.id,
                                   name: draft.newSeriesName.trimmingCharacters(in: .whitespaces),
                                   year: draft.newSeriesYear,
                                   season: draft.newSeriesSeason.isEmpty ? nil : draft.newSeriesSeason)
            overlay.series.append(series)
        }

        // 商品：已存在 → 只追加本次销售记录；否则新建
        //
        // ⚠️ 重复不再是阻断条件（2026-09-22）：补录上新场景里，商品常常已经存在于
        // Catalog，甚至已被用户收进心愿 / 尾款 / 衣橱。此时补录的目的正是给既有
        // 商品补充价格，预约价与现货价都必须能继续录入并提交；一旦拦截，价格就
        // 永远补不上去。
        // 处理口径：商品本体（名称/分类/图片/规格/尺码表）保持不变仅在草稿
        // 携带新资料时补全；本次价格作为一条新的 SaleEvent 追加，永不以"重复"
        // 为由抛错。
        var productID: String
        var summary: String
        if let existing = ShopCatalogDraftValidator.findExistingProduct(for: draft, seriesID: series.id, catalog: catalog ?? overlay) {
            productID = existing.id
            // 追加现货时若草稿带了规格/尺码表/图片，一并补全到既有商品（V1.1 §4.2 编辑）
            if !draft.variants.isEmpty || draft.sizeChart != nil || !draft.images.isEmpty {
                var updated = existing
                if !draft.variants.isEmpty {
                    overlay.variants.append(contentsOf: draft.variants.map { v in
                        var v = v
                        v.productID = existing.id
                        if !overlay.variants.contains(where: { $0.id == v.id }) { return v }
                        var copy = v
                        copy.id = "var-ops-\(UUID().uuidString.prefix(8))"
                        return copy
                    })
                }
                // 尺码表统一挪到下方「款式名回填之后」写入（**款式共享**口径，2026-09-23）：
                // 范围判定要用最终的款式键，早写会按回填前的款式名分组。
                if !draft.images.isEmpty {
                    var assetIDs: [String] = []
                    for var asset in draft.images {
                        if overlay.assets.contains(where: { $0.id == asset.id }) {
                            asset.id = "asset-ops-\(UUID().uuidString.prefix(8))"
                        }
                        overlay.assets.append(asset)
                        assetIDs.append(asset.id)
                    }
                    if updated.images.isEmpty { updated.images = assetIDs }
                    else { updated.images.append(contentsOf: assetIDs) }
                }
                let index = overlay.products.firstIndex { $0.id == existing.id }
                if let index {
                    overlay.products[index] = updated
                } else {
                    // 既有商品在 Bundle 种子里：同 id 替换规则会以覆盖层版本胜出（§5.3）
                    overlay.products.append(updated)
                }
            }
            // V1.4「同款不同色」：既有商品缺款式名时按草稿回填（显式优先、名称派生兜底）。
            // 放在资料补全块之外：纯补价草稿也能让既有商品归入款式组。
            // 判定以**覆盖层**为准（写入目标）：调用方传入的 store 视图可能尚未刷新。
            let overlayProduct = overlay.products.first { $0.id == existing.id } ?? existing
            if overlayProduct.designName == nil {
                let backfilled = ShopCatalogSameDesignGrouper.resolveDesignName(
                    explicit: draft.designName, name: overlayProduct.name)
                if let backfilled {
                    var updated = overlayProduct
                    updated.designName = backfilled
                    if let index = overlay.products.firstIndex(where: { $0.id == existing.id }) {
                        overlay.products[index] = updated
                    } else {
                        overlay.products.append(updated)
                    }
                }
            }
            // 尺码表（**款式共享**，2026-09-23）：从任一颜色补录尺码表，都归一化到整款。
            // 放在款式名回填之后 —— 范围判定必须用最终的款式键。
            if let chart = draft.sizeChart {
                let target = overlay.products.first { $0.id == existing.id } ?? overlayProduct
                Self.applySizeChart(chart, for: target, overlay: &overlay)
            }
            // 本次提交的价格由下方统一的 SaleEvent 追加逻辑落库
            var appendedKinds: [String] = []
            if draft.effectiveReservationPrice != nil { appendedKinds.append("预约价") }
            if draft.effectiveStockPrice != nil { appendedKinds.append("现货价") }
            summary = "已向既有商品「\(existing.name)」追加\(appendedKinds.joined(separator: " + "))记录"
        } else {
            productID = "prod-ops-\(UUID().uuidString.prefix(8))"
            let assetIDs = draft.images.map { asset -> String in
                var a = asset
                if overlay.assets.contains(where: { $0.id == a.id }) {
                    a.id = "asset-ops-\(UUID().uuidString.prefix(8))"
                }
                overlay.assets.append(a)
                return a.id
            }
            // V1.4「同款不同色」：显式款式名优先，未填按名称剥离颜色词派生，
            // 发布后列表按款式归组展示（同款不同色合并为一条）
            overlay.products.append(CatalogProduct(id: productID, shopID: shop.id, seriesID: series.id,
                                                   name: draft.name.trimmingCharacters(in: .whitespaces),
                                                   category: draft.category,
                                                   images: assetIDs,
                                                   designName: ShopCatalogSameDesignGrouper.resolveDesignName(
                                                       explicit: draft.designName,
                                                       name: draft.name.trimmingCharacters(in: .whitespaces))))
            // 规格 / 尺码表随商品一并落库（G5：手动录入可完成全部业务）
            overlay.variants.append(contentsOf: draft.variants.map { v in
                var v = v
                v.productID = productID
                return v
            })
            // 尺码表（**款式共享**，2026-09-23）：新颜色填了尺码表 → 整款统一（含已有颜色）；
            // 没填则不动既有表 —— 读取侧会自动把同款的表给新颜色，无需重复填写。
            if let chart = draft.sizeChart,
               let created = overlay.products.first(where: { $0.id == productID }) {
                Self.applySizeChart(chart, for: created, overlay: &overlay)
            }
            summary = "已发布商品「\(draft.name)」"
        }

        // 销售记录（追加式，历史记录永不覆盖）：预约价与现货价**并存且不互斥**
        //（2026-09-22）—— 都填时各生成一条 SaleEvent；只填其一也放行（现货价可空置后补录）。
        //
        // ⚠️ 事件 ID 由草稿 ID + 内容指纹**确定性**生成（R09）：同一份内容再次发布
        // 得到相同 ID，下面的「已存在则跳过」保证不会写出第二组事件。
        var appendedEventIDs: [String] = []

        func appendEvent(_ event: CatalogSaleEvent) {
            guard !overlay.saleEvents.contains(where: { $0.id == event.id }) else { return }
            overlay.saleEvents.append(event)
            appendedEventIDs.append(event.id)
        }

        // 币种随金额一起落库：草稿未标注 → 明确写「待确认」，不冒充 CNY（R02）
        let eventCurrency: CatalogCurrency = draft.currency ?? .unknown

        if let reservationPrice = draft.effectiveReservationPrice {
            let eventDeposit = draft.deposit.map { Decimal($0) }
            var event = CatalogSaleEvent(
                id: Self.publishEventID(draftID: draft.id, type: .reservation,
                                        eventKey: draft.saleEventKey(.reservation)),
                productID: productID,
                type: .reservation,
                price: Decimal(reservationPrice),
                deposit: eventDeposit,
                balance: draft.balance.map { Decimal($0) },
                startAt: draft.startAt,
                endAt: draft.endAt,
                currency: eventCurrency
            )
            // 只填定金时尾款自动补齐（沿用既有口径：预约价不被覆盖）
            if event.balance == nil {
                event.balance = event.price - (eventDeposit ?? 0)
            }
            appendEvent(event)
        }
        if let stockPrice = draft.effectiveStockPrice {
            appendEvent(CatalogSaleEvent(
                id: Self.publishEventID(draftID: draft.id, type: .stock,
                                        eventKey: draft.saleEventKey(.stock)),
                productID: productID,
                type: .stock,
                price: Decimal(stockPrice),
                deposit: nil,
                balance: nil,
                startAt: draft.startAt,
                endAt: draft.endAt,
                currency: eventCurrency
            ))
        }

        // 款式（SPU）公共资料：面料 / 款式描述 → 款式档案（整款一份，2026-09-23）。
        //
        // ⚠️ 只在草稿**携带**款式资料时才写。`writePlan` 的语义是「空 = 清除」，
        // 若纯补价草稿（两项都空）也走一遍，会把同款既有的面料 / 描述整块抹掉 ——
        // 补价格把面料弄丢，是这个接口最容易出的静默事故。
        // 发布之后要改款式资料，走「款式公共资料」入口（`updateStylePublicInfo`）。
        if ShopCatalogDraftStyleSync.hasStyleContent(draft),
           let target = overlay.products.first(where: { $0.id == productID }) {
            Self.applyStyleProfile(fabric: draft.fabric,
                                   styleDescription: draft.styleDescription,
                                   for: target, overlay: &overlay)
        }

        // ── ① 先落盘发布产物（覆盖层） ──────────────────────────────────────
        try Self.saveOverlay(overlay)
        store.reloadWithOverlay()

        // ── ② 再写回草稿状态与发布结果 ──────────────────────────────────────
        // 这一步失败时产物已经在覆盖层里：不做回滚（产物是事实），
        // 抛错让 UI 提示「已发布，状态回执未保存」，随后可用 publish 或
        // recoverPendingPublish 补齐，且不会重复生成事件。
        var published = draft
        published.status = .published
        published.publishedResult = CatalogDraftPublishResult(
            productID: productID,
            saleEventIDs: appendedEventIDs,
            publishedAt: Date(),
            operationKey: operationKey)
        do {
            try upsert(published)
        } catch {
            throw ShopCatalogDraftStoreError.publishResultUnrecorded(
                summary: summary + "（\(shop.name) · \(series.name)）",
                detail: error.localizedDescription)
        }
        return summary + "（\(shop.name) · \(series.name)）"
    }

    // MARK: 实体编辑 / 归档 / 删除（V1.1 §4.2 + 重构方案 §5.5 引用保护）

    /// 把修改后的实体写入覆盖层（同 id 整体替换，合并规则见 ShopCatalogStore §5.3）。
    /// id 永不改变；所有关联的系列、商品自动跟随展示信息。
    static func upsertEntity<T: Identifiable>(
        _ entity: T, keyPath: WritableKeyPath<ShopCatalog, [T]>
    ) throws {
        try CreatorAccess.requireCreator(.listingEdit)
        var overlay = loadOverlay() ?? ShopCatalog()
        let array = overlay[keyPath: keyPath]
        if let index = array.firstIndex(where: { $0.id == entity.id }) {
            overlay[keyPath: keyPath][index] = entity
        } else {
            overlay[keyPath: keyPath].append(entity)
        }
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    // MARK: 尺码表写入（唯一入口，2026-09-23 款式共享）
    //
    //  尺码表属于**款式**（同系列 + 同品类 + 同款式名），不属于颜色：
    //    · 任一颜色填了尺码表 → 整款所有颜色都拿到同一张（内容逐字相同）；
    //    · 传 nil → 整款清空（不是只清当前颜色）。
    //  三个写入点（新发布 / 补录补全 / 深度编辑）**全部**走 `applySizeChart`，
    //  禁止再自己写 `overlay.sizeCharts.removeAll { productID == … } + append`
    //  —— 那正是「只有红色有尺码表、粉色没有」的来源。

    /// 应用尺码表写入计划（删旧 + 扇出新行）。
    /// 判定范围用「Bundle 基底 + 本次待写覆盖层」的合并视图：既有颜色可能住在只读的
    /// 种子里，只查覆盖层会漏掉同款的颜色。
    private static func applySizeChart(_ chart: CatalogSizeChart?,
                                       for product: CatalogProduct,
                                       overlay: inout ShopCatalog) {
        let (products, charts) = writeTargetCatalog(overlay: overlay)
        let plan = ShopCatalogSizeChartSharing.writePlan(chart: chart, for: product,
                                                        among: products, charts: charts)
        let removals = Set(plan.removals)
        overlay.sizeCharts.removeAll { removals.contains($0.productID) }
        overlay.sizeCharts.append(contentsOf: plan.upserts)
    }

    // MARK: 款式（SPU）档案写入（内部唯一入口，2026-09-23）

    /// 写入款式档案（面料 / 款式描述）：**整款一份**，按款式键整体替换。
    ///
    /// 与尺码表同源：判定范围用「Bundle 基底 + 本次待写覆盖层」的合并视图 ——
    /// 同款的其他颜色可能还住在只读的种子里，只查覆盖层会漏掉它们，
    /// 于是「整款一份」退化成「只写了当前颜色那一份」，读取侧又按款式键取最后一条，
    /// 结果就是改 A 色面料、B 色看不到。
    private static func applyStyleProfile(fabric: String?,
                                         styleDescription: String?,
                                         for product: CatalogProduct,
                                         overlay: inout ShopCatalog) {
        let (products, _) = writeTargetCatalog(overlay: overlay)
        let plan = ShopCatalogStyleProfileSharing.writePlan(
            fabric: fabric,
            styleDescription: styleDescription,
            for: product,
            among: products,
            profiles: writeTargetStyleProfiles(overlay: overlay))
        let removals = Set(plan.removals)
        overlay.styleProfiles.removeAll { removals.contains($0.id) }
        overlay.styleProfiles.append(contentsOf: plan.upserts)
    }

    /// 款式档案的合并视图（Bundle 基底 + 本次覆盖层，同 id 后写胜出）
    private static func writeTargetStyleProfiles(overlay: ShopCatalog) -> [CatalogStyleProfile] {
        var profiles = ShopCatalogStore.shared.catalog?.styleProfiles ?? []
        for profile in overlay.styleProfiles {
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }
        }
        return profiles
    }

    /// 从「覆盖层 + store 已刷新视图」里取商品：
    /// 发布路径里刚写进 overlay 的商品，此时可能还没出现在 store 的视图里。
    private static func mergedProduct(id: String, overlay: ShopCatalog) -> CatalogProduct? {
        if let hit = overlay.products.first(where: { $0.id == id }) { return hit }
        return ShopCatalogStore.shared.catalog?.products.first(where: { $0.id == id })
    }

    /// 写入目标的合并视图：Bundle 基底 + 本次覆盖层（同 id 后写胜出）。
    /// 与 `ShopCatalogStore.rebuildMergedCatalog` 同一口径，只是覆盖层用的是
    /// **本次待写的那一份**（还没落盘，读 store 拿不到）。
    private static func writeTargetCatalog(overlay: ShopCatalog)
        -> (products: [CatalogProduct], charts: [CatalogSizeChart]) {
        let base = ShopCatalogStore.shared.catalog ?? ShopCatalog()
        var products = base.products
        for product in overlay.products {
            if let index = products.firstIndex(where: { $0.id == product.id }) {
                products[index] = product
            } else {
                products.append(product)
            }
        }
        var charts = base.sizeCharts
        for chart in overlay.sizeCharts {
            if let index = charts.firstIndex(where: { $0.id == chart.id }) {
                charts[index] = chart
            } else {
                charts.append(chart)
            }
        }
        return (products, charts)
    }

    // MARK: - 款式（SPU）公共属性写入（唯一入口，2026-09-23 录入端重构）

    /// 写入一个款式的公共属性：**尺码表 + 面料 + 款式描述**，一次落盘。
    ///
    /// 为什么必须合成一个入口：这三项是同一份「款式公共资料」，任何一个界面提交时
    /// 拿到的是整块快照。拆成三个接口就意味着三次落盘，中途失败会留下
    /// 「尺码表换了、面料没换」的半套状态，而且三次之间各自读到的 overlay 版本不同，
    /// 后一次会把前一次的写入整个覆盖掉（覆盖层是整包写的）。
    ///
    /// 语义（与价格修正的「整快照提交」一致）：
    ///   · `sizeChart == nil` → **清除该款式尺码表**（整款，不是只清当前颜色）；
    ///   · `fabric` / `styleDescription` 为空 → 清除该项，不是「跳过不修改」。
    ///
    /// 传入任意一个颜色都能命中整款 —— 款式键由 `styleKey` 归一化。
    @discardableResult
    static func updateStylePublicInfo(fabric: String?,
                                      styleDescription: String?,
                                      sizeChart: CatalogSizeChart?,
                                      forProductID productID: String) throws -> String {
        try CreatorAccess.requireCreator(.listingEdit)
        var overlay = loadOverlay() ?? ShopCatalog()
        let (products, charts) = writeTargetCatalog(overlay: overlay)
        guard let product = products.first(where: { $0.id == productID }) else {
            throw ShopCatalogDraftStoreError.productNotFound(productID)
        }

        // ① 尺码表（款式共享：先删整款旧行，再为每个在售颜色各写一行）
        let chartPlan = ShopCatalogSizeChartSharing.writePlan(chart: sizeChart, for: product,
                                                              among: products, charts: charts)
        let chartRemovals = Set(chartPlan.removals)
        overlay.sizeCharts.removeAll { chartRemovals.contains($0.productID) }
        overlay.sizeCharts.append(contentsOf: chartPlan.upserts)

        // ② 款式档案（面料 / 款式描述：整款一份，按键整体替换）
        let profilePlan = ShopCatalogStyleProfileSharing.writePlan(
            fabric: fabric, styleDescription: styleDescription, for: product,
            among: products, profiles: overlay.styleProfiles)
        let profileRemovals = Set(profilePlan.removals)
        overlay.styleProfiles.removeAll { profileRemovals.contains($0.id) }
        overlay.styleProfiles.append(contentsOf: profilePlan.upserts)

        try Self.saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()

        let designName = ShopCatalogSameDesignGrouper.designName(of: product)
        var parts: [String] = []
        if sizeChart != nil { parts.append("尺码表") }
        if profilePlan.upserts.contains(where: { $0.fabric != nil }) { parts.append("面料") }
        if profilePlan.upserts.contains(where: { $0.styleDescription != nil }) { parts.append("款式描述") }
        return parts.isEmpty
            ? "已清空款式「\(designName)」的公共资料"
            : "已保存款式「\(designName)」的\(parts.joined(separator: " / "))，全部颜色已同步"
    }

    /// 已发布商品深度编辑（V1.1 §4.2 Product 修改：名称/分类/图片/配色尺码/尺码表）。
    /// id 永不改变，用户侧引用不受影响；一次落盘 product + assets + variants + sizeChart。
    /// 图片行 originalURL 未变的复用原 asset id（避免规格图文绑定与用户缓存断链）。
    static func updatePublishedProduct(
        _ product: CatalogProduct,
        assets: [CatalogAsset],
        variants: [CatalogProductVariant],
        sizeChart: CatalogSizeChart?
    ) throws {
        try CreatorAccess.requireCreator(.listingEdit)
        var overlay = loadOverlay() ?? ShopCatalog()

        // 旧商品图（来自覆盖层或 Bundle 种子）：清理覆盖层内旧图 asset，
        // Bundle 种子 asset 只读不可删，但新图用全新 id 写入覆盖层后同 id 合并规则以新图为准
        let oldImages = overlay.products.first { $0.id == product.id }?.images
            ?? ShopCatalogStore.shared.catalog?.products.first { $0.id == product.id }?.images
            ?? []
        if !oldImages.isEmpty {
            overlay.assets.removeAll { oldImages.contains($0.id) }
        }

        // 新 assets 写入（id 冲突时换新 id）
        var assetIDs: [String] = []
        for var asset in assets {
            if overlay.assets.contains(where: { $0.id == asset.id }) {
                asset.id = "asset-edit-\(UUID().uuidString.prefix(8))"
            }
            overlay.assets.append(asset)
            assetIDs.append(asset.id)
        }

        var updated = product
        updated.images = assetIDs
        // 防线：价格修正属于独立流程，资料保存若拿到修正前的旧快照，
        // 不得把修正值清掉（修正只能由 correctCurrentPrice / clearPriceCorrection 改动）
        if updated.priceCorrection == nil,
           let stored = overlay.products.first(where: { $0.id == product.id })?.priceCorrection {
            updated.priceCorrection = stored
        }

        // 规格 / 尺码表整组重建（productID 归位）
        overlay.variants.removeAll { $0.productID == product.id }
        overlay.variants.append(contentsOf: variants.map { v in
            var v = v
            v.productID = product.id
            return v
        })
        // 尺码表（**款式共享**，2026-09-23）：在任一颜色编辑 = 整款生效；
        // 表单留空 = 整款清空（深度编辑页提示文案同款口径）。
        // 用 `updated` 而不是入参 `product`：名称/分类刚被改过，款式分组可能因此变化。
        applySizeChart(sizeChart, for: updated, overlay: &overlay)
        if let index = overlay.products.firstIndex(where: { $0.id == product.id }) {
            overlay.products[index] = updated
        } else {
            // 既有商品在 Bundle 种子里：同 id 替换规则会以覆盖层版本胜出（§5.3）
            overlay.products.append(updated)
        }
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    // MARK: 价格双流程（2026-09-22：价格修正 / 追加销售记录彻底分离）
    //
    // 两条流程的边界（硬约束，任何改动都不得打破）：
    //
    //   ┌──────────────┬──────────────────────────┬──────────────────────────┐
    //   │              │ 价格修正                  │ 追加销售记录              │
    //   │              │ correctCurrentPrice       │ appendSaleRecord          │
    //   ├──────────────┼──────────────────────────┼──────────────────────────┤
    //   │ 语义         │ 更正当前商品属性           │ 新增业务事件（再贩/补货） │
    //   │ 存储         │ product.priceCorrection   │ saleEvents（数组追加）    │
    //   │ 写入方式     │ 覆盖，只留最新状态         │ append-only，永不改写     │
    //   │ 历史记录     │ 不产生                    │ 每条一条，按时间排序      │
    //   │ 时间维度     │ correctedAt（审计）        │ startAt 必填（批次时间）  │
    //   │ 重复提交     │ 幂等（同值覆盖无副作用）   │ 指纹相同 → 抛错拦截      │
    //   └──────────────┴──────────────────────────┴──────────────────────────┘
    //
    // 两者**不共用任何校验或写入代码**：修正只碰 product，追加只碰 saleEvents。

    /// 价格修正：**覆盖**商品的当前价格状态（现货价 / 预约价 / 定金 / 尾款）。
    /// 只保留最新状态，不产生任何历史记录 —— `saleEvents` 全程只读不写。
    ///
    /// 口径（2026-09-22 调整）：传 nil = **清除该价格**（当前生效值变为「暂无」），
    /// 不是「跳过不修改」——修正弹窗预填当前生效值、按完整快照提交，
    /// 所以想保留的字段必须带着原值一起提交。全部留空 = 清除全部价格，合法。
    @discardableResult
    static func correctCurrentPrice(
        productID: String,
        reservationPrice: Decimal?,
        stockPrice: Decimal?,
        deposit: Decimal?,
        balance: Decimal?,
        currency: CatalogCurrency? = nil
    ) throws -> CatalogPriceCorrection {
        try CreatorAccess.requireCreator(.listingEdit)

        let archive = ShopCatalogStore.shared.priceArchive(forProduct: productID)
        let existingCurrency = archive.currentCurrency
        // 币种校验（R02）：修正的是**金额**，不是币种。
        // 商品已有明确币种时，不允许用另一个币种去「修正」它。
        if let currency, let existingCurrency,
           !existingCurrency.isUnknown, !currency.isUnknown, currency != existingCurrency {
            throw ShopCatalogPriceEditError.crossCurrency(
                "商品既有币种为\(existingCurrency.displayName)，本次修正传的是\(currency.displayName)")
        }

        // 校验规则（只服务于「修正」语义：合法性 + 对账，不涉及批次时间）
        if let r = reservationPrice { guard r > 0 else { throw ShopCatalogPriceEditError.invalidPrice } }
        if let s = stockPrice { guard s > 0 else { throw ShopCatalogPriceEditError.invalidPrice } }
        if let d = deposit { guard d >= 0 else { throw ShopCatalogPriceEditError.invalidPrice } }
        if let b = balance { guard b >= 0 else { throw ShopCatalogPriceEditError.invalidPrice } }
        if let d = deposit, let b = balance, let base = reservationPrice, d + b != base {
            throw ShopCatalogPriceEditError.depositBalanceMismatch(
                "定金 \(NSDecimalNumber(decimal: d).stringValue) + 尾款 \(NSDecimalNumber(decimal: b).stringValue) ≠ 预约价 \(NSDecimalNumber(decimal: base).stringValue)")
        }
        // 预约价被清除时，定金 / 尾款失去对账基准，必须一并清空
        if reservationPrice == nil, deposit != nil || balance != nil {
            throw ShopCatalogPriceEditError.depositBalanceMismatch(
                "预约价已留空（清除），定金与尾款也需一并留空；或填回预约价后再修正定金尾款")
        }

        let correction = CatalogPriceCorrection(reservationPrice: reservationPrice,
                                                stockPrice: stockPrice,
                                                deposit: deposit,
                                                balance: balance,
                                                correctedAt: Date(),
                                                currency: currency ?? existingCurrency)

        var overlay = loadOverlay() ?? ShopCatalog()
        var product = overlay.products.first { $0.id == productID }
            ?? ShopCatalogStore.shared.catalog?.products.first { $0.id == productID }
        guard let product else { throw ShopCatalogPriceEditError.productNotFound(productID) }

        var updated = product
        updated.priceCorrection = correction
        if let index = overlay.products.firstIndex(where: { $0.id == productID }) {
            overlay.products[index] = updated
        } else {
            // 既有商品在 Bundle 种子里：同 id 替换规则以覆盖层版本胜出（§5.3）
            overlay.products.append(updated)
        }
        // ⚠️ 这里**绝不触碰 overlay.saleEvents**：修正不产生历史记录
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
        return correction
    }

    /// 撤销价格修正：回到「由 append-only 历史推导」的口径。
    /// 只清 `priceCorrection`，销售历史一条不动。
    static func clearPriceCorrection(productID: String) throws {
        try CreatorAccess.requireCreator(.listingEdit)
        var overlay = loadOverlay() ?? ShopCatalog()
        guard var product = overlay.products.first(where: { $0.id == productID })
            ?? ShopCatalogStore.shared.catalog?.products.first(where: { $0.id == productID })
        else { throw ShopCatalogPriceEditError.productNotFound(productID) }
        product.priceCorrection = nil
        if let index = overlay.products.firstIndex(where: { $0.id == productID }) {
            overlay.products[index] = product
        } else {
            overlay.products.append(product)
        }
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    /// 追加销售记录（往年款再贩 / 复刻 / 补货）：**append-only** 写入。
    ///
    /// 不可变性保证：本函数对 `overlay.saleEvents` 只做 `append`，
    /// 不做任何 remove / replace —— 已有记录永不被修改或覆盖。
    ///
    /// - startAt 必填：再贩日期 / 批次时间，是每条记录的时间维度；
    /// - 重复提交防护：业务指纹（商品 / 类型 / 价格 / 定金尾款 / 批次日）
    ///   命中既有记录时抛 `duplicateRecord`，不会写出第二条。
    @discardableResult
    static func appendSaleRecord(
        productID: String,
        type: CatalogSaleEventType,
        price: Decimal,
        deposit: Decimal? = nil,
        balance: Decimal? = nil,
        startAt: Date,
        endAt: Date? = nil,
        batchLabel: String? = nil,
        currency: CatalogCurrency? = nil
    ) throws -> CatalogSaleEvent {
        try CreatorAccess.requireCreator(.listingEdit)

        // 币种解析：未显式传入 → 沿用商品既有币种；都没有才落「待确认」（R02）
        let archive = ShopCatalogStore.shared.priceArchive(forProduct: productID)
        let existingCurrency = archive.currentCurrency
        if let currency, let existingCurrency,
           !existingCurrency.isUnknown, !currency.isUnknown, currency != existingCurrency {
            throw ShopCatalogPriceEditError.crossCurrency(
                "商品既有币种为\(existingCurrency.displayName)，本次记录传的是\(currency.displayName)")
        }
        let eventCurrency = currency ?? existingCurrency ?? .unknown

        // 校验规则（只服务于「追加」语义：价格合法 + 时间维度必填 + 对账 + 去重）
        guard price > 0 else { throw ShopCatalogPriceEditError.invalidPrice }
        if let d = deposit, let b = balance, d + b != price {
            throw ShopCatalogPriceEditError.depositBalanceMismatch(
                "定金 \(NSDecimalNumber(decimal: d).stringValue) + 尾款 \(NSDecimalNumber(decimal: b).stringValue) ≠ 价格 \(NSDecimalNumber(decimal: price).stringValue)")
        }

        var event = CatalogSaleEvent(
            id: "ev-append-\(UUID().uuidString.prefix(8))",
            productID: productID,
            type: type,
            price: price,
            deposit: deposit,
            balance: balance,
            startAt: startAt,
            endAt: endAt,
            batchLabel: trimmedBatchLabel(batchLabel),
            recordedAt: Date(),
            currency: eventCurrency
        )
        // 预约类记录只填定金时自动补齐尾款（先补齐再算指纹，保证去重口径一致）
        if type == .reservation, event.balance == nil {
            event.balance = event.price - (event.deposit ?? 0)
        }

        var overlay = loadOverlay() ?? ShopCatalog()
        // 重复提交防护：覆盖层 + 已合并进内存的种子记录都要比对
        var known = overlay.saleEvents
        for existing in ShopCatalogStore.shared.catalog?.saleEvents ?? []
        where !known.contains(where: { $0.id == existing.id }) {
            known.append(existing)
        }
        let fingerprint = event.appendFingerprint
        guard !known.contains(where: { $0.appendFingerprint == fingerprint }) else {
            throw ShopCatalogPriceEditError.duplicateRecord
        }

        overlay.saleEvents.append(event)   // 只追加：既有记录不可变
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
        return event
    }

    private static func trimmedBatchLabel(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// 归档：写 archivedAt（同 id 替换）。用户端隐藏，用户已收藏记录保留（§4.2）。
    static func archiveShop(_ shop: CatalogShop) throws {
        try CreatorAccess.requireCreator(.listingStatus)
        var updated = shop
        updated.archivedAt = Date()
        try upsertEntity(updated, keyPath: \.shops)
    }

    static func archiveSeries(_ series: CatalogSeries) throws {
        try CreatorAccess.requireCreator(.listingStatus)
        var updated = series
        updated.archivedAt = Date()
        try upsertEntity(updated, keyPath: \.series)
    }

    static func archiveProduct(_ product: CatalogProduct) throws {
        try CreatorAccess.requireCreator(.listingStatus)
        var updated = product
        updated.archivedAt = Date()
        try upsertEntity(updated, keyPath: \.products)
    }

    /// 物理删除：仅当实体来自运营覆盖层（Bundle 种子不可变）、无下级、且无用户引用时允许；
    /// 否则抛错，提示仅可归档（§4.2 引用保护）。
    static func deleteProduct(
        _ product: CatalogProduct, store: ShopCatalogStore, modelContext: ModelContext
    ) throws {
        try CreatorAccess.requireCreator(.listingDelete)
        let catalog = store.catalog
        // 引用保护：被用户心愿/尾款/衣橱引用（含软删除记录）→ 禁止物理删除
        let referenced = try ShopCatalogReferenceGuard.referencedProductIDs(
            [product.id], modelContext: modelContext)
        guard referenced.isEmpty else {
            throw ShopCatalogEntityError.referencedOnlyArchive(
                kind: "商品", name: product.name)
        }
        guard let overlay = loadOverlay(),
              overlay.products.contains(where: { $0.id == product.id }) else {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "商品", name: product.name)
        }
        var updated = overlay
        updated.products.removeAll { $0.id == product.id }
        // 无引用时连带清理其规格/尺码表（销售事件按硬约束保留历史）
        updated.variants.removeAll { $0.productID == product.id }
        updated.sizeCharts.removeAll { $0.productID == product.id }
        // 种子里也有同 id → 物理删除做不到（Bundle 只读），退化为归档
        if store.isSeedProduct(id: product.id) {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "商品", name: product.name)
        }
        try saveOverlay(updated)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    // MARK: 商品批量删除（2026-09-23 需求：批量删除商品 + 二次确认）

    /// 预检与执行**同源的**决策结果：两个入口都调它，所以「弹窗说会删 5 件」
    /// 与「实际删了 5 件」不可能不一致。
    private struct ProductDeletionPlan {
        var deletable: [CatalogProduct] = []
        var blocked: [CatalogProductDeleteBlock] = []
    }

    /// 逐个判定：被用户引用 → 拦截；种子（Bundle 只读）或不在覆盖层 → 拦截；其余可删。
    /// 引用判定对整批只查一次数据库（不是每件一次）。
    private static func planProductDeletion(
        _ products: [CatalogProduct],
        store: ShopCatalogStore,
        modelContext: ModelContext
    ) throws -> ProductDeletionPlan {
        // 调用方可能传重复项（如全选 + 手点同一件），同 id 只处理一次
        var seen = Set<String>()
        let unique = products.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { return ProductDeletionPlan() }

        // 引用保护：被用户心愿/尾款/衣橱引用（含软删除记录）→ 禁止物理删除
        let referenced = try ShopCatalogReferenceGuard.referencedProductIDs(
            Set(unique.map(\.id)), modelContext: modelContext)
        // 只有覆盖层里的商品才可能被物理删除——种子在 Bundle 里，改不动
        let overlayIDs = Set((loadOverlay()?.products ?? []).map(\.id))

        var plan = ProductDeletionPlan()
        for product in unique {
            if referenced.contains(product.id) {
                plan.blocked.append(CatalogProductDeleteBlock(
                    productID: product.id, name: product.name,
                    reason: .referencedByUserData))
            } else if !overlayIDs.contains(product.id) || store.isSeedProduct(id: product.id) {
                plan.blocked.append(CatalogProductDeleteBlock(
                    productID: product.id, name: product.name,
                    reason: .seedImmutable))
            } else {
                plan.deletable.append(product)
            }
        }
        return plan
    }

    /// 只读预检：算出这批商品里哪些会被删、哪些被拦及原因，**不写盘**。
    /// 供「二次确认」弹窗把真实影响范围说清楚（含「另有 N 件将被跳过」）。
    static func previewProductDeletion(
        _ products: [CatalogProduct],
        store: ShopCatalogStore,
        modelContext: ModelContext
    ) throws -> CatalogProductDeletePreview {
        try CreatorAccess.requireCreator(.listingDelete)
        let plan = try planProductDeletion(products, store: store, modelContext: modelContext)
        return CatalogProductDeletePreview(deletableNames: plan.deletable.map(\.name),
                                          blocked: plan.blocked)
    }

    /// 批量物理删除商品：守卫与单品删除完全相同（种子不可删 / 被引用只能归档），
    /// 差别只在**整批只写一次覆盖层**——逐条调用 `deleteProduct` 会产生 N 次中途落盘
    /// 与 N 次 reload，中途失败就留下「删了一半」的中间态。
    ///
    /// 部分成功是允许的，但绝不静默：`blocked` 原样返回，调用方必须展示。
    @discardableResult
    static func deleteProducts(
        _ products: [CatalogProduct],
        store: ShopCatalogStore,
        modelContext: ModelContext
    ) throws -> CatalogProductDeleteResult {
        try CreatorAccess.requireCreator(.listingDelete)
        let plan = try planProductDeletion(products, store: store, modelContext: modelContext)
        guard !plan.deletable.isEmpty, var overlay = loadOverlay() else {
            return CatalogProductDeleteResult(deletedIDs: [], blocked: plan.blocked)
        }

        let ids = Set(plan.deletable.map(\.id))
        overlay.products.removeAll { ids.contains($0.id) }
        // 与单品删除同口径：无引用时连带清理其规格 / 尺码表（销售事件按硬约束保留历史）
        overlay.variants.removeAll { ids.contains($0.productID) }
        overlay.sizeCharts.removeAll { ids.contains($0.productID) }
        try saveOverlay(overlay)
        ShopCatalogStore.shared.reloadWithOverlay()
        return CatalogProductDeleteResult(deletedIDs: ids, blocked: plan.blocked)
    }

    static func deleteSeries(
        _ series: CatalogSeries, store: ShopCatalogStore, modelContext: ModelContext
    ) throws {
        try CreatorAccess.requireCreator(.listingDelete)
        let catalog = store.catalog
        let childProducts = (catalog?.products ?? []).filter { $0.seriesID == series.id }
        guard childProducts.isEmpty else {
            throw ShopCatalogEntityError.hasChildrenOnlyArchive(
                kind: "系列", name: series.name, childCount: childProducts.count)
        }
        guard let overlay = loadOverlay(),
              overlay.series.contains(where: { $0.id == series.id }) else {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "系列", name: series.name)
        }
        var updated = overlay
        updated.series.removeAll { $0.id == series.id }
        if store.isSeedSeries(id: series.id) {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "系列", name: series.name)
        }
        try saveOverlay(updated)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    static func deleteShop(
        _ shop: CatalogShop, store: ShopCatalogStore, modelContext: ModelContext
    ) throws {
        try CreatorAccess.requireCreator(.listingDelete)
        let catalog = store.catalog
        let childSeries = (catalog?.series ?? []).filter { $0.shopID == shop.id }
        let childProducts = (catalog?.products ?? []).filter { $0.shopID == shop.id }
        guard childSeries.isEmpty && childProducts.isEmpty else {
            throw ShopCatalogEntityError.hasChildrenOnlyArchive(
                kind: "店家", name: shop.name, childCount: childSeries.count + childProducts.count)
        }
        guard let overlay = loadOverlay(),
              overlay.shops.contains(where: { $0.id == shop.id }) else {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "店家", name: shop.name)
        }
        var updated = overlay
        updated.shops.removeAll { $0.id == shop.id }
        if store.isSeedShop(id: shop.id) {
            throw ShopCatalogEntityError.seedImmutableOnlyArchive(kind: "店家", name: shop.name)
        }
        try saveOverlay(updated)
        ShopCatalogStore.shared.reloadWithOverlay()
    }

    // MARK: 覆盖层读写

    nonisolated static func loadOverlay() -> ShopCatalog? {
        guard let data = try? Data(contentsOf: overlayURL) else { return nil }
        return try? ShopCatalogJSONCoding.decoder().decode(ShopCatalog.self, from: data)
    }

    private nonisolated static func saveOverlay(_ overlay: ShopCatalog) throws {
        let data = try ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(overlay)
        try data.write(to: overlayURL, options: .atomic)
    }

    /// 导出整包（含 Bundle 种子 + 覆盖层），用于交接 / 备份
    func exportJSON(store: ShopCatalogStore) -> String? {
        guard let catalog = store.catalog else { return nil }
        guard let data = try? ShopCatalogJSONCoding.encoder(prettyPrinted: true).encode(catalog) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 引用保护（V1.1 §4.2 + 重构方案 §5.5）

/// 判定 Catalog 实体是否被用户私有状态引用（心愿 / 尾款 / 少女衣橱）。
/// 口径：`Clothing.catalog*` 引用字段命中即算被引用——**含软删除记录**
/// （deletedAt 不豁免），保证「被引用过 → 只能归档」保守成立。
enum ShopCatalogReferenceGuard {

    /// 返回入参中被引用的商品 id 集合
    static func referencedProductIDs(
        _ productIDs: Set<String>, modelContext: ModelContext
    ) throws -> Set<String> {
        guard !productIDs.isEmpty else { return [] }
        let descriptor = FetchDescriptor<Clothing>(
            predicate: #Predicate { clothing in
                clothing.catalogProductID != nil
            }
        )
        let clothings = try modelContext.fetch(descriptor)
        var hit = Set<String>()
        for clothing in clothings {
            if let pid = clothing.catalogProductID, productIDs.contains(pid) {
                hit.insert(pid)
            }
        }
        return hit
    }

    /// 系列被引用判定：系列下存在任意商品（含已归档）或商品被用户引用
    static func seriesHasReferencedContent(
        _ series: CatalogSeries, store: ShopCatalogStore, modelContext: ModelContext
    ) throws -> Bool {
        let products = (store.catalog?.products ?? []).filter { $0.seriesID == series.id }
        guard !products.isEmpty else { return false }
        let referenced = try referencedProductIDs(Set(products.map(\.id)), modelContext: modelContext)
        return !referenced.isEmpty || !products.isEmpty // 有商品即算有内容引用
    }
}

// MARK: - 实体操作错误（V1.1 §4.2）

nonisolated enum ShopCatalogEntityError: LocalizedError {
    /// 被用户心愿/尾款/衣橱引用 → 禁止物理删除，仅可归档
    case referencedOnlyArchive(kind: String, name: String)
    /// 存在下级实体（系列/商品）→ 禁止物理删除
    case hasChildrenOnlyArchive(kind: String, name: String, childCount: Int)
    /// 实体来自 Bundle 种子（只读）→ 无法物理删除，仅可归档
    case seedImmutableOnlyArchive(kind: String, name: String)

    var errorDescription: String? {
        switch self {
        case .referencedOnlyArchive(let kind, let name):
            return "「\(name)」已被用户心愿/尾款/衣橱引用，禁止删除，仅可归档。"
        case .hasChildrenOnlyArchive(let kind, let name, let count):
            return "「\(name)」名下仍有 \(count) 个下级条目，请先处理下级，或仅归档。"
        case .seedImmutableOnlyArchive(let kind, let name):
            return "「\(name)」来自随版本内置的种子档案，无法物理删除，仅可归档。"
        }
    }
}
