//
//  OpsChartRecognition.swift
//  PinkHouseOps
//
//  运营端（Mac）尺码表 / 价格表文本 → **识别结论**（2026-10-01 需求）。
//
//  ## 为什么还需要这一层
//
//  「这份录入能不能用」的判定与全部文案在共享包 `CatalogChartRecognition` 里，
//  两个平台共用同一份。但 Mac 的**文本语法与 iOS 不同**：
//    · Mac（导向上新 / 系列价格表）：`S = 80, 78-83`（等号）
//    · iOS（粘贴录入）：`S:80,78-83`（冒号）
//  所以 Mac 需要一层**薄适配**：按 Mac 自己的语法解析出 columns / rows，
//  再交给共享判定出结论。
//
//  ⚠️ 本文件**不许自己拼「识别成功 / 识别失败」**，也不许把门禁规则抄一份 ——
//  那正是本项目反复吃亏的「两端各写一份判定」。
//
//  ## 与落库同源
//
//  `parse` 就是各编辑页保存时用的那一份（价格表保存路径已收敛到这里，
//  尺码表走 `OpsSeriesSizeChartParsing`）。所以卡片说成功就是真能存、
//  说失败就是真存不成形状，不存在「预览一套、保存另一套」。
//

import Foundation

// MARK: - Mac 文本语法解析

enum OpsChartTextParsing {

    struct Parsed: Equatable {
        var columns: [String]
        var rows: [CatalogSizeRow]
    }

    /// 列名文本 → **数据列**。逗号（中英文）、竖线（中英文）都算分隔符；
    /// 首列若是「款式 / 尺码」这类**行标签列名**则剔除。
    ///
    /// 实现走共享包 `CatalogChartTextSyntax.dataColumns`（**唯一口径**）——
    /// 归一化、切分、剔除行标签列都不再各留一份。
    /// 剔除这一步是**防错**而非宽容：不剔除就会出现
    /// 「Mac 按含标签列的列数校验放行 → iOS 渲染时剔掉该列、行的值却没剔 → 整列错位」。
    static func columns(_ text: String) -> [String] {
        CatalogChartTextSyntax.dataColumns(from: text)
    }

    /// 列名文本 + 行文本（每行 `标签 = 值1, 值2, …`）→ 结构。
    ///
    /// 切分、归一化、个数校验全部走共享包 `CatalogChartTextSyntax`（**唯一口径**，
    /// 本机可用 `swift test` 秒级验证）；本类型只把它翻译成价格表这边的措辞。
    ///
    /// 结构错误（缺 `=`、标签为空、值个数与数据列不齐、整表为空）通过 `issue` 返回，
    /// **不静默兜底** —— 兜底会让「缺一列」变成「整列错位」存进线上，事后看不出来。
    static func parse(columnsText: String, rowsText: String) -> (parsed: Parsed?, issue: String?) {
        let rawColumns = CatalogChartTextSyntax.splitColumns(columnsText)
        let columns = CatalogChartTextSyntax.dataColumns(from: columnsText)
        let listedLabelColumn = rawColumns.first.flatMap {
            CatalogChartTextSyntax.isLabelColumn($0) ? $0 : nil
        }

        let rows: [CatalogSizeRow]
        switch CatalogChartTextSyntax.parseRowLines(rowsText, dataColumnCount: columns.count) {
        case .failure(let issue):
            return (nil, message(for: issue, listedLabelColumn: listedLabelColumn))
        case .success(let lines):
            rows = lines.map { CatalogSizeRow(label: $0.label, values: $0.values) }
        }

        guard !columns.isEmpty, !rows.isEmpty else {
            return (nil, "至少要有列名与一行数据。")
        }
        return (Parsed(columns: columns, rows: rows), nil)
    }

    /// 共享层的事实 → 价格表的措辞（**文案留在这里，规则不在这里**）。
    private static func message(for issue: CatalogChartTextSyntax.RowLineIssue,
                                listedLabelColumn: String?) -> String {
        switch issue {
        case .missingSeparator(let line):
            return "这一行没有「=」，格式应为 `标签 = 值1, 值2`：\(line)"
        case .emptyLabel(let line):
            return "有一行没有写标签：\(line)"
        case .valueCountMismatch(let label, let actual, let expected):
            var hint = "请把这一行补齐到 \(expected) 个值"
                + "（值之间用半角逗号「,」分隔）。"
            if let listedLabelColumn {
                hint += "列名里的「\(listedLabelColumn)」是**行标签列**、不占数据列的名额。"
            }
            return "「\(label)」有 \(actual) 个值，而数据列有 \(expected) 个 —— " + hint
        }
    }
}

// MARK: - 结论

/// Mac 侧唯一的「识别结论」出口：把解析结果交给共享判定。
enum OpsChartRecognition {

    /// 解析结果 → 结论。
    ///
    /// - Parameters:
    ///   - issue: 结构错误原文（来自解析层）。非 nil 一律落成**识别失败**，
    ///            且**不再往下跑门禁** —— 结构都没成形时谈填写率没有意义。
    ///   - columns / rows: 结构错误时为空的占位（未解析出内容）
    static func make(kind: CatalogChartKind,
                     columns: [String],
                     rows: [CatalogSizeRow],
                     issue: String?) -> CatalogChartRecognition {
        if let issue {
            return .rejected(kind: kind, source: .pastedText, reason: issue)
        }
        return .verdict(kind: kind, source: .pastedText, columns: columns, rows: rows)
    }

    /// 解析结果（`OpsChartTextParsing.parse` 的原样返回）→ 结论。
    static func make(kind: CatalogChartKind,
                     parsed: OpsChartTextParsing.Parsed?,
                     issue: String?) -> CatalogChartRecognition {
        make(kind: kind,
             columns: parsed?.columns ?? [],
             rows: parsed?.rows ?? [],
             issue: issue)
    }
}

// MARK: - 向导 S2：系列价格表（草稿侧的唯一口径）

extension OpsSeriesEntryDraft {

    /// 向导 S2 价格表文本 → 结构。
    ///
    /// ⭐ **唯一调用点**（识别卡片、S2 校验、提交写回都走它），
    /// 底层就是系列配置 sheet 保存时用的那一个 `OpsChartTextParsing.parse`。
    /// 于是「卡片说识别成功」与「提交真正写进去的结构」永远是同一份 ——
    /// 不可能出现「预览一套、保存另一套」。
    var parsedPriceChart: (parsed: OpsChartTextParsing.Parsed?, issue: String?) {
        OpsChartTextParsing.parse(columnsText: priceChartColumnsText,
                                  rowsText: priceChartRowsText)
    }

    /// 已关联的价格表原图张数（`sourceImage` 恒取首图，见 `updateSeriesPriceChart`）
    var priceChartImageCount: Int { priceChartImageAssetIDs.count }

    /// 是否有可提交的价格表内容（结构化列行 **或** 原图，两者之一即可）。
    /// 只有原图是**合法状态**：`CatalogPriceChart.hasStructuredContent == false`，
    /// 客户端详情页会退化成展示原图（这是模型契约，不是容错）。
    var hasPriceChartContent: Bool {
        if !isPriceChartTextEmpty, parsedPriceChart.parsed != nil { return true }
        return !priceChartImageAssetIDs.isEmpty
    }
}

/// S2 价格表的问题清单。
///
/// ## 为什么单独一个类型，而不是塞进 `OpsSeriesEntryValidator`
///
/// 校验规则本身用不着 Mac 的文本语法，但**「这份文本能不能成形」必须问同一个解析器**
/// （`OpsChartTextParsing`）。把 S2 价格表这几条放回 Models 会让 `OpsSeriesEntryDraft.swift`
/// 反向依赖 Services 里的文本口径 —— 所以规则留在 Services，Models 只调用一个纯函数。
enum OpsSeriesPriceChartValidation {

    /// 返回问题文案（空数组 = 可以照原样提交）。
    ///
    /// 开关**关着**时恒返回空：`declaresPriceChart == false` 表示「本次提交完全不碰价格表」，
    /// 此时连「填了一半」都不该拦 —— 那是别的入口留下的草稿内容。
    static func issues(for draft: OpsSeriesEntryDraft) -> [String] {
        guard draft.declaresPriceChart else { return [] }

        // 文本整块空 → 不做结构判定（空文本的「结构错误」没有意义），
        // 但**必须有原图**，否则这次提交等于开着开关却什么都没写。
        if draft.isPriceChartTextEmpty {
            guard draft.priceChartImageAssetIDs.isEmpty else { return [] }
            return ["系列价格表：已打开「在本向导里维护系列价格表」，"
                    + "但既没有列名/数据行，也没有上传原图 —— "
                    + "请上传一张价格表图片或填一份表格，也可以关掉这个开关。"]
        }

        // 有文本 → 结构错误一律按原话上报（缺「=」/ 标签为空 / 值个数与数据列不齐）
        let parsed = draft.parsedPriceChart
        if let issue = parsed.issue {
            return ["系列价格表：\(issue)"]
        }
        // 结构对但一张图都没有：可以提交（纯表格价格表是合法的），不拦。
        return []
    }
}
