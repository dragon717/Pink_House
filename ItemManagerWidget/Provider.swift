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
    let statsType: StatsType
    let clothings: [Clothing]
    let seriesStats: [SeriesInfo]
    
    // New Fields for High Information Density
    let totalCount: Int
    let totalPrice: Decimal
    let recentClothings: [Clothing]
}

struct Provider: AppIntentTimelineProvider {
    @MainActor
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(), 
            size: .small, 
            statsType: .month, 
            clothings: [], 
            seriesStats: [],
            totalCount: 0,
            totalPrice: 0,
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
        // 从配置中获取统计类型，默认为 month
        let statsType: StatsType
        if let config = configuration {
            statsType = (config.statsType == .series) ? .series : .month
        } else {
            statsType = .month
        }
        
        // 从共享容器中 Fetch 数据
        let modelContext = SharedPersistence.shared.sharedModelContainer.mainContext
        var clothings: [Clothing] = []
        var seriesStats: [SeriesInfo] = []
        var totalCount: Int = 0
        var totalPrice: Decimal = 0
        var recentClothings: [Clothing] = []
        
        do {
            // 获取所有 Clothing
            let descriptor = FetchDescriptor<Clothing>(sortBy: [SortDescriptor(\.purchaseDate, order: .reverse)])
            clothings = try modelContext.fetch(descriptor)
            
            // 计算高密度数据
            totalCount = clothings.reduce(0) { $0 + $1.stock }
            totalPrice = clothings.reduce(0) { $0 + ($1.price * Decimal($1.stock)) }
            recentClothings = Array(clothings.prefix(5)) // 获取最近5件
            
            // 计算系列数据
            // 注意：SeriesAnalyzer 需要在 Widget Target 中可见
            // 这里我们简单同步执行，因为 Widget 渲染时间有限
            seriesStats = SeriesAnalyzer.shared.analyzeSeriesSync(from: clothings)
        } catch {
            print("Widget Provider Error: \(error)")
        }
        
        return SimpleEntry(
            date: Date(),
            size: .small, // 尺寸参数不再重要，视图会根据 family 自适应
            statsType: statsType,
            clothings: clothings,
            seriesStats: seriesStats,
            totalCount: totalCount,
            totalPrice: totalPrice,
            recentClothings: recentClothings
        )
    }
}

// 扩展 SeriesAnalyzer 以支持同步调用（或者假设 analyzeSeries 已经很快了）
// 为了避免 async/await 问题，我们在 Widget 中直接复用逻辑或创建一个同步版本
// 这里为了方便，我们假设 SeriesAnalyzer 的 analyzeSeries 其实可以直接用，但在 Provider 里我们不能很容易地 await
// 所以我们在 SeriesAnalyzer 里加一个同步 helper 或者在这里简单实现
extension SeriesAnalyzer {
    func analyzeSeriesSync(from clothings: [Clothing]) -> [SeriesInfo] {
        // 简化版同步实现，避免 Task 调度问题
        var candidateCounts: [String: Int] = [:]
        var candidateBalances: [String: Decimal] = [:]
        
        for clothing in clothings {
            let name = clothing.name
            let candidates = self.generateCandidates(from: name) // 需要确保 generateCandidates 是 internal/public
            
            for candidate in candidates {
                candidateCounts[candidate, default: 0] += 1
                candidateBalances[candidate, default: 0] += (clothing.balance * Decimal(clothing.stock))
            }
        }
        
        let validCandidates = candidateCounts.keys.filter { (candidateCounts[$0] ?? 0) >= 2 }
        let sortedCandidates = validCandidates.sorted { $0.count > $1.count }
        
        var seriesList: [SeriesInfo] = []
        
        // 简化去重逻辑
        for candidate in sortedCandidates {
            let count = candidateCounts[candidate]!
            var isRedundant = false
            for existing in seriesList {
                if existing.name.localizedCaseInsensitiveContains(candidate) {
                    // 简单判定：如果已存在包含该词的更长系列，且数量相差不大，视为冗余
                    // 这里为了 Widget 性能做简化
                    if existing.count >= count {
                        isRedundant = true
                        break
                    }
                }
            }
            
            if !isRedundant {
                seriesList.append(SeriesInfo(name: candidate, count: count, totalBalance: candidateBalances[candidate] ?? 0))
            }
        }
        
        return seriesList.sorted {
            if $0.totalBalance != $1.totalBalance {
                return $0.totalBalance > $1.totalBalance
            }
            return $0.count > $1.count
        }
    }
}
