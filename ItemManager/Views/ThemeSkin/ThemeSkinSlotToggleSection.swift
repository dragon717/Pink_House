import SwiftUI

struct ThemeSkinSlotToggleSection: View {
    let themeId: String

    @ObservedObject private var themeSkinManager = ThemeSkinManager.shared
    @Environment(ThemeManager.self) private var themeManager

    private struct SlotGroup: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let slots: [ThemeSkinSlot]
    }

    private let groups: [SlotGroup] = [
        SlotGroup(
            id: "chrome",
            title: "顶部与搜索",
            subtitle: "顶部栏、分段、图标按钮与搜索入口",
            icon: "rectangle.topthird.inset.filled",
            slots: [.topBarMain, .topBarSegment, .topBarIconButton, .topBarAddButton, .searchBar]
        ),
        SlotGroup(
            id: "tabbar",
            title: "底部导航",
            subtitle: "底栏容器、Tab 项与异形轮廓",
            icon: "rectangle.bottomthird.inset.filled",
            slots: [.tabBarMain, .tabBarItem]
        ),
        SlotGroup(
            id: "cards",
            title: "卡片与列表",
            subtitle: "详情页、我界面、手帐与书页列表的核心卡片",
            icon: "rectangle.stack.fill",
            slots: [.statsCard, .wardrobeItemCard, .settingsGridCard, .sectionCard]
        ),
        SlotGroup(
            id: "controls",
            title: "按钮与控件",
            subtitle: "主按钮、圆形徽标、筛选胶囊与折扣标识",
            icon: "slider.horizontal.3",
            slots: [.primaryButton, .iconCircleButton, .segmentedControl, .filterChip, .discountBadge]
        ),
        SlotGroup(
            id: "surfaces",
            title: "面板与空状态",
            subtitle: "筛选面板和没有内容时的提示容器",
            icon: "sparkles.rectangle.stack.fill",
            slots: [.filterSheet, .emptyState]
        )
    ]

    private var product: ThemeSkinProduct? {
        themeSkinManager.product(for: themeId)
    }

    private var isPurchased: Bool {
        themeSkinManager.isPurchased(themeId)
    }

    private var isActive: Bool {
        themeSkinManager.isActiveTheme(themeId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ForEach(groupsWithSupportedSlots) { group in
                slotGroupCard(group)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("组件开关")
                .font(.title3.weight(.bold))
                .foregroundStyle(themeManager.primaryTextColor)

            Text(isPurchased ? "同一主题内部可以单独启用或停用组件；未启用的组件会回退到应用默认样式。" : "请先购买并应用这个主题，之后才能控制组件开关。")
                .font(.footnote)
                .foregroundStyle(themeManager.secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    private var groupsWithSupportedSlots: [SlotGroup] {
        guard let product else { return [] }
        return groups.compactMap { group in
            let slots = group.slots.filter { product.supportedSlots.contains($0) }
            guard !slots.isEmpty else { return nil }
            return SlotGroup(
                id: group.id,
                title: group.title,
                subtitle: group.subtitle,
                icon: group.icon,
                slots: slots
            )
        }
    }

    private func slotGroupCard(_ group: SlotGroup) -> some View {
        ThemeSkinSectionCardContainer(cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ThemeSkinIconBadge(systemName: group.icon, fallbackColor: themeManager.accentTextColor, size: 36, symbolSize: 15)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title)
                            .font(.headline)
                            .foregroundStyle(themeManager.primaryTextColor)
                        Text(group.subtitle)
                            .font(.caption)
                            .foregroundStyle(themeManager.secondaryTextColor)
                    }

                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    ForEach(group.slots) { slot in
                        Toggle(isOn: Binding(
                            get: { isActive && themeSkinManager.isSlotEnabled(slot) },
                            set: { newValue in
                                _ = themeSkinManager.setSlot(slot, enabled: newValue)
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(themeManager.primaryTextColor)
                                Text(slot.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(themeManager.secondaryTextColor)
                            }
                        }
                        .disabled(!isPurchased || !isActive)
                        .padding(.vertical, 9)

                        if slot.id != (group.slots.last?.id ?? "") {
                            Divider()
                                .opacity(0.45)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
