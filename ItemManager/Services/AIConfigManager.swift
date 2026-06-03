import Foundation

class AIConfigManager {
    static let shared = AIConfigManager()
    
    private(set) var apiKey: String?
    private(set) var dsApiKey: String?
    private(set) var dbApiKey: String?
    private(set) var qwenApiKey: String?
    private(set) var minimaxApiKey: String?
    private(set) var ttsAppId: String?
    
    private init() {
        loadConfig()
    }

    func reloadConfig() {
        apiKey = nil
        dsApiKey = nil
        dbApiKey = nil
        qwenApiKey = nil
        minimaxApiKey = nil
        ttsAppId = nil
        loadConfig()
    }
    
    private func loadConfig() {
        guard let url = Bundle.main.url(forResource: "GenerativeAI-Info", withExtension: "plist") else {
            print("⚠️ GenerativeAI-Info.plist not found in app bundle")
            return
        }

        guard
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            print("⚠️ GenerativeAI-Info.plist exists but could not be parsed")
            return
        }

        apiKey = nonEmptyConfigValue(dict["API_KEY"])
        dsApiKey = nonEmptyConfigValue(dict["DS_API_KEY"])
        dbApiKey = nonEmptyConfigValue(dict["DB_API_KEY"])
        qwenApiKey = nonEmptyConfigValue(dict["QWEN_API_KEY"])
        minimaxApiKey = nonEmptyConfigValue(dict["MINIMAX_API_KEY"])
        ttsAppId = nonEmptyConfigValue(dict["TTS_APP_ID"])

        let loadedKeyNames = [
            ("API_KEY", apiKey),
            ("DS_API_KEY", dsApiKey),
            ("DB_API_KEY", dbApiKey),
            ("QWEN_API_KEY", qwenApiKey),
            ("MINIMAX_API_KEY", minimaxApiKey),
            ("TTS_APP_ID", ttsAppId)
        ]
            .compactMap { entry -> String? in
                entry.1 == nil ? nil : entry.0
            }

        if loadedKeyNames.isEmpty {
            print("⚠️ GenerativeAI-Info.plist loaded but all AI config values are empty")
        } else {
            print("✅ GenerativeAI-Info.plist loaded keys: \(loadedKeyNames.joined(separator: ", "))")
        }
    }

    private func nonEmptyConfigValue(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    var isAIEnabled: Bool {
        return apiKey != nil || dsApiKey != nil || dbApiKey != nil || minimaxApiKey != nil
    }
}
