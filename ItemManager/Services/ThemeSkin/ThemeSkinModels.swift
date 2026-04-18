import Foundation

enum ThemeSkinSlot: String, Codable, CaseIterable, Identifiable, Hashable {
    case topBarMain
    case topBarSegment
    case topBarIconButton
    case topBarAddButton
    case searchBar
    case tabBarMain
    case tabBarItem
    case segmentedControl
    case filterChip
    case statsCard
    case wardrobeItemCard
    case settingsGridCard
    case sectionCard
    case primaryButton
    case iconCircleButton
    case discountBadge
    case filterSheet
    case emptyState

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topBarMain: return "顶部栏容器"
        case .topBarSegment: return "顶部栏分段"
        case .topBarIconButton: return "顶部栏图标按钮"
        case .topBarAddButton: return "顶部栏新增按钮"
        case .searchBar: return "搜索栏"
        case .tabBarMain: return "底部栏容器"
        case .tabBarItem: return "底部栏项目"
        case .segmentedControl: return "分段选择器"
        case .filterChip: return "筛选胶囊"
        case .statsCard: return "统计卡"
        case .wardrobeItemCard: return "衣橱商品卡"
        case .settingsGridCard: return "设置豆腐块"
        case .sectionCard: return "分组卡片"
        case .primaryButton: return "主按钮"
        case .iconCircleButton: return "圆形图标按钮"
        case .discountBadge: return "折扣徽标"
        case .filterSheet: return "筛选面板"
        case .emptyState: return "空状态容器"
        }
    }

    var descriptorNamespace: String {
        switch self {
        case .topBarMain, .topBarSegment, .topBarIconButton, .topBarAddButton:
            return "top_bar"
        case .searchBar:
            return "search_bar"
        case .tabBarMain, .tabBarItem:
            return "tab_bar"
        case .segmentedControl:
            return "segmented"
        case .filterChip:
            return "filter"
        case .statsCard, .wardrobeItemCard, .settingsGridCard, .sectionCard:
            return "card"
        case .primaryButton:
            return "button"
        case .iconCircleButton:
            return "icon_button"
        case .discountBadge:
            return "badge"
        case .filterSheet:
            return "sheet"
        case .emptyState:
            return "empty_state"
        }
    }

    var descriptorVariant: String {
        switch self {
        case .topBarMain: return "main"
        case .topBarSegment: return "segment"
        case .topBarIconButton: return "icon_button"
        case .topBarAddButton: return "add_button"
        case .searchBar: return "compact"
        case .tabBarMain: return "main"
        case .tabBarItem: return "item"
        case .segmentedControl: return "control"
        case .filterChip: return "chip"
        case .statsCard: return "stats"
        case .wardrobeItemCard: return "wardrobe_item"
        case .settingsGridCard: return "settings_grid"
        case .sectionCard: return "section"
        case .primaryButton: return "primary"
        case .iconCircleButton: return "circle"
        case .discountBadge: return "discount"
        case .filterSheet: return "filter"
        case .emptyState: return "search"
        }
    }
}

enum ThemeSkinState: String, Codable, CaseIterable, Identifiable {
    case `default`
    case selected
    case highlighted
    case pressed
    case disabled
    case focused

    var id: String { rawValue }
}

struct ThemeSkinProduct: Identifiable, Codable, Equatable {
    let id: String
    let themeId: String
    let name: String
    let subtitle: String
    let basePrice: Int
    let vipPrice: Int
    let previewAssetNames: [String]
    let supportedSlots: [ThemeSkinSlot]
    let defaultEnabledSlots: [ThemeSkinSlot]

    var assetNamespace: String {
        themeId.replacingOccurrences(of: "theme_skin.", with: "")
    }

    static let girlCloset = ThemeSkinProduct(
        id: "theme_skin.girl_closet",
        themeId: "theme_skin.girl_closet",
        name: "少女衣橱",
        subtitle: "旋转木马 · 奶白蕾丝 · 贴纸感装饰",
        basePrice: 99,
        vipPrice: 89,
        previewAssetNames: ["temp/主题-旋转木马/少女衣橱.png"],
        supportedSlots: [
            .topBarMain,
            .topBarIconButton,
            .topBarSegment,
            .searchBar,
            .tabBarMain,
            .tabBarItem,
            .statsCard,
            .wardrobeItemCard,
            .settingsGridCard,
            .discountBadge
        ],
        defaultEnabledSlots: [
            .topBarMain,
            .topBarIconButton,
            .tabBarMain,
            .tabBarItem,
            .statsCard,
            .wardrobeItemCard
        ]
    )
}

struct OwnedThemeSkin: Identifiable, Codable, Equatable {
    let id: String
    let purchasedAt: Date
    let paidPrice: Int
}

struct ActiveThemeSkinSelection: Codable, Equatable {
    var activeThemeId: String?
    var enabledSlots: Set<ThemeSkinSlot>

    static let inactive = ActiveThemeSkinSelection(activeThemeId: nil, enabledSlots: [])
}

struct ThemeSkinDescriptor: Identifiable, Codable, Equatable, Hashable {
    let themeId: String
    let assetNamespace: String
    let slot: ThemeSkinSlot
    let variant: String
    let state: ThemeSkinState
    let descriptorCode: String

    var id: String { descriptorCode }
}

struct ThemeSkinPriceQuote: Equatable {
    let productId: String
    let themeId: String
    let basePrice: Int
    let finalPrice: Int
    let isVIPDiscountApplied: Bool
    let discountLabel: String?
}

struct ThemeSkinActionResult: Equatable {
    let success: Bool
    let message: String

    static func success(_ message: String) -> ThemeSkinActionResult {
        ThemeSkinActionResult(success: true, message: message)
    }

    static func failure(_ message: String) -> ThemeSkinActionResult {
        ThemeSkinActionResult(success: false, message: message)
    }
}

protocol ThemeSkinProviding {
    func isSlotEnabled(_ slot: ThemeSkinSlot) -> Bool
    func activeThemeDescriptor(for slot: ThemeSkinSlot, state: ThemeSkinState) -> ThemeSkinDescriptor?
}
