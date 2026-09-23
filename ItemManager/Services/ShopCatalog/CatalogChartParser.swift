//
//  CatalogChartParser.swift
//  ItemManager
//
//  尺码表 / 预约价格表 图片自动解析（2026-09-22）：
//    上传图片 → Vision OCR 逐词元识别 → 按包围盒重建行 → 表格文本解析 → 结构化 columns / rows，
//    详情页按表格样式直接渲染，无需人工二次录入。
//    · parse(image:)   —— OCR 通道（异步）
//    · parseText(_:)   —— 纯文本解析（nonisolated 纯函数，单测覆盖）
//    · reconstructLineTexts —— 包围盒 → 行文本（纯函数，单测覆盖）
//    · CatalogManualChartText —— 手动录入文本（逗号分隔列 + 「标签:值,值」行）共享解析
//    · 解析失败 / 字段缺失一律抛 CatalogChartParserError，给出明确可操作的提示；
//      原图引用始终保留，详情页可查看原图并引导人工修正。
//
//  2026-09-22 修复（用户反馈「表头下没有数据行」）：
//    Vision 对列间距大的表格会把**每个单元格识别成独立 observation**，
//    旧实现按「一行文本一个 observation」解析 → 表头后全是单词元行被当孤立标签丢弃。
//    现改为按包围盒垂直聚类重建行、水平排序拼列（\t 分隔），单元格被打散也能还原表格。
//

import UIKit
import Vision

nonisolated enum CatalogChartParserError: LocalizedError {
    case imageUnavailable
    case noTextRecognized
    case tableUnparsable(reason: String)

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return "无法读取图片内容，请重新上传（支持截图或清晰拍照）"
        case .noTextRecognized:
            return "图片中未识别到文字，请确认上传的是价格表 / 尺码表截图"
        case .tableUnparsable(let reason):
            return "表格解析失败：\(reason)。原图已保留，可在下方手动修正识别结果"
        }
    }
}

nonisolated enum CatalogChartParser {

    struct Table: Sendable, Hashable {
        var columns: [String]
        var rows: [CatalogSizeRow]
    }

    /// OCR 单元格：文本 + 归一化包围盒（Vision 坐标系，原点左下）
    struct Cell: Sendable, Equatable {
        let text: String
        let box: CGRect
    }

    // MARK: OCR 通道

    /// 图片 → OCR 词元 → 包围盒重建行 → 结构化表格
    static func parse(image: UIImage) async throws -> Table {
        guard let cgImage = image.cgImage else { throw CatalogChartParserError.imageUnavailable }
        let cells = try await recognizeCells(cgImage: cgImage)
        guard !cells.isEmpty else { throw CatalogChartParserError.noTextRecognized }
        return try parseText(reconstructLineTexts(from: cells))
    }

    private static func recognizeCells(cgImage: CGImage) async throws -> [Cell] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let cells: [Cell] = observations.compactMap { observation in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    return Cell(text: text, box: observation.boundingBox)
                }
                continuation.resume(returning: cells)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: 包围盒 → 行文本（纯函数，可单测）

    /// 单元格按行聚类（垂直中心接近 = 同一行）、行内按 x 排序，列间用 \t 分隔。
    /// Vision 坐标系原点在**左下**：midY 越大越靠图片上方，应排在越前。
    nonisolated static func reconstructLineTexts(from cells: [Cell]) -> [String] {
        guard !cells.isEmpty else { return [] }
        let sorted = cells.sorted { $0.box.midY > $1.box.midY }
        var rows: [[Cell]] = []
        var current: [Cell] = []
        var currentMidY: CGFloat = 0
        for cell in sorted {
            if let last = current.last,
               abs(cell.box.midY - currentMidY) > max(cell.box.height, last.box.height) * 0.6 {
                rows.append(current)
                current = [cell]
            } else {
                current.append(cell)
            }
            currentMidY = current.map(\.box.midY).reduce(0, +) / CGFloat(current.count)
        }
        if !current.isEmpty { rows.append(current) }
        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: "\t")
        }
    }

    // MARK: 文本解析（纯函数，可单测）

    /// 行文本 → 表格。口径：
    ///   · 第一个含 ≥2 个词元的行 = 列头行（首个词元是左上角标签，如「尺码」「项目」）
    ///   · 其后每行 = 「行标签 值 值 …」，值不足的列补 nil（详情页显示「—」）
    ///   · 词元支持空格 / 制表符（包围盒重建输出 \t 分隔）分隔
    ///   · 值为「-」「/」「—」「暂无」等占位时视为空；词元尾部冒号 / 逗号（OCR 噪声）剔除
    nonisolated static func parseText(_ lines: [String]) throws -> Table {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let headerIndex = cleaned.firstIndex(where: { tokens($0).count >= 2 }) else {
            throw CatalogChartParserError.tableUnparsable(reason: "未找到至少两列的表头行")
        }
        let columns = Array(tokens(cleaned[headerIndex]).dropFirst())
        guard !columns.isEmpty else {
            throw CatalogChartParserError.tableUnparsable(reason: "表头除行标签外没有数据列")
        }
        var rows: [CatalogSizeRow] = []
        for line in cleaned[(cleaned.index(after: headerIndex))...] {
            let lineTokens = tokens(line)
            guard let label = lineTokens.first else { continue }
            let values: [String?] = (1...columns.count).map { offset in
                guard lineTokens.indices.contains(offset) else { return nil }
                let value = lineTokens[offset]
                return placeholderTokens.contains(value) ? nil : value
            }
            // 孤立标签行（OCR 把行标签和数值拆开时可能出现）：暂存为标签行跳过
            if values.allSatisfy({ $0 == nil }) && lineTokens.count <= 1 { continue }
            rows.append(CatalogSizeRow(label: label, values: values))
        }
        guard !rows.isEmpty else {
            throw CatalogChartParserError.tableUnparsable(reason: "表头下没有数据行")
        }
        return Table(columns: columns, rows: rows)
    }

    nonisolated private static let placeholderTokens: Set<String> = ["-", "/", "—", "–", "―", "暂无"]

    /// 词元切分：制表符（包围盒重建输出）优先，空格（含连续空白）兜底；
    /// 词元尾部冒号 / 逗号（OCR 噪声，如「86-92:」）剔除
    nonisolated private static func tokens(_ line: String) -> [String] {
        let raw: [Substring] = line.contains("\t")
            ? line.split(separator: "\t", omittingEmptySubsequences: true)
            : line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return raw
            .map { CatalogManualChartText.cleanToken(String($0)) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - 手动录入文本共享解析（深度编辑 / 补录草稿编辑器 / 系列价格表）

/// 手动表格文本（列名逗号分隔 + 每行「标签:值,值,…」）的共享解析与规范化。
/// 三处编辑器共用同一口径，避免各自实现漂移（2026-09-22 修复重复「尺码」列）。
nonisolated enum CatalogManualChartText {

    /// 行标签列的列名（用户在列头里把标签列也写进去时，剔除以免与角落标签列重复）
    static let labelColumnNames: Set<String> = [
        "尺码", "尺寸", "规格", "型号", "项目", "款式", "商品", "名称", "颜色", "size", "item",
    ]

    /// 词元清洗：去掉尾部冒号（全半角）与逗号（全半角），如「86-92:」→「86-92」
    static func cleanToken(_ token: String) -> String {
        var result = token.trimmingCharacters(in: .whitespaces)
        while let last = result.last, last == ":" || last == "：" || last == "," || last == "，" {
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// 列名文本 → 数据列。首列若为行标签列名（如「尺码」）则剔除——
    /// 渲染时角落已有独立标签列，保留会出现重复「尺码」列且整体错位一列。
    static func parseColumns(_ text: String) -> [String] {
        let columns = text
            .components(separatedBy: ",")
            .map { cleanToken($0.replacingOccurrences(of: "，", with: ",")) }
            .filter { !$0.isEmpty }
        guard let first = columns.first, isLabelColumn(first) else { return columns }
        return Array(columns.dropFirst())
    }

    /// 行文本（每行「标签:值,值,…」）→ 行。值尾冒号 / 逗号清洗，空段补 nil。
    /// 2026-09-23：先做全角 → 半角归一（中文输入法打出的「：」「，」也算分隔符）。
    static func parseRows(_ text: String) -> [CatalogSizeRow] {
        text
            .components(separatedBy: .newlines)
            .map { normalizeSeparators($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line -> CatalogSizeRow? in
                let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
                guard let label = pair.first else { return nil }
                let values = (pair.count > 1 ? String(pair[1]) : "")
                    .components(separatedBy: ",")
                    .map { cleanToken($0) }
                    .map { $0.isEmpty ? nil : $0 }
                return CatalogSizeRow(label: cleanToken(String(label)), values: values)
            }
    }

    /// 全角 → 半角（：，｜、全角空格）+ 去 Markdown 强调符与反引号。
    /// 粘贴来源五花八门（微信 / 备忘录 / Excel / 模型回复），先归一再解析。
    static func normalizeSeparators(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "：", with: ":")
        result = result.replacingOccurrences(of: "，", with: ",")
        result = result.replacingOccurrences(of: "｜", with: "|")
        result = result.replacingOccurrences(of: "　", with: " ")
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        return result
    }

    /// 渲染 / 保存前的统一规范化（旧数据里已存入的重复标签列在此兜底修复）：
    ///   · 值 / 标签去尾冒号
    ///   · 首列是行标签列名（如「尺码」）时剔除，行的值保持原序——
    ///     旧数据里值本就整体左移一列，剔除后恰好对齐（多余尾值无害）
    static func normalized(columns: [String], rows: [CatalogSizeRow])
        -> (columns: [String], rows: [CatalogSizeRow]) {
        let cleanedRows = rows.map { row in
            CatalogSizeRow(label: cleanToken(row.label),
                           values: row.values.map { value in
                               guard let value else { return nil }
                               let cleaned = cleanToken(value)
                               return cleaned.isEmpty ? nil : cleaned
                           })
        }
        guard let first = columns.first, isLabelColumn(first) else {
            return (columns, cleanedRows)
        }
        return (Array(columns.dropFirst()), cleanedRows)
    }

    static func isLabelColumn(_ name: String) -> Bool {
        labelColumnNames.contains(name.lowercased())
    }

    // MARK: 整段文本 → 表格（「粘贴录入」与「多模态回复」共用口径，2026-09-23 需求 M）

    /// 整段文本的解析结果。
    struct PastedChart: Sendable {
        /// 列名行原文（回填「列名」输入框；找不到列名行时为空串）
        var columnsText: String
        /// 数据行文本（逐行「标签:值,值,…」，回填「行」输入框）
        var rowsText: String
        /// 解析后的列名（已剔行标签列，可直接展示 / 保存）
        var columns: [String]
        var rows: [CatalogSizeRow]

        var isEmpty: Bool { columns.isEmpty && rows.isEmpty }
    }

    /// 用户直接粘贴的整段文本 → 表格。兼容三种来源：
    ///   · 手工 / 模型输出的「列名行 + 标签:值」纯文本
    ///   · Markdown 表格（`| 款式 | 预约价 |`）
    ///   · Excel / Numbers 复制出来的制表符分隔表
    ///
    /// 用户诉求原文：「我需要的是能直接复制粘贴的规整文本」——模板不重要，
    /// 整段丢进来就能识别并按行拆分，才算真的可用。
    static func parsePastedText(_ text: String) -> PastedChart {
        let lines = normalizeSeparators(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return PastedChart(columnsText: "", rowsText: "", columns: [], rows: [])
        }
        if lines.contains(where: { $0.hasPrefix("|") }) {
            return markdownTable(lines)
        }
        var headerIndex: Int?
        for (index, line) in lines.enumerated() where isHeaderCandidate(line) {
            // 列名行之后必须至少有一行数据行，否则更像是被误当表头的说明文字
            let hasDataAfter = lines[(index + 1)...].contains { dataLine($0) != nil }
            if hasDataAfter {
                headerIndex = index
                break
            }
        }
        var rowLines: [String] = []
        for (index, line) in lines.enumerated() where index != headerIndex {
            if let converted = dataLine(line) { rowLines.append(converted) }
        }
        // 列名行原文回填前把制表符 / 竖线归一成逗号：
        // 否则「尺码\t胸围」会被 parseColumns 当成**一个**列名（只认逗号分隔）
        let columnsText = headerIndex.map { headerText(lines[$0]) } ?? ""
        return make(columnsText: columnsText, rowLines: rowLines)
    }

    /// 列名行 → 逗号分隔文本（兼容 Excel 复制的制表符、Markdown / 网页的竖线）
    private static func headerText(_ line: String) -> String {
        line.replacingOccurrences(of: "\t", with: ",")
            .replacingOccurrences(of: "|", with: ",")
    }

    /// 列名行判定：不含冒号 + 至少 2 段 + **没有任何一段含数字**。
    /// 最后一条是关键：数据行（款名,318,91,227）必然带数字，靠它避免把数据行误判成列名行。
    private static func isHeaderCandidate(_ line: String) -> Bool {
        guard !line.contains(":") else { return false }
        let fields = splitFields(line)
        guard fields.count >= 2 else { return false }
        return !fields.contains(where: { $0.contains(where: \.isNumber) })
    }

    /// 数据行归一化：已是「标签:值」的原样保留；
    /// 否则首段当标签、其余当值（兼容用户按「款名,318,91,227」贴过来的写法）
    private static func dataLine(_ line: String) -> String? {
        if line.contains(":") { return line }
        let fields = splitFields(line).map(cleanToken)
        guard fields.count >= 2, !fields[0].isEmpty else { return nil }
        return fields[0] + ":" + fields.dropFirst().joined(separator: ",")
    }

    /// 字段切分：英文 / 中文逗号、制表符、竖线都算分隔符
    private static func splitFields(_ line: String) -> [String] {
        line.split(whereSeparator: { character in
            character == "," || character == "\t" || character == "|"
        })
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }

    private static func markdownTable(_ lines: [String]) -> PastedChart {
        var header: [String] = []
        var rowLines: [String] = []
        for line in lines where line.hasPrefix("|") {
            let cells = splitFields(line)
            guard !cells.isEmpty else { continue }
            if cells.allSatisfy(isSeparatorCell) { continue }   // |---|---| 分隔行
            if header.isEmpty {
                header = cells
                continue
            }
            let label = cleanToken(cells[0])
            guard !label.isEmpty else { continue }
            rowLines.append(label + ":" + cells.dropFirst().map(cleanToken).joined(separator: ","))
        }
        return make(columnsText: header.joined(separator: ","), rowLines: rowLines)
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        !cell.isEmpty && cell.allSatisfy { $0 == "-" || $0 == ":" || $0 == "=" || $0 == " " }
    }

    /// 组装：列名走 parseColumns（剔行标签列）→ 行文本走 parseRows → 统一 normalized。
    /// 与「保存价格表 / 尺码表」链路完全同一套口径，**预览即落库结果**。
    private static func make(columnsText: String, rowLines: [String]) -> PastedChart {
        let rowsText = rowLines.joined(separator: "\n")
        let parsed = normalized(columns: parseColumns(columnsText), rows: parseRows(rowsText))
        return PastedChart(columnsText: columnsText,
                           rowsText: rowsText,
                           columns: parsed.columns,
                           rows: parsed.rows)
    }
}
