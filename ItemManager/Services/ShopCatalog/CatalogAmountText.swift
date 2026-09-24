//
//  CatalogAmountText.swift
//  ItemManager
//
//  金额文本的解析 / 校验 / 派生口径（2026-09-24 需求）：
//  补录草稿价格组「尾款自动计算 + 异常输入提示」的唯一口径，录入端与单测共用。
//
//  口径：
//    · 空 / 纯空白 → nil（= 未填，合法）
//    · "88" / "88.5" / 全角点 "88。5" / 全角逗号 "88，5" → 88 / 88.5
//    · 非数字（"八十八"、带单位 "88元"、多小数点…）→ 解析失败，调用方给红字提示
//    · 尾款 = 预约价 − 定金（定金缺省按 0）；未填预约价 → nil（没有对账基准）
//

import Foundation

nonisolated enum CatalogAmountText {

    /// 解析金额文本。空 = 未填（nil，合法）；解析失败 = nil（调用方用
    /// `isInvalid` 区分「未填」与「填错」）。
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: "。", with: ".")
        return Double(normalized)
    }

    /// 非空且解析失败 → 提示文案；空或合法数字 → nil
    static func validationErrorText(for text: String, label: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if parse(trimmed) == nil {
            return "「\(label)」需为数字（当前输入：\(trimmed)）"
        }
        return nil
    }

    /// 尾款派生（2026-09-24 需求）：尾款 = 预约价 − 定金，无需手动输入；
    /// 定金未填按 0；预约价未填 → nil（没有对账基准，尾款无从谈起）。
    static func balance(reservation: Double?, deposit: Double?) -> Double? {
        reservation.map { $0 - (deposit ?? 0) }
    }

    /// 展示口径：整数不带小数点（88 → "88"），小数原样（88.5 → "88.5"）。
    /// 用于既有草稿回填输入框，避免 "88.0" 这种机器腔。
    static func displayText(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
