import SwiftUI
import CoreText
import Combine

class FontManager: ObservableObject {
    static let shared = FontManager()
    
    // 硬编码路径 (仅供特定开发环境调试使用，真机环境应留空)
    static let defaultCustomFontPath = ""
    static let debugPath = defaultCustomFontPath
    
    // UserDefaults Keys
    private let kUserFontFileName = "UserCustomFontFileName"
    
    // 缓存已注册的字体名称
    @Published var registeredFontName: String?
    @Published var isUsingUserFont: Bool = false
    
    // 缓存已注册的字体 URL，避免重复注册导致系统日志报错
    private var registeredURLs = Set<URL>()
    
    private init() {
        // 初始化时检查是否在使用用户字体
        if let _ = UserDefaults.standard.string(forKey: kUserFontFileName) {
            isUsingUserFont = true
        }
    }
    
    // 获取当前自定义字体的名称 (会自动注册)
    func getCustomFontName() -> String? {
        if let name = registeredFontName {
            return name
        }
        return registerActiveFont()
    }
    
    // MARK: - User Font Management
    
    func importUserFont(from sourceURL: URL) -> Bool {
        // 1. 获取安全访问权限
        guard sourceURL.startAccessingSecurityScopedResource() else {
            print("FontManager: Failed to access security scoped resource")
            return false
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }
        
        // 2. 准备目标路径
        guard let userFontsDir = getUserFontsDirectory() else { return false }
        
        let fileName = sourceURL.lastPathComponent
        let destinationURL = userFontsDir.appendingPathComponent(fileName)
        
        // 3. 复制文件
        do {
            // 如果目标文件已存在，先删除
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            print("FontManager: Copied user font to \(destinationURL.path)")
            
            // 4. 更新状态
            UserDefaults.standard.set(fileName, forKey: kUserFontFileName)
            
            // 5. 重新注册
            // 注意：CTFontManager 不支持轻易卸载进程级字体，但我们可以尝试注册新字体
            // 实际上如果已经注册了A字体，现在注册B字体，getCustomFontName会返回B的名字
            // View层通过id变化或状态更新来刷新
            self.registeredFontName = nil // 清除缓存
            self.isUsingUserFont = true
            let _ = registerActiveFont()
            
            return true
            
        } catch {
            print("FontManager: Error importing font: \(error)")
            return false
        }
    }
    
    func resetToDefaultFont() {
        // 移除用户字体记录 (不一定要删除文件，保留文件以便后续可能再次选择? 还是删了吧保持干净)
        if let fileName = UserDefaults.standard.string(forKey: kUserFontFileName),
           let userFontsDir = getUserFontsDirectory() {
            let fileURL = userFontsDir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        UserDefaults.standard.removeObject(forKey: kUserFontFileName)
        
        self.registeredFontName = nil
        self.isUsingUserFont = false
        let _ = registerActiveFont()
    }
    
    // MARK: - Internal Registration Logic
    
    private func registerActiveFont() -> String? {
        var fontURL: URL?
        
        // 1. 尝试加载用户导入的字体
        if let userFileName = UserDefaults.standard.string(forKey: kUserFontFileName),
           let userFontsDir = getUserFontsDirectory() {
            let userFileURL = userFontsDir.appendingPathComponent(userFileName)
            if FileManager.default.fileExists(atPath: userFileURL.path) {
                fontURL = userFileURL
                print("FontManager: Using user imported font at \(userFileURL.path)")
            }
        }
        
        // 2. 如果没有用户字体，使用内置字体
        if fontURL == nil {
            fontURL = getBuiltInFontURL()
        }
        
        guard let finalURL = fontURL else {
            print("FontManager: No font file available")
            return nil
        }
        
        return registerFont(from: finalURL)
    }
    
    private func getBuiltInFontURL() -> URL? {
        // 尝试从 Bundle 获取
        if let bundleURL = Bundle.main.url(forResource: "也字工厂小石头", withExtension: "ttf") {
            return bundleURL
        } else if let bundleURL = Bundle.main.url(forResource: "也字工厂小石头", withExtension: "ttf", subdirectory: "asserts") {
            return bundleURL
        } else if let bundleURL = Bundle.main.url(forResource: "也字工厂小石头", withExtension: "ttf", subdirectory: "ItemManager/asserts") {
            return bundleURL
        }
        
        // 调试路径
        if FileManager.default.fileExists(atPath: FontManager.debugPath) {
            return URL(fileURLWithPath: FontManager.debugPath)
        }
        
        return nil
    }
    
    private func registerFont(from url: URL) -> String? {
        // 先尝试获取字体名称
        guard let fontDataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(fontDataProvider),
              let postScriptName = font.postScriptName as String? else {
            print("FontManager: Failed to parse font file at \(url)")
            return nil
        }
        
        // 检查是否已经注册过该 URL
        if registeredURLs.contains(url) {
            // print("FontManager: Font already registered (cached URL): \(postScriptName)")
            DispatchQueue.main.async {
                self.registeredFontName = postScriptName
            }
            return postScriptName
        }
        
        // 如果已经注册过这个名字，直接返回
        // 这里的 registeredFontName 是为了避免重复调用 CTFontManagerRegisterFontsForURL
        // 但如果切换了字体文件，我们需要允许重新注册流程（虽然 CTFontManager 可能会报错说已注册）
        
        // 使用 CTFontManagerRegisterFontsForURL 进行进程级注册
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            print("FontManager: Successfully registered font: \(postScriptName)")
            registeredURLs.insert(url)
            DispatchQueue.main.async {
                self.registeredFontName = postScriptName
            }
            return postScriptName
        } else {
            var errorDesc = "Unknown error"
            var errorCode = 0
            
            if let errorRef = error {
                 let nsError = errorRef.takeUnretainedValue() as Error as NSError
                 errorDesc = nsError.localizedDescription
                 errorCode = nsError.code
             }
            
            // CoreText error code 105 means "Already registered"
            print("FontManager: Error registering font (might be already registered): \(errorDesc)")
            
            // 如果是因为已注册导致的错误，我们将其标记为已注册，避免下次再报错
            if errorCode == 105 {
                registeredURLs.insert(url)
            }
            
            DispatchQueue.main.async {
                self.registeredFontName = postScriptName
            }
            return postScriptName
        }
    }
    
    private func getUserFontsDirectory() -> URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let userFontsDir = documentsURL.appendingPathComponent("UserFonts")
        
        if !FileManager.default.fileExists(atPath: userFontsDir.path) {
            do {
                try FileManager.default.createDirectory(at: userFontsDir, withIntermediateDirectories: true)
            } catch {
                print("FontManager: Failed to create UserFonts directory: \(error)")
                return nil
            }
        }
        
        return userFontsDir
    }
}
