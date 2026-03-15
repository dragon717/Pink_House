import UIKit
import SwiftUI

// MARK: - 优化的图片加载器
/// 专为小内存 iPhone 优化的图片加载器
actor OptimizedImageLoader {
    static let shared = OptimizedImageLoader()
    
    // MARK: - 配置
    private let maxCacheSize: Int = 50 * 1024 * 1024  // 50MB 内存缓存限制
    private let maxConcurrentLoads = 3  // 最大并发加载数
    private let thumbnailSize = CGSize(width: 300, height: 400)  // 缩略图尺寸
    
    // MARK: - 缓存
    private var memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100  // 最多缓存100张图片
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB
        return cache
    }()
    
    // MARK: - 加载控制
    private var loadingTasks: [String: Task<UIImage?, Never>] = [:]
    private var semaphoreValue = 3
    private var semaphoreWaiters: [CheckedContinuation<Void, Never>] = []
    
    // MARK: - 公共方法
    
    /// 加载贴纸图片（带降采样和缓存）
    func loadStickerImage(fileName: String, targetSize: CGSize? = nil) async -> UIImage? {
        let cacheKey = "\(fileName)_\(Int(targetSize?.width ?? 300))" as NSString
        
        // 1. 检查内存缓存
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }
        
        // 2. 检查是否已有正在进行的加载任务
        if let existingTask = loadingTasks[fileName] {
            return await existingTask.value
        }
        
        // 3. 创建新加载任务
        let task = Task { () -> UIImage? in
            // 等待信号量
            await self.waitSemaphore()
            defer { self.signalSemaphore() }
            
            // 再次检查缓存（可能其他任务已加载）
            if let cached = self.memoryCache.object(forKey: cacheKey) {
                return cached
            }
            
            // 加载并降采样图片
            let size = targetSize ?? self.thumbnailSize
            let fileURL = self.imagesDirectory.appendingPathComponent(fileName)
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            
            // 在后台线程执行降采样
            let image = await Task.detached(priority: .userInitiated) { [size] in
                return downsampleImage(at: fileURL, to: size)
            }.value
            
            // 缓存结果
            if let image = image {
                let cost = self.calculateImageCost(image)
                self.memoryCache.setObject(image, forKey: cacheKey, cost: cost)
            }
            
            return image
        }
        
        loadingTasks[fileName] = task
        let result = await task.value
        loadingTasks.removeValue(forKey: fileName)
        
        return result
    }
    
    /// 预加载图片（用于提前准备）
    func preloadImages(fileNames: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for fileName in fileNames.prefix(5) {  // 最多预加载5张
                group.addTask {
                    _ = await self.loadStickerImage(fileName: fileName)
                }
            }
        }
    }
    
    /// 清理缓存（内存紧张时调用）
    func clearCache() {
        memoryCache.removeAllObjects()
        loadingTasks.removeAll()
    }
    
    /// 清理特定图片的缓存
    func removeFromCache(fileName: String) {
        let cacheKey = "\(fileName)_300" as NSString
        memoryCache.removeObject(forKey: cacheKey)
    }
    
    // MARK: - 信号量控制
    
    private func waitSemaphore() async {
        if semaphoreValue > 0 {
            semaphoreValue -= 1
        } else {
            await withCheckedContinuation { continuation in
                semaphoreWaiters.append(continuation)
            }
        }
    }
    
    private func signalSemaphore() {
        if let waiter = semaphoreWaiters.first {
            semaphoreWaiters.removeFirst()
            waiter.resume()
        } else {
            semaphoreValue += 1
        }
    }
    
    // MARK: - 私有方法
    
    private func calculateImageCost(_ image: UIImage) -> Int {
        let bytesPerPixel = 4
        return Int(image.size.width * image.size.height * CGFloat(bytesPerPixel))
    }
    
    private var imagesDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Images")
    }
}

// MARK: - 降采样函数（非 actor 隔离）
private nonisolated func downsampleImage(at url: URL, to size: CGSize) -> UIImage? {
    let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    
    guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
        return fallbackLoad(at: url, targetSize: size)
    }
    
    let scale = UIScreen.main.scale
    let maxDimensionInPixels = max(size.width, size.height) * scale
    
    let downsampleOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
    ]
    
    guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions as CFDictionary) else {
        return fallbackLoad(at: url, targetSize: size)
    }
    
    return UIImage(cgImage: downsampledImage, scale: scale, orientation: .up)
}

private nonisolated func fallbackLoad(at url: URL, targetSize: CGSize) -> UIImage? {
    guard let data = try? Data(contentsOf: url),
          let image = UIImage(data: data) else {
        return nil
    }
    
    // 如果图片太大，进行缩放
    if image.size.width > targetSize.width * 2 || image.size.height > targetSize.height * 2 {
        return image.resized(to: targetSize)
    }
    
    return image
}

// MARK: - UIImage 扩展
extension UIImage {
    /// 缩放图片到指定尺寸
    func resized(to targetSize: CGSize) -> UIImage? {
        let size = self.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)
        
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
