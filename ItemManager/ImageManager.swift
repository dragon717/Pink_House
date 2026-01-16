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

@MainActor
class ImageManager {
    static let shared = ImageManager()
    
    private init() {}
    
    // MARK: - Directory Management
    private var imagesDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        let imagesDirectory = documentsDirectory.appendingPathComponent("Images")
        
        if !FileManager.default.fileExists(atPath: imagesDirectory.path) {
            try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }
        
        return imagesDirectory
    }
    
    // MARK: - Core Logic
    
    /// 保存图片：压缩 -> 哈希去重 -> 存储/引用计数
    /// - Returns: 文件名 (如果成功)
    func saveImage(_ image: UIImage, context: ModelContext) -> String? {
        // 1. Compression
        guard let data = compressImage(image) else {
            AppLogger.error("Failed to compress image")
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
                return existingImage.fileName
            } else {
                // New image: Save to disk and DB
                let fileName = "\(UUID().uuidString).jpg"
                let fileURL = imagesDirectory.appendingPathComponent(fileName)
                
                try data.write(to: fileURL)
                
                let storedImage = StoredImage(imageHash: hash, fileName: fileName)
                context.insert(storedImage)
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
                    // Delete file
                    let fileURL = imagesDirectory.appendingPathComponent(fileName)
                    try? FileManager.default.removeItem(at: fileURL)
                    
                    // Delete from DB
                    context.delete(storedImage)
                    AppLogger.info("Deleted image file and record: \(fileName)")
                }
            }
        } catch {
            AppLogger.error("Failed to delete image: \(error)")
        }
    }
    
    /// 获取图片
    func loadImage(fileName: String) -> UIImage? {
        let fileURL = imagesDirectory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
    
    // MARK: - Helpers
    
    private func compressImage(_ image: UIImage) -> Data? {
        // 智能压缩：先尝试 0.7 质量，如果还太大可以继续调整，这里简化为固定 0.7 JPEG
        return image.jpegData(compressionQuality: 0.7)
    }
    
    private func computeHash(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
