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
    case tinted
    case solid
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .transparent: return "透明"
        case .tinted: return "色调"
        case .solid: return "经典"
        }
    }
}

@Observable
class ThemeManager {
    static let shared = ThemeManager()
    
    // MARK: - Card Settings
    var cardStyle: CardStyle = .solid {
        didSet {
            UserDefaults.standard.set(cardStyle.rawValue, forKey: "theme_card_style")
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
        }
    }
    
    // MARK: - Image Settings
    var backgroundStyle: BackgroundStyle = .color {
        didSet {
            UserDefaults.standard.set(backgroundStyle.rawValue, forKey: "theme_background_style")
        }
    }
    
    var backgroundOpacity: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(backgroundOpacity, forKey: "theme_background_opacity")
        }
    }
    
    var backgroundImage: UIImage? = nil
    var originalImage: UIImage? = nil // Cache for original image
    
    // MARK: - Common Settings
    var isBlurEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isBlurEnabled, forKey: "theme_is_blur_enabled")
        }
    }
    
    // 预留
    var textColorHex: String = "#000000"
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
        
        if UserDefaults.standard.object(forKey: "theme_transparent_opacity") != nil {
            self.transparentOpacity = UserDefaults.standard.double(forKey: "theme_transparent_opacity")
        }
        
        if UserDefaults.standard.object(forKey: "theme_tint_opacity") != nil {
            self.tintOpacity = UserDefaults.standard.double(forKey: "theme_tint_opacity")
        }
        
        if let savedCardTint = UserDefaults.standard.string(forKey: "theme_card_tint_color") {
            self.cardTintColorHex = savedCardTint
        }
        
        // Load opacity, default to 1.0 if not set (register defaults would be better, but this works)
        if UserDefaults.standard.object(forKey: "theme_background_opacity") != nil {
            self.backgroundOpacity = UserDefaults.standard.double(forKey: "theme_background_opacity")
        }
        
        self.isBlurEnabled = UserDefaults.standard.bool(forKey: "theme_is_blur_enabled")
        
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
        
        self.backgroundOpacity = UserDefaults.standard.double(forKey: "theme_background_opacity")
        // Handle case where opacity might be 0.0 if key missing, but default logic in init handled it. 
        // Here we just trust UserDefaults which was just restored.
        if self.backgroundOpacity == 0.0 && UserDefaults.standard.object(forKey: "theme_background_opacity") == nil {
            self.backgroundOpacity = 1.0
        }
        
        self.isBlurEnabled = UserDefaults.standard.bool(forKey: "theme_is_blur_enabled")
        
        // Load Debug Parameters
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
    }
    
    private func loadBackgroundImage() {
        reloadBackgroundImage()
    }
}
