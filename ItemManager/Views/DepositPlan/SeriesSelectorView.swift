//
//  SeriesSelectorView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import SwiftUI

struct SeriesSelectorView: View {
    @Binding var selectedSeries: Set<String>
    @Binding var year: Int
    let seriesList: [SeriesInfo]
    let isAnalyzing: Bool
    @Binding var showYearStats: Bool
    let clothings: [Clothing] // 用于计算当前月统计（不区分系列）
    @Binding var isExpanded: Bool
    @State private var showTips: Bool = false

    // Adaptive grid columns
    let columns = [GridItem(.adaptive(minimum: 100), spacing: 10)]

    // 计算系列视图的年份统计
    private var yearStats: (totalCount: Int, styleCount: Int, paidDeposit: Decimal, pendingBalance: Decimal) {
        // 从 seriesList 计算总计
        let totalCount = seriesList.reduce(0) { $0 + $1.itemCount }
        let styleCount = seriesList.count
        let paidDeposit = seriesList.reduce(0) { $0 + $1.totalDeposit }
        let pendingBalance = seriesList.reduce(0) { $0 + $1.totalBalance }

        return (totalCount, styleCount, paidDeposit, pendingBalance)
    }

    // 计算最近添加的统计（一个月内添加的商品，不区分系列）
    private var recentAddedStats: (title: String, count: Int, amount: Decimal, hasData: Bool) {
        let calendar = Calendar.current
        let now = Date()
        // 获取一个月前的日期
        guard let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) else {
            return ("最近添加", 0, 0, false)
        }

        // 统计最近一个月内添加的商品（按 createdAt 字段）
        let recentClothings = clothings.filter { clothing in
            clothing.createdAt >= oneMonthAgo
        }

        let count = recentClothings.reduce(0) { $0 + $1.stock }
        // 注意：totalBalance 已经包含了 stock 的乘法，所以这里直接使用，不要再乘 stock
        let amount = recentClothings.reduce(0) { $0 + $1.totalBalance }

        return ("最近添加", count, amount, count > 0)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("按系列预估尾款 (点我隐藏并显示最近添加)")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    
                    // Tips Icon
                    Button {
                        showTips = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .alert("系列分类规则", isPresented: $showTips) {
                        Button("知道了", role: .cancel) { }
                    } message: {
                        Text("系统会自动根据商品名称的前 2-4 个字（去除特殊符号）作为系列前缀进行归类。\n\n例如：\n\"少女心愿 连衣裙\"\n\"少女心愿 半裙\"\n\n都会被归类为 \"Pink\" 系列。\n注：同名属于同一款商品。")
                    }
                    
                    if isAnalyzing {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.leading, 8)
                    }
                    
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if isExpanded {
                // Year Selector（带小眼睛按钮）
                YearSelectorView(
                    year: $year,
                    showStats: showYearStats,
                    onToggleStats: { showYearStats.toggle() }
                )
                
                // 年份统计（简洁显示）
                YearStatsCard(
                    stats: yearStats,
                    year: year,
                    isVisible: showYearStats
                )
                
                if seriesList.isEmpty {
                    if isAnalyzing {
                        Text("正在分析系列...")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        Text("暂无系列数据")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(seriesList) { series in
                                let isSelected = selectedSeries.contains(series.name)
                                
                                Button {
                                    if isSelected {
                                        selectedSeries.remove(series.name)
                                    } else {
                                        selectedSeries = [series.name]
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(series.name)
                                                .font(.caption)
                                                .fontWeight(isSelected ? .bold : .medium)
                                                .lineLimit(1)
                                            Spacer()
                                            Text("\(series.itemCount)")
                                                .font(.system(size: 9))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 4)
                                                .background(Color.black.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        
                                        Text("¥\(NSDecimalNumber(decimal: series.totalBalance).stringValue)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(isSelected ? .white.opacity(0.9) : (series.totalBalance > 0 ? .orange : .secondary.opacity(0.7)))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .padding(8)
                                    .background {
                                        if isSelected {
                                            Color.brown
                                        } else {
                                            CardBackgroundView(cornerRadius: 8)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: isSelected ? 0 : 1)
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 300) // Limit height to avoid taking too much space
                }
            } else {
                // 隐藏时显示最近添加统计（一个月内）
                RecentAddedCard(stats: recentAddedStats)
            }
        }
    }
}

// MARK: - 最近添加统计卡片
struct RecentAddedCard: View {
    let stats: (title: String, count: Int, amount: Decimal, hasData: Bool)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.brown)
                Text(stats.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Spacer()
                if stats.hasData {
                    Text("一个月内")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.brown)
                        .clipShape(Capsule())
                }
            }

            if stats.hasData {
                HStack(spacing: 0) {
                    DepositStatItem(
                        title: "待付件数",
                        value: "\(stats.count)",
                        valueColor: .primary
                    )

                    Divider()
                        .frame(height: 30)

                    DepositStatItem(
                        title: "待付尾款",
                        value: "¥\(NSDecimalNumber(decimal: stats.amount).stringValue)",
                        valueColor: Color(hex: "C94C72")
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            } else {
                Text("暂无最近添加")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(CardBackgroundView(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
    }
}
