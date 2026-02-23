import Foundation

/// 视频资源管理器
/// 负责管理视频资源的加载，支持 DEBUG 和 RELEASE 模式
/// - DEBUG 模式：从源代码目录直接加载（开发/模拟器使用）
/// - RELEASE 模式：从 App Bundle 加载（真机发布使用）
class VideoResourceManager {
    static let shared = VideoResourceManager()
    
    // 视频资源在源代码中的基础路径
    private let sourceBasePath = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/asserts"
    
    // 视频资源在 Bundle 中的子目录
    private let bundleSubdirectory = "asserts"
    
    private init() {}
    
    /// 查找视频文件的 URL
    /// - Parameter videoName: 视频名称（不含扩展名）
    /// - Returns: 视频文件的 URL，如果找不到则返回 nil
    func findVideoURL(name videoName: String) -> URL? {
        // 1. 如果是绝对路径，直接使用
        if videoName.hasPrefix("/") {
            let url = URL(fileURLWithPath: videoName)
            if FileManager.default.fileExists(atPath: videoName) {
                return url
            }
            print("VideoResourceManager: Absolute path not found: \(videoName)")
            return nil
        }
        
        // 2. 根据构建配置选择加载策略
        #if DEBUG
        // DEBUG 模式：优先从源代码目录加载
        if let url = findInSourceDirectory(name: videoName) {
            return url
        }
        #endif
        
        // 3. 从 Bundle 加载（RELEASE 模式或 DEBUG 模式下的 fallback）
        if let url = findInBundle(name: videoName) {
            return url
        }
        
        return nil
    }
    
    /// 从源代码目录查找视频（仅 DEBUG 模式使用）
    private func findInSourceDirectory(name videoName: String) -> URL? {
        // 确定子目录
        let subdirectory: String
        if videoName.hasPrefix("naicha_") {
            subdirectory = "naicha"
        } else if videoName.hasPrefix("maomao_") {
            subdirectory = "maomao"
        } else {
            subdirectory = ""
        }
        
        // 构建完整路径
        let path: String
        if subdirectory.isEmpty {
            path = "\(sourceBasePath)/\(videoName).mov"
        } else {
            path = "\(sourceBasePath)/\(subdirectory)/\(videoName).mov"
        }
        
        if FileManager.default.fileExists(atPath: path) {
            print("VideoResourceManager: Found video in source directory: \(path)")
            return URL(fileURLWithPath: path)
        }
        
        return nil
    }
    
    /// 从 App Bundle 查找视频
    private func findInBundle(name videoName: String) -> URL? {
        // 确定子目录
        let subdirectory: String
        if videoName.hasPrefix("naicha_") {
            subdirectory = "\(bundleSubdirectory)/naicha"
        } else if videoName.hasPrefix("maomao_") {
            subdirectory = "\(bundleSubdirectory)/maomao"
        } else {
            subdirectory = bundleSubdirectory
        }
        
        // 尝试查找 mov 文件
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mov", subdirectory: subdirectory) {
            print("VideoResourceManager: Found video in Bundle: \(url.lastPathComponent)")
            return url
        }
        
        // 回退到 mp4
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4", subdirectory: subdirectory) {
            print("VideoResourceManager: Found video in Bundle (mp4): \(url.lastPathComponent)")
            return url
        }
        
        return nil
    }
    
    /// 检查视频资源是否可用
    /// - Parameter videoName: 视频名称
    /// - Returns: 是否可用
    func isVideoAvailable(name videoName: String) -> Bool {
        return findVideoURL(name: videoName) != nil
    }
    
    /// 获取所有可用的视频名称列表（用于调试）
    func listAvailableVideos() -> [String] {
        var videos: [String] = []
        
        // 检查 naicha 目录
        let naichaPath = "\(sourceBasePath)/naicha"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: naichaPath) {
            for file in contents where file.hasSuffix(".mov") {
                videos.append(file.replacingOccurrences(of: ".mov", with: ""))
            }
        }
        
        // 检查 maomao 目录
        let maomaoPath = "\(sourceBasePath)/maomao"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: maomaoPath) {
            for file in contents where file.hasSuffix(".mov") {
                videos.append(file.replacingOccurrences(of: ".mov", with: ""))
            }
        }
        
        return videos.sorted()
    }
}
