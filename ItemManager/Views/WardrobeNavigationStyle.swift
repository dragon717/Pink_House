import SwiftUI

enum WardrobeNavigationStyle: String, CaseIterable, Identifiable {
    case classic = "classic"
    case fashion = "fashion"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .classic:
            return "经典样式"
        case .fashion:
            return "时尚样式"
        }
    }
    
    var subtitle: String {
        switch self {
        case .classic:
            return "当前布局，标签页在左侧。"
        case .fashion:
            return "顶部居中分段，操作按钮左右分区。"
        }
    }
}

enum WardrobeMonthIndicator {
    case current(Int)
    case next(Int)
}

struct WardrobeFashionTabSwitcher: View {
    @Binding var selectedTab: HomeTab
    let monthIndicator: WardrobeMonthIndicator?
    
    var body: some View {
        HStack(spacing: 4) {
            tabButton(
                title: "少女衣橱",
                icon: "cabinet.fill",
                targetTab: .wardrobe,
                activeColor: .pink
            )
            
            tabButton(
                title: "尾款天使",
                icon: "calendar.badge.clock",
                targetTab: .depositPlan,
                activeColor: .brown
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
        )
    }
    
    @ViewBuilder
    private func tabButton(
        title: String,
        icon: String,
        targetTab: HomeTab,
        activeColor: Color
    ) -> some View {
        let isSelected = selectedTab == targetTab
        
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = targetTab
            }
        } label: {
            VStack(spacing: 3) {
                iconView(icon: icon, targetTab: targetTab, isSelected: isSelected, activeColor: activeColor)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? activeColor : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.78) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func iconView(
        icon: String,
        targetTab: HomeTab,
        isSelected: Bool,
        activeColor: Color
    ) -> some View {
        if targetTab == .depositPlan,
           selectedTab == .wardrobe,
           let monthIndicator {
            switch monthIndicator {
            case .current(let day):
                CalendarDayIcon(day: day)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.pink)
            case .next(let day):
                CalendarDayIcon(day: day)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.brown)
            }
        } else {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? activeColor : .secondary)
        }
    }
}
