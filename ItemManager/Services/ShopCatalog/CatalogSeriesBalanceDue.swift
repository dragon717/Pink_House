//
//  CatalogSeriesBalanceDue.swift
//  ItemManager
//
//  「尾款时间」（2026-09-24 需求四）的唯一口径：录入校验、存储归一、展示文本、到期判定。
//
//  ── 需求原文 ──
//
//  「当系列的系列状态为预约中时，需新增尾款时间填写项，支持填写大致时间或具体时间，
//    并说明该字段的校验规则、存储方式及联动逻辑。」
//
//  ── 三个设计决定（都写在类型里，后续改动先读这里） ──
//
//  1. **两种粒度分开存，不共用字段**：`balanceDueKind` 声明粒度，
//     `balanceDueText` 只承载「大致」的原文，`balanceDueAt` 只承载「具体」的时刻。
//     合成一个字符串会让「展示」与「能否自动流转」互相污染 —— 那正是
//     「文本里恰好有 2027-03 就被当成时间点」这类假判定。切换粒度时**另一种清空**：
//     两个字段同时有值，界面就得替用户挑一个说，一定会说错。
//
//  2. **只有「具体时间」能驱动状态流转**：大致时间（「大货到后 1 个月」/「春节前」）
//     是人的描述，不是时间点。拿它做 `now > x` 就是把猜测当事实。所以
//     `isDue` 对 `approximate` **恒为 false**（与既有「缺依据就不猜」口径一致）。
//
//  3. **非必填**：不填 = 不启用尾款时间，阶段流转完全按既有规则走
//     （预约中 → 过了预约结束时间 → 预约已结束），旧数据与旧行为零变化。
//
//  ── 2026-09-24 需求五：尾款时间 → 尾款**期**（开始 + 结束） ──
//
//  用户要求「『预约中』和『尾款中』都必须同时包含开始时间和结束时间，不能只提供开始时间」。
//  于是本模块从「一个时间点」升级成「一段区间」，两种粒度都要有起止：
//
//    大致：`balanceDueText`（起）+ `balanceDueEndText`（止，选填）
//    具体：`balanceDueAt`（起，**key 不变**）+ `balanceDueEndAt`（止，选填）
//
//  **「起」是必填、「止」是选填** —— 三条理由：
//    · 起是自动流转的唯一依据（`isDue`），必须确定；止只用于展示与提醒；
//    · 止如果必填，存量系列（只有起、没有止）一打开表单就会因为空值报错，
//      「什么都没改也保存不了」；
//    · 缺止就给一个默认日期 = 替运营编一条事实，与全项目「缺依据就不猜」冲突。
//  表单上用「是否设置结束时间」开关显式声明 —— 与加购弹窗的「已公布尾款时间」同一写法。
//
//  **止不参与任何自动流转**：尾款期的出口只能是运营声明
//  （`CatalogSeriesSalePhaseResolver.balancePhaseExitsByDeclarationOnly`），
//  因为「尾款收齐没有」在这套数据里没有可判定依据。到点只给一条**提示**（`isEnded`）。
//
//  ── 与 `reservationEndAt` 的关系 ──
//
//  `reservationEndAt` 是「预约（收定金）窗口关闭」的时刻，本字段是「开始收尾款」的时间。
//  业务上尾款不可能早于预约结束开始，所以**具体时间必须严格晚于预约结束时间**；
//  预约结束时间未填时不做这一比对（没有基准就不猜，与既有口径相同）。
//
//  ── 隔离约定 ──
//
//  纯逻辑（校验 / 归一 / 到期）是 `nonisolated`，可单测；
//  依赖 `LanguageManager.shared.locale` 的展示文案在 `@MainActor` 扩展里，
//  不把本地化拖进纯逻辑（否则 nonisolated 上下文调用 `appLocalized` 直接编译失败）。
//

import Foundation

nonisolated enum CatalogSeriesBalanceDue {

    /// 大致时间的长度上限（超出多半是误把整段说明粘进来了）
    static let maxTextLength = 30

    // MARK: - 校验（表单唯一入口）

    /// 校验尾款期输入（唯一入口）。返回 `nil` = 通过；否则返回**可直接显示**的中文错误文案。
    ///
    /// 规则（逐条对应需求的「校验规则」）：
    ///   1. `kind == nil`（未填写）→ 通过：非必填，且是「清除已填尾款期」的合法表达；
    ///   2. 大致时间：`text` 非空、长度 ≤ `maxTextLength`；
    ///      `endText` 选填，填了才校验长度；**两者都不解析成日期**；
    ///   3. 具体时间：`exactAt`（开始）必须**严格晚于**预约结束时间（预约结束时间已填时）；
    ///      `endDeclared == true` 时 `endAt` 不得早于 `exactAt`（同日允许 —— 那是「当天收完」）；
    ///      开始时间早于当前时间**不拦** —— 那表示尾款已经开始收，读完即自动流转为「尾款中」，
    ///      拦下来反而与自动流转矛盾（与 `reservationEndAt` 的「只提示不拦」同口径）。
    static func validationErrorText(kind: CatalogBalanceDueKind?,
                                    text: String,
                                    endText: String,
                                    exactAt: Date,
                                    endAt: Date,
                                    endDeclared: Bool,
                                    reservationEndAt: Date?) -> String? {
        guard let kind else { return nil }
        switch kind {
        case .approximate:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "请填写大致时间（如「大货到后 1 个月」「2027 年春节前」）"
            }
            if trimmed.count > maxTextLength {
                return "大致时间请控制在 \(maxTextLength) 字以内（现在是 \(trimmed.count) 字）"
            }
            let endTrimmed = endText.trimmingCharacters(in: .whitespacesAndNewlines)
            if endTrimmed.count > maxTextLength {
                return "尾款结束（大致）请控制在 \(maxTextLength) 字以内（现在是 \(endTrimmed.count) 字）"
            }
            return nil
        case .exact:
            if let reservationEndAt, exactAt <= reservationEndAt {
                return "尾款时间必须晚于预约结束时间（预约结束：\(shortDateText(reservationEndAt))）"
            }
            if endDeclared, endAt < exactAt {
                return "尾款结束时间不能早于尾款开始时间（开始：\(shortDateText(exactAt))）"
            }
            return nil
        }
    }

    /// 旧签名（不涉及区间）：`validationErrorText(kind:text:exactAt:reservationEndAt:)`。
    /// **保留** —— 既有调用方与既有单测的行为逐字不变（等于「没有结束时间」的区间）。
    static func validationErrorText(kind: CatalogBalanceDueKind?,
                                    text: String,
                                    exactAt: Date,
                                    reservationEndAt: Date?) -> String? {
        validationErrorText(kind: kind,
                            text: text,
                            endText: "",
                            exactAt: exactAt,
                            endAt: exactAt,
                            endDeclared: false,
                            reservationEndAt: reservationEndAt)
    }

    // MARK: - 存储归一（唯一落库形态）

    /// 把表单五项归一化成存储字段。**切换粒度会清空另一种**（见文件头决定 1）：
    ///   · `approximate` → 只留 text / endText，两个日期都清空；
    ///   · `exact`       → 只留两个日期（`endDeclared == false` 时结束时间也清空），文本清空；
    ///   · `nil`         → 五个字段全清（用户明确「不填」）。
    static func stored(kind: CatalogBalanceDueKind?,
                       text: String,
                       endText: String,
                       exactAt: Date,
                       endAt: Date,
                       endDeclared: Bool)
        -> (kind: CatalogBalanceDueKind?, text: String?, endText: String?, at: Date?, endAt: Date?) {
        switch kind {
        case .none:
            return (nil, nil, nil, nil, nil)
        case .approximate:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let endTrimmed = endText.trimmingCharacters(in: .whitespacesAndNewlines)
            return (.approximate,
                    trimmed.isEmpty ? nil : trimmed,
                    endTrimmed.isEmpty ? nil : endTrimmed,
                    nil, nil)
        case .exact:
            return (.exact, nil, nil, exactAt, endDeclared ? endAt : nil)
        }
    }

    /// 旧签名（不涉及区间）
    static func stored(kind: CatalogBalanceDueKind?,
                       text: String,
                       exactAt: Date) -> (kind: CatalogBalanceDueKind?, text: String?, at: Date?) {
        let result = stored(kind: kind,
                            text: text,
                            endText: "",
                            exactAt: exactAt,
                            endAt: exactAt,
                            endDeclared: false)
        return (result.kind, result.text, result.at)
    }

    // MARK: - 回填（存储 → 表单）

    /// 存储字段回填成表单件套；缺值给一个**可编辑的起点**而不是 nil，
    /// 免得 `DatePicker` 要一个非可选值。
    ///
    /// `hasEnd`：是否声明了结束时间。**由存储值本身决定**（没有结束 = 开关关闭），
    /// 不额外存一个布尔 —— 两份真值迟早会不一致。
    static func formValues(kind: CatalogBalanceDueKind?,
                           text: String?,
                           endText: String?,
                           at: Date?,
                           endAt: Date?,
                           fallbackExactAt: Date)
        -> (kind: CatalogBalanceDueKind?, text: String, endText: String,
            exactAt: Date, endAt: Date, hasEnd: Bool) {
        (kind,
         text ?? "",
         endText ?? "",
         at ?? fallbackExactAt,
         endAt ?? at ?? fallbackExactAt,
         endAt != nil)
    }

    /// 旧签名（不涉及区间）
    static func formValues(kind: CatalogBalanceDueKind?,
                           text: String?,
                           at: Date?,
                           fallbackExactAt: Date) -> (kind: CatalogBalanceDueKind?, text: String, exactAt: Date) {
        let result = formValues(kind: kind,
                                text: text,
                                endText: nil,
                                at: at,
                                endAt: nil,
                                fallbackExactAt: fallbackExactAt)
        return (result.kind, result.text, result.exactAt)
    }

    // MARK: - 到期判定（自动流转的唯一依据）

    /// 是否已到（或已过）尾款时间。**只有具体时间可判定**：大致粒度恒为 false。
    static func isDue(kind: CatalogBalanceDueKind?, at: Date?, now: Date) -> Bool {
        guard kind == .exact, let at else { return false }
        return now >= at
    }

    /// `CatalogSeries` 便捷入口（视图/服务层统一读这里，别自己写 `if now > at`）
    static func isDue(of series: CatalogSeries, now: Date) -> Bool {
        isDue(kind: series.balanceDueKind, at: series.balanceDueAt, now: now)
    }

    /// 尾款期是否**已经过了声明的结束时间**。
    ///
    /// ⚠️ **只用于提示，绝不驱动流转**：尾款期的出口只能是运营声明
    /// （见 `CatalogSeriesSalePhaseResolver.balancePhaseExitsByDeclarationOnly`）——
    /// 「结束时间到了」不等于「尾款收齐了」。大致粒度恒为 false（不是时间点）。
    static func isEnded(kind: CatalogBalanceDueKind?, at endAt: Date?, now: Date) -> Bool {
        guard kind == .exact, let endAt else { return false }
        return now > endAt
    }

    /// `CatalogSeries` 便捷入口
    static func isEnded(of series: CatalogSeries, now: Date) -> Bool {
        isEnded(kind: series.balanceDueKind, at: series.balanceDueEndAt, now: now)
    }

    /// 是否填过尾款期（大致或具体都算「填过」——用于列表上的展示判定）
    static func isPresent(kind: CatalogBalanceDueKind?, text: String?, at: Date?) -> Bool {
        switch kind {
        case .approximate: return !(text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .exact: return at != nil
        case .none: return false
        }
    }

    /// 是否**声明了结束时间**（两种粒度任一；用于决定展示「尾款时间」还是「尾款期」）
    static func hasDeclaredEnd(endText: String?, at endAt: Date?) -> Bool {
        if !(endText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return endAt != nil
    }

    // MARK: - 展示（纯逻辑部分：值文本）

    /// 值文本（不含「尾款时间：」这类前缀，前缀由调用方本地化）：
    ///   · 大致 → 「起 — 止（大致）」，止未填则只有「起（大致）」；
    ///   · 具体 → 按 locale 格式化到分，「起 — 止」，止未填则只有「起」。
    /// 未填 → `nil`（调用方据此不渲染任何尾款期行）。
    static func valueText(kind: CatalogBalanceDueKind?,
                          text: String?,
                          endText: String?,
                          at: Date?,
                          endAt: Date?,
                          locale: Locale) -> String? {
        switch kind {
        case .approximate:
            let start = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !start.isEmpty else { return nil }
            let end = (endText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let core = end.isEmpty ? start : "\(start) — \(end)"
            return core + "（大致）"
        case .exact:
            guard let at else { return nil }
            let start = Self.dateText(at, locale: locale)
            guard let endAt else { return start }
            return "\(start) — \(Self.dateText(endAt, locale: locale))"
        case .none:
            return nil
        }
    }

    /// 旧签名（不涉及区间）
    static func valueText(kind: CatalogBalanceDueKind?,
                          text: String?,
                          at: Date?,
                          locale: Locale) -> String? {
        valueText(kind: kind,
                  text: text,
                  endText: nil,
                  at: at,
                  endAt: nil,
                  locale: locale)
    }

    /// 单个时刻按 locale 格式化到分（例如「2027年3月15日 14:00」）
    private static func dateText(_ date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar.current
        formatter.setLocalizedDateFormatFromTemplate("yMMMdjm")
        return formatter.string(from: date)
    }

    /// 校验错误文案里用的短日期（年-月-日），固定模板，不跟随语言模板拼装
    static func shortDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - 文案（跟随默认 MainActor 隔离）

extension CatalogSeriesBalanceDue {

    /// 值文本（用 App 当前 locale）
    static func valueText(of series: CatalogSeries) -> String? {
        valueText(kind: series.balanceDueKind,
                  text: series.balanceDueText,
                  endText: series.balanceDueEndText,
                  at: series.balanceDueAt,
                  endAt: series.balanceDueEndAt,
                  locale: LanguageManager.shared.locale)
    }

    /// 是否声明了结束时间（`CatalogSeries` 便捷入口）
    static func hasDeclaredEnd(of series: CatalogSeries) -> Bool {
        hasDeclaredEnd(endText: series.balanceDueEndText, at: series.balanceDueEndAt)
    }

    /// 「尾款时间：xxx」/「尾款期：起 — 止」整行文案；未填 → `nil`。
    ///
    /// 前缀随内容变：只有开始（旧数据 / 只关心哪天开始收）时说「时间」，
    /// 声明了结束才是真正的「期」—— 用统一的「期」去描述一个点会让人以为漏填了结束。
    static func displayText(of series: CatalogSeries) -> String? {
        guard let value = valueText(of: series) else { return nil }
        let prefix = hasDeclaredEnd(of: series) ? "尾款期：" : "尾款时间："
        return prefix.appLocalized + value
    }
}
