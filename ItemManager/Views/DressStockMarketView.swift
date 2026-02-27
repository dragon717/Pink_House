//
//  DressStockMarketView.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 2/24/26.
//

import SwiftUI

struct DressStockMarketView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LiquidBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue.opacity(0.5))
                    
                    Text("裙子股市")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    
                    Text("该功能正在激情开发中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("敬请期待！")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("裙子股市")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    DressStockMarketView()
}
