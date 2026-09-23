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

import Foundation
import UIKit

// MARK: - 图表类型

/// 图表用途：决定多模态提示词口径与质量门禁的数值要求。
nonisolated enum CatalogChartKind: String, Sendable {
    /// 预约价格表（行 = 款式，列 = 预约价 / 定金 / 尾款 / 现货价…）
    case price
    /// 尺码表（行 = 尺码，列 = 胸围 / 衣长…）
    case size

    var displayName: String {
        switch self {
        case .price: return "预约价格表"
        case .size: return "尺码表"
        }
    }
}

// MARK: - 质量门禁（纯逻辑，可单测）

/// 识别结果的**可用性判定**。nil = 可用；非 nil = 不可用原因（可直接展示给用户）。
///
/// 这个类型是「不再把垃圾填进输入框」的唯一依据：任何通道的结果都要先过这里。
nonisolated enum CatalogChartQuality {

    /// 判定阈值：数据格填写率低于此值视为「多数单元格没识别出来」
    static let minimumFillRatio = 0.4

    /// 结果里不应出现的说明性文字（模型很爱输出「列名：」「备注：」这类行）
    static let metaLabels: Set<String> = [
        "列名", "表头", "行名", "说明", "备注", "注意", "示例", "格式", "注意：",
        "columns", "header", "note", "notes", "remark", "example",
    ]

    /// 允许出现的纯拉丁词元（尺码 / 常见表头英文），避免把正常英文表头误判成乱码
    static let allowedLatinTokens: Set<String> = [
        "size", "sizes", "item", "color", "colour", "style", "price", "prices",
        "deposit", "balance", "total", "bust", "waist", "hip", "length", "shoulder",
        "sleeve", "chest", "cuff", "hem", "height", "width", "weight", "unit",
        "cn", "us", "uk", "eu", "cm", "mm", "kg", "jpy", "cny", "rmb", "usd",
    ]

    /// 检查一张解析结果是否可以进入输入框 / 直接展示
    static func issue(with table: CatalogChartParser.Table, kind: CatalogChartKind) -> String? {
        if table.columns.count < 2 {
            return "只识别出 \(table.columns.count) 列（至少需要 2 列）"
        }
        if table.rows.isEmpty {
            return "没有识别到任何数据行"
        }

        // 覆盖度：数据格填写率（「只识别出第一列」的典型特征是标签有值、数值全空）
        let totalCells = table.columns.count * table.rows.count
        let filledValues = table.rows.flatMap { $0.values.compactMap { $0 } }
        let ratio = Double(filledValues.count) / Double(max(totalCells, 1))
        if ratio < minimumFillRatio {
            return "多数单元格没识别出来（\(filledValues.count)/\(totalCells) 格有值）"
        }

        // 全表无数字：价格表 / 尺码表的数据格必然带数字
        if !filledValues.contains(where: { $0.contains(where: \.isNumber) }) {
            return "没有识别到任何数值"
        }

        // 乱码词元（G PROMOTTOI 型 OCR 噪声）
        let labels = table.columns + table.rows.map(\.label)
        let garbage = labels.filter { isGarbageToken($0) }
        if !garbage.isEmpty {
            return "识别到疑似乱码文字「\(garbage.prefix(3).joined(separator: "、"))」"
        }

        // 行列错位：行标签与列名重名（「定金:尼款」型错位会在这里暴露）
        if let misplaced = table.rows.first(where: { row in table.columns.contains(row.label) }) {
            return "行标签「\(misplaced.label)」与列名重复，行列可能错位"
        }

        // 混入说明文字
        if let meta = table.rows.map(\.label).first(where: { metaLabels.contains($0) }) {
            return "结果里混入了说明文字「\(meta)」，不是\(kind.displayName)内容"
        }

        return nil
    }

    /// 是否疑似乱码词元。口径（保守，尽量不误杀正常英文表头）：
    ///   1. 含中文 → 不是乱码；
    ///   2. 长度 < 3 → 不是（S / M / L / XL 等尺码）；
    ///   3. 命中白名单 → 不是；
    ///   4. 存在 ≥3 个连续大写拉丁字母 → 是（`PROMOTTOI` 型 OCR 噪声的典型形态）；
    ///   5. 拉丁字母 ≥3 且完全不含元音 → 是（`GXF` 型）。
    static func isGarbageToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        if trimmed.contains(where: { $0.isCJK }) { return false }

        let lower = trimmed.lowercased()
        if allowedLatinTokens.contains(lower) { return false }

        // 连续大写拉丁 ≥3
        var run = 0
        for character in trimmed {
            if character.isUppercase, character.isLetter {
                run += 1
                if run >= 3 { return true }
            } else {
                run = 0
            }
        }

        // 拉丁字母 ≥3 且无元音
        let letters = trimmed.filter { $0.isLetter }
        guard letters.count >= 3 else { return false }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        return !lower.contains(where: { vowels.contains($0) })
    }
}

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

/// 图片 → 结构化表格。多模态优先 → 端上 OCR 兜底 → 统一质量门禁。
///
/// 失败一律抛 `Failure.notUsable`，**绝不返回未过门禁的结果**——
/// 这是「识别失败不要往输入框填乱码」这条需求的执行点。
enum CatalogChartExtraction {

    /// 结果来源（用于 UI 提示，让用户知道该信几分）
    enum Source: String, Sendable {
        /// 多模态大模型（能理解行列关系，优先）
        case multimodalAI
        /// 端上 Vision OCR（兜底）
        case onDeviceOCR

        var displayName: String {
            switch self {
            case .multimodalAI: return "AI 表格识别"
            case .onDeviceOCR: return "本机文字识别"
            }
        }
    }

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
        if let issue = CatalogChartQuality.issue(with: table, kind: kind) {
            throw Failure.notUsable(reasons: ["\(source.displayName)结果不可用：\(issue)"])
        }
        return Outcome(table: table, source: source)
    }

    // MARK: 真实链路

    /// 图片 → 表格。多模态优先，失败退端上 OCR，两者都不过门禁则抛错（不返回垃圾）。
    @MainActor
    static func extract(image: UIImage, kind: CatalogChartKind) async throws -> Outcome {
        var reasons: [String] = []

        // 1. 多模态大模型（理解行列关系，优先）
        do {
            let reply = try await QwenService.shared.analyzeImage(
                image: image,
                prompt: CatalogChartModelReply.prompt(for: kind))
            do {
                return try accept(kind: kind, modelReply: reply)
            } catch {
                reasons.append("AI 识别结果不可用：\(shortReason(error))")
            }
        } catch {
            reasons.append("AI 识别不可用：\(shortReason(error))")
        }

        // 2. 端上 Vision OCR 兜底
        do {
            let table = try await CatalogChartParser.parse(image: image)
            return try accept(kind: kind, table: table, source: .onDeviceOCR)
        } catch {
            reasons.append("本机文字识别不可用：\(shortReason(error))")
        }

        throw Failure.notUsable(reasons: reasons)
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

// MARK: - 小工具

extension Character {
    /// 是否中日韩文字（含常用扩展区），用于乱码判定
    var isCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // 基本区
                || (0x3400...0x4DBF).contains(scalar.value)  // 扩展 A
                || (0xF900...0xFAFF).contains(scalar.value)  // 兼容区
        }
    }
}
