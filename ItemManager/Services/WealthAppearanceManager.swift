import SwiftUI
import Observation

@Observable
class WealthAppearanceManager {
    static let shared = WealthAppearanceManager()
    
    // MARK: - Properties
    // Dictionary to store images per currency and denomination
    // Key format: "CurrencyType_DenominationValue"
    // e.g. "rmb_100", "jpy_10000"
    var customImages: [String: UIImage] = [:]
    
    // Dictionary to store dominant colors per currency and denomination
    var customColors: [String: Color] = [:]
    
    // Custom container background image
    var containerBackgroundImage: UIImage?
    
    // MARK: - Settings
    var shouldShowWealthContainerBackground: Bool {
        didSet {
            UserDefaults.standard.set(shouldShowWealthContainerBackground, forKey: "shouldShowWealthContainerBackground")
        }
    }
    
    // MARK: - Initialization
    init() {
        self.shouldShowWealthContainerBackground = UserDefaults.standard.object(forKey: "shouldShowWealthContainerBackground") as? Bool ?? false
        loadImages()
    }
    
    // MARK: - Helper
    private func imageKey(currency: CurrencyType, denominationValue: Int) -> String {
        return "\(currency.rawValue)_\(denominationValue)"
    }
    
    private func imageURL(currency: CurrencyType, denominationValue: Int) -> URL? {
        let filename = "wealth_\(currency.rawValue)_\(denominationValue).png"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(filename)
    }
    
    private var containerBackgroundImageURL: URL? {
        let filename = "wealth_container_background.png"
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(filename)
    }
    
    // MARK: - Methods
    
    func setContainerBackgroundImage(_ image: UIImage) {
        if let data = image.pngData(), let url = containerBackgroundImageURL {
            try? data.write(to: url)
        }
        self.containerBackgroundImage = image
    }
    
    func removeContainerBackgroundImage() {
        if let url = containerBackgroundImageURL {
            try? FileManager.default.removeItem(at: url)
        }
        self.containerBackgroundImage = nil
    }
    
    func setCustomImage(currency: CurrencyType, denominationValue: Int, image: UIImage) {
        // Save to disk
        if let data = image.pngData(), let url = imageURL(currency: currency, denominationValue: denominationValue) {
            try? data.write(to: url)
        }
        
        // Update memory
        let key = imageKey(currency: currency, denominationValue: denominationValue)
        customImages[key] = image
        
        // Extract and cache color
        if let color = image.averageColor {
            customColors[key] = Color(uiColor: color)
        }
    }
    
    func removeCustomImage(currency: CurrencyType, denominationValue: Int) {
        // Remove from disk
        if let url = imageURL(currency: currency, denominationValue: denominationValue) {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Update memory
        let key = imageKey(currency: currency, denominationValue: denominationValue)
        customImages.removeValue(forKey: key)
        customColors.removeValue(forKey: key)
    }
    
    func getCustomImage(currency: CurrencyType, denominationValue: Int) -> UIImage? {
        let key = imageKey(currency: currency, denominationValue: denominationValue)
        return customImages[key]
    }
    
    func getCustomColor(currency: CurrencyType, denominationValue: Int) -> Color? {
        let key = imageKey(currency: currency, denominationValue: denominationValue)
        return customColors[key]
    }
    
    private func loadImages() {
        // Pre-load common denominations to avoid IO on main thread during scroll?
        // Or just load on demand?
        // For now, let's load all known possible denominations if we can, or just iterate file system?
        // Iterating file system might be safer to catch all.

        // Known denominations
        let rmbDenominations = [100, 50, 20, 10, 5, 1]
        let jpyDenominations = [10000, 5000, 1000] // Common JPY notes
        let usdDenominations = [100, 50, 20, 10, 5, 2, 1] // USD notes (包括2美元)

        for val in rmbDenominations {
            loadSingleImage(currency: .rmb, val: val)
        }

        for val in jpyDenominations {
            loadSingleImage(currency: .jpy, val: val)
        }

        for val in usdDenominations {
            loadSingleImage(currency: .usd, val: val)
        }

        // Load container background
        if let url = containerBackgroundImageURL,
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            self.containerBackgroundImage = image
        }
    }
    
    private func loadSingleImage(currency: CurrencyType, val: Int) {
        if let url = imageURL(currency: currency, denominationValue: val),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            let key = imageKey(currency: currency, denominationValue: val)
            customImages[key] = image
            
            // Extract color on load
            if let color = image.averageColor {
                customColors[key] = Color(uiColor: color)
            }
        }
    }
}
