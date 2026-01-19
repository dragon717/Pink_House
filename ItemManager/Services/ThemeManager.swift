import SwiftUI
import Observation

@Observable
class ThemeManager {
    static let shared = ThemeManager()
    
    var backgroundColorHex: String = "#F2F2F7" { // Default system grouped background
        didSet {
            UserDefaults.standard.set(backgroundColorHex, forKey: "theme_background_color")
        }
    }
    
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
        self.isBlurEnabled = UserDefaults.standard.bool(forKey: "theme_is_blur_enabled")
    }
    
    var backgroundColor: Color {
        Color(hex: backgroundColorHex)
    }
}
