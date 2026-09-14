import Foundation

/// 尺码表数据的来源与解析。
///
/// ## 数据从哪来（已核实，非推测）
///
/// 品牌官网商品页的尺寸文本，**随 `description` / `descriptionZH` 一起被采集入库了**，
/// 但历史上从未解析成结构化字段。格式高度规整，例如：
///
/// ```
/// 着丈：約98cm
/// バスト：約88～140cm
/// ウエスト：約68～138cm
/// 肩幅：約34cm
/// 袖丈：約62cm
/// ```
///
/// 实测覆盖率（2026-09-14 统计 `ItemManager/Resources/TimeHall/*.json`）：
///
/// | 目录 | 商品数 | 可解析尺码表（≥3 项） |
/// |---|---|---|
/// | baby-stars-shine-bright | 861 | 283（33%） |
/// | wunderwelt-fleur | 3116 | 2 |
/// | angelic-pretty | 267 | 0 |
/// | juliette-et-justine | 221 | 0 |
/// | catalog.json | 308 | 0 |
/// | **合计** | **4773** | **285（6%）** |
///
/// 结论：**约 6% 的商品零成本可落地**（尤其 Baby 品牌达 33%），
/// 其余品牌（Angelic Pretty、Wunderwelt 二手）的尺码表在**图片**里，
/// 抓不到结构化数据 —— 这正是人工录入入口存在的理由，写入时置
/// `TimeHallSizeChart.isManuallyEntered = true` 以便区分来源。
///
/// 另有一类「HTML 表格被拍平成文本行」的情况（如 Juliette et Justine，
/// 会看到 `バストトップ /cm Bust /cm 胸围 /cm` 这样的表头行），
/// 表头可识别但数值行需要逐条核对，本解析器暂不处理，留给人工录入。
nonisolated enum TimeHallSizeChartParser {

  /// 规范列顺序。解析结果一律按此顺序排列，保证表格渲染稳定。
  /// 第一列固定为尺码标签列，由 `TimeHallSizeChart.columns[0]` 承担。
  static let labelColumnName = "尺码"

  /// 规范列定义：`key` 为 Canonical 列名，`aliases` 为各语言的原始标签。
  private static let canonicalColumns: [(key: String, aliases: [String])] = [
    ("衣长", ["着丈", "総丈", "衣长", "全长"]),
    ("胸围", ["バスト", "胸围"]),
    ("腰围", ["ウエスト", "腰围"]),
    ("肩宽", ["肩幅", "肩宽"]),
    ("袖长", ["袖丈", "袖长"]),
    ("臀围", ["ヒップ", "臀围"]),
  ]

  /// 别名 → 规范列名的反查表。
  private static let aliasToKey: [String: String] = {
    var map: [String: String] = [:]
    for column in canonicalColumns {
      for alias in column.aliases {
        map[alias] = column.key
      }
    }
    return map
  }()

  /// 所有可识别标签，按长度降序拼接成正则的交替分支
  /// （长标签优先，避免「着丈」被「丈」之类前缀误切）。
  private static let allAliasesPattern: String = {
    let aliases = aliasToKey.keys.sorted { $0.count > $1.count }
    return aliases.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
  }()

  /// 匹配 `标签 [：:] 約? 数字 [～数字] cm?`。
  /// 数值区间用 `～〜~-–` 各种连字符都能识别。
  private static let measurementRegex: NSRegularExpression? = {
    let pattern =
      "(\(allAliasesPattern))\\s*[:：]\\s*(?:約|约)?\\s*"
      + "([0-9]+(?:\\.[0-9]+)?)"
      + "(?:\\s*[～〜~\\-–]\\s*([0-9]+(?:\\.[0-9]+)?))?"
      + "\\s*(?:cm|CM|ｃｍ|センチ)?"
    return try? NSRegularExpression(pattern: pattern)
  }()

  // MARK: - 解析

  /// 从商品描述文本解析尺码表。
  ///
  /// - Parameters:
  ///   - japaneseText: 日文描述（`TimeHallCommerceItemDTO.description`）。
  ///   - chineseText: 中文描述（`descriptionZH`），用于补齐日文缺失的项。
  ///   - sizes: 商品的尺码列表，决定行标签。
  ///   - sourceURL: 溯源链接，写进结果。
  /// - Returns: 至少解析出 3 个规范列时返回尺码表，否则返回 nil（交给人工录入）。
  static func parse(
    japaneseText: String?,
    chineseText: String?,
    sizes: [String],
    sourceURL: String? = nil
  ) -> TimeHallSizeChart? {
    var extracted: [String: String] = [:]
    // 日文优先：日文描述里的原始尺寸最权威，中文只补日文没有的列。
    for text in [japaneseText, chineseText] {
      guard let text, !text.isEmpty else { continue }
      for (key, value) in extract(from: text) where extracted[key] == nil {
        extracted[key] = value
      }
    }

    // 阈值 3：少于 3 项的多半是描述正文里偶然出现的词，不是尺码表。
    guard extracted.count >= 3 else { return nil }

    let orderedColumns = canonicalColumns
      .map(\.key)
      .filter { extracted[$0] != nil }

    let columns = [labelColumnName] + orderedColumns
    let values = orderedColumns.compactMap { extracted[$0] }

    // 单一尺寸取该尺码为行标签；多尺码时这批测量值并不分尺码，
    // 标「均码」并在 note 里说明，避免误导。
    let rowLabel: String
    let note: String?
    if sizes.count == 1, let only = sizes.first, !only.isEmpty {
      rowLabel = only
      note = "尺寸为品牌公开的实测值（该款单一尺码）。"
    } else if sizes.isEmpty {
      rowLabel = "均码"
      note = "尺寸为品牌公开的实测值。该款未标注尺码。"
    } else {
      rowLabel = "均码"
      note = "尺寸为品牌公开的单一实测值，不区分 \(sizes.count) 个尺码，仅供参考。"
    }

    return TimeHallSizeChart(
      unit: "cm",
      columns: columns,
      rows: [TimeHallSizeRow(label: rowLabel, values: values, alignTo: orderedColumns.count)],
      sourceURL: sourceURL,
      isManuallyEntered: false,
      noteZH: note
    )
  }

  /// 从单个文本块抽取 `规范列名 → 数值文案`。
  private static func extract(from text: String) -> [String: String] {
    guard let regex = measurementRegex else { return [:] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    var result: [String: String] = [:]

    regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
      guard let match, match.numberOfRanges >= 3 else { return }
      guard
        let labelRange = Range(match.range(at: 1), in: text),
        let lowerRange = Range(match.range(at: 2), in: text)
      else { return }

      let label = String(text[labelRange])
      guard let key = aliasToKey[label] else { return }
      // 同一列只保留第一次出现，避免描述里重复提及造成覆盖。
      guard result[key] == nil else { return }

      let lower = String(text[lowerRange])
      if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound,
        let upperRange = Range(match.range(at: 3), in: text)
      {
        result[key] = "\(lower)～\(String(text[upperRange]))"
      } else {
        result[key] = lower
      }
    }

    return result
  }
}

// MARK: - 取用入口

extension TimeHallCommerceItemDTO {
  /// 实际使用的尺码表：优先用已存的结构化数据（含人工录入），
  /// 没有再尝试从描述文本现解析。两者都没有时返回 nil，
  /// 由界面渲染「尺码表待补充」空态。
  nonisolated var resolvedSizeChart: TimeHallSizeChart? {
    if let sizeChart, sizeChart.isUsable { return sizeChart }
    return TimeHallSizeChartParser.parse(
      japaneseText: description,
      chineseText: descriptionZH,
      sizes: sizes,
      sourceURL: productPageURL.isEmpty ? nil : productPageURL
    )
  }
}
