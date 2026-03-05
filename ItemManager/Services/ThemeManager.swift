import SwiftUI
import Observation

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case color
    case image
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .color: return "纯色背景"
        case .image: return "图片背景"
        }
    }
}

enum CardStyle: String, CaseIterable, Identifiable {
    case transparent
    case fullyTransparent
    case tinted
    case solid
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .transparent: return "半透明"
        case .fullyTransparent: return "全透明"
        case .tinted: return "色调"
        case .solid: return "经典"
        }
    }
}

enum SkirtFillMode: String, CaseIterable, Identifiable {
    case transparent
    case fullyTransparent
    case tinted
    case solid
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .transparent: return "半透明"
        case .fullyTransparent: return "全透明"
        case .tinted: return "色调"
        case .solid: return "经典"
        }
    }
}

@Observable
class ThemeManager {
    static let shared = ThemeManager()
    
    // MARK: - V2 Color System (New)
    /// 主题配色配置（支持备份恢复）
    var themeColorConfig: ThemeColorConfig = .default {
        didSet {
            // 加载配置时不重复保存
            if !isLoadingConfig {
                saveThemeColorConfig()
            }
            updateAdaptivePalette()
        }
    }
    
    /// 当前配色模式
    var colorSchemeMode: ColorSchemeMode {
        get { themeColorConfig.colorSchemeMode }
        set {
            var newConfig = themeColorConfig
            newConfig.colorSchemeMode = newValue
            themeColorConfig = newConfig
        }
    }
    
    // MARK: - Card Settings
    var cardStyle: CardStyle = .solid {
        didSet {
            UserDefaults.standard.set(cardStyle.rawValue, forKey: "theme_card_style")
        }
    }
    
    var skirtFillMode: SkirtFillMode = .transparent {
        didSet {
            UserDefaults.standard.set(skirtFillMode.rawValue, forKey: "theme_skirt_fill_mode")
        }
    }
    
    var transparentOpacity: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(transparentOpacity, forKey: "theme_transparent_opacity")
        }
    }
    
    var tintOpacity: Double = 0.2 {
        didSet {
            UserDefaults.standard.set(tintOpacity, forKey: "theme_tint_opacity")
        }
    }
    
    // Legacy property for compatibility or if needed
    var cardOpacity: Double {
        get {
            switch cardStyle {
            case .transparent: return transparentOpacity
            case .tinted: return tintOpacity
            default: return 1.0
            }
        }
        set {
            switch cardStyle {
            case .transparent: transparentOpacity = newValue
            case .tinted: tintOpacity = newValue
            default: break
            }
        }
    }
    
    var cardTintColorHex: String = "#FFB6C1" { // Default Light Pink
        didSet {
            UserDefaults.standard.set(cardTintColorHex, forKey: "theme_card_tint_color")
        }
    }
    
    var cardTintColor: Color {
        Color(hex: cardTintColorHex)
    }
    
    // MARK: - Color Settings
    var backgroundColorHex: String = "#F2F2F7" { // Default system grouped background
        didSet {
            UserDefaults.standard.set(backgroundColorHex, forKey: "theme_background_color")
            updateAdaptivePalette()
        }
    }
    
    // MARK: - Image Settings
    var backgroundStyle: BackgroundStyle = .color {
        didSet {
            UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "theme_background_style")
            updateAdaptivePalette()
        }
    }
    
    var backgroundOpacity: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(backgroundOpacity, forKey: "theme_background_opacity")
        }
    }
    
    var backgroundImage: UIImage? = nil {
        didSet {
            updateAdaptivePalette()
        }
    }
    var originalImage: UIImage? = nil // Cache for original image
    
    // MARK: - Common Settings
    var isBlurEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isBlurEnabled, forKey: "theme_is_blur_enabled")
        }
    }
    
    // MARK: - Smart Text Color Settings
    /// 是否启用智能字体配色
    var isSmartTextColorEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isSmartTextColorEnabled, forKey: "theme_smart_text_color_enabled")
            updateAdaptivePalette()
        }
    }
    
    /// 手动字体颜色 (当智能配色关闭时使用)
    var manualTextColorHex: String = "#000000" {
        didSet {
            UserDefaults.standard.set(manualTextColorHex, forKey: "theme_manual_text_color")
            updateAdaptivePalette()
        }
    }
    
    /// 当前自适应调色板 (根据背景自动计算)
    private(set) var adaptivePalette: AdaptivePalette = .lightBackground
    
    /// 主文本色 (便捷访问) - 支持客制化配色
    var primaryTextColor: Color {
        if colorSchemeMode == .custom {
            // 根据当前暗夜/亮色模式返回对应颜色
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            if isDark {
                return themeColorConfig.darkPrimaryRGBA.color
            } else {
                return themeColorConfig.customPrimaryRGBA.color
            }
        }
        return adaptivePalette.primary
    }
    /// 副文本色 (便捷访问) - 支持客制化配色
    var secondaryTextColor: Color {
        if colorSchemeMode == .custom {
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            if isDark {
                return themeColorConfig.darkSecondaryRGBA.color
            } else {
                return themeColorConfig.customSecondaryRGBA.color
            }
        }
        return adaptivePalette.secondary
    }
    /// 辅助文本色 (便捷访问) - 支持客制化配色
    var tertiaryTextColor: Color {
        if colorSchemeMode == .custom {
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            if isDark {
                return themeColorConfig.darkTertiaryRGBA.color
            } else {
                return themeColorConfig.customTertiaryRGBA.color
            }
        }
        return adaptivePalette.tertiary
    }
    /// 强调色 (便捷访问) - 支持客制化配色
    var accentTextColor: Color {
        if colorSchemeMode == .custom {
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            if isDark {
                return themeColorConfig.darkAccentRGBA.color
            } else {
                return themeColorConfig.customAccentRGBA.color
            }
        }
        return adaptivePalette.accent
    }
    
    /// 更新自适应调色板
    func updateAdaptivePalette() {
        if !isSmartTextColorEnabled {
            // 手动模式: 根据手动设置的颜色生成调色板
            let manualColor = Color(hex: manualTextColorHex)
            adaptivePalette = AdaptivePalette.generate(
                from: manualColor.isDark ? Color.white : Color.black,
                accentColor: cardTintColor
            )
            return
        }
        
        // 智能模式: 根据背景自动判断
        switch backgroundStyle {
        case .color:
            adaptivePalette = AdaptivePalette.generate(from: backgroundColor, accentColor: cardTintColor)
        case .image:
            // 图片背景: 尝试提取图片主色调,否则使用暗色预设
            if let image = backgroundImage,
               let avgColor = image.averageColor {
                adaptivePalette = AdaptivePalette.generate(from: Color(uiColor: avgColor), accentColor: cardTintColor)
            } else {
                adaptivePalette = .darkBackground
            }
        }
    }
    
    var selectionColorHex: String = "#A52A2A" // Brown
    
    // MARK: - Debug Parameters (Liquid Glass)
    #if DEBUG
    var dbg_glass_fallback_light: Double = 0.1 { didSet { UserDefaults.standard.set(dbg_glass_fallback_light, forKey: "dbg_glass_fallback_light") } }
    var dbg_glass_fallback_dark: Double = 0.05 { didSet { UserDefaults.standard.set(dbg_glass_fallback_dark, forKey: "dbg_glass_fallback_dark") } }
    
    var dbg_glass_border_light_start: Double = 0.4 { didSet { UserDefaults.standard.set(dbg_glass_border_light_start, forKey: "dbg_glass_border_light_start") } }
    var dbg_glass_border_light_end: Double = 0.1 { didSet { UserDefaults.standard.set(dbg_glass_border_light_end, forKey: "dbg_glass_border_light_end") } }
    var dbg_glass_border_dark_start: Double = 0.25 { didSet { UserDefaults.standard.set(dbg_glass_border_dark_start, forKey: "dbg_glass_border_dark_start") } }
    var dbg_glass_border_dark_end: Double = 0.05 { didSet { UserDefaults.standard.set(dbg_glass_border_dark_end, forKey: "dbg_glass_border_dark_end") } }
    
    // MARK: - Debug Parameters (Mica Tint)
    var dbg_mica_border_light_start: Double = 0.5 { didSet { UserDefaults.standard.set(dbg_mica_border_light_start, forKey: "dbg_mica_border_light_start") } }
    var dbg_mica_border_light_end: Double = 0.1 { didSet { UserDefaults.standard.set(dbg_mica_border_light_end, forKey: "dbg_mica_border_light_end") } }
    var dbg_mica_border_dark_start: Double = 0.3 { didSet { UserDefaults.standard.set(dbg_mica_border_dark_start, forKey: "dbg_mica_border_dark_start") } }
    var dbg_mica_border_dark_end: Double = 0.05 { didSet { UserDefaults.standard.set(dbg_mica_border_dark_end, forKey: "dbg_mica_border_dark_end") } }
    #endif
    
    init() {
        if let savedColor = UserDefaults.standard.string(forKey: "theme_background_color") {
            self.backgroundColorHex = savedColor
        }
        
        if let savedStyle = UserDefaults.standard.string(forKey: "theme_background_style"),
           let style = BackgroundStyle(rawValue: savedStyle) {
            self.backgroundStyle = style
        }
        
        // Load card settings
        if let savedCardStyle = UserDefaults.standard.string(forKey: "theme_card_style"),
           let style = CardStyle(rawValue: savedCardStyle) {
            self.cardStyle = style
        }
        
        if let savedSkirtFillMode = UserDefaults.standard.string(forKey: "theme_skirt_fill_mode"),
           let mode = SkirtFillMode(rawValue: savedSkirtFillMode) {
            self.skirtFillMode = mode
        }
        
        if UserDefaults.standard.object(forKey: "theme_transparent_opacity") != nil {
            self.transparentOpacity = UserDefaults.standard.double(forKey: "theme_transparent_opacity")
        }
        
        if UserDefaults.standard.object(forKey: "theme_tint_opacity") != nil {
            self.tintOpacity = UserDefaults.standard.double(forKey: "theme_tint_opacity")
        }
        
        if let savedCardTint = UserDefaults.standard.string(forKey: "theme_card_tint_color") {
            self.cardTintColorHex = savedCardTint
        }
        
        // 图片不透明度：强制默认100%，如果未设置则使用默认值1.0
        if UserDefaults.standard.object(forKey: "theme_background_opacity") != nil {
            self.backgroundOpacity = UserDefaults.standard.double(forKey: "theme_background_opacity")
        } else {
            self.backgroundOpacity = 1.0
        }
        
        self.isBlurEnabled = UserDefaults.standard.bool(forKey: "theme_is_blur_enabled")
        
        // Load Smart Text Color Settings
        self.isSmartTextColorEnabled = UserDefaults.standard.object(forKey: "theme_smart_text_color_enabled") != nil
            ? UserDefaults.standard.bool(forKey: "theme_smart_text_color_enabled")
            : true // 默认开启
        if let savedManualTextColor = UserDefaults.standard.string(forKey: "theme_manual_text_color") {
            self.manualTextColorHex = savedManualTextColor
        }
        
        // Load Debug Parameters
        #if DEBUG
        if UserDefaults.standard.object(forKey: "dbg_glass_fallback_light") != nil { self.dbg_glass_fallback_light = UserDefaults.standard.double(forKey: "dbg_glass_fallback_light") }
        if UserDefaults.standard.object(forKey: "dbg_glass_fallback_dark") != nil { self.dbg_glass_fallback_dark = UserDefaults.standard.double(forKey: "dbg_glass_fallback_dark") }
        
        if UserDefaults.standard.object(forKey: "dbg_glass_border_light_start") != nil { self.dbg_glass_border_light_start = UserDefaults.standard.double(forKey: "dbg_glass_border_light_start") }
        if UserDefaults.standard.object(forKey: "dbg_glass_border_light_end") != nil { self.dbg_glass_border_light_end = UserDefaults.standard.double(forKey: "dbg_glass_border_light_end") }
        if UserDefaults.standard.object(forKey: "dbg_glass_border_dark_start") != nil { self.dbg_glass_border_dark_start = UserDefaults.standard.double(forKey: "dbg_glass_border_dark_start") }
        if UserDefaults.standard.object(forKey: "dbg_glass_border_dark_end") != nil { self.dbg_glass_border_dark_end = UserDefaults.standard.double(forKey: "dbg_glass_border_dark_end") }
        
        if UserDefaults.standard.object(forKey: "dbg_mica_border_light_start") != nil { self.dbg_mica_border_light_start = UserDefaults.standard.double(forKey: "dbg_mica_border_light_start") }
        if UserDefaults.standard.object(forKey: "dbg_mica_border_light_end") != nil { self.dbg_mica_border_light_end = UserDefaults.standard.double(forKey: "dbg_mica_border_light_end") }
        if UserDefaults.standard.object(forKey: "dbg_mica_border_dark_start") != nil { self.dbg_mica_border_dark_start = UserDefaults.standard.double(forKey: "dbg_mica_border_dark_start") }
        if UserDefaults.standard.object(forKey: "dbg_mica_border_dark_end") != nil { self.dbg_mica_border_dark_end = UserDefaults.standard.double(forKey: "dbg_mica_border_dark_end") }
        #endif
        
        // Load image
        loadBackgroundImage()
        
        // Load V2 Color System Config
        loadThemeColorConfig()
        
        // 初始化自适应调色板
        updateAdaptivePalette()
    }
    
    var backgroundColor: Color {
        Color(hex: backgroundColorHex)
    }
    
    func getOriginalImageURL() -> URL? {
        return originalImageURL
    }
    
    private var imageURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("theme_background_image.png")
    }
    
    private var originalImageURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("theme_background_image_original.png")
    }
    
    func setBackgroundImage(_ image: UIImage, isOriginal: Bool = false) {
        // Always update the display image
        self.backgroundImage = image
        
        // Save display image
        if let data = image.pngData(), let url = imageURL {
            try? data.write(to: url)
        }
        
        // If this is a new original image (from picker), save it separately
        if isOriginal {
            self.originalImage = image // Update cache
            if let data = image.pngData(), let url = originalImageURL {
                try? data.write(to: url)
            }
        }
    }
    
    func getOriginalImage() -> UIImage? {
        // Return cached original image if available
        if let cached = originalImage {
            return cached
        }
        
        // Try load from disk
        if let url = originalImageURL {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                self.originalImage = image // Cache it
                return image
            }
        }
        
        return backgroundImage // Fallback to current image if original not found
    }
    
    func reloadBackgroundImage() {
        if let url = imageURL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            self.backgroundImage = image
        } else {
            // 如果文件不存在（可能被删除了），需要重置
            self.backgroundImage = nil
        }
        
        // Preload original image to cache
        if let url = originalImageURL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            self.originalImage = image
        } else {
            self.originalImage = nil
        }
        
        // Refresh properties from UserDefaults in case they were restored
        if let savedColor = UserDefaults.standard.string(forKey: "theme_background_color") {
            self.backgroundColorHex = savedColor
        }
        
        if let savedStyle = UserDefaults.standard.string(forKey: "theme_background_style"),
           let style = BackgroundStyle(rawValue: savedStyle) {
            self.backgroundStyle = style
        }
        
        // Reload card settings
        if let savedCardStyle = UserDefaults.standard.string(forKey: "theme_card_style"),
           let style = CardStyle(rawValue: savedCardStyle) {
            self.cardStyle = style
        }
        
        if UserDefaults.standard.object(forKey: "theme_transparent_opacity") != nil {
            self.transparentOpacity = UserDefaults.standard.double(forKey: "theme_transparent_opacity")
        }
        
        if UserDefaults.standard.object(forKey: "theme_tint_opacity") != nil {
            self.tintOpacity = UserDefaults.standard.double(forKey: "theme_tint_opacity")
        }
        
        if let savedCardTint = UserDefaults.standard.string(forKey: "theme_card_tint_color") {
            self.cardTintColorHex = savedCardTint
        }
        
        // 图片不透明度：强制默认100%，如果未设置则使用默认值1.0
        if UserDefaults.standard.object(forKey: "theme_background_opacity") != nil {
            self.backgroundOpacity = UserDefaults.standard.double(forKey: "theme_background_opacity")
        } else {
            self.backgroundOpacity = 1.0
        }
        
        self.isBlurEnabled = UserDefaults.standard.bool(forKey: "theme_is_blur_enabled")
        
        // Reload Smart Text Color Settings
        self.isSmartTextColorEnabled = UserDefaults.standard.object(forKey: "theme_smart_text_color_enabled") != nil
            ? UserDefaults.standard.bool(forKey: "theme_smart_text_color_enabled")
            : true
        if let savedManualTextColor = UserDefaults.standard.string(forKey: "theme_manual_text_color") {
            self.manualTextColorHex = savedManualTextColor
        }
        
        // Load Debug Parameters
        #if DEBUG
        if UserDefaults.standard.object(forKey: "dbg_glass_fallback_light") != nil { self.dbg_glass_fallback_light = UserDefaults.standard.double(forKey: "dbg_glass_fallback_light") }
        if UserDefaults.standard.object(forKey: "dbg_glass_fallback_dark") != nil { self.dbg_glass_fallback_dark = UserDefaults.standard.double(forKey: "dbg_glass_fallback_dark") }
        
        if UserDefaults.standard.object(forKey: "dbg_glass_border_light_start") != nil { self.dbg_glass_border_light_start = UserDefaults.standard.double(forKey: "dbg_glass_border_light_start") }
        if UserDefaults.standard.object(forKey: "dbg_glass_border_light_end") != nil { self.dbg_glass_border_light_end = UserDefaults.standard.double(forKey: "dbg_glass_border_light_end") }
        if UserDefaults.standard.object(forKey: "dbg_glass_border_dark_start") != nil { self.dbg_glass_border_dark_start = UserDefaults.standard.double(forKey: "dbg_glass_border_dark_start") }
        if UserDefaults.standard.object(forKey: "dbg_glass_border_dark_end") != nil { self.dbg_glass_border_dark_end = UserDefaults.standard.double(forKey: "dbg_glass_border_dark_end") }
        
        if UserDefaults.standard.object(forKey: "dbg_mica_border_light_start") != nil { self.dbg_mica_border_light_start = UserDefaults.standard.double(forKey: "dbg_mica_border_light_start") }
        if UserDefaults.standard.object(forKey: "dbg_mica_border_light_end") != nil { self.dbg_mica_border_light_end = UserDefaults.standard.double(forKey: "dbg_mica_border_light_end") }
        if UserDefaults.standard.object(forKey: "dbg_mica_border_dark_start") != nil { self.dbg_mica_border_dark_start = UserDefaults.standard.double(forKey: "dbg_mica_border_dark_start") }
        if UserDefaults.standard.object(forKey: "dbg_mica_border_dark_end") != nil { self.dbg_mica_border_dark_end = UserDefaults.standard.double(forKey: "dbg_mica_border_dark_end") }
        #endif
    }
    
    private func loadBackgroundImage() {
        reloadBackgroundImage()
    }
    
    // MARK: - V2 Color System Methods
    
    /// 保存主题配色配置
    func saveThemeColorConfig() {
        if let encoded = try? JSONEncoder().encode(themeColorConfig) {
            UserDefaults.standard.set(encoded, forKey: "theme_color_config_v2")
        }
    }
    
    /// 加载主题配色配置
    private var isLoadingConfig = false
    
    func loadThemeColorConfig() {
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        
        if let data = UserDefaults.standard.data(forKey: "theme_color_config_v2"),
           let config = try? JSONDecoder().decode(ThemeColorConfig.self, from: data) {
            self.themeColorConfig = config
        }
    }
    
    /// 获取容器就近调色板
    func getPaletteForContainer(
        containerBackground: ContainerBackgroundType,
        colorScheme: ColorScheme,
        overrideAccent: Color? = nil
    ) -> AdaptivePaletteV2 {
        let accent = overrideAccent ?? cardTintColor
        
        // 判断当前是亮色还是暗色模式
        let isDarkMode: Bool
        if themeColorConfig.followSystemDarkMode {
            isDarkMode = colorScheme == .dark
        } else {
            // 如果不跟随系统，根据容器背景判断
            isDarkMode = containerBackground.isDark
        }
        
        switch colorSchemeMode {
        case .magic:
            // 魔法配色：根据容器背景生成
            return AdaptivePaletteV2.generate(
                from: backgroundColor,
                isDark: isDarkMode,
                accentColor: accent,
                containerBackground: containerBackground
            )
            
        case .custom:
            // 客制化配色：根据当前模式选择颜色
            let primaryRGBA = isDarkMode ? themeColorConfig.darkPrimaryRGBA : themeColorConfig.customPrimaryRGBA
            let secondaryRGBA = isDarkMode ? themeColorConfig.darkSecondaryRGBA : themeColorConfig.customSecondaryRGBA
            let tertiaryRGBA = isDarkMode ? themeColorConfig.darkTertiaryRGBA : themeColorConfig.customTertiaryRGBA
            let accentRGBA = isDarkMode ? themeColorConfig.darkAccentRGBA : themeColorConfig.customAccentRGBA
            
            print("🎨 getPaletteForContainer (custom): Primary RGB = \(primaryRGBA.r), \(primaryRGBA.g), \(primaryRGBA.b)")
            
            return AdaptivePaletteV2.fromRGBA(
                primary: primaryRGBA,
                secondary: secondaryRGBA,
                tertiary: tertiaryRGBA,
                accent: accentRGBA
            )
        }
    }
    
    /// 更新客制化颜色（当前模式）
    func updateCustomColors(
        primary: Color,
        secondary: Color,
        tertiary: Color,
        accent: Color,
        forDarkMode: Bool? = nil
    ) {
        let isDark = forDarkMode ?? (UITraitCollection.current.userInterfaceStyle == .dark)

        if let primaryRGBA = primary.rgba,
           let secondaryRGBA = secondary.rgba,
           let tertiaryRGBA = tertiary.rgba,
           let accentRGBA = accent.rgba {

            // 创建新的配置副本，修改后重新赋值以触发 didSet
            var newConfig = themeColorConfig

            if isDark {
                newConfig.darkPrimaryRGBA = primaryRGBA
                newConfig.darkSecondaryRGBA = secondaryRGBA
                newConfig.darkTertiaryRGBA = tertiaryRGBA
                newConfig.darkAccentRGBA = accentRGBA
            } else {
                newConfig.customPrimaryRGBA = primaryRGBA
                newConfig.customSecondaryRGBA = secondaryRGBA
                newConfig.customTertiaryRGBA = tertiaryRGBA
                newConfig.customAccentRGBA = accentRGBA
            }

            // 重新赋值以触发 didSet 和视图更新
            themeColorConfig = newConfig
            
            print("✅ ThemeManager: Custom colors updated - Primary: \(primaryRGBA.r), \(primaryRGBA.g), \(primaryRGBA.b)")
        } else {
            print("❌ ThemeManager: Failed to convert colors to RGBA")
        }
    }
    
    /// 切换配色模式
    func switchColorSchemeMode(to mode: ColorSchemeMode) {
        var newConfig = themeColorConfig
        newConfig.colorSchemeMode = mode
        themeColorConfig = newConfig  // 重新赋值触发 didSet
    }
}
