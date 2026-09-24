//
//  WardrobeStatsMonthLabelTests.swift
//  ItemManagerTests
//
//  「购买时间统计」卡片的时间标注口径（2026-09-24 需求）：
//  时间标注必须精确到月份（如「2024年3月」），12 个月各一条、互不重复、
//  按时间升序；且卡片要能真的把图表渲染出来（快照附件留档，
//  供版式核对，尤其是「标签是否被省略/叠字」这类 eyeball 项）。
//

import XCTest
import SwiftUI
@testable import ItemManager

@MainActor
final class WardrobeStatsMonthLabelTests: XCTestCase {

    /// 覆盖「当前月」往前 14 个月，每月 1 件 —— 12 个月窗口里必然跨年，
    /// 这正是「只显示年份/只显示月份会看不出是哪一年」的场景。
    private func makeClothings() -> [Clothing] {
        let calendar = Calendar.current
        let now = Date()
        return (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: -offset, to: now) else { return nil }
            return Clothing(name: "统计样本\(offset)", price: 100, purchaseDate: date)
        }
    }

    /// 月份部分（与视图内 `wardrobeStatsMonthLabel` 同 locale/模板基线，
    /// 但模板是旧的 "MMM"：只出「3月」/「Mar」）
    private func monthOnlyText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = LanguageManager.shared.locale
        formatter.calendar = Calendar.current
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    /// 标签必须含年份（精确到月份的前提）且保留月份部分
    func testMonthLabelsCarryYearAndMonth() {
        let card = PurchaseTimeStatsCard(clothings: makeClothings())
        let stats = card.last12MonthsStats
        XCTAssertEqual(stats.count, 12, "最近 12 个月必须恰好 12 档")

        for stat in stats {
            let label = stat.monthLabel
            let year = Calendar.current.component(.year, from: stat.date)
            XCTAssertTrue(label.contains("\(year)"),
                          "标签「\(label)」缺少年份 \(year)（应形如 2024年3月）")
            XCTAssertTrue(label.contains(monthOnlyText(for: stat.date)),
                          "标签「\(label)」丢失了月份部分")
        }
    }

    /// 12 条标签互不相同，且按时间升序（图表 X 轴顺序）
    func testMonthLabelsAreDistinctAndChronological() {
        let card = PurchaseTimeStatsCard(clothings: makeClothings())
        let stats = card.last12MonthsStats

        XCTAssertEqual(Set(stats.map(\.monthLabel)).count, 12, "存在重复月份标签")
        let dates = stats.map(\.date)
        XCTAssertEqual(dates, dates.sorted(), "月份标签必须按时间升序")
    }

    /// 卡片能渲染出非空图表；PNG 作为附件留档供「标签是否完整、是否叠字」核对
    func testPurchaseTimeStatsCardRendersNonBlankSnapshot() throws {
        let card = PurchaseTimeStatsCard(clothings: makeClothings())
            .frame(width: 370, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            // ThemeManager 是 @Observable：卡片背景/文字可读性走 @Environment(ThemeManager.self)，
            // 不注入的话 ImageRenderer 会直接崩（No Observable object of type ThemeManager found）
            .environment(ThemeManager.shared)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true

        let image = try XCTUnwrap(renderer.uiImage, "ImageRenderer 未产出图像")
        // 坑：image.size 是「点」，不是像素
        XCTAssertEqual(image.size.width, 370, accuracy: 4)
        XCTAssertGreaterThan(image.size.height, 200, "卡片高度异常，图表很可能没渲染")

        let attachment = XCTAttachment(image: image)
        attachment.name = "purchase-time-stats-card"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
