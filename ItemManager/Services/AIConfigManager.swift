import Foundation

class AIConfigManager {
    static let shared = AIConfigManager()
    
    private init() {}
    
    var apiKey: String? {
        guard let path = Bundle.main.path(forResource: "GenerativeAI-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let key = dict["API_KEY"] as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }
}
