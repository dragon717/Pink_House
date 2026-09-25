//
//  CatalogBalanceDueApproximation.swift
//  ItemManager
//
//  大致尾款时间 → 固定具体日期 的估算（2026-09-25 需求三；nonisolated 可单测）。
//
//  ── 需求原文 ──
//
//  「运营给出的尾款时间为大致描述（如上旬、中旬、中下旬、下旬），系统需依据该大致时间
//    估算并固定为一个具体的尾款日期，而不是直接展示模糊描述，也不是以用户当天添加的
//    日期作为尾款时间；估算时以约一个月为基准，结合上旬/中旬/下旬等描述推算出大致日期。」
//
//  ── 三个设计决定（改动前先读这里） ──
//
//  1. **锚点是运营侧事实，绝不是用户的加购日期**：估算锚点由调用方传运营侧事实
//     （系列 `reservationEndAt` → 预约销售记录 `endAt`）。加购当天是「用户什么时候
//     决定入橱」，与运营的收款安排无关，拿它当尾款基准就是编造事实。
//
//  2. **同一输入 → 同一日期（估一次就固定）**：估算完全由
//     `声明文本 + 锚点` 决定，不掺入 `Date()`。这样加购时估一次、之后每次同步
//     重算结果都相同，「固定为一个具体的尾款日期」天然成立，无需额外落盘去重。
//
//  3. **缺依据就不猜**：文本里没有旬关键词（如「大货到后 1 个月」「春节前」）
//     → 返回 `nil`，调用方维持既有行为。与 `CatalogSeriesBalanceDue` 的
//     「大致粒度不解析成日期」并不矛盾——那条守的是**运营端的自动流转**
//     （不能拿猜测驱动状态机）；本模块只服务**用户侧记录用的估算窗口**，
//     且估算结果通过备注留痕（如实告知「这是估算」），不回写运营数据。
//
//  ── 估算规则 ──
//
//    · 目标月：文本带显式月份（「10月」「2027年3月」「十月」）→ 用那个月
//      （未带年份且该月今年已过 → 顺延一年）；未带 → 锚点所在月 + 1
//      （「以约一个月为基准」）。
//    · 目标日：上旬/月初 → 10 日；中旬 → 20 日；中下旬 → 25 日；
//      下旬/月末/月底 → 当月最后一天。
//    · 估算只向后看：候选日期早于锚点 → 整月推进直到不早于锚点
//      （锚点 7-15 +「上旬」→ 8-10，而不是已过去的 7-10）。
//    · 落到当天 12:00：日期型估算不带时刻语义，正午可避开夏令时/日界歧义，
//      展示时也不会被时区偏移挪到前一天。
//

import Foundation

nonisolated enum CatalogBalanceDueApproximation {

    // MARK: - 单个文本 → 具体日期

    /// 把一段大致时间文本估算成固定具体日期；无旬关键词 → `nil`（缺依据不猜）。
    ///
    /// - Parameters:
    ///   - text: 运营原文（如「上旬」「中下旬」「10月上旬」「月底」）
    ///   - anchor: 估算锚点（预约结束时间等运营侧事实）
    ///   - calendar: 日历（测试可注入固定时区）
    static func estimatedDate(text: String,
                              anchor: Date,
                              calendar: Calendar = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let dayRule = dayRule(in: trimmed) else { return nil }

        // ① 目标月：显式月份优先；未带 → 锚点所在月 + 1（约一个月为基准）
        let anchorYear = calendar.component(.year, from: anchor)
        let anchorMonth = calendar.component(.month, from: anchor)
        var year = anchorYear
        var month = anchorMonth
        if let explicit = explicitMonth(in: trimmed) {
            month = explicit.month
            if let explicitYear = explicit.year {
                year = explicitYear
            } else if anchorMonth > explicit.month {
                // 未带年份、但这个月今年已经过了 → 指的是明年这个月
                year = anchorYear + 1
            }
        } else if let next = calendar.date(byAdding: .month, value: 1, to: anchor) {
            year = calendar.component(.year, from: next)
            month = calendar.component(.month, from: next)
        }

        // ② 目标日：旬规则；下旬 = 当月最后一天
        func candidateDate(year: Int, month: Int) -> Date? {
            switch dayRule {
            case .fixed(let day):
                return noonDate(year: year, month: month, day: day, calendar: calendar)
            case .lastDayOfMonth:
                guard let firstOfNext = noonDate(year: year, month: month, day: 1, calendar: calendar),
                      let interval = calendar.dateInterval(of: .month, for: firstOfNext),
                      let lastDay = calendar.date(byAdding: DateComponents(day: -1), to: interval.end)
                else { return nil }
                return noonDate(year: calendar.component(.year, from: lastDay),
                                month: calendar.component(.month, from: lastDay),
                                day: calendar.component(.day, from: lastDay),
                                calendar: calendar)
            }
        }

        // ③ 估算只向后看：候选早于锚点 → 整月推进直到不早于锚点
        var candidate = candidateDate(year: year, month: month)
        var guardCounter = 0
        while let date = candidate, date < anchor, guardCounter < 36 {
            month += 1
            if month > 12 { month = 1; year += 1 }
            candidate = candidateDate(year: year, month: month)
            guardCounter += 1
        }
        return candidate
    }

    // MARK: - 系列声明 → 尾款窗口（加购与同步的唯一共用口径）

    /// 「尾款窗口」：start/end + 给备注用的来源说明。
    nonisolated struct Window: Equatable {
        var start: Date
        var end: Date
        /// 来源说明（写进 Clothing.note 留痕，如「按运营描述「10月上旬」以约一个月为基准估算」）
        var basis: String
    }

    /// 从系列尾款期声明解出**具体**窗口。
    ///
    ///   · 未声明（kind == nil）→ `nil`；
    ///   · 具体（exact）→ 直接用 `at` / `endAt`（运营给的是事实，不需要估算）；
    ///   · 大致（approximate）→ 按 `anchor` 估算成固定具体日期；
    ///     文本无旬关键词或锚点缺失 → `nil`（调用方维持旧行为）。
    ///
    /// 加购（`ShopCatalogWardrobeDraftBuilder`）与同步（`ShopCatalogWardrobeBalanceSync`）
    /// 都必须走这里，禁止各自再写一套解析。
    static func declaredWindow(kind: CatalogBalanceDueKind?,
                               text: String?,
                               endText: String?,
                               at: Date?,
                               endAt: Date?,
                               anchor: Date?,
                               calendar: Calendar = .current) -> Window? {
        switch kind {
        case .exact:
            guard let at else { return nil }
            return Window(start: at,
                          end: endAt ?? at,
                          basis: "按运营声明的具体尾款时间")
        case .approximate:
            let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let anchor else { return nil }
            guard let start = estimatedDate(text: trimmed, anchor: anchor, calendar: calendar) else {
                return nil
            }
            var end = start
            let trimmedEnd = (endText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedEnd.isEmpty,
               let estimatedEnd = estimatedDate(text: trimmedEnd, anchor: anchor, calendar: calendar) {
                end = max(start, estimatedEnd)
            }
            return Window(start: start,
                          end: end,
                          basis: "按运营描述「\(trimmed)」以约一个月为基准估算")
        case .none:
            return nil
        }
    }

    /// `CatalogSeries` 便捷入口（唯一读法）
    static func declaredWindow(of series: CatalogSeries,
                               anchor: Date?,
                               calendar: Calendar = .current) -> Window? {
        declaredWindow(kind: series.balanceDueKind,
                       text: series.balanceDueText,
                       endText: series.balanceDueEndText,
                       at: series.balanceDueAt,
                       endAt: series.balanceDueEndAt,
                       anchor: anchor,
                       calendar: calendar)
    }

    // MARK: - 内部：旬关键词

    /// 旬规则。旬关键词判定长词优先（先「中下旬」再「中旬/下旬」）；
    /// 「月初」= 上旬同义、「月末/月底」= 下旬同义——都是运营常写的同义说法。
    private enum DayRule {
        case fixed(Int)
        case lastDayOfMonth
    }

    private static func dayRule(in text: String) -> DayRule? {
        if text.contains("中下旬") { return .fixed(25) }
        if text.contains("上旬") || text.contains("月初") { return .fixed(10) }
        if text.contains("中旬") { return .fixed(20) }
        if text.contains("下旬") || text.contains("月末") || text.contains("月底") {
            return .lastDayOfMonth
        }
        return nil
    }

    // MARK: - 内部：显式月份解析

    /// 解析显式月份：「2027年3月」「10月」「十月」「十二月」。找不到 → `nil`。
    private static func explicitMonth(in text: String) -> (year: Int?, month: Int)? {
        // ① 阿拉伯数字（可带年份）
        if let match = firstMatch(pattern: "(\\d{4})\\s*年\\s*(\\d{1,2})\\s*月", in: text) {
            if let year = Int(match[0]), let month = Int(match[1]), (1...12).contains(month) {
                return (year, month)
            }
        }
        if let match = firstMatch(pattern: "(\\d{1,2})\\s*月", in: text) {
            if let month = Int(match[0]), (1...12).contains(month) {
                return (nil, month)
            }
        }
        // ② 中文数字月份（一~十二月）
        if let match = firstMatch(pattern: "([一二三四五六七八九十]{1,2})月", in: text) {
            if let month = chineseMonthNumber(match[0]) {
                return (nil, month)
            }
        }
        return nil
    }

    /// 中文数字月份：一~九 → 1~9；十 → 10；十一/十二 → 11/12。
    /// 其余组合（「十三」及乱序）不可能是月份 → nil。
    private static func chineseMonthNumber(_ raw: String) -> Int? {
        let digits: [String: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
                                     "六": 6, "七": 7, "八": 8, "九": 9]
        switch raw {
        case "十":
            return 10
        default:
            if raw.hasPrefix("十"), let tail = digits[String(raw.dropFirst())] {
                return 10 + tail <= 12 ? 10 + tail : nil
            }
            return digits[raw]
        }
    }

    // MARK: - 内部：日期工具

    /// 该年该月 `day` 日的 12:00（日界/夏令时歧义回避）
    private static func noonDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        return calendar.date(from: comps)
    }

    private static func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1 else { return nil }
        var groups: [String] = []
        for index in 1..<match.numberOfRanges {
            guard let group = Range(match.range(at: index), in: text) else { return nil }
            groups.append(String(text[group]))
        }
        return groups
    }
}
