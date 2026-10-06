//
//  CatalogChartTextSyntax.swift
//  SharedCatalog
//
//  图表文本的**分隔符归一化**（尺码表 / 预约价格表；iOS 与 Mac 共用一份口径）。
//
//  ## 为什么必须共用
//
//  粘贴来源五花八门：微信 / 备忘录 / Excel / 模型回复，**中文输入法打出来的是全角
//  标点**（「，」不是「,」）。而两端的「值计数」校验都按**半角逗号**切分：
//  一个全角逗号就会让 `,49,85` 这种写法少切出一段 ⇒ **8 个值变 7 个**，
//  于是报「值个数与列名不符」。用户看着自己明明写对了，完全无从下手。
//
//  2026-10-01 实测：Mac 侧**只**在列名切分里认全角逗号、**行值里不认**，
//  而 iOS 侧行值先过了 `normalizedSeparators` 才切 —— 同一段文本 iOS 过、Mac 不过。
//  这正是本项目反复吃亏的「两端各写一份判定」。所以归一化上收到这里，
//  两端（含 iOS 原有实现）都调这一份，**不许再各留一份**。
//
//  ⚠️ 归一化只做「同义标点的等价替换」，**不改变任何语义**：
//  不补值、不删行、不猜用户意图。缺值仍然要如实报错（不静默兜底）。
//

import Foundation

/// 图表文本的分隔符归一化与切分。**唯一口径**。
public enum CatalogChartTextSyntax {

    /// 全角 → 半角 + 去 Markdown 强调符与反引号。
    ///
    /// 归一化后 `,` / `|` / `:` / 空格 才是**唯一的**分隔符写法，
    /// 下游按半角切分就不会因为输入法而少切一段。
    ///
    /// - 全角逗号「，」→ `,`
    /// - 全角冒号「：」→ `:`
    /// - 全角竖线「｜」→ `|`
    /// - 全角空格「　」（U+3000）→ 半角空格
    /// - 去掉 `**`（Markdown 加粗）与反引号 —— 从模型回复里粘贴时常见
    public static func normalizedSeparators(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "：", with: ":")
        result = result.replacingOccurrences(of: "，", with: ",")
        result = result.replacingOccurrences(of: "｜", with: "|")
        result = result.replacingOccurrences(of: "　", with: " ")
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        return result
    }

    /// 值文本 → 值列表：按**半角逗号**切，空段补 `nil`（「用逗号留空占位」的写法靠这个成立）。
    ///
    /// 调用方**必须先把整行过一遍 `normalizedSeparators(_:)`** —— 否则全角逗号不会切分，
    /// 值个数会静默少一个（2026-10-01 的缺陷根因）。
    public static func splitValues(_ text: String) -> [String?] {
        text
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { part -> String? in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
    }

    /// 列名文本 → 列：半角/全角逗号、半角/全角竖线都算分隔符，空段丢弃。
    public static func splitColumns(_ text: String) -> [String] {
        normalizedSeparators(text)
            .split(whereSeparator: { $0 == "," || $0 == "|" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - 行标签列（**列口径的唯一出处**）

    /// 「行标签列」的列名。用户在列头里把标签列也写进去时，这一列要**忽略**。
    ///
    /// 为什么必须忽略：渲染时角落已有独立的行标签列（`S` / `XS` / 款式名），
    /// 列名里再来一个「尺码」就是重复列，且整个表会**错位一列**。
    public static let labelColumnNames: Set<String> = [
        "尺码", "尺寸", "规格", "型号", "项目", "款式", "商品", "名称", "颜色", "size", "item",
    ]

    public static func isLabelColumn(_ name: String) -> Bool {
        labelColumnNames.contains(name.lowercased())
    }

    /// 列名文本 → **数据列**（首列若是行标签列名则剔除）。
    ///
    /// ⭐ **两端取列口径的唯一入口**。历史上 iOS 走 `normalized` 剔除、Mac 不剔除，
    /// 于是同一段「列名含尺码」的文本：
    ///   · Mac 按 8 列做「值个数」校验 → **放行**；
    ///   · iOS 渲染时剔成 7 列，但行的值仍是 8 个 → **整列错位**
    ///     （2026-10-01 实测：`胸围` 显示成后衣长的值，末尾一个值被丢掉）。
    ///     界面还一路显示「识别成功」——静默的数据损坏。
    /// 现在两端都从这里取列，校验与渲染看到的是同一份列。
    public static func dataColumns(from text: String) -> [String] {
        let columns = splitColumns(text)
        guard let first = columns.first, isLabelColumn(first) else { return columns }
        return Array(columns.dropFirst())
    }

    // MARK: - 一行 `标签 = 值1, 值2` 的解析（唯一口径）

    /// 解析出来的一行。
    public struct RowLine: Equatable {
        public var label: String
        public var values: [String?]

        public init(label: String, values: [String?]) {
            self.label = label
            self.values = values
        }
    }

    /// 行解析失败的原因。**只描述事实，不带文案** —— 各端的措辞由自己决定
    /// （尺码表说「尺码表行「XS」…」，价格表说「「款式」…」，共用一份文案反而会别扭）。
    public enum RowLineIssue: Error, Equatable {
        /// 整行没有分隔符（`=`）
        case missingSeparator(line: String)
        /// 分隔符左边的标签是空的
        case emptyLabel(line: String)
        /// 值个数与数据列个数不符 —— **这条是「防静默错位」的关键**
        case valueCountMismatch(label: String, actual: Int, expected: Int)
    }

    /// 一行文本 → `RowLine`。
    ///
    /// 顺序**必须是**：先 `normalizedSeparators`（全角→半角）→ 再切分值。
    /// 反过来的话，一个全角逗号会让值个数静默少一个，报出来的却是「值个数与列名不符」，
    /// 用户盯着自己写对的数字完全无从下手（2026-10-01 用户报障的根因）。
    ///
    /// - Parameter dataColumnCount: **数据列**个数（已剔除行标签列，见 `dataColumns(from:)`）。
    ///   传 0 表示「还不知道列数」，此时跳过个数校验。
    public static func parseRowLine(_ rawLine: String,
                                    dataColumnCount: Int,
                                    separator: Character = "=")
        -> Result<RowLine, RowLineIssue> {
        let line = normalizedSeparators(rawLine)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = line.firstIndex(of: separator) else {
            return .failure(.missingSeparator(line: line))
        }
        let label = String(line[line.startIndex..<index])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            return .failure(.emptyLabel(line: line))
        }
        let values = splitValues(String(line[line.index(after: index)...]))
        if dataColumnCount > 0, values.count != dataColumnCount {
            return .failure(.valueCountMismatch(label: label,
                                                actual: values.count,
                                                expected: dataColumnCount))
        }
        return .success(RowLine(label: label, values: values))
    }

    /// 整段行文本 → 若干行。遇到第一处错误就停（**不静默跳过坏行**）。
    public static func parseRowLines(_ text: String, dataColumnCount: Int)
        -> Result<[RowLine], RowLineIssue> {
        var lines: [RowLine] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard !String(raw).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            switch parseRowLine(String(raw), dataColumnCount: dataColumnCount) {
            case .success(let line): lines.append(line)
            case .failure(let issue): return .failure(issue)
            }
        }
        return .success(lines)
    }
}
