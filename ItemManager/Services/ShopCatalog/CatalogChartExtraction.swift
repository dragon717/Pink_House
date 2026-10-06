//
//  CatalogChartExtraction.swift
//  ItemManager
//
//  预约价格表 / 尺码表 图片 → 结构化表格的**统一提取入口**（2026-09-23 需求 M）。
//
//  ## 用户报的问题（原文）
//    在「编辑系列 → 预约价格表」上传图片后，自动解析结果完全不可用：
//      1. 只识别出第一列（款式名），后面的定金 / 尾款 / 预约价 / 现货价全丢；
//      2. 结果没有结构，出现 `G PROMOTTOI`（英文字母乱码）、`定金:尼款`（错别字）；
//      3. 下方输入框被自动填入这些垃圾数据，用户还得全删重打。
//
//  ## 根因
//    · 只走 Vision OCR + 启发式行列重建，对**设计过的**图表（彩色底、艺术字、大列距）
//      本来就不可靠：数字小字容易整体漏识别，装饰性英文被当成表头；
//    · 「解析成功」的定义太弱 —— 只要凑出行列就算成功，于是垃圾也被回填进输入框；
//    · 没有本地兜底路径，用户只能在那两个残缺输入框里手敲。
//
//  ## 本文件的修复口径（三层）
//    1. **多模态优先**：先用具备表格理解能力的大模型（App 内既有 Qwen-VL 通道）
//       读图，直接要求它输出「列名行 + 标签:值,值」的规整文本，不再靠 OCR 拼列。
//    2. **端上 OCR 兜底**：多模态不可用（未配置 Key / 网络失败 / 结果不合格）时，
//       再退回 Vision OCR，走既有 `CatalogChartParser`。
//    3. **质量门禁**：无论哪条通道，结果都必须过 `CatalogChartQuality`——
//       列数不足、覆盖度过低（典型「只识别到第一列」）、乱码词元、
//       行列错位（行标签与列名重名）、混入说明文字、全表无数字，
//       任一命中即判定**解析失败**：不往输入框写任何内容，由 UI 弹窗引导用户
//       改用「粘贴文本录入」或手动填写。
//
//  纯逻辑（门禁 / 模型回复解析）全部 `nonisolated`，可离线单测，不依赖网络。
//
//  2026-10-01 需求：「尺码表和价格表的识别都要分别给出『识别成功 / 识别失败』提示」。
//  判定口径与文案已迁到共享包 `CatalogChartRecognition`（两端同一份），本文件只留
//  平台相关的编排：Qwen 读图 / Vision OCR / 结果归一。
//  ⚠️ **不要在本文件（或任何 iOS 文件）里重新拼「识别成功 / 识别失败」结论** ——
//  一律走 `CatalogChartRecognition`，否则两张表的文案很快会各写各的。
//

import Foundation
import UIKit

// MARK: - 质量门禁与判定口径

// `CatalogChartKind` / `CatalogChartQuality` / `Character.isCJK` 已迁至
// `SharedCatalog/Sources/SharedCatalog/Editing/CatalogChartRecognition.swift`
// （判定逻辑一字未改，只是换了住址好让 Mac 运营端共用）。iOS 侧经
// `ItemManager/SharedCatalogBridge.swift` 的 `@_exported import` 直接可见。

// MARK: - 多模态回复 → 表格（纯逻辑，可单测）

/// 大模型回复（自然语言包裹的表格文本）→ 结构化表格。
///
/// 与「用户直接粘贴文本」共用同一套解析口径（`CatalogManualChartText.parsePastedText`），
/// 避免两条链路各自实现导致漂移。
nonisolated enum CatalogChartModelReply {

    /// 提示词：要求模型按行列关系输出**可粘贴的规整文本**，不要 Markdown、不要解释。
    static func prompt(for kind: CatalogChartKind) -> String {
        let role: String
        switch kind {
        case .price:
            role = "一张中文服装「预约价格表」截图（通常每行一个款式，列是预约价 / 定金 / 尾款 / 现货价等）"
        case .size:
            role = "一张中文服装「尺码表」截图（通常每行一个尺码，列是胸围 / 前裙长 / 推荐胸围等）"
        }
        return """
        你是表格结构化助手。图片是\(role)。
        请严格按图片的**行、列关系**提取内容，输出纯文本表格。

        输出格式（严格遵守，不要任何多余内容）：
        第一行：列名，用英文逗号分隔；若最左边一列是行标签列（如「款式」「尺码」），把它写在第一个。
        其余每行：行标签:值,值,…
        值的个数必须与列名个数一致，图片里没有内容的格子留空（写成两个相邻逗号）。

        硬性要求：
        1. 不要输出解释、前言、标题、不要 Markdown 表格、不要代码块。
        2. 看不清或不确定的格子一律留空，绝对不要猜测、不要编造。
        3. 图片里的标题、店铺名、备注、广告语、水印等非表格文字一律忽略。
        4. 不要输出「列名：」「备注：」这类说明行。
        """
    }

    /// 模型回复 → 表格。清洗围栏 / 列表符号后交给共享的整段文本解析。
    static func table(from reply: String, kind: CatalogChartKind) throws -> CatalogChartParser.Table {
        let cleaned = clean(reply)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogChartParserError.tableUnparsable(reason: "模型没有返回任何内容")
        }
        let parsed = CatalogManualChartText.parsePastedText(cleaned)
        guard !parsed.columns.isEmpty else {
            throw CatalogChartParserError.tableUnparsable(reason: "模型回复里找不到列名行")
        }
        guard !parsed.rows.isEmpty else {
            throw CatalogChartParserError.tableUnparsable(reason: "模型回复里找不到数据行")
        }
        return CatalogChartParser.Table(columns: parsed.columns, rows: parsed.rows)
    }

    /// 去掉代码围栏、行首列表符号、`**粗体**`、以及「列名:」这种前缀，
    /// 并丢弃模型的前言 / 后记 / 备注句（有冒号但冒号后既无分隔符也无数字 = 不是数据行）。
    static func clean(_ reply: String) -> String {
        var lines: [String] = []
        for rawLine in CatalogManualChartText.normalizeSeparators(reply)
            .components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            // 行首符号：> • · * ，以及「- 」列表符号（避免吃掉负数，只在后面还有内容时剔）
            while let first = line.first, ">•·*".contains(first) {
                line.removeFirst()
                line = line.trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("- ") {
                line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
            line = stripHeaderPrefix(line)
            if !line.isEmpty, !isProseLine(line) { lines.append(line) }
        }
        return lines.joined(separator: "\n")
    }

    /// 非表格文字判定：含冒号，但冒号之后既没有分隔符（逗号 / 制表符 / 竖线）
    /// 也没有数字 → 是「好的，结果如下：」「备注：价格以店铺为准」这类叙述句，不是数据行。
    private static func isProseLine(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        let valuePart = line[line.index(after: colon)...]
        let hasSeparator = valuePart.contains { $0 == "," || $0 == "\t" || $0 == "|" }
        let hasDigit = valuePart.contains { $0.isNumber }
        return !hasSeparator && !hasDigit
    }

    /// 剔除模型习惯加的行前缀：「列名:」「表头:」「columns:」
    private static func stripHeaderPrefix(_ line: String) -> String {
        for prefix in ["列名:", "列名：", "表头:", "表头：", "columns:", "Columns:", "header:", "Header:"] {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return line
    }
}

// MARK: - 统一提取编排

/// 图片 → 结构化表格 → **识别结论**。多模态优先 → 端上 OCR 兜底 → 统一质量门禁。
///
/// ⚠️ **本模块在 App 内没有界面入口，而且是故意的**（2026-09-23 需求一：用户反馈
/// 上传图片自动识别「频繁报错 + 常驻霸屏」，要求整条移除；价格表只走「粘贴文本录入」
/// + 列名/行文本/单位手填）。文件与它的测试按「其他保留」留下，**别再借它把入口加回来**。
/// 下面这套门禁口径是该模块自身的契约，供离线单测与将来复用，不是待接的活。
///
/// 对外只剩 `accept(...)`（`nonisolated`）：给单测与真实链路共用，
/// 不过门禁就抛 `Failure.notUsable`，**绝不返回未过门禁的结果**。
///
/// 「识别失败不要往输入框填乱码」这条需求的执行点，就是这里**只**经过共享包的
/// `CatalogChartQuality` —— 界面侧的识别结论（成功/失败提示）走 `CatalogChartRecognition`。
enum CatalogChartExtraction {

    /// 结果来源：与结论文案同源（`CatalogChartRecognition.Source`），
    /// **不再单开一个枚举**——两处各写一份必然漂移。
    typealias Source = CatalogChartRecognition.Source

    struct Outcome: Sendable {
        let table: CatalogChartParser.Table
        let source: Source
    }

    enum Failure: LocalizedError {
        case imageUnavailable
        case noTextRecognized
        /// 两条通道都不可用 / 结果都没过门禁；reasons 为各通道的具体原因
        case notUsable(reasons: [String])

        var errorDescription: String? {
            switch self {
            case .imageUnavailable:
                return "无法读取图片内容，请重新上传（支持截图或清晰拍照）"
            case .noTextRecognized:
                return "图片中没有识别到文字"
            case .notUsable(let reasons):
                return reasons.isEmpty ? "未能提取出可用的表格内容" : reasons.joined(separator: "；")
            }
        }
    }

    // MARK: 离线可用部分（纯逻辑，单测覆盖）

    /// 模型回复 → 表格 → 过门禁。不联网，供单测与真实链路共用。
    nonisolated static func accept(kind: CatalogChartKind, modelReply: String) throws -> Outcome {
        let table = try CatalogChartModelReply.table(from: modelReply, kind: kind)
        return try accept(kind: kind, table: table, source: .multimodalAI)
    }

    /// 任意来源的表格 → 过门禁。
    nonisolated static func accept(kind: CatalogChartKind,
                                   table: CatalogChartParser.Table,
                                   source: Source) throws -> Outcome {
        if let issue = CatalogChartQuality.issue(columns: table.columns,
                                                 rows: table.rows,
                                                 kind: kind) {
            throw Failure.notUsable(reasons: ["\(source.displayName)结果不可用：\(issue)"])
        }
        return Outcome(table: table, source: source)
    }

    /// 过门禁的结果 → 用户可见的识别结论。`Table` → `CatalogChartRecognition` 的**唯一**转换点。
    nonisolated static func recognition(kind: CatalogChartKind,
                                        table: CatalogChartParser.Table,
                                        source: Source) -> CatalogChartRecognition {
        .verdict(kind: kind, source: source, columns: table.columns, rows: table.rows)
    }

    /// 压缩原因文本：去掉结果型错误的冗长前缀，便于拼进一句话
    nonisolated static func shortReason(_ error: Error) -> String {
        if let failure = error as? Failure, let description = failure.errorDescription {
            return description
        }
        let description = error.localizedDescription
        return description.hasPrefix("表格解析失败：")
            ? String(description.dropFirst("表格解析失败：".count))
            : description
    }
}
