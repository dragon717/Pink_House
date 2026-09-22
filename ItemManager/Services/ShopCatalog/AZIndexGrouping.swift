//
//  AZIndexGrouping.swift
//  ItemManager
//
//  「字典序」的唯一权威实现（Service 层，供 Store 与所有列表 UI 共用）：
//    根因背景：Catalog 实体在 JSON / 内存数组里是**录入顺序**，
//    任何直接遍历数组的地方都没有字典序保证（曾导致运营端「系列」列表乱序）。
//    规范：所有需要按名称展示的列表，必须走 `sortedByName` 或 `groups`，
//    禁止直接 ForEach 原始数组。
//
//  排序口径：先按索引字母（# → A → … → Z，中文转拼音首字母），
//  同字母组内按 `localizedStandardCompare` 排（大小写不敏感、数字按自然序）。
//

import Foundation
import CoreFoundation

enum AZIndexGrouping {

    /// 取名称索引字母：A-Z（小写转大写）/ 中文转拼音首字母 / 其它归 "#"
    nonisolated static func indexLetter(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "#" }
        let s = String(first)
        if s.range(of: "^[A-Za-z]", options: .regularExpression) != nil {
            return s.uppercased()
        }
        // 中文（或其它非拉丁文字）转拼音后取首字母
        let mutable = NSMutableString(string: s)
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        if let c = (mutable as String).first, c.isASCII, c.isLetter {
            return String(c).uppercased()
        }
        return "#"
    }

    /// 全量字典序排序（不分组）——Store 与简单列表用这个
    nonisolated static func sortedByName<T>(_ items: [T], name: (T) -> String) -> [T] {
        items.sorted { lhs, rhs in
            let l = name(lhs), r = name(rhs)
            let ll = indexLetter(for: l), rl = indexLetter(for: r)
            if ll != rl { return Self.sortKey(ll) < Self.sortKey(rl) }
            return l.localizedStandardCompare(r) == .orderedAscending
        }
    }

    /// 按索引字母分组：组按 # → A → … → Z，组内按本地化规则排序
    nonisolated static func groups<T>(_ items: [T], name: (T) -> String) -> [(letter: String, items: [T])] {
        let buckets = Dictionary(grouping: items, by: { indexLetter(for: name($0)) })
        let order = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        return order.compactMap { letter -> (letter: String, items: [T])? in
            guard let bucket = buckets[letter] else { return nil }
            let sorted = bucket.sorted {
                name($0).localizedStandardCompare(name($1)) == .orderedAscending
            }
            return (letter, sorted)
        }
    }

    /// 搜索匹配：名称或任一别名命中即算（空查询全匹配）
    nonisolated static func matches(name: String, aliases: [String], query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(q)
            || aliases.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// "#" 排在 A 之前，其余按字母序
    nonisolated private static func sortKey(_ letter: String) -> Int {
        letter == "#" ? -1 : Int(letter.unicodeScalars.first?.value ?? 0)
    }
}
