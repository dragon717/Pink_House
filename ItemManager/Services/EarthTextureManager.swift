//
//  EarthTextureManager.swift
//  ItemManager
//
//  地球纹理管理器 - 管理真实地图和夜晚灯光纹理
//  支持 Black Marble 夜晚灯光数据
//

import Foundation
import UIKit
import SceneKit
import Combine

@MainActor
class EarthTextureManager: ObservableObject {
    static let shared = EarthTextureManager()
    
    // MARK: - Published Properties
    @Published var dayTexture: UIImage?
    @Published var nightTexture: UIImage?
    @Published var isLoading = false
    @Published var loadError: String?
    
    // MARK: - Texture URLs
    private let textureBaseURL = "https://eoimages.gsfc.nasa.gov/images/imagerecords"
    
    // NASA Blue Marble 白天纹理 (2K分辨率)
    private let blueMarbleDayURL = "https://eoimages.gsfc.nasa.gov/images/imagerecords/74000/74092/world.200407.3x5400x2700.jpg"
    
    // NASA Black Marble 夜晚灯光纹理
    private let blackMarbleNightURL = "https://eoimages.gsfc.nasa.gov/images/imagerecords/90000/90008/earth_lights_4800.tiff"
    
    private init() {
        // 尝试加载本地缓存的纹理
        loadCachedTextures()
    }
    
    // MARK: - Public Methods
    
    /// 获取白天纹理
    func getDayTexture() -> UIImage {
        if let texture = dayTexture {
            return texture
        }
        return createProceduralDayTexture()
    }
    
    /// 获取夜晚灯光纹理
    func getNightTexture() -> UIImage {
        if let texture = nightTexture {
            return texture
        }
        return createProceduralNightTexture()
    }
    
    /// 从本地文件加载纹理
    func loadTexture(from url: URL, type: TextureType) async {
        isLoading = true
        loadError = nil
        
        do {
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                throw TextureError.invalidImageData
            }
            
            // 调整图像大小以优化性能
            let optimizedImage = optimizeTexture(image)
            
            await MainActor.run {
                switch type {
                case .day:
                    self.dayTexture = optimizedImage
                case .night:
                    self.nightTexture = optimizedImage
                }
                self.isLoading = false
            }
            
            // 缓存到本地
            cacheTexture(optimizedImage, type: type)
            
        } catch {
            await MainActor.run {
                self.loadError = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    /// 下载 NASA 纹理
    func downloadNASATextures() async {
        isLoading = true
        loadError = nil
        
        // 下载白天纹理
        if let dayURL = URL(string: blueMarbleDayURL) {
            do {
                let (dayData, _) = try await URLSession.shared.data(from: dayURL)
                if let image = UIImage(data: dayData) {
                    let optimizedImage = optimizeTexture(image, maxDimension: 2048)
                    await MainActor.run {
                        self.dayTexture = optimizedImage
                    }
                    cacheTexture(optimizedImage, type: .day)
                }
            } catch {
                print("Failed to download day texture: \(error)")
            }
        }
        
        // 下载夜晚纹理
        if let nightURL = URL(string: blackMarbleNightURL) {
            do {
                let (nightData, _) = try await URLSession.shared.data(from: nightURL)
                if let image = UIImage(data: nightData) {
                    let optimizedImage = optimizeTexture(image, maxDimension: 2048)
                    await MainActor.run {
                        self.nightTexture = optimizedImage
                    }
                    cacheTexture(optimizedImage, type: .night)
                }
            } catch {
                print("Failed to download night texture: \(error)")
            }
        }
        
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCachedTextures() {
        // 首先尝试从 Assets 加载 EarthTexture（高清版本优先）
        if let hdImage = UIImage(named: "EarthTexture_HD") {
            dayTexture = hdImage
            print("Loaded EarthTexture_HD from Assets")
        } else if let assetImage = UIImage(named: "EarthTexture") {
            dayTexture = assetImage
            print("Loaded EarthTexture from Assets")
        }
        
        // 从 Assets 加载夜晚灯光纹理
        if let nightImage = UIImage(named: "NightLights") {
            nightTexture = nightImage
            print("Loaded NightLights from Assets")
        } else {
            // 如果 Assets 中没有，生成一个
            nightTexture = generateNightTexture()
            print("Generated night texture")
        }
        
        let fileManager = FileManager.default
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        // 如果从 Assets 没有加载到，尝试从 Documents 加载白天纹理缓存
        if dayTexture == nil {
            let dayCachePath = documentsDir.appendingPathComponent("earth_day_texture.jpg")
            if fileManager.fileExists(atPath: dayCachePath.path),
               let image = UIImage(contentsOfFile: dayCachePath.path) {
                dayTexture = image
            }
        }
        
        // 如果从 Assets 没有加载到，尝试从 Documents 加载夜晚纹理缓存
        if nightTexture == nil {
            let nightCachePath = documentsDir.appendingPathComponent("earth_night_texture.jpg")
            if fileManager.fileExists(atPath: nightCachePath.path),
               let image = UIImage(contentsOfFile: nightCachePath.path) {
                nightTexture = image
            }
        }
    }
    
    /// 生成程序化夜晚灯光纹理
    private func generateNightTexture() -> UIImage {
        let size = CGSize(width: 2048, height: 1024)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return UIImage()
        }
        
        // 黑色背景（海洋）
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // 定义主要城市区域和灯光密度
        let cityRegions: [(x: CGFloat, y: CGFloat, radius: CGFloat, density: Int, brightness: CGFloat)] = [
            // 东亚
            (0.70, 0.35, 80, 300, 0.9),  // 东京
            (0.65, 0.38, 60, 250, 0.85), // 首尔
            (0.62, 0.40, 100, 400, 0.9), // 北京-天津
            (0.65, 0.45, 80, 350, 0.85), // 上海
            (0.58, 0.50, 70, 300, 0.8),  // 广州-深圳
            
            // 欧洲
            (0.52, 0.32, 50, 200, 0.8),  // 伦敦
            (0.54, 0.35, 40, 180, 0.75), // 巴黎
            (0.56, 0.32, 35, 150, 0.7),  // 柏林
            (0.58, 0.33, 30, 120, 0.7),  // 华沙
            (0.62, 0.30, 60, 250, 0.75), // 莫斯科
            
            // 北美
            (0.28, 0.35, 70, 350, 0.9),  // 纽约
            (0.25, 0.38, 50, 250, 0.8),  // 芝加哥
            (0.22, 0.42, 60, 300, 0.85), // 洛杉矶
            (0.20, 0.45, 40, 200, 0.75), // 旧金山
            (0.30, 0.30, 45, 220, 0.8),  // 多伦多
            
            // 南美
            (0.32, 0.65, 50, 250, 0.8),  // 圣保罗
            (0.30, 0.62, 40, 200, 0.75), // 里约
            (0.28, 0.55, 35, 150, 0.7),  // 波哥大
            
            // 中东
            (0.60, 0.45, 30, 120, 0.7),  // 迪拜
            
            // 澳洲
            (0.85, 0.70, 40, 180, 0.75), // 悉尼
            (0.82, 0.68, 35, 150, 0.7),  // 墨尔本
            
            // 印度
            (0.68, 0.48, 50, 200, 0.75), // 孟买
            (0.72, 0.45, 45, 180, 0.7),  // 德里
            
            // 东南亚
            (0.75, 0.55, 35, 150, 0.7),  // 新加坡
            (0.78, 0.50, 40, 160, 0.72), // 曼谷
            
            // 非洲
            (0.55, 0.55, 30, 100, 0.6),  // 开罗
            (0.52, 0.70, 25, 80, 0.55),  // 约翰内斯堡
        ]
        
        // 绘制城市灯光
        for region in cityRegions {
            let centerX = region.x * size.width
            let centerY = region.y * size.height
            
            for _ in 0..<region.density {
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let distance = CGFloat.random(in: 0...1) * region.radius
                let x = centerX + cos(angle) * distance
                let y = centerY + sin(angle) * distance
                
                // 根据距离中心的远近调整亮度
                let normalizedDistance = distance / region.radius
                let brightness = region.brightness * (1 - normalizedDistance * 0.5)
                
                // 灯光颜色（偏暖黄色）
                let color = UIColor(
                    red: 1.0,
                    green: 0.8 + CGFloat.random(in: 0...0.2),
                    blue: 0.4 + CGFloat.random(in: 0...0.3),
                    alpha: brightness
                )
                
                context.setFillColor(color.cgColor)
                
                // 灯光大小
                let lightSize = CGFloat.random(in: 1...3)
                context.fillEllipse(in: CGRect(x: x, y: y, width: lightSize, height: lightSize))
            }
        }
        
        // 添加一些随机分布的次要灯光（农村地区）
        context.setFillColor(UIColor(red: 1.0, green: 0.9, blue: 0.6, alpha: 0.4).cgColor)
        for _ in 0..<2000 {
            let x = CGFloat.random(in: 0...size.width)
            let y = CGFloat.random(in: 0...size.height)
            let lightSize = CGFloat.random(in: 0.5...1.5)
            context.fillEllipse(in: CGRect(x: x, y: y, width: lightSize, height: lightSize))
        }
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
    
    private func cacheTexture(_ image: UIImage, type: TextureType) {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = image.jpegData(compressionQuality: 0.9) else { return }
        
        let filename = type == .day ? "earth_day_texture.jpg" : "earth_night_texture.jpg"
        let fileURL = documentsDir.appendingPathComponent(filename)
        
        try? data.write(to: fileURL)
    }
    
    private func optimizeTexture(_ image: UIImage, maxDimension: CGFloat = 2048) -> UIImage {
        let size = image.size
        
        // 如果图像已经小于最大尺寸，直接返回
        if size.width <= maxDimension && size.height <= maxDimension {
            return image
        }
        
        // 计算缩放比例
        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    // MARK: - Procedural Textures (Fallback)
    
    private func createProceduralDayTexture() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        // 海洋背景
        context.setFillColor(UIColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0).cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // 绘制简单的大陆轮廓
        context.setFillColor(UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1.0).cgColor)
        
        // 亚洲
        context.fillEllipse(in: CGRect(x: 600, y: 150, width: 200, height: 120))
        // 欧洲
        context.fillEllipse(in: CGRect(x: 480, y: 140, width: 80, height: 60))
        // 非洲
        context.fillEllipse(in: CGRect(x: 480, y: 200, width: 100, height: 140))
        // 北美
        context.fillEllipse(in: CGRect(x: 150, y: 120, width: 180, height: 120))
        // 南美
        context.fillEllipse(in: CGRect(x: 200, y: 260, width: 100, height: 140))
        // 澳洲
        context.fillEllipse(in: CGRect(x: 800, y: 320, width: 100, height: 60))
        
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
    
    private func createProceduralNightTexture() -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        
        // 黑色背景
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        // 绘制城市灯光点
        context.setFillColor(UIColor.orange.withAlphaComponent(0.6).cgColor)
        
        // 主要城市灯光
        let cities: [CGPoint] = [
            CGPoint(x: 600, y: 180), // 北京
            CGPoint(x: 550, y: 190), // 上海
            CGPoint(x: 500, y: 160), // 莫斯科
            CGPoint(x: 450, y: 180), // 巴黎
            CGPoint(x: 420, y: 170), // 伦敦
            CGPoint(x: 250, y: 160), // 纽约
            CGPoint(x: 220, y: 200), // 洛杉矶
            CGPoint(x: 280, y: 280), // 圣保罗
            CGPoint(x: 620, y: 220), // 孟买
            CGPoint(x: 680, y: 200), // 东京
        ]
        
        for city in cities {
            context.fillEllipse(in: CGRect(x: city.x - 10, y: city.y - 10, width: 20, height: 20))
        }
        
        return UIGraphicsGetImageFromCurrentImageContext()!
    }
}

// MARK: - Supporting Types

enum TextureType {
    case day
    case night
}

enum TextureError: Error {
    case invalidImageData
    case downloadFailed
    case cacheFailed
}
