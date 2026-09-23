//
//  ShopCatalogYearMonth.swift
//  ItemManager
//
//  系列的「年月」字段（2026-09-24 需求）：原「年份」（如 2026）升级为「年月」，
//  录入同时支持 "2026-10" 与 "2026年10月" 两种形式；纯年份输入仍然有效，
//  否则存量系列打开编辑页（回填 "2026"）再保存会被校验拦下。
//
//  存储口径：`CatalogSeries.year`（年）+ `CatalogSeries.month`（月，Optional）。
//  month 是**新增 Optional** 字段：合成 `Decodable` 走 decodeIfPresent，
//  旧 JSON / 已发布覆盖层缺键自动置 nil，旧数据零迁移。
//

import Foundation

/// 年月文本的解析与展示（唯一口径，录入端与展示端共用）
nonisolated enum CatalogYearMonthText {

    /// 解析结果：year 必有；month = nil 表示只填了年份（旧数据形态）
    struct Parsed: Equatable {
        let year: Int
        let month: Int?
    }

    /// 合理年份区间：这类系列的档案不会早于近代，也不会写到下个世纪
    static let validYearRange: ClosedRange<Int> = 1900...2100

    /// 解析录入文本。
    ///   · 空 / 纯空白 → nil（调用方按「清除」处理）
    ///   · "2026" → (2026, nil)（兼容旧数据）
    ///   · "2026-10" / "2026年10月" → (2026, 10)
    ///   · 其余（非数字、月份越界、年份越界）→ 解析失败，调用方给校验错误
    static func parse(_ text: String) -> Parsed? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 统一「年 / 月」为分隔符后按数字段拆解，两种形态共用同一套校验
        trimmed = trimmed
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "")

        let parts = trimmed.components(separatedBy: "-").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard (1...2).contains(parts.count) else { return nil }
        guard let year = Int(parts[0]), validYearRange.contains(year) else { return nil }
        guard parts.count == 2 else { return Parsed(year: year, month: nil) }
        guard let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        return Parsed(year: year, month: month)
    }

    /// 校验失败时给用户的具体原因（空文本不进这里）
    static func validationErrorText(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if parse(trimmed) == nil {
            return "年月格式不正确：请填 2026-10 或 2026年10月（月份 1-12），也可只填年份 2026"
        }
        return nil
    }

    /// 展示口径：有月 → "2026-10"；只有年 → "2026"；都没有 → nil（展示 "—" 由调用方决定）
    static func displayText(year: Int?, month: Int?) -> String? {
        guard let year else { return nil }
        guard let month else { return String(year) }
        return "\(year)-\(month)"
    }
}

extension CatalogSeries {
    /// 系列的「年月」展示文本（"2026-10" / "2026"）；未填 → nil
    var yearMonthText: String? {
        CatalogYearMonthText.displayText(year: year, month: month)
    }
}
