//
//  WardrobeView.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import SwiftUI
import SwiftData

struct WardrobeView: View {
    @Binding var searchText: String
    @Query(sort: \Clothing.createdAt, order: .reverse) private var clothings: [Clothing]
    @State private var showStats = true
    
    // Grid layout
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var filteredClothings: [Clothing] {
        if searchText.isEmpty {
            return clothings
        } else {
            return clothings.filter { clothing in
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
                    WardrobeStatsView(clothings: clothings)
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            
            // Grid
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredClothings) { clothing in
                    NavigationLink {
                        ClothingDetailView(clothing: clothing)
                    } label: {
                        ClothingCard(clothing: clothing)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100) // Bottom padding for scrolling
        }
        .padding(.top, 10)
    }
}

struct WardrobeStatsView: View {
    let clothings: [Clothing]
    
    var totalCount: Int {
        clothings.count
    }
    
    var dressValue: Decimal {
        clothings.reduce(0) { $0 + $1.price }
    }
    
    var totalValue: Decimal {
        clothings.reduce(0) { $0 + $1.price + $1.accessoriesPrice }
    }
    
    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                // Main Stats
                HStack(spacing: 0) {
                    statItem(title: "总裙子数", value: "\(totalCount)")
                    
                    Divider()
                        .frame(height: 30)
                    
                    statItem(title: "裙子价值", value: "¥\(NSDecimalNumber(decimal: dressValue).stringValue)", valueColor: Color(hex: "FF9800"))
                    
                    Divider()
                        .frame(height: 30)
                    
                    statItem(title: "总价值 (含小物)", value: "¥\(NSDecimalNumber(decimal: totalValue).stringValue)")
                }
                
                // Bottom Action
                Button {
                    // Action for detailed stats
                } label: {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                        Text("查看详细统计")
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.caption)
                        Text("会员专属")
                            .font(.caption)
                    }
                    .padding()
                    .background(Color.brown.opacity(0.1))
                    .foregroundStyle(Color.brown)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
