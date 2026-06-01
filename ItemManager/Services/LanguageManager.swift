import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case portugueseBrazil = "pt-BR"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .portugueseBrazil: return "Português (Brasil)"
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .system: return "跟随系统".appLocalized
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .portugueseBrazil: return "Português (Brasil)"
        }
    }
}

@Observable
class LanguageManager {
    static let shared = LanguageManager()
    private static let selectedLanguageKey = "app.selected_language"
    private static let sourceLanguageFallbackIdentifiers: Set<String> = [
        AppLanguage.simplifiedChinese.rawValue,
        AppLanguage.traditionalChinese.rawValue,
        AppLanguage.english.rawValue
    ]
    
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
            if preferred.hasPrefix("zh-Hans") || preferred.hasPrefix("zh-CN") || preferred.hasPrefix("zh-SG") {
                return AppLanguage.simplifiedChinese.rawValue
            }
            if preferred.hasPrefix("en") {
                return AppLanguage.english.rawValue
            }
            if preferred.hasPrefix("ja") {
                return AppLanguage.japanese.rawValue
            }
            if preferred.hasPrefix("ko") {
                return AppLanguage.korean.rawValue
            }
            if preferred.hasPrefix("fr") {
                return AppLanguage.french.rawValue
            }
            if preferred.hasPrefix("de") {
                return AppLanguage.german.rawValue
            }
            if preferred.hasPrefix("es") {
                return AppLanguage.spanish.rawValue
            }
            if preferred.hasPrefix("pt") {
                return AppLanguage.portugueseBrazil.rawValue
            }
            return AppLanguage.english.rawValue
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

    private var englishFallbackBundle: Bundle? {
        guard let path = Bundle.main.path(forResource: AppLanguage.english.rawValue, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    func localizedString(forKey key: String) -> String {
        let value = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
        if value != key {
            return value
        }

        guard !Self.sourceLanguageFallbackIdentifiers.contains(localeIdentifier),
              let englishFallbackBundle else {
            return key
        }

        return englishFallbackBundle.localizedString(forKey: key, value: key, table: nil)
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
        LanguageManager.shared.localizedString(forKey: self)
    }

    func appLocalized(_ arguments: CVarArg...) -> String {
        String(format: appLocalized, locale: LanguageManager.shared.locale, arguments: arguments)
    }
}
