import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .system: return "跟随系统".appLocalized
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        }
    }
}

@Observable
class LanguageManager {
    static let shared = LanguageManager()
    private static let selectedLanguageKey = "app.selected_language"
    
    var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: Self.selectedLanguageKey)
            if currentLanguage == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([currentLanguage.rawValue], forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
        }
    }

    var localeIdentifier: String {
        if currentLanguage == .system {
            let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
            if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-HK") || preferred.hasPrefix("zh-TW") {
                return AppLanguage.traditionalChinese.rawValue
            }
            if preferred.hasPrefix("en") {
                return AppLanguage.english.rawValue
            }
            return AppLanguage.simplifiedChinese.rawValue
        }
        return currentLanguage.rawValue
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
    
    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.selectedLanguageKey),
           let lang = AppLanguage(rawValue: stored) {
            self.currentLanguage = lang
        } else if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = languages.first,
           let lang = AppLanguage(rawValue: first) {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = .system
        }
    }
}

extension String {
    var appLocalized: String {
        LanguageManager.shared.localizedBundle.localizedString(forKey: self, value: self, table: nil)
    }

    func appLocalized(_ arguments: CVarArg...) -> String {
        String(format: appLocalized, locale: LanguageManager.shared.locale, arguments: arguments)
    }
}
