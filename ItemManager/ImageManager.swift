//
//  ImageManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/16/26.
//

import UIKit
import Foundation
import SwiftData
import SwiftUI
import CryptoKit
import PhotosUI
import UniformTypeIdentifiers
import Accelerate

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
        
        // Add Observer for Background state to clear cache and free up memory
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            // Only clear if aggressive mode is on, or if we want to be nice citizens
            // Clearing on background is generally safe and good for low memory devices
            if self?.useAggressiveMemoryOptimization == true {
                AppLogger.info("App entered background, clearing image cache (Aggressive Mode)")
                self?.clearCache()
            } else {
                // For standard mode, maybe just trim? NSCache handles itself, but we can be explicit.
                // Let's keep 50% capacity or just leave it to OS.
                // For now, let's clear it to be safe against termination.
                // self?.clearCache() 
            }
        }
    }
    
    private func configureCacheLimits() {
        // 配置缓存限制，针对不同内存设备动态优化
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        var limitInMB: Int
        
        if useAggressiveMemoryOptimization {
            // 积极模式：大幅降低缓存上限，优先保证不崩溃
            if totalMemory <= 2 * 1024 * 1024 * 1024 { // <= 2GB (iPhone 8, X, XR, SE2 etc)
                limitInMB = 20 // 极小缓存，防止OOM
                memoryCache.countLimit = 20
            } else if totalMemory <= 4 * 1024 * 1024 * 1024 { // <= 4GB (iPhone 11, 12, 13 non-pro)
                limitInMB = 50
                memoryCache.countLimit = 40
            } else {
                limitInMB = 100
                memoryCache.countLimit = 80
            }
            AppLogger.info("Memory Optimization: Aggressive Mode Enabled (Limit: \(limitInMB)MB)")
        } else {
            // 标准模式：利用更多内存换取流畅度
            if totalMemory <= 2 * 1024 * 1024 * 1024 { // <= 2GB
                limitInMB = 50
                memoryCache.countLimit = 50
            } else if totalMemory <= 4 * 1024 * 1024 * 1024 { // <= 4GB
                limitInMB = 150
                memoryCache.countLimit = 100
            } else {
                limitInMB = 300
                memoryCache.countLimit = 200
            }
            AppLogger.info("Memory Optimization: Standard Mode Enabled (Limit: \(limitInMB)MB)")
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
    
    /// iCloud Documents 目录（用于自动同步图片）
    var imagesDirectory: URL {
        // 使用 iCloud Documents 实现图片自动同步
        // 优先使用 iCloud Documents，如果不可用则回退到本地 Documents
        let fileManager = FileManager.default
        
        // 尝试获取 iCloud Documents URL
        if let iCloudURL = fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents") {
            let imagesDirectory = iCloudURL.appendingPathComponent("Images")
            
            // 确保目录存在（包括中间目录）
            if !fileManager.fileExists(atPath: imagesDirectory.path) {
                do {
                    try fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true, attributes: nil)
                    print("✅ 创建 iCloud Images 目录: \(imagesDirectory.path)")
                } catch {
                    print("❌ 创建 iCloud Images 目录失败: \(error)")
                    // 回退到本地存储
                    return localImagesDirectory
                }
            }
            return imagesDirectory
        }
        
        // 回退到本地 Documents
        print("⚠️ 图片保存云端失败 iCloud 不可用，使用本地存储")
        return localImagesDirectory
    }
    
    /// 本地 Documents 目录（回退使用）
    private var localImagesDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let imagesDirectory = documentsDirectory.appendingPathComponent("Images")
        
        if !FileManager.default.fileExists(atPath: imagesDirectory.path) {
            try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }
        
        return imagesDirectory
    }
    
    /// 检查 iCloud 是否可用
    var isICloudAvailable: Bool {
        return FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
    }
    
    /// 确保文件上传到 iCloud
    /// - Parameter fileURL: 文件 URL
    private func ensureFileUploadedToiCloud(fileURL: URL) throws {
        let fileManager = FileManager.default
        
        // 设置文件属性，确保上传到 iCloud
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        
        var mutableURL = fileURL
        try mutableURL.setResourceValues(resourceValues)
        
        // 开始下载/上传（如果需要在不同设备间同步）
        try fileManager.startDownloadingUbiquitousItem(at: fileURL)
        
        AppLogger.info("已设置 iCloud 同步: \(fileURL.lastPathComponent)")
    }
    
    /// 检查文件是否已在本地下载
    func isFileDownloaded(fileName: String) -> Bool {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                return status == .current
            }
            // 如果不是 iCloud 文件，直接检查文件是否存在
            return FileManager.default.fileExists(atPath: fileURL.path)
        } catch {
            return FileManager.default.fileExists(atPath: fileURL.path)
        }
    }
    
    /// 下载 iCloud 文件（如果尚未下载）
    func downloadFileIfNeeded(fileName: String) async -> Bool {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        let fileManager = FileManager.default
        
        // 检查文件是否已存在本地
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // 文件不存在，尝试从 iCloud 下载
            do {
                try fileManager.startDownloadingUbiquitousItem(at: fileURL)
                AppLogger.info("开始从 iCloud 下载: \(fileName)")
                return true
            } catch {
                AppLogger.error("下载文件失败: \(error)")
                return false
            }
        }
        
        // 检查下载状态
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                switch status {
                case .current:
                    return true
                case .downloaded, .notDownloaded:
                    // 需要下载
                    try fileManager.startDownloadingUbiquitousItem(at: fileURL)
                    return true
                default:
                    return false
                }
            }
        } catch {
            AppLogger.error("检查下载状态失败: \(error)")
        }
        
        return true
    }
    
    // MARK: - Maintenance
    
    /// 清理未被任何 Clothing 引用的图片文件
    /// - Parameter context: ModelContext
    /// - Returns: 删除的文件数量
    func cleanOrphanedImages(context: ModelContext) -> Int {
        var deletedCount = 0
        do {
            // 1. 获取所有 Clothing (包括软删除的)
            let clothingDescriptor = FetchDescriptor<Clothing>()
            let allClothing = try context.fetch(clothingDescriptor)
            
            // 2. 收集所有正在使用的图片文件名
            var usedFileNames: Set<String> = []
            for clothing in allClothing {
                for path in clothing.imagePaths {
                    usedFileNames.insert(path)
                }
            }
            
            // 2.1 收集所有 CutoutItem 使用的图片文件名
            // 修复：确保贴纸图片不被误删
            let cutoutDescriptor = FetchDescriptor<CutoutItem>()
            let allCutouts = try context.fetch(cutoutDescriptor)
            for cutout in allCutouts {
                if !cutout.imagePath.isEmpty {
                    usedFileNames.insert(cutout.imagePath)
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
        // Note: resized(toMaxDimension:) works in points, so we need to adjust for scale to limit pixels
        let maxPixels: CGFloat = 2048
        let currentMaxPixels = max(image.size.width, image.size.height) * image.scale
        
        let resizedImage: UIImage
        if currentMaxPixels > maxPixels {
            // Adjust maxDimension (points) to achieve target maxPixels
            resizedImage = image.resized(toMaxDimension: maxPixels / image.scale)
        } else {
            resizedImage = image
        }
        
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
                existingImage.lastModified = Date()
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
                
                // 确保文件上传到 iCloud
                if isICloudAvailable {
                    try? ensureFileUploadedToiCloud(fileURL: fileURL)
                }
                
                let storedImage = StoredImage(imageHash: hash, fileName: fileName)
                context.insert(storedImage)
                
                // Cache the new image
                let cost = Int(image.size.width * image.size.height * 4)
                memoryCache.setObject(image, forKey: fileName as NSString, cost: cost)
                
                AppLogger.info("New image saved (Hash: \(hash), File: \(fileName))")
                
                // 触发 CloudKit 同步（异步，不阻塞主线程）
                Task {
                    await ClothingImageSyncService.shared.syncPendingImages()
                }
                
                return fileName
            }
        } catch {
            AppLogger.error("Failed to save image: \(error)")
            return nil
        }
    }

    /// 保存表图（尺码表/价格表）：高质量、高压缩率
    /// - 使用 HEIF/HEIC 格式实现更高压缩率和更好质量
    /// - 保持原始比例，不强制裁剪
    /// - 输出分辨率提高到 1920px 宽度
    /// - 兼容老数据：使用 jpeg 格式回退
    func saveChartImage(_ image: UIImage, context: ModelContext) -> String? {
        let maxWidth: CGFloat = 1920
        let originalSize = image.size
        let scale = originalSize.width > maxWidth ? maxWidth / originalSize.width : 1.0
        let newSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let resizedImage = image.resized(toMaxDimension: newSize.width)
        let normalizedImage = resizedImage.normalized(forceCopy: true)

        guard let data = convertImage(normalizedImage, format: .heic(quality: 0.85)) else {
            AppLogger.info("HEIC not supported, falling back to JPEG quality 0.9")
            guard let jpegData = normalizedImage.jpegData(compressionQuality: 0.9) else {
                AppLogger.error("Failed to convert chart image to JPEG")
                return nil
            }
            return saveChartImageData(jpegData, fileExtension: "jpg", context: context)
        }

        return saveChartImageData(data, fileExtension: "heic", context: context)
    }

    private func saveChartImageData(_ data: Data, fileExtension: String, context: ModelContext) -> String? {
        let hash = computeHash(data: data)
        let descriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.imageHash == hash })

        do {
            let results = try context.fetch(descriptor)

            if let existingImage = results.first {
                existingImage.refCount += 1
                existingImage.updatedAt = Date()
                existingImage.lastModified = Date()
                AppLogger.info("Chart image exists (Hash: \(hash)), incrementing refCount to \(existingImage.refCount)")

                if let image = UIImage(data: data) {
                    let cost = Int(image.size.width * image.size.height * 4)
                    memoryCache.setObject(image, forKey: existingImage.fileName as NSString, cost: cost)
                }

                return existingImage.fileName
            } else {
                let fileName = "\(UUID().uuidString).\(fileExtension)"
                let fileURL = imagesDirectory.appendingPathComponent(fileName)

                try data.write(to: fileURL)

                if isICloudAvailable {
                    try? ensureFileUploadedToiCloud(fileURL: fileURL)
                }

                let storedImage = StoredImage(imageHash: hash, fileName: fileName)
                context.insert(storedImage)

                if let image = UIImage(data: data) {
                    let cost = Int(image.size.width * image.size.height * 4)
                    memoryCache.setObject(image, forKey: fileName as NSString, cost: cost)
                }

                AppLogger.info("New chart image saved (Hash: \(hash), File: \(fileName), Size: \(data.count / 1024)KB)")

                Task {
                    await ClothingImageSyncService.shared.syncPendingImages()
                }

                return fileName
            }
        } catch {
            AppLogger.error("Failed to save chart image: \(error)")
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
    
    /// 批量删除图片：优化性能，减少后台任务数量
    /// - Parameters:
    ///   - fileNames: 要处理的文件名列表
    ///   - context: ModelContext
    func batchDeleteImages(fileNames: [String], context: ModelContext) {
        var filesToDelete: [String] = []
        
        // 1. Process DB changes on Main Actor
        // Using autoreleasepool to keep memory footprint low during loop
        autoreleasepool {
            for fileName in fileNames {
                let descriptor = FetchDescriptor<StoredImage>(predicate: #Predicate { $0.fileName == fileName })
                
                do {
                    if let storedImage = try context.fetch(descriptor).first {
                        storedImage.refCount -= 1
                        
                        if storedImage.refCount <= 0 {
                            // Remove from cache immediately
                            memoryCache.removeObject(forKey: fileName as NSString)
                            
                            // Delete from DB
                            context.delete(storedImage)
                            
                            // Mark for file deletion
                            filesToDelete.append(fileName)
                            AppLogger.info("Marked for batch deletion: \(fileName)")
                        } else {
                            AppLogger.info("Decremented refCount for \(fileName) to \(storedImage.refCount)")
                        }
                    }
                } catch {
                    AppLogger.error("Failed to process batch delete for image \(fileName): \(error)")
                }
            }
        }
        
        // 2. Process file deletion in ONE background task
        if !filesToDelete.isEmpty {
            let directory = self.imagesDirectory // Capture on MainActor
            Task.detached(priority: .background) {
                for fileName in filesToDelete {
                    let fileURL = directory.appendingPathComponent(fileName)
                    do {
                        try FileManager.default.removeItem(at: fileURL)
                    } catch {
                        // Ignore file not found errors, log others
                         print("Failed to delete file \(fileName): \(error)")
                    }
                }
                print("Batch deleted \(filesToDelete.count) image files")
            }
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
                storedImage.lastModified = Date()
                AppLogger.info("Incremented refCount for \(fileName) to \(storedImage.refCount)")
            } else {
                AppLogger.info("WARNING: Attempted to increment refCount for non-existent image: \(fileName)")
            }
        } catch {
            AppLogger.error("Failed to increment refCount: \(error)")
        }
    }
    
    /// 获取图片（自动处理 iCloud 下载）
    func loadImage(fileName: String) -> UIImage? {
        // Check cache first
        if let cachedImage = memoryCache.object(forKey: fileName as NSString) {
            return cachedImage
        }
        
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        let fileManager = FileManager.default
        
        // 检查文件是否存在，如果不存在可能是 iCloud 文件尚未下载
        if !fileManager.fileExists(atPath: fileURL.path) && isICloudAvailable {
            // 尝试触发下载
            do {
                try fileManager.startDownloadingUbiquitousItem(at: fileURL)
                AppLogger.info("触发 iCloud 下载: \(fileName)")
            } catch {
                AppLogger.error("触发下载失败: \(error)")
            }
            return nil
        }
        
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

    /// 异步获取图片 (用于列表滚动优化，自动处理 iCloud 下载)
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
        let fileManager = FileManager.default
        
        // 检查文件是否存在，如果不存在可能是 iCloud 文件尚未下载
        if !fileManager.fileExists(atPath: fileURL.path) && isICloudAvailable {
            // 尝试触发下载
            let success = await downloadFileIfNeeded(fileName: fileName)
            if !success {
                return nil
            }
            // 等待一小段时间让下载开始
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
        }
        
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
            // 如果无法创建 imageSource，尝试回退到正常加载
            return fallbackLoadImage(at: imageURL)
        }
        
        // Fix: kCGImageSourceThumbnailMaxPixelSize cannot be larger than the original image dimensions
        // Get original dimensions first
        let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        var maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        
        if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, propertiesOptions) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = properties[kCGImagePropertyPixelHeight] as? CGFloat {
            
            let originalMaxDimension = max(width, height)
            if maxDimensionInPixels > originalMaxDimension {
                // If requested size is larger than original, just use original size (no upscaling in downsample)
                maxDimensionInPixels = originalMaxDimension
            }
        }
        
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ] as CFDictionary
        
        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            // 降采样失败时回退到正常加载，而不是返回 nil
            // 这可能是由于某些特殊格式的图片（如某些 PNG 带透明通道）导致降采样失败
            return fallbackLoadImage(at: imageURL)
        }
        
        return UIImage(cgImage: downsampledImage)
    }
    
    /// 降采样失败时的回退加载方式
    private nonisolated func fallbackLoadImage(at imageURL: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: imageURL),
              let loadedImage = UIImage(data: data) else {
            return nil
        }
        return loadedImage
    }
    
    /// Force decode image on background thread
    private nonisolated func forceDecode(_ image: UIImage) -> UIImage? {
        // Optimization: Skip force decode on low memory devices to save RAM
        // Force decoding decompresses the entire image into memory (bitmap), which can be huge.
        // On modern iOS, UIKit handles lazy decoding reasonably well, so skipping this on
        // constrained devices is a good trade-off.
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        if totalMemory <= 2 * 1024 * 1024 * 1024 { // <= 2GB
             return image // Just return the image, let UIKit decode it when displaying
        }
        
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
            
            guard var sourceCGImage = image.cgImage else { return nil }
            
            // 优化：检测并移除不必要的 Alpha 通道
            // 解决 "ItemManager is trying to save an opaque image... with AlphaPremulLast" 问题
            if ImageManager.imageHasAlpha(sourceCGImage) {
                // 进一步检查像素是否全为不透明
                if ImageManager.isImageActuallyOpaque(sourceCGImage) {
                    // 使用 CoreGraphics 创建明确的无 Alpha (NoneSkipLast) 副本
                    if let stripped = ImageManager.stripAlpha(from: sourceCGImage) {
                        sourceCGImage = stripped
                    }
                }
            }
            
            guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
                return nil
            }
            
            let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            CGImageDestinationAddImage(destination, sourceCGImage, options)
            
            guard CGImageDestinationFinalize(destination) else { return nil }
            return data as Data
        }
    }
    
    // MARK: - Alpha Optimization Helpers
    
    private static func imageHasAlpha(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo
        return alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
    }
    
    private static func isImageActuallyOpaque(_ image: CGImage) -> Bool {
        var format = vImage_CGImageFormat(
            bitsPerComponent: UInt32(image.bitsPerComponent),
            bitsPerPixel: UInt32(image.bitsPerPixel),
            colorSpace: Unmanaged.passUnretained(image.colorSpace ?? CGColorSpaceCreateDeviceRGB()),
            bitmapInfo: image.bitmapInfo,
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
        
        var buffer = vImage_Buffer()
        // vImageBuffer_InitWithCGImage 会尝试直接访问数据，或者分配内存并复制
        let error = vImageBuffer_InitWithCGImage(&buffer, &format, nil, image, vImage_Flags(kvImageNoFlags))
        guard error == kvImageNoError else { return false }
        defer { free(buffer.data) }
        
        // 使用直方图计算来检查 Alpha 通道
        if image.bitsPerComponent == 8 && image.bitsPerPixel == 32 {
            var histogram = [UInt](repeating: 0, count: 256 * 4)
            
            let error = histogram.withUnsafeMutableBufferPointer { histogramBuf -> vImage_Error in
                guard let base = histogramBuf.baseAddress else { return kvImageMemoryAllocationError }
                
                var histogramPtrs: [UnsafeMutablePointer<vImagePixelCount>?] = [
                    base,
                    base.advanced(by: 256),
                    base.advanced(by: 512),
                    base.advanced(by: 768)
                ]
                
                return histogramPtrs.withUnsafeMutableBufferPointer { ptrs in
                    vImageHistogramCalculation_ARGB8888(&buffer, ptrs.baseAddress!, vImage_Flags(kvImageNoFlags))
                }
            }
            
            if error == kvImageNoError {
                // 检查是否有任何通道完全是 255
                for i in 0..<4 {
                    let start = i * 256
                    let end = start + 254 // Check 0 to 254
                    let sum = histogram[start...end].reduce(0, +)
                    if sum == 0 {
                        // 该通道所有像素都是 255，这极有可能是 Alpha 通道
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    private static func stripAlpha(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let bitsPerComponent = 8
        let bytesPerRow = 4 * width
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        // 使用 NoneSkipLast 明确忽略 Alpha 通道
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        
        return context.makeImage()
    }

    private static func createOpaqueImage(from image: CGImage) -> CGImage? {
        guard image.bitsPerComponent == 8 && image.bitsPerPixel == 32 else { return nil }
        
        // 确定新的 AlphaInfo: PremultipliedFirst -> NoneSkipFirst, etc.
        let alphaInfo = image.alphaInfo
        var newAlphaInfo: CGImageAlphaInfo = .none
        
        switch alphaInfo {
        case .first, .premultipliedFirst:
            newAlphaInfo = .noneSkipFirst
        case .last, .premultipliedLast:
            newAlphaInfo = .noneSkipLast
        default:
            return nil
        }
        
        var newBitmapInfo = image.bitmapInfo
        // 清除旧的 AlphaInfo
        let rawBitmapInfo = newBitmapInfo.rawValue & ~CGBitmapInfo.alphaInfoMask.rawValue
        // 设置新的 AlphaInfo
        newBitmapInfo = CGBitmapInfo(rawValue: rawBitmapInfo | newAlphaInfo.rawValue)
        
        guard let dataProvider = image.dataProvider else { return nil }
        
        return CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: image.bitsPerComponent,
            bitsPerPixel: image.bitsPerPixel,
            bytesPerRow: image.bytesPerRow,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: newBitmapInfo,
            provider: dataProvider,
            decode: image.decode,
            shouldInterpolate: image.shouldInterpolate,
            intent: image.renderingIntent
        )
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
