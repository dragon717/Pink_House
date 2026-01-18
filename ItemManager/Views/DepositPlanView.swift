//
//  DepositPlanView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData

struct DepositPlanView: View {
    @Binding var searchText: String
    @Query(filter: #Predicate<Clothing> { $0.isDepositPlan == true }, sort: \Clothing.createdAt, order: .reverse) private var depositClothings: [Clothing]
    
    @State private var selectedYear: Int = 2026
    @State private var showStats = true
    
    var filteredClothings: [Clothing] {
        if searchText.isEmpty {
            return depositClothings
        } else {
            return depositClothings.filter { clothing in
                clothing.name.localizedCaseInsensitiveContains(searchText) ||
                (clothing.brand?.name.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Stats Section
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation {
                            showStats.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showStats ? "隐藏统计" : "显示统计")
                            Image(systemName: showStats ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                
                if showStats {
                    DepositStatsView(clothings: depositClothings)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            
            // Month Selector
            MonthSelectorView(year: $selectedYear)
                .padding(.horizontal)
            
            // List
            LazyVStack(spacing: 16) {
                ForEach(filteredClothings) { clothing in
                    DepositItemRow(clothing: clothing)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100)
        }
        .padding(.top, 10)
    }
}

struct DepositStatsView: View {
    let clothings: [Clothing]
    
    var totalCount: Int {
        clothings.count
    }
    
    var paidDeposit: Decimal {
        clothings.reduce(0) { $0 + $1.deposit }
    }
    
    var pendingBalance: Decimal {
        clothings.reduce(0) { $0 + $1.balance }
    }
    
    var body: some View {
        GlassCard {
            HStack(spacing: 0) {
                statItem(title: "总裙子数", value: "\(totalCount)")
                
                Divider()
                    .frame(height: 30)
                
                statItem(title: "已付定金", value: "¥\(NSDecimalNumber(decimal: paidDeposit).stringValue)", valueColor: Color(hex: "FF9800"))
                
                Divider()
                    .frame(height: 30)
                
                statItem(title: "待付尾款", value: "¥\(NSDecimalNumber(decimal: pendingBalance).stringValue)")
            }
        }
    }
    
    private func statItem(title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MonthSelectorView: View {
    @Binding var year: Int
    @State private var expanded: Bool = true
    
    let months = Array(1...12)
    let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            Button {
                withAnimation {
                    expanded.toggle()
                }
            } label: {
                HStack {
                    Text("按月预估尾款")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if expanded {
                // Year Selector
                HStack {
                    Button {
                        year -= 1
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("\(String(year))年")
                        .font(.headline)
                        .frame(width: 80)
                    
                    Button {
                        year += 1
                    } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Month Grid
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(months, id: \.self) { month in
                        VStack {
                            Text("\(month)月")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("-")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 1)
                    }
                }
            }
        }
    }
}
