//
//  CatalogChartRecognition.swift
//  SharedCatalog
//
//  尺码表 / 预约价格表「识别结果」的**唯一判定口径与文案**（2026-10-01 需求）。
//
//  ## 用户诉求原文
//    「针对尺码表和价格表的识别功能，请实现并明确以下内容：用户提交数据后，
//      系统需根据识别结果给出明确提示，区分『识别成功』与『识别失败』两种状态，
//      尺码表和价格表的识别都要分别提供对应的结果提示。」
//
//  ## 为什么放在共享包，而不是各自 App 里
//    「这份识别结果能不能用」是**领域事实**，不是界面细节。本项目已经因为
//    「两端各写一份判定」栽过跟头（2026-09-28：iOS 与 Mac 各手拼一份图片引用清单，
//    双双漏掉 174 张图）。所以：
//      · 判定（`CatalogChartQuality`）与结论文案（`CatalogChartRecognition`）**只此一份**；
//      · 各平台界面只允许消费同一个 `CatalogChartRecognition`，
//        **不许自己拼「识别成功 / 识别失败」这类结论**。
//    本文件**零平台依赖**（纯 Foundation），可离线单测，两个平台同一份验证。
//
//  ## 「明确」到什么程度才算够
//    · `headline` 必须自带图表名（「尺码表识别成功」/「预约价格表识别失败」）——
//      运营常常同时录两张表，只说「识别成功」等于没说；
//    · 失败必须同时给 `detail`（卡在门禁的哪一条）与 `guidance`（下一步怎么办）；
//    · 失败**绝不写库**：调用方拿到 `isSuccess == false` 时不得回填 / 落盘任何内容。
//
//  ## 迁移说明
//    `CatalogChartKind`、`CatalogChartQuality`、`Character.isCJK` 原先住在
//    `ItemManager/Services/ShopCatalog/CatalogChartExtraction.swift`（iOS 独有）。
//    本次原样迁入这里 —— 判定逻辑一字未改，只是换了住址，好让 Mac 运营端也能用同一份。
//

import Foundation

// MARK: - 图表类型

/// 图表用途：决定质量门禁的数值要求，以及全部提示文案的主语。
public enum CatalogChartKind: String, Sendable, CaseIterable {
    /// 尺码表（行 = 尺码，列 = 胸围 / 衣长 / 肩宽…）
    case size
    /// 预约价格表（行 = 款式，列 = 预约价 / 定金 / 尾款…）
    case price

    /// 新建或补录表格时的默认单位；已有非空单位保持原文。
    public var defaultUnit: String {
        switch self {
        case .size: return "CM"
        case .price: return "元"
        }
    }

    public func unitForEditing(_ storedUnit: String?) -> String {
        guard let storedUnit,
              !storedUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultUnit
        }
        return storedUnit
    }

    /// 用户可见的图表名。**提示文案必须带上它**——两张表同时录入时，主语不能省。
    public var displayName: String {
        switch self {
        case .size: return "尺码表"
        case .price: return "预约价格表"
        }
    }
}

// MARK: - 质量门禁（纯逻辑，可单测）

/// 识别结果的**可用性判定**。nil = 可用；非 nil = 不可用原因（可直接展示给用户）。
///
/// 这是「不把垃圾填进输入框」的唯一依据：任何通道（AI 读图 / 端上 OCR / 文本粘贴）
/// 的结果都要先过这里，过了才允许写库。
public enum CatalogChartQuality {

    /// 判定阈值：数据格填写率低于此值视为「多数单元格没识别出来」
    public static let minimumFillRatio = 0.4

    /// 结果里不应出现的说明性文字（模型很爱输出「列名：」「备注：」这类行）
    public static let metaLabels: Set<String> = [
        "列名", "表头", "行名", "说明", "备注", "注意", "示例", "格式", "注意：",
        "columns", "header", "note", "notes", "remark", "example",
    ]

    /// 允许出现的纯拉丁词元（尺码 / 常见表头英文 / 配饰名），避免误判正常商品文字
    public static let allowedLatinTokens: Set<String> = [
        "size", "sizes", "item", "color", "colour", "style", "price", "prices",
        "deposit", "balance", "total", "bust", "waist", "hip", "length", "shoulder",
        "sleeve", "chest", "cuff", "hem", "height", "width", "weight", "unit",
        "cn", "us", "uk", "eu", "cm", "mm", "kg", "jpy", "cny", "rmb", "usd",
        "bnt", // 小物配饰名称，不能因连续大写或无元音被判为 OCR 乱码
    ]

    /// 列 / 行 → 可用性。**唯一判定点**。
    ///
    /// 用 `[String] + [CatalogSizeRow]` 而不是 `CatalogChartParser.Table` 做入参，
    /// 是为了让本判定能被 Mac 端复用 —— `Table` 定义在 iOS 的 OCR 解析器里。
    public static func issue(columns: [String],
                             rows: [CatalogSizeRow],
                             kind: CatalogChartKind) -> String? {
        if columns.isEmpty {
            return "没有识别到列名行"
        }
        if columns.count < 2 {
            return "只识别出 \(columns.count) 列（至少需要 2 列）"
        }
        if rows.isEmpty {
            return "没有识别到任何数据行"
        }

        // 覆盖度：数据格填写率（「只识别出第一列」的典型特征是标签有值、数值全空）
        let totalCells = columns.count * rows.count
        let filledValues = rows.flatMap { $0.values.compactMap { $0 } }
        let ratio = Double(filledValues.count) / Double(max(totalCells, 1))
        if ratio < minimumFillRatio {
            return "多数单元格没识别出来（\(filledValues.count)/\(totalCells) 格有值）"
        }

        // 全表无数字：价格表 / 尺码表的数据格必然带数字
        if !filledValues.contains(where: { $0.contains(where: \.isNumber) }) {
            return "没有识别到任何数值"
        }

        // 乱码词元（G PROMOTTOI 型 OCR 噪声）
        let labels = columns + rows.map(\.label)
        let garbage = labels.filter { isGarbageToken($0) }
        if !garbage.isEmpty {
            return "识别到疑似乱码文字「\(garbage.prefix(3).joined(separator: "、"))」"
        }

        // 行列错位：行标签与列名重名（「定金:尼款」型错位会在这里暴露）
        if let misplaced = rows.first(where: { row in columns.contains(row.label) }) {
            return "行标签「\(misplaced.label)」与列名重复，行列可能错位"
        }

        // 混入说明文字
        if let meta = rows.map(\.label).first(where: { metaLabels.contains($0) }) {
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
    public static func isGarbageToken(_ token: String) -> Bool {
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

// MARK: - 识别结论

/// 一次识别的结论：**成功还是失败**，以及给用户看的那几句话。
///
/// 界面只允许读这里的 `headline` / `detail` / `guidance`，不许自己拼结论 ——
/// 这是「尺码表和价格表各自给对应提示」不会写歪的唯一保障。
public struct CatalogChartRecognition: Equatable, Sendable {

    /// 识别来源：既用于成功时的「该信几分」，也用于失败时判断该引导用户走哪条路。
    public enum Source: String, Sendable, CaseIterable {
        /// 多模态大模型（能理解行列关系，优先）
        case multimodalAI
        /// 端上 Vision OCR（兜底）
        case onDeviceOCR
        /// 用户直接粘贴文本（不经过图像，最可控）
        case pastedText

        public var displayName: String {
            switch self {
            case .multimodalAI: return "AI 表格识别"
            case .onDeviceOCR: return "本机文字识别"
            case .pastedText: return "文本粘贴识别"
            }
        }
    }

    public enum Status: Equatable, Sendable {
        /// 可用：列 / 行已过质量门禁
        case succeeded(Source, columns: [String], rows: [CatalogSizeRow])
        /// 不可用：`reason` 即卡住的门禁条款；`Source` 为 nil 表示还没走到具体通道
        case failed(Source?, reason: String)

        public var isSuccess: Bool {
            if case .succeeded = self { return true }
            return false
        }
    }

    public let kind: CatalogChartKind
    public let status: Status

    private init(kind: CatalogChartKind, status: Status) {
        self.kind = kind
        self.status = status
    }

    // MARK: 构造（唯一入口）

    /// 带门禁的统一入口：列 / 行 → 结论。
    ///
    /// 空内容也算**失败**（而不是「没试过」）——用户点了提交就应该拿到一个明确结论。
    /// 界面若不想在空输入时显示结论，请自己判断输入是否为空，不要在这里造第三种状态。
    public static func verdict(kind: CatalogChartKind,
                               source: Source,
                               columns: [String],
                               rows: [CatalogSizeRow]) -> CatalogChartRecognition {
        if columns.isEmpty, rows.isEmpty {
            return CatalogChartRecognition(
                kind: kind,
                status: .failed(source, reason: "没有可识别的表格内容（列名行与数据行都是空的）"))
        }
        if let issue = CatalogChartQuality.issue(columns: columns, rows: rows, kind: kind) {
            return CatalogChartRecognition(kind: kind, status: .failed(source, reason: issue))
        }
        return CatalogChartRecognition(
            kind: kind,
            status: .succeeded(source, columns: columns, rows: rows))
    }

    /// 失败结论（通道整个不可用：读图失败、网络失败、模型没返回内容…）。
    /// `reason` 由调用方归一，`CatalogChartExtraction.shortReason` 是现成口径。
    public static func rejected(kind: CatalogChartKind,
                                source: Source?,
                                reason: String) -> CatalogChartRecognition {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return CatalogChartRecognition(
            kind: kind,
            status: .failed(source, reason: trimmed.isEmpty ? "未能提取出可用的表格内容" : trimmed))
    }

    /// 还没开始识别时用（界面据此不渲染结论板块）。
    public static func idle(kind: CatalogChartKind) -> CatalogChartRecognition {
        CatalogChartRecognition(kind: kind, status: .failed(nil, reason: "尚未识别"))
    }

    // MARK: 结论

    public var isSuccess: Bool { status.isSuccess }

    /// 本次走了哪条通道（失败时也能回答「是哪条通道失败的」）
    public var source: Source? {
        switch status {
        case .succeeded(let source, _, _): return source
        case .failed(let source, _): return source
        }
    }

    /// 「尺码表识别成功」/「预约价格表识别失败」——**永远带图表名**。
    public var headline: String {
        kind.displayName + (isSuccess ? "识别成功" : "识别失败")
    }

    /// 结论的依据：成功给「来源 + 规模 + 填写率」，失败给卡住的那一条门禁。
    public var detail: String {
        switch status {
        case .failed(_, let reason):
            return reason
        case .succeeded(let source, let columns, let rows):
            let total = columns.count * rows.count
            let filled = rows.reduce(0) { $0 + $1.values.compactMap { $0 }.count }
            return "\(source.displayName) · 共 \(rows.count) 行 × \(columns.count) 列 · \(filled)/\(total) 格有内容"
        }
    }

    /// 失败时的下一步。成功时为 nil（成功不需要引导）。
    public var guidance: String? {
        guard case .failed(let source, _) = status else { return nil }
        switch source {
        case .some(.multimodalAI), .some(.onDeviceOCR):
            return "识别失败不会写入任何内容，已录入的数据不受影响。"
                + "可以换一张更清晰、表格边框完整的截图重试，"
                + "或用「粘贴文本录入」把\(kind.displayName)整段贴进来。"
        case .some(.pastedText), .none:
            // 文本是用户自己贴的：不承诺「不会写入」，改为承诺「不会清空已有内容」
            // （`apply` 只在解析出内容时才覆盖对应输入框，见 ShopCatalogChartPasteSheet）。
            return "粘贴的内容没有解析成完整的\(kind.displayName)。"
                + "请确认既有列名行，也有「标签:值,值」形式的数据行；"
                + "修正后重新识别即可，原有的列名与数据不会被清空。"
        }
    }

    /// 成功时识别到的列（失败时为空）
    public var recognizedColumns: [String] {
        if case .succeeded(_, let columns, _) = status { return columns }
        return []
    }

    /// 成功时识别到的行（失败时为空）
    public var recognizedRows: [CatalogSizeRow] {
        if case .succeeded(_, _, let rows) = status { return rows }
        return []
    }

    /// 成功且**确实有内容**可展示（供界面决定要不要渲染表格预览）
    public var hasRecognizedContent: Bool {
        !recognizedColumns.isEmpty && !recognizedRows.isEmpty
    }

    /// 无障碍朗读 / 日志用的一句话
    public var summaryLine: String {
        "\(headline)：\(detail)"
    }
}

// MARK: - 小工具

extension Character {
    /// 是否中日韩文字（含常用扩展区），用于乱码判定
    public var isCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // 基本区
                || (0x3400...0x4DBF).contains(scalar.value)  // 扩展 A
                || (0xF900...0xFAFF).contains(scalar.value)  // 兼容区
        }
    }
}
