import SwiftUI

struct ThemeSkinSlotToggleSection: View {
    let themeId: String

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(ThemeManager.self) private var themeManager

    private let commonSlots: [ThemeSkinSlot] = [
        .topBarMain,
        .topBarSegment,
        .topBarIconButton,
        .searchBar,
        .statsCard,
        .wardrobeItemCard,
        .tabBarMain,
        .tabBarItem
    ]

    private var supportedSlots: [ThemeSkinSlot] {
        guard let product = themeSkinManager.product(for: themeId) else { return commonSlots }
        return commonSlots.filter { product.supportedSlots.contains($0) }
    }

    private var isPurchased: Bool {
        themeSkinManager.isPurchased(themeId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("组件开关")
                .font(.headline)
                .foregroundStyle(themeManager.primaryTextColor)

            Text(isPurchased ? "同一主题内部可以单独启用或停用组件；未启用的组件会回退到应用默认样式。" : "请先购买并应用这个主题，之后才能控制组件开关。")
                .font(.footnote)
                .foregroundStyle(themeManager.secondaryTextColor)

            ForEach(supportedSlots) { slot in
                Toggle(isOn: Binding(
                    get: { themeSkinManager.isActiveTheme(themeId) && themeSkinManager.isSlotEnabled(slot) },
                    set: { newValue in
                        _ = themeSkinManager.setSlot(slot, enabled: newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.displayName)
                            .foregroundStyle(themeManager.primaryTextColor)
                        Text(slot.rawValue)
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }
                }
                .disabled(!isPurchased || !themeSkinManager.isActiveTheme(themeId))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background {
            CardBackgroundView(cornerRadius: 24)
        }
    }
}
