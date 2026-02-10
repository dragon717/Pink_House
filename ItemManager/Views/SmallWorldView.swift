//
//  SmallWorldView.swift
//  ItemManager
//
//  Created by Pink House Dev on 2/10/26.
//

import SwiftUI

enum SmallWorldDestination {
    case menu
    case ootd
    case pet
    case wealth
    case calendar
}

struct SmallWorldView: View {
    @Binding var selectedTab: Int // MainTabView selection
    @Binding var homeTab: HomeTab // HomeView selection
    @Binding var destination: SmallWorldDestination
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 20) {
                    // 1. 少女衣橱
                    SmallWorldCard(title: "少女衣橱", icon: "cabinet.fill", color: .pink) {
                        homeTab = .wardrobe
                        selectedTab = 0
                    }
                    
                    // 2. 尾款天使
                    SmallWorldCard(title: "尾款天使", icon: "list.clipboard.fill", color: .blue) {
                        homeTab = .depositPlan
                        selectedTab = 0
                    }
                    
                    // 3. 梦裙日历 (New)
                    SmallWorldCard(title: "梦裙日历", icon: "calendar", color: .purple) {
                        destination = .calendar
                    }
                    
                    // 4. OOTD
                    SmallWorldCard(title: "OOTD", icon: "tshirt.fill", color: .purple) {
                        destination = .ootd
                    }
                    
                    // 5. 萌宠
                    SmallWorldCard(title: "萌宠", icon: "pawprint.fill", color: .orange) {
                        destination = .pet
                    }
                    
                    // 6. 来财
                    SmallWorldCard(title: "来财", icon: "yensign.circle.fill", color: .yellow) {
                        destination = .wealth
                    }
                }
                .padding()
            }
            .navigationTitle("小世界")
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

struct SmallWorldCard: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        }
    }
}
