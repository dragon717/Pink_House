import SwiftUI
import Observation

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case color
    case image
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .color: return "纯色背景".appLocalized
        case .image: return "图片背景".appLocalized
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
        case .transparent: return "半透明".appLocalized
        case .fullyTransparent: return "全透明".appLocalized
        case .tinted: return "色调".appLocalized
        case .solid: return "经典".appLocalized
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
        case .transparent: return "半透明".appLocalized
        case .fullyTransparent: return "全透明".appLocalized
        case .tinted: return "色调".appLocalized
        case .solid: return "经典".appLocalized
        }
    }
}

@Observable
class ThemeManager {
    static let shared = ThemeManager()
    static var themeSkinBackgroundHarmonyAppendix: String {
        "为了让这套主题更完整，已帮你切回纯色背景；停用主题后可再使用图片背景。".appLocalized
    }

    static var themeSkinBackgroundLockAlertTitle: String {
        "先让主题保持成套吧".appLocalized
    }

    static func themeSkinBackgroundLockAlertMessage(activeThemeName: String?) -> String {
        let name = activeThemeName ?? "当前主题".appLocalized
        return "当前正在使用「%@」。图片背景会和主题装饰抢风格，已帮你保持纯色背景；停用主题后就可以继续换回自己的照片啦。".appLocalized(name)
    }
    
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

    // MARK: - Pet Chat Skin
    var petChatSkinTheme: PetChatSkinTheme = .classic {
        didSet {
            UserDefaults.standard.set(petChatSkinTheme.rawValue, forKey: "pet_chat_skin_theme")
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

    // 半透明模式默认100%透明度（完全不透明，即实色效果）
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

    // 图片填充色调配置
    var imageFillTintColorHex: String = "#FFB6C1" {
        didSet {
            UserDefaults.standard.set(imageFillTintColorHex, forKey: "theme_image_fill_tint_color")
        }
    }

    var imageFillTintOpacity: Double = 0.3 {
        didSet {
            UserDefaults.standard.set(imageFillTintOpacity, forKey: "theme_image_fill_tint_opacity")
        }
    }

    /// 图片填充色调颜色
    var imageFillTintColor: Color {
        Color(hex: imageFillTintColorHex)
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

    /// 卡片色调颜色 - 根据当前配色模式返回主题强调色或自定义色调色
    var cardTintColor: Color {
        if colorSchemeMode == .custom {
            // 客制化配色：使用当前主题的强调色
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            let colors = themeColorConfig.customColorConfig.currentCustom.textColors(forDarkMode: isDark)
            return colors.accent.color
        }
        // 魔法配色：使用自定义色调色
        return Color(hex: cardTintColorHex)
    }

    /// 卡片背景颜色 - 根据当前配色模式返回主题卡片背景色
    var cardBackgroundColor: Color {
        let isDark = UITraitCollection.current.userInterfaceStyle == .dark
        
        if colorSchemeMode == .custom {
            // 客制化配色：使用当前主题的卡片背景色
            let cardColors = themeColorConfig.customColorConfig.currentCustom.cardColors(forDarkMode: isDark)
            return cardColors.backgroundRGBA.color
        }
        
        // 魔法配色：基于用户设置的背景色智能生成卡片背景色
        // 根据背景色的亮度，生成与之协调的卡片背景色
        return generateMagicCardBackground(isDarkMode: isDark)
    }
    
    /// 为魔法配色智能生成卡片背景色
    private func generateMagicCardBackground(isDarkMode: Bool) -> Color {
        let bgColor = backgroundColor
        let isDarkBackground = bgColor.isDark
        
        // 提取背景色的HSB值
        let uiColor = UIColor(bgColor)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        
        guard uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            // 如果无法提取HSB，使用默认颜色
            return isDarkMode ? Color(white: 0.2) : Color(white: 0.95)
        }
        
        if isDarkMode {
            // 暗夜模式：生成比背景色稍亮的颜色，保持色调一致
            // 降低饱和度，提高亮度，使卡片有层次感但不过分鲜艳
            let newSaturation = max(saturation * 0.6, 0.1)
            let newBrightness = min(brightness * 1.3, 0.35)
            return Color(hue: Double(hue), saturation: Double(newSaturation), brightness: Double(newBrightness))
        } else {
            // 亮色模式：基于背景色生成柔和的卡片色
            if isDarkBackground {
                // 如果背景是深色，使用浅灰色作为卡片背景
                return Color(white: 0.95)
            } else {
                // 如果背景是浅色，生成与背景色调一致但更亮/更饱和的颜色
                // 降低饱和度使颜色更柔和，提高亮度使卡片突出
                let newSaturation = max(saturation * 0.4, 0.05)
                let newBrightness = min(brightness * 1.15, 0.98)
                return Color(hue: Double(hue), saturation: Double(newSaturation), brightness: Double(newBrightness))
            }
        }
    }

    // MARK: - Color Settings
    var backgroundColorHex: String = "#F4DADB" { // 默认浅樱粉背景色
        didSet {
            UserDefaults.standard.set(backgroundColorHex, forKey: "theme_background_color")
            updateAdaptivePalette()
        }
    }
    
    // MARK: - Image Settings
    var backgroundStyle: BackgroundStyle = .color {
        didSet {
            if backgroundStyle == .image,
               !isApplyingThemeBackgroundHarmony,
               isThemeSkinBackgroundImageLocked() {
                enforceThemeSkinBackgroundHarmonyIfNeeded()
                return
            }

            persistBackgroundStyle()
        }
    }
    private var isApplyingThemeBackgroundHarmony = false
    
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
            let colors = themeColorConfig.customColorConfig.currentCustom.textColors(forDarkMode: isDark)
            return colors.primary.color
        }
        return adaptivePalette.primary
    }
    /// 副文本色 (便捷访问) - 支持客制化配色
    var secondaryTextColor: Color {
        if colorSchemeMode == .custom {
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            let colors = themeColorConfig.customColorConfig.currentCustom.textColors(forDarkMode: isDark)
            return colors.secondary.color
        }
        return adaptivePalette.secondary
    }
    /// 辅助文本色 (便捷访问) - 支持客制化配色
    var tertiaryTextColor: Color {
        if colorSchemeMode == .custom {
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            let colors = themeColorConfig.customColorConfig.currentCustom.textColors(forDarkMode: isDark)
            return colors.tertiary.color
        }
        return adaptivePalette.tertiary
    }
    /// 强调色 (便捷访问) - 支持客制化配色
    var accentTextColor: Color {
        if colorSchemeMode == .custom {
            let isDark = UITraitCollection.current.userInterfaceStyle == .dark
            let colors = themeColorConfig.customColorConfig.currentCustom.textColors(forDarkMode: isDark)
            return colors.accent.color
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
        switch effectiveBackgroundStyle {
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

        // 半透明模式默认100%透明度（如果未设置则使用默认值1.0）
        if UserDefaults.standard.object(forKey: "theme_transparent_opacity") != nil {
            self.transparentOpacity = UserDefaults.standard.double(forKey: "theme_transparent_opacity")
        } else {
            self.transparentOpacity = 1.0
        }

        if UserDefaults.standard.object(forKey: "theme_tint_opacity") != nil {
            self.tintOpacity = UserDefaults.standard.double(forKey: "theme_tint_opacity")
        }

        if let savedCardTint = UserDefaults.standard.string(forKey: "theme_card_tint_color") {
            self.cardTintColorHex = savedCardTint
        }

        if let savedPetChatSkin = UserDefaults.standard.string(forKey: "pet_chat_skin_theme"),
           let skin = PetChatSkinTheme(rawValue: savedPetChatSkin) {
            self.petChatSkinTheme = skin
        }

        // 加载图片填充色调配置
        if let savedImageFillTint = UserDefaults.standard.string(forKey: "theme_image_fill_tint_color") {
            self.imageFillTintColorHex = savedImageFillTint
        }
        if UserDefaults.standard.object(forKey: "theme_image_fill_tint_opacity") != nil {
            self.imageFillTintOpacity = UserDefaults.standard.double(forKey: "theme_image_fill_tint_opacity")
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

        // 根据版本号强制设置默认预设方案（新版本时重置为莫妮卡主题）
        checkAndApplyVersionBasedDefaultTheme()

        enforceThemeSkinBackgroundHarmonyIfNeeded()

        // 初始化自适应调色板
        updateAdaptivePalette()
    }

    // MARK: - 版本控制默认主题

    /// 当前应用版本号（用于强制重置默认主题）
    private static let appVersionKey = "app_theme_version"
    private static let targetVersion = "1.0.3" // 目标版本号，当版本变化时触发重置

    /// 检查并根据版本号应用默认主题
    private func checkAndApplyVersionBasedDefaultTheme() {
        let savedVersion = UserDefaults.standard.string(forKey: Self.appVersionKey)
        let currentVersion = Self.targetVersion

        // 如果版本号不同，强制设置默认预设方案
        if savedVersion != currentVersion {
            print("🎨 [ThemeManager] 版本变化 detected: \(savedVersion ?? "nil") -> \(currentVersion)，强制设置经典样式为默认")

            // 强制设置为经典样式
            forceApplyDefaultStyle()

            // 保存新版本号
            UserDefaults.standard.set(currentVersion, forKey: Self.appVersionKey)
        }
    }

    /// 强制应用经典样式（作为 App 默认方案）
    private func forceApplyDefaultStyle() {
        // 1. 设置梦幻衣橱默认为经典样式
        UserDefaults.standard.set(WardrobeNavigationStyle.classic.rawValue, forKey: "UserPreference_WardrobeNavigationStyle")
        
        // 2. 检查用户是否已自定义图片背景，如果有则不覆盖
        let hasCustomImageBackground = (backgroundStyle == .image && backgroundImage != nil)
        
        if !hasCustomImageBackground {
            // 用户没有自定义图片背景，才应用默认柔和粉白主题
            self.backgroundColorHex = "#F4DADB"
            self.backgroundStyle = .color
            self.isBlurEnabled = false
            self.cardStyle = .solid

            // 重置为客制化配色模式，设置莫妮卡粉主题
            var newConfig = themeColorConfig
            newConfig.colorSchemeMode = .custom
            newConfig.customColorConfig.selectedPresetId = "monica_pink" // 莫妮卡粉主题 ID

            // 同步莫妮卡粉预设的颜色到 currentCustom
            let monicaPinkPreset = CustomColorPresets.monicaPink
            newConfig.customColorConfig.currentCustom.textPrimaryRGBA = monicaPinkPreset.textPrimaryRGBA
            newConfig.customColorConfig.currentCustom.textSecondaryRGBA = monicaPinkPreset.textSecondaryRGBA
            newConfig.customColorConfig.currentCustom.textTertiaryRGBA = monicaPinkPreset.textTertiaryRGBA
            newConfig.customColorConfig.currentCustom.textAccentRGBA = monicaPinkPreset.textAccentRGBA
            newConfig.customColorConfig.currentCustom.cardConfig = monicaPinkPreset.cardConfig

            // 同步暗夜模式配色
            if monicaPinkPreset.supportsDarkMode {
                newConfig.customColorConfig.currentCustom.darkTextPrimaryRGBA = monicaPinkPreset.darkTextPrimaryRGBA ?? monicaPinkPreset.textPrimaryRGBA
                newConfig.customColorConfig.currentCustom.darkTextSecondaryRGBA = monicaPinkPreset.darkTextSecondaryRGBA ?? monicaPinkPreset.textSecondaryRGBA
                newConfig.customColorConfig.currentCustom.darkTextTertiaryRGBA = monicaPinkPreset.darkTextTertiaryRGBA ?? monicaPinkPreset.textTertiaryRGBA
                newConfig.customColorConfig.currentCustom.darkTextAccentRGBA = monicaPinkPreset.darkTextAccentRGBA ?? monicaPinkPreset.textAccentRGBA
                newConfig.customColorConfig.currentCustom.darkCardConfig = monicaPinkPreset.darkCardConfig ?? monicaPinkPreset.cardConfig
            }

            newConfig.customColorConfig.currentCustom.updatedAt = Date()

            // 应用新配置（不触发保存，避免循环）
            isLoadingConfig = true
            themeColorConfig = newConfig
            isLoadingConfig = false

            // 保存配置
            saveThemeColorConfig()
            
            print("✅ [ThemeManager] 经典样式 + 莫妮卡粉主题已强制设置为默认方案")
        } else {
            // 用户已有自定义图片背景，只设置经典样式，不覆盖主题
            print("✅ [ThemeManager] 检测到自定义图片背景，仅设置经典样式，保留用户主题")
        }
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

        // 半透明模式默认100%透明度
        if UserDefaults.standard.object(forKey: "theme_transparent_opacity") != nil {
            self.transparentOpacity = UserDefaults.standard.double(forKey: "theme_transparent_opacity")
        } else {
            self.transparentOpacity = 1.0
        }

        if UserDefaults.standard.object(forKey: "theme_tint_opacity") != nil {
            self.tintOpacity = UserDefaults.standard.double(forKey: "theme_tint_opacity")
        }

        if let savedCardTint = UserDefaults.standard.string(forKey: "theme_card_tint_color") {
            self.cardTintColorHex = savedCardTint
        }

        if let savedPetChatSkin = UserDefaults.standard.string(forKey: "pet_chat_skin_theme"),
           let skin = PetChatSkinTheme(rawValue: savedPetChatSkin) {
            self.petChatSkinTheme = skin
        }

        // 重新加载图片填充色调配置
        if let savedImageFillTint = UserDefaults.standard.string(forKey: "theme_image_fill_tint_color") {
            self.imageFillTintColorHex = savedImageFillTint
        }
        if UserDefaults.standard.object(forKey: "theme_image_fill_tint_opacity") != nil {
            self.imageFillTintOpacity = UserDefaults.standard.double(forKey: "theme_image_fill_tint_opacity")
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

        enforceThemeSkinBackgroundHarmonyIfNeeded()
    }
    
    private func loadBackgroundImage() {
        reloadBackgroundImage()
    }

    var effectiveBackgroundStyle: BackgroundStyle {
        isThemeSkinBackgroundImageLocked() ? .color : backgroundStyle
    }

    func isThemeSkinBackgroundImageLocked(activeThemeId: String? = ThemeSkinManager.shared.activeThemeId) -> Bool {
        activeThemeId != nil
    }

    @discardableResult
    func enforceThemeSkinBackgroundHarmonyIfNeeded(activeThemeId: String? = ThemeSkinManager.shared.activeThemeId) -> Bool {
        guard isThemeSkinBackgroundImageLocked(activeThemeId: activeThemeId) else { return false }

        let savedStyle = UserDefaults.standard.string(forKey: "theme_background_style")
        let needsSwitch = backgroundStyle == .image || savedStyle == BackgroundStyle.image.rawValue
        guard needsSwitch else { return false }

        isApplyingThemeBackgroundHarmony = true
        backgroundStyle = .color
        isApplyingThemeBackgroundHarmony = false
        persistBackgroundStyle()
        return true
    }

    private func persistBackgroundStyle() {
        UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "theme_background_style")
        updateAdaptivePalette()
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
            let textColors = themeColorConfig.customColorConfig.currentCustom.textColors(forDarkMode: isDarkMode)
            
            return AdaptivePaletteV2.fromRGBA(
                primary: textColors.primary,
                secondary: textColors.secondary,
                tertiary: textColors.tertiary,
                accent: textColors.accent
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
                newConfig.customColorConfig.currentCustom.darkTextPrimaryRGBA = primaryRGBA
                newConfig.customColorConfig.currentCustom.darkTextSecondaryRGBA = secondaryRGBA
                newConfig.customColorConfig.currentCustom.darkTextTertiaryRGBA = tertiaryRGBA
                newConfig.customColorConfig.currentCustom.darkTextAccentRGBA = accentRGBA
            } else {
                newConfig.customColorConfig.currentCustom.textPrimaryRGBA = primaryRGBA
                newConfig.customColorConfig.currentCustom.textSecondaryRGBA = secondaryRGBA
                newConfig.customColorConfig.currentCustom.textTertiaryRGBA = tertiaryRGBA
                newConfig.customColorConfig.currentCustom.textAccentRGBA = accentRGBA
            }
            // 切换到自定义模式并更新时间
            newConfig.customColorConfig.selectedPresetId = nil
            newConfig.customColorConfig.currentCustom.updatedAt = Date()

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
