import Foundation

/// 节日前的大致尾款日。固定取用户允许的 5–7 天中间值，不依赖当前时间。
enum CatalogHolidayEstimate {
    static let leadDays = 6

    struct Result {
        let date: Date
        let festivalYear: Int
        let name: String
        let hasExplicitYear: Bool
        let relativeYearWord: String?
    }

    private enum Rule {
        case solar(Int, Int)
        case lunar(Int, Int)
        case lunarNewYearsEve
    }

    private struct Festival {
        let name: String
        let aliases: [String]
        let rule: Rule
    }

    private static let festivals: [Festival] = [
        .init(name: "圣诞节", aliases: ["圣诞节", "圣诞", "聖誕節", "聖誕"], rule: .solar(12, 25)),
        .init(name: "平安夜", aliases: ["平安夜"], rule: .solar(12, 24)),
        .init(name: "元旦", aliases: ["元旦节", "元旦", "元旦節"], rule: .solar(1, 1)),
        .init(name: "国庆节", aliases: ["国庆节", "国庆", "國慶節", "國慶"], rule: .solar(10, 1)),
        .init(name: "劳动节", aliases: ["五一劳动节", "劳动节", "五一", "勞動節"], rule: .solar(5, 1)),
        .init(name: "儿童节", aliases: ["六一儿童节", "儿童节", "六一", "兒童節"], rule: .solar(6, 1)),
        .init(name: "妇女节", aliases: ["妇女节", "婦女節"], rule: .solar(3, 8)),
        .init(name: "情人节", aliases: ["情人节", "情人節"], rule: .solar(2, 14)),
        .init(name: "春节", aliases: ["春节", "春節", "农历新年", "農曆新年"], rule: .lunar(1, 1)),
        .init(name: "除夕", aliases: ["除夕"], rule: .lunarNewYearsEve),
        .init(name: "元宵节", aliases: ["元宵节", "元宵", "元宵節"], rule: .lunar(1, 15)),
        .init(name: "端午节", aliases: ["端午节", "端午", "端午節"], rule: .lunar(5, 5)),
        .init(name: "七夕", aliases: ["七夕情人节", "七夕情人節", "七夕节", "七夕", "七夕節"], rule: .lunar(7, 7)),
        .init(name: "中秋节", aliases: ["中秋节", "中秋", "中秋節"], rule: .lunar(8, 15)),
        .init(name: "重阳节", aliases: ["重阳节", "重阳", "重陽節", "重陽"], rule: .lunar(9, 9))
    ]

    static func resolve(text: String, anchor: Date?, calendar: Calendar) -> Result? {
        var matches = festivals.filter { festival in
            festival.aliases.contains { alias in
                // 仅解释“节前 / 节之前 / 节前夕”，不把节后、前后或明确的一月/一周偏移当六天。
                let pattern = NSRegularExpression.escapedPattern(for: alias)
                    + "\\s*(?:之前|以前|前夕|前)(?![后後0-9０-９一二三四五六七八九十两兩几幾半])"
                return text.range(of: pattern, options: .regularExpression) != nil
            }
        }
        // “七夕情人节”是农历七夕，不是公历二月十四日。
        if matches.contains(where: { $0.name == "七夕" }) { matches.removeAll { $0.name == "情人节" } }
        guard matches.count == 1, let festival = matches.first else { return nil }

        var civil = Calendar(identifier: .gregorian)
        civil.timeZone = calendar.timeZone
        let explicitYear = text.range(of: "(?<![0-9])[0-9]{4}\\s*年", options: .regularExpression)
            .flatMap { Int(text[$0].prefix(4)) }
        let relative = [("明年", 1), ("后年", 2), ("後年", 2), ("今年", 0), ("去年", -1), ("前年", -2)]
            .first { text.contains($0.0) }
        guard let year = explicitYear ?? anchor.map({ civil.component(.year, from: $0) + (relative?.1 ?? 0) })
        else { return nil }
        let pinnedYear = explicitYear != nil || relative != nil
        var festivalYear = year
        guard var holiday = festivalDate(festival.rule, year: festivalYear, calendar: civil) else { return nil }
        // 按节日本身是否已过选择年份。临近节日时，估算日已过也不能跳到明年。
        if !pinnedYear, let anchor, civil.startOfDay(for: holiday) < civil.startOfDay(for: anchor) {
            festivalYear += 1
            guard let next = festivalDate(festival.rule, year: festivalYear, calendar: civil) else { return nil }
            holiday = next
        }
        guard let date = civil.date(byAdding: .day, value: -leadDays, to: holiday) else { return nil }
        return Result(date: date, festivalYear: festivalYear, name: festival.name,
                      hasExplicitYear: explicitYear != nil, relativeYearWord: relative?.0)
    }

    private static func festivalDate(_ rule: Rule, year: Int, calendar: Calendar) -> Date? {
        switch rule {
        case .solar(let month, let day):
            return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        case .lunar(let month, let day):
            // 中国农历按东八区换算，随后把公历月日放进调用方时区，旅行也不改变节日日期。
            var chinese = Calendar(identifier: .chinese)
            chinese.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            var chinaCivil = Calendar(identifier: .gregorian)
            chinaCivil.timeZone = chinese.timeZone
            guard let midyear = chinaCivil.date(from: DateComponents(year: year, month: 7, day: 1, hour: 12)) else { return nil }
            var components = chinese.dateComponents([.era, .year], from: midyear)
            components.month = month; components.day = day; components.hour = 12
            components.isLeapMonth = false
            guard let lunarDate = chinese.date(from: components),
                  chinaCivil.component(.year, from: lunarDate) == year else { return nil }
            let civilDay = chinaCivil.dateComponents([.year, .month, .day], from: lunarDate)
            return calendar.date(from: DateComponents(year: civilDay.year, month: civilDay.month,
                                                     day: civilDay.day, hour: 12))
        case .lunarNewYearsEve:
            guard let newYear = festivalDate(.lunar(1, 1), year: year, calendar: calendar) else { return nil }
            return calendar.date(byAdding: .day, value: -1, to: newYear)
        }
    }
}
