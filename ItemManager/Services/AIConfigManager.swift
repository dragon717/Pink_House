import Foundation

class AIConfigManager {
    static let shared = AIConfigManager()
    
    private(set) var apiKey: String?
    private(set) var dsApiKey: String?
    private(set) var dbApiKey: String?
    private(set) var ttsAppId: String?
    
    private init() {
        loadConfig()
    }
    
    private func loadConfig() {
        // 尝试从 Bundle 读取
        if let path = Bundle.main.path(forResource: "GenerativeAI-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
            
            if let key = dict["API_KEY"] as? String, !key.isEmpty {
                self.apiKey = key
            }
            
            if let dsKey = dict["DS_API_KEY"] as? String, !dsKey.isEmpty {
                self.dsApiKey = dsKey
            }
            
            if let dbKey = dict["DB_API_KEY"] as? String, !dbKey.isEmpty {
                self.dbApiKey = dbKey
            }
            
            if let appId = dict["TTS_APP_ID"] as? String, !appId.isEmpty {
                self.ttsAppId = appId
            }
            return
        }
        
        // 如果 Bundle 中没有（可能是开发环境未打包进 Bundle），尝试直接读取文件系统（仅限模拟器/调试）
        #if DEBUG
        let fileManager = FileManager.default
        // 假设项目根目录结构，尝试查找
        // 注意：在真机上这通常无效，但在模拟器或 Mac 开发环境可能有用
        // 这里主要依赖 Bundle 资源
        #endif
        
        print("⚠️ GenerativeAI-Info.plist not found or API_KEY is empty")
    }
    
    var isAIEnabled: Bool {
        return apiKey != nil || dsApiKey != nil || dbApiKey != nil
    }
}
