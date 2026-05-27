import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum WardrobeNavigationStyle: String, CaseIterable, Identifiable {
    case classic = "classic"
    case fashion = "fashion"
    
    static let userDefaultsKey = "UserPreference_WardrobeNavigationStyle"
    
    var id: String { rawValue }
    
    static var availableStylesForCurrentDevice: [WardrobeNavigationStyle] {
        availableStyles(for: currentUserInterfaceIdiom)
    }
    
    static var currentUserInterfaceIdiom: UIUserInterfaceIdiom {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom
        #else
        .unspecified
        #endif
    }
    
    static func availableStyles(for idiom: UIUserInterfaceIdiom) -> [WardrobeNavigationStyle] {
        idiom == .pad ? [.classic] : Self.allCases
    }
    
    func resolved(for idiom: UIUserInterfaceIdiom) -> WardrobeNavigationStyle {
        Self.availableStyles(for: idiom).contains(self) ? self : .classic
    }
    
    var resolvedForCurrentDevice: WardrobeNavigationStyle {
        resolved(for: Self.currentUserInterfaceIdiom)
    }
    
    @discardableResult
    static func normalizeStoredPreference(
        userDefaults: UserDefaults = .standard,
        idiom: UIUserInterfaceIdiom = currentUserInterfaceIdiom
    ) -> WardrobeNavigationStyle {
        let storedStyle = userDefaults.string(forKey: userDefaultsKey)
            .flatMap(Self.init(rawValue:))
            ?? .classic
        let normalizedStyle = storedStyle.resolved(for: idiom)
        
        if storedStyle != normalizedStyle || userDefaults.string(forKey: userDefaultsKey) != normalizedStyle.rawValue {
            userDefaults.set(normalizedStyle.rawValue, forKey: userDefaultsKey)
        }
        
        return normalizedStyle
    }
    
    var displayName: String {
        switch self {
        case .classic:
            return "经典导航栏"
        case .fashion:
            return "时尚导航栏"
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
    let themeSkinDescriptor: ThemeSkinDescriptor?

    init(
        selectedTab: Binding<HomeTab>,
        monthIndicator: WardrobeMonthIndicator?,
        themeSkinDescriptor: ThemeSkinDescriptor? = nil
    ) {
        self._selectedTab = selectedTab
        self.monthIndicator = monthIndicator
        self.themeSkinDescriptor = themeSkinDescriptor
    }

    private var palette: MagicThemePalette {
        MagicThemeDesignSystem.palette(themeManager: themeManager, colorScheme: colorScheme)
    }

    private var isThemeSkinActive: Bool {
        WardrobeThemeSkinSupport.isThemeSkinDescriptor(themeSkinDescriptor)
    }
    
    var body: some View {
        HStack(spacing: WardrobeTopBarMetrics.segmentInterItemSpacing) {
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
        .background(fashionSwitcherBackground)
        .frame(width: 132, height: WardrobeTopBarMetrics.segmentVisualHeight)
    }

    @ViewBuilder
    private var fashionSwitcherBackground: some View {
        if isThemeSkinActive {
            Capsule()
                .fill(Color.clear)
        } else {
            Capsule()
                .fill(palette.segmentedBackground)
        }
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
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = targetTab
            }
        } label: {
            VStack(spacing: WardrobeTopBarMetrics.segmentStackSpacing) {
                Image(systemName: icon)
                    .font(.system(size: WardrobeTopBarMetrics.segmentIconSize, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: WardrobeTopBarMetrics.segmentTextSize, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(tabForeground(isSelected: isSelected, fallbackActiveColor: activeColor))
            .padding(.horizontal, WardrobeTopBarMetrics.segmentItemHorizontalPadding)
            .padding(.vertical, WardrobeTopBarMetrics.segmentItemVerticalPadding)
            .background {
                tabSelectionBackground(isSelected: isSelected)
            }
            .frame(height: WardrobeTopBarMetrics.segmentVisualHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tabForeground(isSelected: Bool, fallbackActiveColor: Color) -> Color {
        guard isThemeSkinActive else {
            return isSelected ? fallbackActiveColor : .secondary
        }

        return isSelected
            ? SkyConcertThemeSkin.accent(for: themeSkinDescriptor)
            : SkyConcertThemeSkin.labelColor(for: themeSkinDescriptor).opacity(0.68)
    }

    @ViewBuilder
    private func tabSelectionBackground(isSelected: Bool) -> some View {
        if isThemeSkinActive && isSelected {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            SkyConcertThemeSkin.shellFillTop(for: themeSkinDescriptor).opacity(0.98),
                            SkyConcertThemeSkin.accentSoft(for: themeSkinDescriptor).opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Capsule()
                        .stroke(SkyConcertThemeSkin.shellStroke(for: themeSkinDescriptor).opacity(0.72), lineWidth: 0.8)
                }
                .shadow(color: SkyConcertThemeSkin.shadowColor(for: themeSkinDescriptor).opacity(0.22), radius: 3, x: 0, y: 1)
        } else if isSelected {
            Capsule()
                .fill(palette.segmentedSelectedBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
        } else {
            Color.clear
        }
    }
}
