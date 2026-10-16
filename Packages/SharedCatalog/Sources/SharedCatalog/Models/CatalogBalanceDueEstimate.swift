// Mac 录入预览与 iOS 入橱、同步共用的大致尾款估算。
// 各旬取中间日固定估算：上旬 / 月初 = 5 日，中旬 = 15 日，下旬 = 25 日。
// 中下旬取 20 日；明确写「月末 / 月底」仍指当月最后一天。
// 常见节日前按节日当天提前六天估算。明确年月可独立估算；不使用入橱当天。
import Foundation

public enum CatalogBalanceDueEstimate {

    // MARK: - 单个文本 → 具体日期

    /// 把大致时间文本估算成固定日期：月份与旬，或可识别的节日前描述。
    ///
    /// - Parameters:
    ///   - text: 运营原文（如「上旬」「中下旬」「10月上旬」「月底」）
    ///   - anchor: 估算锚点（预约结束时间等运营侧事实）
    ///   - calendar: 日历（测试可注入固定时区）
    public static func estimatedDate(text: String,
                              anchor: Date?,
                              calendar: Calendar = .current) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let holiday = CatalogHolidayEstimate.resolve(text: trimmed, anchor: anchor, calendar: calendar) {
            return holiday.date
        }
        guard !trimmed.isEmpty, let dayRule = dayRule(in: trimmed) else { return nil }

        let explicit = explicitMonth(in: trimmed)
        // 明确写出年月时，不依赖预约结束，也不把已过去的日期挪到别的月份。
        guard let reference = anchor ?? explicit.flatMap({ value in
            value.year.flatMap { noonDate(year: $0, month: value.month, day: 1, calendar: calendar) }
        }) else { return nil }
        let anchorYear = calendar.component(.year, from: reference)
        let anchorMonth = calendar.component(.month, from: reference)
        var year = anchorYear
        var month = anchorMonth
        if let explicit {
            month = explicit.month
            year = explicit.year ?? (anchorMonth > month ? anchorYear + 1 : anchorYear)
        } else if let next = calendar.date(byAdding: .month, value: 1, to: reference) {
            year = calendar.component(.year, from: next)
            month = calendar.component(.month, from: next)
        }

        // ② 目标日：各旬取固定中间日；明确写月末才取当月最后一天。
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

        var candidate = candidateDate(year: year, month: month)
        // 只给月份时，过去的同月顺延一年；显式月份始终保留。
        if let explicit, explicit.year == nil, let date = candidate, date < reference {
            candidate = candidateDate(year: year + 1, month: month)
        }
        return candidate
    }

    /// 编辑大致时间时固定年份，避免用户跨年入橱或后续同步时日期漂移。
    /// 原文保留在目录字段，供计算的文本给省略年份的月份或节日固定年份。
    public static func yearQualifiedText(_ text: String?, reference: Date?,
                                         calendar: Calendar = .current) -> String? {
        guard let text, let reference else { return text }
        if let holiday = CatalogHolidayEstimate.resolve(text: text, anchor: reference, calendar: calendar) {
            guard !holiday.hasExplicitYear else { return text }
            if let relative = holiday.relativeYearWord {
                return text.replacingOccurrences(of: relative, with: "\(holiday.festivalYear)年")
            }
            // 元旦前六天会落在上一公历年，固定的是节日年份，不能用估算日的年份。
            return "\(holiday.festivalYear)年\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        guard let explicit = explicitMonth(in: text), explicit.year == nil,
              let date = estimatedDate(text: text, anchor: reference, calendar: calendar) else { return text }
        return "\(calendar.component(.year, from: date))年\(text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    // MARK: - 系列声明 → 尾款窗口（加购与同步的唯一共用口径）

    /// 「尾款窗口」：start/end + 给确认页用的来源说明。
    public struct Window: Equatable, Sendable {
        public var start: Date
        public var end: Date
        /// 来源说明（供确认页展示，如「按运营描述「10月上旬」以约一个月为基准估算」）
        public var basis: String
    }

    /// 从系列尾款期声明解出**具体**窗口。
    ///
    ///   · 未声明（kind == nil）→ `nil`；
    ///   · 具体（exact）→ 直接用 `at` / `endAt`（运营给的是事实，不需要估算）；
    ///   · 大致（approximate）→ 按 `anchor` 估算成固定具体日期；
    ///     无可识别描述或推算年份所需的基准缺失 → `nil`。
    ///
    /// 加购（`ShopCatalogWardrobeDraftBuilder`）与同步（`ShopCatalogWardrobeBalanceSync`）
    /// 都必须走这里，禁止各自再写一套解析。
    public static func declaredWindow(kind: CatalogBalanceDueKind?,
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
            guard !trimmed.isEmpty else { return nil }
            guard let start = estimatedDate(text: trimmed, anchor: anchor, calendar: calendar) else {
                return nil
            }
            var end = start
            let trimmedEnd = (endText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let durationEnd = durationEndDate(text: trimmedEnd, start: start, calendar: calendar)
            if let durationEnd {
                end = durationEnd
            } else if !trimmedEnd.isEmpty,
               let estimatedEnd = estimatedDate(text: trimmedEnd, anchor: anchor, calendar: calendar) {
                end = max(start, estimatedEnd)
            }
            let holiday = CatalogHolidayEstimate.resolve(text: trimmed, anchor: anchor, calendar: calendar)
            var basis = holiday.map { "按运营描述「\(trimmed)」在\($0.name)前\(CatalogHolidayEstimate.leadDays)天估算" }
                ?? (explicitMonth(in: trimmed) == nil
                ? "按运营描述「\(trimmed)」以约一个月为基准估算"
                : "按运营描述「\(trimmed)」的月份和旬估算")
            if durationEnd != nil { basis += "；结束按开始后「\(trimmedEnd)」推算" }
            return Window(start: start,
                          end: end,
                          basis: basis)
        case .none:
            return nil
        }
    }

    // MARK: - 内部：结束时长（从尾款开始日算，不从录入日或预约结束日算）

    private static func durationEndDate(text: String, start: Date, calendar: Calendar) -> Date? {
        let compact = text.filter { !$0.isWhitespace }
        if compact == "半个月" {
            return calendar.date(byAdding: .day, value: 15, to: start)
        }
        // 整段匹配，避免把「大货到后一个月」「十月上旬」误当作支付时长。
        guard let parts = firstMatch(pattern: "^([0-9]{1,4}|[一二两三四五六七八九十]{1,3})(天|日|个月|月|周)$", in: compact),
              let value = Int(parts[0]) ?? chineseDurationNumber(parts[0]), value > 0 else { return nil }
        switch parts[1] {
        case "天", "日":
            guard value <= 3660 else { return nil }
            return calendar.date(byAdding: .day, value: value, to: start)
        case "周":
            guard value <= 520 else { return nil }
            return calendar.date(byAdding: .day, value: value * 7, to: start)
        case "个月", "月":
            guard value <= 120 else { return nil }
            // 日历月保留月份含义：1 月 31 日的一个月后是 2 月末，不固定为 30 天。
            return calendar.date(byAdding: .month, value: value, to: start)
        default: return nil
        }
    }

    private static func chineseDurationNumber(_ raw: String) -> Int? {
        if raw == "两" { return 2 }
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return (1...99).first { number in
            let text = number < 10 ? digits[number]
                : (number >= 20 ? digits[number / 10] : "") + "十" + digits[number % 10]
            return text == raw
        }
    }

    /// `CatalogSeries` 便捷入口（唯一读法）
    public static func declaredWindow(of series: CatalogSeries,
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
    /// 「月初」沿用上旬中间日；「月末/月底」保留月底含义。
    private enum DayRule {
        case fixed(Int)
        case lastDayOfMonth
    }

    private static func dayRule(in text: String) -> DayRule? {
        if text.contains("中下旬") { return .fixed(20) }
        if text.contains("上旬") || text.contains("月初") { return .fixed(5) }
        if text.contains("中旬") { return .fixed(15) }
        if text.contains("下旬") { return .fixed(25) }
        if text.contains("月末") || text.contains("月底") {
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
