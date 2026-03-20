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
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedTab: HomeTab
    let monthIndicator: WardrobeMonthIndicator?

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            tabButton(
                title: "少女衣橱",
                icon: "cabinet.fill",
                targetTab: .wardrobe,
                activeColor: palette.accent
            )

            tabButton(
                title: "心愿尾款",
                icon: "calendar.badge.clock",
                targetTab: .depositPlan,
                activeColor: palette.cardAccent
            )
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(palette.segmentedBackground)
        )
        // 修复：减小固定高度，使导航栏更紧凑
        .frame(height: 32)
        // 修复：确保在 principal 位置居中显示
        .frame(maxWidth: .infinity, alignment: .center)
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
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 8, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? activeColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? palette.segmentedSelectedBackground : Color.clear)
                    .shadow(color: isSelected ? Color.black.opacity(0.08) : Color.clear, radius: 1, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
