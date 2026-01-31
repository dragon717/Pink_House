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

@Observable
class ThemeManager {
    static let shared = ThemeManager()
    
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
    
    // MARK: - Common Settings
    var isBlurEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isBlurEnabled, forKey: "theme_is_blur_enabled")
        }
    }
    
    // 预留
    var textColorHex: String = "#000000"
    var selectionColorHex: String = "#A52A2A" // Brown
    
    init() {
        if let savedColor = UserDefaults.standard.string(forKey: "theme_background_color") {
            self.backgroundColorHex = savedColor
        }
        
        if let savedStyle = UserDefaults.standard.string(forKey: "theme_background_style"),
           let style = BackgroundStyle(rawValue: savedStyle) {
            self.backgroundStyle = style
        }
        
        // Load opacity, default to 1.0 if not set (register defaults would be better, but this works)
        if UserDefaults.standard.object(forKey: "theme_background_opacity") != nil {
            self.backgroundOpacity = UserDefaults.standard.double(forKey: "theme_background_opacity")
        }
        
        self.isBlurEnabled = UserDefaults.standard.bool(forKey: "theme_is_blur_enabled")
        
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
            if let data = image.pngData(), let url = originalImageURL {
                try? data.write(to: url)
            }
        }
    }
    
    func getOriginalImage() -> UIImage? {
        if let url = originalImageURL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            return image
        }
        return backgroundImage // Fallback to current image if original not found
    }
    
    private func loadBackgroundImage() {
        if let url = imageURL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            self.backgroundImage = image
        }
    }
}
