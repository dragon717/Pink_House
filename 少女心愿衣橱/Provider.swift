//
//  Provider.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import WidgetKit
import SwiftUI
import SwiftData

struct SimpleEntry: TimelineEntry {
    let date: Date
    let size: WidgetSize
    let monthStats: [WidgetMonthInfo]
    
    // New Fields for High Information Density
    let totalCount: Int
    let totalStyleCount: Int
    let depositCount: Int
    let depositStyleCount: Int
    let totalPrice: Decimal
    let totalDeposit: Decimal
    let totalBalance: Decimal
    let recentClothings: [WidgetClothing]
}

struct Provider: AppIntentTimelineProvider {
    @MainActor
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(), 
            size: .small, 
            monthStats: [],
            totalCount: 0,
            totalStyleCount: 0,
            depositCount: 0,
            depositStyleCount: 0,
            totalPrice: 0,
            totalDeposit: 0,
            totalBalance: 0,
            recentClothings: []
        )
    }

    @MainActor
    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        createEntry(with: configuration)
    }

    @MainActor
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let entry = createEntry(with: configuration)
        
        // 每天更新一次，或者当数据变化时（通过 App 端触发 reload）
        // 这里设置每小时刷新一次作为保底
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
    
    @MainActor
    private func createEntry(with configuration: ConfigurationAppIntent? = nil) -> SimpleEntry {
        // 从共享容器中 Load 数据
        let data = WidgetDataManager.shared.load()
        
        return SimpleEntry(
            date: Date(),
            size: .small, // 尺寸参数不再重要，视图会根据 family 自适应
            monthStats: data.monthStats,
            totalCount: data.totalCount,
            totalStyleCount: data.totalStyleCount,
            depositCount: data.depositCount,
            depositStyleCount: data.depositStyleCount,
            totalPrice: data.totalPrice,
            totalDeposit: data.totalDeposit,
            totalBalance: data.totalBalance,
            recentClothings: data.recentClothings
        )
    }
}
