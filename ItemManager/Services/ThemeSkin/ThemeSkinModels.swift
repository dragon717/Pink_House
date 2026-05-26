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
        case .topBarMain: return "顶部栏容器".appLocalized
        case .topBarSegment: return "顶部栏分段".appLocalized
        case .topBarIconButton: return "顶部栏图标按钮".appLocalized
        case .topBarAddButton: return "顶部栏新增按钮".appLocalized
        case .searchBar: return "搜索栏".appLocalized
        case .tabBarMain: return "底部栏容器".appLocalized
        case .tabBarItem: return "底部栏项目".appLocalized
        case .segmentedControl: return "分段选择器".appLocalized
        case .filterChip: return "筛选胶囊".appLocalized
        case .statsCard: return "统计卡".appLocalized
        case .wardrobeItemCard: return "衣橱商品卡".appLocalized
        case .settingsGridCard: return "设置豆腐块".appLocalized
        case .sectionCard: return "分组卡片".appLocalized
        case .primaryButton: return "主按钮".appLocalized
        case .iconCircleButton: return "圆形图标按钮".appLocalized
        case .discountBadge: return "折扣徽标".appLocalized
        case .filterSheet: return "筛选面板".appLocalized
        case .emptyState: return "空状态容器".appLocalized
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

enum ThemeSkinWallpaperLayoutPreset: String, Codable, CaseIterable, Identifiable {
    case mixedFocus
    case heroStatement
    case balancedScatter
    case miniPattern

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mixedFocus: return "大小混合".appLocalized
        case .heroStatement: return "大主图".appLocalized
        case .balancedScatter: return "均匀散点".appLocalized
        case .miniPattern: return "小图满铺".appLocalized
        }
    }

    var shortLabel: String {
        switch self {
        case .mixedFocus: return "混合".appLocalized
        case .heroStatement: return "大".appLocalized
        case .balancedScatter: return "散点".appLocalized
        case .miniPattern: return "小图".appLocalized
        }
    }

    var summary: String {
        switch self {
        case .mixedFocus:
            return "大主图压住焦点，小贴纸按墙纸节奏补满。".appLocalized
        case .heroStatement:
            return "减少小图数量，让大主图成为主要视觉。".appLocalized
        case .balancedScatter:
            return "所有贴纸均匀散开，适合清爽背景。".appLocalized
        case .miniPattern:
            return "取消大主图，使用小贴纸密铺。".appLocalized
        }
    }

    var systemImageName: String {
        switch self {
        case .mixedFocus: return "square.grid.3x3.middle.filled"
        case .heroStatement: return "rectangle.inset.filled"
        case .balancedScatter: return "circle.grid.cross"
        case .miniPattern: return "circle.grid.3x3.fill"
        }
    }
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

    var localizedName: String {
        name.appLocalized
    }

    var localizedSubtitle: String {
        subtitle.appLocalized
    }

    var backgroundStickerOptions: [ThemeSkinBackgroundStickerOption] {
        switch assetNamespace {
        case "sky_concert":
            return [
                ThemeSkinBackgroundStickerOption(assetName: "sky_concert_decor_winged_unicorn_prince", displayName: "独角琴王子"),
                ThemeSkinBackgroundStickerOption(assetName: "sky_concert_decor_sky_balloon_doves", displayName: "云端热气球"),
                ThemeSkinBackgroundStickerOption(assetName: "sky_concert_decor_bunny_accordion_stage", displayName: "手风琴小兔"),
                ThemeSkinBackgroundStickerOption(assetName: "sky_concert_decor_whale_cloud_stars", displayName: "星云鲸鱼"),
                ThemeSkinBackgroundStickerOption(assetName: "sky_concert_decor_moon_star_clouds", displayName: "月亮云朵"),
                ThemeSkinBackgroundStickerOption(assetName: "sky_concert_decor_music_scroll_clouds", displayName: "云端乐谱")
            ]
        case "swan_dream":
            return [
                ThemeSkinBackgroundStickerOption(assetName: "swan_dream_decor_crowned_swan_clouds", displayName: "皇冠天鹅"),
                ThemeSkinBackgroundStickerOption(assetName: "swan_dream_decor_flying_swan_stars", displayName: "飞翔天鹅"),
                ThemeSkinBackgroundStickerOption(assetName: "swan_dream_decor_dream_castle_clouds", displayName: "梦境城堡"),
                ThemeSkinBackgroundStickerOption(assetName: "swan_dream_decor_ribbon_swan_clouds", displayName: "丝带天鹅"),
                ThemeSkinBackgroundStickerOption(assetName: "swan_dream_decor_moon_bow_bottle", displayName: "月亮瓶"),
                ThemeSkinBackgroundStickerOption(assetName: "swan_dream_decor_crystal_stars", displayName: "水晶星光")
            ]
        default:
            return []
        }
    }

    var defaultBackgroundHeroAssetName: String? {
        backgroundStickerOptions.first?.assetName
    }

    private static let allThemeSurfaceSlots = ThemeSkinSlot.allCases
    private static let coreDefaultEnabledSlots: [ThemeSkinSlot] = [
        .topBarMain,
        .topBarSegment,
        .topBarIconButton,
        .topBarAddButton,
        .tabBarMain,
        .tabBarItem,
        .statsCard,
        .wardrobeItemCard,
        .settingsGridCard,
        .sectionCard,
        .primaryButton,
        .iconCircleButton,
        .emptyState
    ]

    static let girlCloset = ThemeSkinProduct(
        id: "theme_skin.girl_closet",
        themeId: "theme_skin.girl_closet",
        name: "少女衣橱",
        subtitle: "旋转木马 · 奶白蕾丝 · 贴纸感装饰",
        basePrice: 99,
        vipPrice: 89,
        previewAssetNames: ["preview_store_hero"],
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

    static let skyConcert = ThemeSkinProduct(
        id: "theme_skin.sky_concert",
        themeId: "theme_skin.sky_concert",
        name: "天空音乐会",
        subtitle: "云端管弦 · 星河谱表 · 鎏金五线谱",
        basePrice: 99,
        vipPrice: 89,
        previewAssetNames: ["preview_store_hero"],
        supportedSlots: allThemeSurfaceSlots,
        defaultEnabledSlots: coreDefaultEnabledSlots
    )

    static let swanDream = ThemeSkinProduct(
        id: "theme_skin.swan_dream",
        themeId: "theme_skin.swan_dream",
        name: "天鹅入梦",
        subtitle: "月色湖面 · 天鹅羽翼 · 蕾丝纱裙",
        basePrice: 99,
        vipPrice: 89,
        previewAssetNames: ["preview_store_hero"],
        supportedSlots: allThemeSurfaceSlots,
        defaultEnabledSlots: coreDefaultEnabledSlots
    )

}

struct ThemeSkinBackgroundStickerOption: Identifiable, Codable, Equatable, Hashable {
    let assetName: String
    let displayName: String

    var id: String { assetName }

    var localizedDisplayName: String {
        displayName.appLocalized
    }
}

struct ThemeSkinBackgroundSelection: Codable, Equatable {
    var heroAssetName: String?
    var layoutPreset: ThemeSkinWallpaperLayoutPreset?
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
