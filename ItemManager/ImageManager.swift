//
//  ImageManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

import UIKit
import Foundation
import SwiftData
import SwiftUI
import CryptoKit
import PhotosUI
import UniformTypeIdentifiers

@MainActor
class ImageManager {
    @MainActor
    static let shared = ImageManager()
    
    // Cache
    private let memoryCache = NSCache<NSString, UIImage>()
    
    // Memory Optimization Config
    @AppStorage("useAggressiveMemoryOptimization") private var useAggressiveMemoryOptimization = true {
        didSet {
            configureCacheLimits()
        }
    }
    
    private init() {
        configureCacheLimits()
        
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.clearCache()
        }
    }
    
    private func configureCacheLimits() {
        // 配置缓存限制，针对不同内存设备动态优化
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        var limitInMB: Int
        
        if useAggressiveMemoryOptimization {
            // 积极模式：大幅降低缓存上限，优先保证不崩溃
            if totalMemory <= 2 * 1024 * 1024 * 1024 { // <= 2GB
                limitInMB = 30 // 极小缓存
            } else if totalMemory <= 4 * 1024 * 1024 * 1024 { // <= 4GB
                limitInMB = 50
            } else {
                limitInMB = 100
            }
            memoryCache.countLimit = 50
            AppLogger.info("Memory Optimization: Aggressive Mode Enabled")
        } else {
            // 标准模式：利用更多内存换取流畅度
            if totalMemory <= 2 * 1024 * 1024 * 1024 { // <= 2GB
                limitInMB = 50
            } else if totalMemory <= 4 * 1024 * 1024 * 1024 { // <= 4GB
                limitInMB = 150
            } else {
                limitInMB = 300
            }
            memoryCache.countLimit = 200
            AppLogger.info("Memory Optimization: Standard Mode Enabled")
        }
        
        // 限制总容量
        memoryCache.totalCostLimit = limitInMB * 1024 * 1024
        
        AppLogger.info("ImageCache re-configured: Limit \(limitInMB)MB, Physical Memory: \(totalMemory / 1024 / 1024)MB")
    }
    
    func clearCache() {
        AppLogger.info("Memory warning received, clearing image cache")
        memoryCache.removeAllObjects()
    }
    
    // MARK: - Directory Management
    var imagesDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let imagesDirectory = documentsDirectory.appendingPathComponent("Images")
        
        if !FileManager.default.fileExists(atPath: imagesDirectory.path) {
            try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }
        
        return imagesDirectory
    }
    
    // MARK: - Maintenance
    
    /// 清理未被任何 Clothing 引用的图片文件
    /// - Parameter context: ModelContext
    /// - Returns: 删除的文件数量
    func cleanOrphanedImages(context: ModelContext) -> Int {
        var deletedCount = 0
        do {
            // 1. 获取所有 Clothing (包括软删除的)
            let descriptor = FetchDescriptor<Clothing>()
            let allClothing = try context.fetch(descriptor)
            
            // 2. 收集所有正在使用的图片文件名
            var usedFileNames: Set<String> = []
            for clothing in allClothing {
                for path in clothing.imagePaths {
                    usedFileNames.insert(path)
                }
            }
            
            // 3. 遍历图片目录
            let fileManager = FileManager.default
            let fileURLs = try fileManager.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                // 排除系统文件和目录
                if !fileName.hasPrefix(".") && !usedFileNames.contains(fileName) {
                    try fileManager.removeItem(at: fileURL)
                    deletedCount += 1
                    
                    // 同时尝试从内存缓存中移除
                    memoryCache.removeObject(forKey: fileName as NSString)
                }
            }
            
            // 4. 清理 StoredImage 表中对应的孤儿记录
            let imageDescriptor = FetchDescriptor<StoredImage>()
            let allStoredImages = try context.fetch(imageDescriptor)
            
            for storedImage in allStoredImages {
                if !usedFileNames.contains(storedImage.fileName) {
                    context.delete(storedImage)
                }
            }
            try context.save()
            
            AppLogger.info("Cleaned \(deletedCount) orphaned image files")
            
        } catch {
            AppLogger.error("Failed to clean orphaned images: \(error)")
        }
        return deletedCount
    }
    
    // MARK: - Core Logic
    
    enum ImageFormat {
        case jpeg(quality: CGFloat)
        case png
        case heic(quality: CGFloat)
        
        var fileExtension: String {
            switch self {
            case .png: return "png"
            case .jpeg: return "jpg"
            case .heic: return "heic"
            }
        }
    }
    
    /// 保存图片：压缩 -> 哈希去重 -> 存储/引用计数
    /// - Returns: 文件名 (如果成功)
    func saveImage(_ image: UIImage, context: ModelContext, format: ImageFormat = .jpeg(quality: 0.7)) -> String? {
        // 1. Resize large images to save disk space and memory
        // Limit max dimension to 2048px (Enough for full screen on most iPhones)
        let resizedImage = image.resized(toMaxDimension: 2048)
        
        // 2. Normalize image (fix orientation)
        let normalizedImage = resizedImage.normalized()
        
        // 3. Compression/Data Conversion
        guard let data = convertImage(normalizedImage, format: format) else {
            AppLogger.error("Failed to convert image")
            return nil
        }
        
        // 3. Hashing
        let hash = computeHash(data: data)
        
        // 3. Check for existence in DB
        let descriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.imageHash == hash })
        
        do {
            let results = try context.fetch(descriptor)
            
            if let existingImage = results.first {
                // Already exists: Increment ref count
                existingImage.refCount += 1
                existingImage.updatedAt = Date()
                AppLogger.info("Image exists (Hash: \(hash)), incrementing refCount to \(existingImage.refCount)")
                
                // Ensure it's in cache
                let cost = Int(image.size.width * image.size.height * 4)
                memoryCache.setObject(image, forKey: existingImage.fileName as NSString, cost: cost)
                
                return existingImage.fileName
            } else {
                // New image: Save to disk and DB
                let fileName = "\(UUID().uuidString).\(format.fileExtension)"
                let fileURL = imagesDirectory.appendingPathComponent(fileName)
                
                try data.write(to: fileURL)
                
                let storedImage = StoredImage(imageHash: hash, fileName: fileName)
                context.insert(storedImage)
                
                // Cache the new image
                let cost = Int(image.size.width * image.size.height * 4)
                memoryCache.setObject(image, forKey: fileName as NSString, cost: cost)
                
                AppLogger.info("New image saved (Hash: \(hash), File: \(fileName))")
                return fileName
            }
        } catch {
            AppLogger.error("Failed to save image: \(error)")
            return nil
        }
    }
    
    /// 删除图片：减少引用计数 -> (<=0) 删除文件
    func deleteImage(fileName: String, context: ModelContext) {
        let descriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.fileName == fileName })
        
        do {
            let results = try context.fetch(descriptor)
            if let storedImage = results.first {
                storedImage.refCount -= 1
                AppLogger.info("Decremented refCount for \(fileName) to \(storedImage.refCount)")
                
                if storedImage.refCount <= 0 {
                    // Remove from cache
                    memoryCache.removeObject(forKey: fileName as NSString)
                    
                    // Delete from DB first
                    context.delete(storedImage)
                    AppLogger.info("Deleted image record: \(fileName)")
                    
                    // Delete file asynchronously in background to avoid blocking Main Thread
                    let fileURL = imagesDirectory.appendingPathComponent(fileName)
                    Task.detached(priority: .background) {
                        do {
                            try FileManager.default.removeItem(at: fileURL)
                            AppLogger.info("Deleted image file asynchronously: \(fileName)")
                        } catch {
                            AppLogger.error("Failed to delete image file asynchronously: \(error)")
                        }
                    }
                }
            }
        } catch {
            AppLogger.error("Failed to delete image: \(error)")
        }
    }
    
    /// 增加图片引用计数 (用于复制条目时)
    func incrementRefCount(fileName: String, context: ModelContext) {
        let descriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.fileName == fileName })
        
        do {
            let results = try context.fetch(descriptor)
            if let storedImage = results.first {
                storedImage.refCount += 1
                storedImage.updatedAt = Date()
                AppLogger.info("Incremented refCount for \(fileName) to \(storedImage.refCount)")
            } else {
                AppLogger.info("WARNING: Attempted to increment refCount for non-existent image: \(fileName)")
            }
        } catch {
            AppLogger.error("Failed to increment refCount: \(error)")
        }
    }
    
    /// 获取图片
    func loadImage(fileName: String) -> UIImage? {
        // Check cache first
        if let cachedImage = memoryCache.object(forKey: fileName as NSString) {
            return cachedImage
        }
        
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else { return nil }
        
        // Cache loaded image
        let cost = Int(image.size.width * image.size.height * 4)
        memoryCache.setObject(image, forKey: fileName as NSString, cost: cost)
        return image
    }
    
    /// 检查内存缓存
    func cachedImage(fileName: String, targetSize: CGSize? = nil) -> UIImage? {
        let cacheKey = (fileName + (targetSize != nil ? "_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : "")) as NSString
        return memoryCache.object(forKey: cacheKey)
    }

    /// 异步获取图片 (用于列表滚动优化)
    /// - Parameters:
    ///   - fileName: 文件名
    ///   - targetSize: 目标尺寸 (可选，如果提供则会进行降采样)
    func loadImageAsync(fileName: String, targetSize: CGSize? = nil) async -> UIImage? {
        let cacheKey = (fileName + (targetSize != nil ? "_\(Int(targetSize!.width))x\(Int(targetSize!.height))" : "")) as NSString
        
        // Check cache first (fast path)
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        // Capture URL on MainActor
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        // Load in background
        let scale = UIScreen.main.scale
        let image = await Task.detached(priority: .userInitiated) {
            if let targetSize = targetSize {
                // Downsampling path
                return self.downsample(imageAt: fileURL, to: targetSize, scale: scale)
            } else {
                // Normal load path
                guard let data = try? Data(contentsOf: fileURL),
                      let loadedImage = UIImage(data: data) else {
                    return nil
                }
                // Force decode
                return self.forceDecode(loadedImage)
            }
        }.value
        
        // Cache back on MainActor
        if let image = image {
            let cost = Int(image.size.width * image.size.height * 4)
            memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        }
        
        return image
    }
    
    // MARK: - Helpers
    
    /// Downsample image to save memory and improve performance
    private nonisolated func downsample(imageAt imageURL: URL, to pointSize: CGSize, scale: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, imageSourceOptions) else {
            return nil
        }
        
        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }
        
        return UIImage(cgImage: downsampledImage)
    }
    
    /// Force decode image on background thread
    private nonisolated func forceDecode(_ image: UIImage) -> UIImage? {
        // Use normalized(forceCopy: true) to fix orientation AND force decode (render to bitmap)
        // This ensures the image is loaded into memory and orientation is applied correctly
        return image.normalized(forceCopy: true)
    }
    
    private func convertImage(_ image: UIImage, format: ImageFormat) -> Data? {
        switch format {
        case .jpeg(let quality):
            return image.jpegData(compressionQuality: quality)
        case .png:
            return image.pngData()
        case .heic(let quality):
            let data = NSMutableData()
            
            // 检查图片是否有 Alpha 通道，如果是不透明的，尝试去除 Alpha 信息以避免保存时的警告和不必要的体积
            // 警告: 'ItemManager' is trying to save an opaque image ... with 'AlphaPremulLast'
            var sourceCGImage = image.cgImage
            
            // 如果能获取到 cgImage 且它声称有 Alpha，但我们想检查它是否真的需要（或者只是为了消除警告，我们可以尝试创建一个不带 Alpha 的上下文重绘？）
            // 这里为了性能，我们主要依赖 ImageIO 的处理。
            // 但如果源图是 opaque 的（比如从 Jpeg 加载），但被绘制到了带 Alpha 的 context 中，就会有这个警告。
            // 我们可以尝试显式指定 kCGImagePropertyHasAlpha = false 如果我们确信它是 opaque。
            // 不过 CGImageDestinationAddImage 的 options 主要是压缩质量等。
            
            guard let cgImage = sourceCGImage,
                  let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
                return nil
            }
            
            let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            CGImageDestinationAddImage(destination, cgImage, options)
            
            guard CGImageDestinationFinalize(destination) else { return nil }
            return data as Data
        }
    }

    private func compressImage(_ image: UIImage) -> Data? {
        // 智能压缩：先尝试 0.7 质量，如果还太大可以继续调整，这里简化为固定 0.7 JPEG
        return convertImage(image, format: .jpeg(quality: 0.7))
    }
    
    private func computeHash(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
