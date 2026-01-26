//
//  ImageManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/16/26.
//

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
    
    private init() {
        // Optional: Configure cache limits
        memoryCache.countLimit = 100 // Cache up to 100 images
        memoryCache.totalCostLimit = 1024 * 1024 * 200 // 200 MB
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
        // 1. Compression/Data Conversion
        guard let data = convertImage(image, format: format) else {
            AppLogger.error("Failed to convert image")
            return nil
        }
        
        // 2. Hashing
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
                memoryCache.setObject(image, forKey: existingImage.fileName as NSString)
                
                return existingImage.fileName
            } else {
                // New image: Save to disk and DB
                let fileName = "\(UUID().uuidString).\(format.fileExtension)"
                let fileURL = imagesDirectory.appendingPathComponent(fileName)
                
                try data.write(to: fileURL)
                
                let storedImage = StoredImage(imageHash: hash, fileName: fileName)
                context.insert(storedImage)
                
                // Cache the new image
                memoryCache.setObject(image, forKey: fileName as NSString)
                
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
        memoryCache.setObject(image, forKey: fileName as NSString)
        return image
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
        let image = await Task.detached(priority: .userInitiated) {
            if let targetSize = targetSize {
                // Downsampling path
                return self.downsample(imageAt: fileURL, to: targetSize, scale: 1.0) // Scale handled by SwiftUI typically or provide screen scale
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
            memoryCache.setObject(image, forKey: cacheKey)
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
        guard let cgImage = image.cgImage else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        
        let alphaInfo = cgImage.alphaInfo
        let hasAlpha = alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst || 
                       alphaInfo == .last || alphaInfo == .first
        
        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        
        if hasAlpha {
            bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue
        } else {
            bitmapInfo |= CGImageAlphaInfo.noneSkipFirst.rawValue
        }
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let decodedImage = context.makeImage() else { return image }
        
        return UIImage(cgImage: decodedImage)
    }
    
    private func convertImage(_ image: UIImage, format: ImageFormat) -> Data? {
        switch format {
        case .jpeg(let quality):
            return image.jpegData(compressionQuality: quality)
        case .png:
            return image.pngData()
        case .heic(let quality):
            let data = NSMutableData()
            guard let cgImage = image.cgImage,
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
