import SwiftUI

enum ThemeSkinPreviewMode: String, CaseIterable, Identifiable {
    case appDefault
    case theme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appDefault: return "默认".appLocalized
        case .theme: return "主题".appLocalized
        }
    }
}

enum ThemeSkinPreviewScene: String, CaseIterable, Identifiable {
    case me
    case wardrobe
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .me: return "我界面".appLocalized
        case .wardrobe: return "衣橱".appLocalized
        case .settings: return "设置".appLocalized
        }
    }
}

enum ThemeSkinPreviewAnchor: String, CaseIterable, Identifiable {
    case topBar
    case searchBar
    case tabBar
    case statsCard
    case wardrobeCard
    case settingsGrid
    case sectionCard
    case primaryButton
    case iconButton
    case segmentedControl
    case filterChip
    case discountBadge
    case filterSheet
    case emptyState

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topBar: return "顶部".appLocalized
        case .searchBar: return "搜索".appLocalized
        case .tabBar: return "底栏".appLocalized
        case .statsCard: return "统计卡".appLocalized
        case .wardrobeCard: return "衣橱卡".appLocalized
        case .settingsGrid: return "豆腐块".appLocalized
        case .sectionCard: return "分组卡".appLocalized
        case .primaryButton: return "主按钮".appLocalized
        case .iconButton: return "圆形按钮".appLocalized
        case .segmentedControl: return "分段".appLocalized
        case .filterChip: return "筛选".appLocalized
        case .discountBadge: return "折扣".appLocalized
        case .filterSheet: return "面板".appLocalized
        case .emptyState: return "空状态".appLocalized
        }
    }

    nonisolated var representativeSlot: ThemeSkinSlot {
        switch self {
        case .topBar: return .topBarMain
        case .searchBar: return .searchBar
        case .tabBar: return .tabBarMain
        case .statsCard: return .statsCard
        case .wardrobeCard: return .wardrobeItemCard
        case .settingsGrid: return .settingsGridCard
        case .sectionCard: return .sectionCard
        case .primaryButton: return .primaryButton
        case .iconButton: return .iconCircleButton
        case .segmentedControl: return .segmentedControl
        case .filterChip: return .filterChip
        case .discountBadge: return .discountBadge
        case .filterSheet: return .filterSheet
        case .emptyState: return .emptyState
        }
    }

    nonisolated static func anchor(for slot: ThemeSkinSlot) -> ThemeSkinPreviewAnchor {
        switch slot {
        case .topBarMain, .topBarSegment, .topBarIconButton, .topBarAddButton:
            return .topBar
        case .searchBar:
            return .searchBar
        case .tabBarMain, .tabBarItem:
            return .tabBar
        case .statsCard:
            return .statsCard
        case .wardrobeItemCard:
            return .wardrobeCard
        case .settingsGridCard:
            return .settingsGrid
        case .sectionCard:
            return .sectionCard
        case .primaryButton:
            return .primaryButton
        case .iconCircleButton:
            return .iconButton
        case .segmentedControl:
            return .segmentedControl
        case .filterChip:
            return .filterChip
        case .discountBadge:
            return .discountBadge
        case .filterSheet:
            return .filterSheet
        case .emptyState:
            return .emptyState
        }
    }
}

enum ThemeSkinSlotRowID {
    static let previewCard = "theme-skin-detail-preview-card"

    static func slot(_ slot: ThemeSkinSlot) -> String {
        "theme-skin-slot-row-\(slot.rawValue)"
    }
}

struct ThemeSkinPreviewContext {
    let product: ThemeSkinProduct
    let mode: ThemeSkinPreviewMode
    let enabledSlots: Set<ThemeSkinSlot>

    func isThemed(_ slot: ThemeSkinSlot) -> Bool {
        mode == .theme && product.supportedSlots.contains(slot) && enabledSlots.contains(slot)
    }

    func descriptor(for slot: ThemeSkinSlot, state: ThemeSkinState = .default) -> ThemeSkinDescriptor? {
        guard isThemed(slot) else { return nil }
        return ThemeSkinManager.shared.descriptor(forThemeId: product.themeId, slot: slot, state: state)
    }

    func descriptor(for anchor: ThemeSkinPreviewAnchor) -> ThemeSkinDescriptor? {
        descriptor(for: anchor.representativeSlot)
    }

    var representativeDescriptor: ThemeSkinDescriptor? {
        for slot in ThemeSkinSlot.allCases where isThemed(slot) {
            return descriptor(for: slot)
        }
        return nil
    }
}
