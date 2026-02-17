//
//  ClothingShareCardView.swift
//  ItemManager
//
//  裙子详情分享卡片视图 - 正反面都显示裙子主图+详细信息
//  使用莫妮卡色系配色方案
//

import SwiftUI

// MARK: - 莫妮卡色系配色
struct MonicaColors {
    // 主色调 - 莫妮卡粉
    static let primaryPink = Color(hex: "FF9AA2")
    static let lightPink = Color(hex: "FFB7B2")
    static let softPink = Color(hex: "FFDAC1")
    
    // 辅助色
    static let mintGreen = Color(hex: "E2F0CB")
    static let skyBlue = Color(hex: "B5EAD7")
    static let lavender = Color(hex: "C7CEEA")
    
    // 背景色
    static let creamBackground = Color(hex: "FFF9F5")
    static let warmWhite = Color(hex: "FFFBF7")
    
    // 文字色
    static let darkText = Color(hex: "4A4A4A")
    static let mediumText = Color(hex: "6B6B6B")
    static let lightText = Color(hex: "9B9B9B")
    
    // 渐变
    static var cardGradient: LinearGradient {
        LinearGradient(
            colors: [primaryPink, lightPink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [creamBackground, softPink.opacity(0.3)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - 粉边白边文字修饰符
struct PinkStrokeText: ViewModifier {
    let strokeWidth: CGFloat
    let strokeColor: Color
    
    func body(content: Content) -> some View {
        content
            .foregroundColor(.white)
            .shadow(color: strokeColor, radius: strokeWidth / 2, x: 0, y: 0)
            .shadow(color: strokeColor, radius: strokeWidth / 2, x: 0, y: 0)
            .shadow(color: strokeColor, radius: strokeWidth / 2, x: 0, y: 0)
            .shadow(color: strokeColor, radius: strokeWidth / 2, x: 0, y: 0)
    }
}

extension View {
    func pinkStrokeText(strokeWidth: CGFloat = 4, strokeColor: Color = MonicaColors.primaryPink) -> some View {
        self.modifier(PinkStrokeText(strokeWidth: strokeWidth, strokeColor: strokeColor))
    }
}

// MARK: - 裙子分享卡片内容（正反面相同）
struct ClothingShareCardContentView: View {
    let clothing: Clothing
    let image: UIImage?
    var fontProvider: FontProvider = DefaultFontProvider()
    
    var body: some View {
        VStack(spacing: 12) {
            // 裙子图片
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: MonicaColors.primaryPink.opacity(0.3), radius: 8, x: 0, y: 4)
            } else {
                // 占位图
                RoundedRectangle(cornerRadius: 12)
                    .fill(MonicaColors.softPink.opacity(0.3))
                    .frame(width: 160, height: 220)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundColor(MonicaColors.primaryPink.opacity(0.5))
                    )
            }
            
            // 详细信息 - 与图片等宽
            VStack(alignment: .leading, spacing: 6) {
                // 名称
                Text(clothing.name)
                    .font(fontProvider.titleFont())
                    .pinkStrokeText(strokeWidth: 3, strokeColor: MonicaColors.primaryPink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 品牌
                if let brand = clothing.brand {
                    ShareInfoRow(title: "品牌", value: brand.name, fontProvider: fontProvider)
                }
                
                // 颜色
                if !clothing.colors.isEmpty {
                    ShareInfoRow(title: "颜色", value: clothing.colors, fontProvider: fontProvider)
                }
                
                // 型色
                if !clothing.types.isEmpty {
                    ShareInfoRow(title: "型色", value: clothing.types, fontProvider: fontProvider)
                }
                
                // 小物
                if !clothing.accessories.isEmpty {
                    ShareInfoRow(title: "小物", value: clothing.accessories, fontProvider: fontProvider)
                }
            }
            .frame(width: 160)
            
            Spacer()
        }
        .padding(12)
    }
}

// MARK: - 分享卡片信息行
struct ShareInfoRow: View {
    let title: String
    let value: String
    var fontProvider: FontProvider = DefaultFontProvider()
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(fontProvider.captionFont())
                .foregroundColor(MonicaColors.mediumText)
                .frame(width: 40, alignment: .leading)
            
            Text(value)
                .font(fontProvider.bodyFont())
                .foregroundColor(MonicaColors.darkText)
                .lineLimit(1)
            
            Spacer()
        }
    }
}

// MARK: - 字体协议（预留接口）
protocol FontProvider {
    func titleFont() -> Font
    func bodyFont() -> Font
    func captionFont() -> Font
}

// MARK: - EnvironmentKey for FontProvider
struct FontProviderKey: EnvironmentKey {
    static let defaultValue: FontProvider = DefaultFontProvider()
}

extension EnvironmentValues {
    var fontProvider: FontProvider {
        get { self[FontProviderKey.self] }
        set { self[FontProviderKey.self] = newValue }
    }
}

// MARK: - 默认字体提供器
struct DefaultFontProvider: FontProvider {
    func titleFont() -> Font {
        return .system(size: 18, weight: .bold)
    }
    
    func bodyFont() -> Font {
        return .system(size: 14, weight: .medium)
    }
    
    func captionFont() -> Font {
        return .system(size: 12, weight: .regular)
    }
}

import CoreText

// MARK: - 自定义字体提供器（中文：端庄宋体，英文：Lovers Quarrel）
struct CustomFontProvider: FontProvider {
    // 中文字体文件名和注册名
    private let chineseFontFile = "XCDUANZHUANGSONGTI"
    private var chineseFontName = "XCDuanZhuangSongTi"
    // 英文字体文件名和注册名
    private let englishFontFile = "LoversQuarrel-Regular"
    private var englishFontName = "LoversQuarrel-Regular"
    
    // 静态缓存：已注册的字体 URL 和对应的 PostScript 名称
    private static var registeredFonts: [URL: String] = [:]
    
    init() {
        // 注册字体并获取实际的 PostScript 名称
        registerFonts()
    }
    
    private mutating func registerFonts() {
        // 注册中文字体
        if let chineseFontURL = Bundle.main.url(forResource: chineseFontFile, withExtension: "ttf") {
            if let name = registerFontIfNeeded(from: chineseFontURL) {
                chineseFontName = name
            }
        } else if let chineseFontURL = Bundle.main.url(forResource: chineseFontFile, withExtension: "ttf", subdirectory: "asserts") {
            if let name = registerFontIfNeeded(from: chineseFontURL) {
                chineseFontName = name
            }
        } else {
            // 尝试从文件路径直接加载（开发调试使用）
            let directPath = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/asserts/\(chineseFontFile).ttf"
            if FileManager.default.fileExists(atPath: directPath) {
                let url = URL(fileURLWithPath: directPath)
                if let name = registerFontIfNeeded(from: url) {
                    chineseFontName = name
                }
            }
        }
        
        // 注册英文字体
        if let englishFontURL = Bundle.main.url(forResource: englishFontFile, withExtension: "ttf") {
            if let name = registerFontIfNeeded(from: englishFontURL) {
                englishFontName = name
            }
        } else if let englishFontURL = Bundle.main.url(forResource: englishFontFile, withExtension: "ttf", subdirectory: "asserts") {
            if let name = registerFontIfNeeded(from: englishFontURL) {
                englishFontName = name
            }
        } else {
            // 尝试从文件路径直接加载（开发调试使用）
            let directPath = "/Users/muniao/Library/Mobile Documents/com~apple~CloudDocs/游戏/github/Pink_House/ItemManager/asserts/\(englishFontFile).ttf"
            if FileManager.default.fileExists(atPath: directPath) {
                let url = URL(fileURLWithPath: directPath)
                if let name = registerFontIfNeeded(from: url) {
                    englishFontName = name
                }
            }
        }
    }
    
    /// 注册字体（如果尚未注册），返回 PostScript 名称
    private func registerFontIfNeeded(from url: URL) -> String? {
        // 检查是否已注册
        if let cachedName = CustomFontProvider.registeredFonts[url] {
            return cachedName
        }
        
        guard let fontDataProvider = CGDataProvider(url: url as CFURL),
              let font = CGFont(fontDataProvider),
              let postScriptName = font.postScriptName as String? else {
            return nil
        }
        
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        
        // 检查是否成功或已注册（error code 105）
        let isAlreadyRegistered = error?.takeUnretainedValue()._code == 105
        
        if success || isAlreadyRegistered {
            // 注册成功或已注册，缓存结果
            CustomFontProvider.registeredFonts[url] = postScriptName
            return postScriptName
        }
        
        return nil
    }
    
    func titleFont() -> Font {
        return Font.custom(chineseFontName, size: 20)
    }
    
    func bodyFont() -> Font {
        return Font.custom(chineseFontName, size: 14)
    }
    
    func captionFont() -> Font {
        return Font.custom(chineseFontName, size: 12)
    }
    
    // 获取混合字体（中文用端庄宋体，英文用Lovers Quarrel）
    func mixedFont(for text: String, size: CGFloat) -> Font {
        // 检查文本是否包含中文字符
        let hasChinese = text.contains { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        }
        
        if hasChinese {
            return Font.custom(chineseFontName, size: size)
        } else {
            return Font.custom(englishFontName, size: size)
        }
    }
}

// MARK: - 裙子分享卡片完整视图（正反面内容相同）
struct ClothingShareCardFullView: View {
    let clothing: Clothing
    let image: UIImage?
    let cardBackground: UIImage?
    var fontProvider: FontProvider = DefaultFontProvider()
    
    var body: some View {
        ZStack {
            // card_front 背景 - 不透明
            if let bg = cardBackground {
                Image(uiImage: bg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // 默认莫妮卡色系背景
                MonicaColors.cardGradient
            }
            
            // 内容卡片 - 透明背景
            ClothingShareCardContentView(
                clothing: clothing,
                image: image,
                fontProvider: fontProvider
            )
            .frame(width: 260, height: 420)
            .background(Color.clear)
        }
        .frame(width: 280, height: 440)
        .cornerRadius(16)
    }
}

// MARK: - 预览
#Preview {
    let sampleClothing = Clothing(
        name: "天使之心",
        types: "JSK",
        colors: "粉色,白色",
        accessories: "发带,手袖",
        imagePaths: []
    )
    
    ClothingShareCardFullView(
        clothing: sampleClothing,
        image: nil,
        cardBackground: nil
    )
}
