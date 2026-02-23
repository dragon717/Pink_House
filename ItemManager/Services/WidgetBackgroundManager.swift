//
//  WidgetBackgroundManager.swift
//  ItemManager
//
//  Created by 少女心愿 Dev on 1/20/26.
//

import UIKit
import WidgetKit
import ImageIO

enum WidgetFamilyType: String, CaseIterable {
    case small
    case medium
    case large
    case common // The default one, used as fallback
    
    var filename: String {
        switch self {
        case .common: return "widget_background.jpg"
        case .small: return "widget_background_small.jpg"
        case .medium: return "widget_background_medium.jpg"
        case .large: return "widget_background_large.jpg"
        }
    }
    
    var displayName: String {
        switch self {
        case .common: return "通用"
        case .small: return "小号"
        case .medium: return "中号"
        case .large: return "大号"
        }
    }
    
    var aspectRatio: CGFloat {
        switch self {
        case .small: return 1.0 // 1:1
        case .medium: return 2.14 // ~338/158
        case .large: return 0.95 // ~338/354 (approx 1:1)
        case .common: return 1.0
        }
    }
}

class WidgetBackgroundManager {
    static let shared = WidgetBackgroundManager()
    private let fileManager = FileManager.default
    
    // MARK: - File Management
    
    private func getContainerURL() -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) else {
            print("WidgetBackgroundManager: Could not find App Group container.")
            return nil
        }
        return container
    }
    
    private func imageURL(for family: WidgetFamilyType) -> URL? {
        return getContainerURL()?.appendingPathComponent(family.filename)
    }
    
    // MARK: - Save
    
    func saveImage(_ image: UIImage, for family: WidgetFamilyType = .common) {
        guard let url = imageURL(for: family) else { return }
        
        // Resize image to avoid memory limits
        let maxDimension: CGFloat = 800
        let resizedImage = image.resizedForWidget(toMaxDimension: maxDimension)
        
        // Compress and write to shared container
        if let data = resizedImage.jpegData(compressionQuality: 0.6) {
            do {
                try data.write(to: url)
                print("WidgetBackgroundManager: Image saved to \(url.path), size: \(data.count) bytes")
                // Notify Widget to reload
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                print("WidgetBackgroundManager: Error saving image - \(error)")
            }
        }
    }
    
    // MARK: - Load
    
    func loadImage(for family: WidgetFamilyType = .common) -> UIImage? {
        // 1. Try to load specific image
        if let url = imageURL(for: family), fileManager.fileExists(atPath: url.path) {
            return loadFromURL(url)
        }
        
        // 2. If requesting specific, but not found, try fallback to common
        if family != .common {
            if let commonUrl = imageURL(for: .common), fileManager.fileExists(atPath: commonUrl.path) {
                return loadFromURL(commonUrl)
            }
        }
        
        return nil
    }
    
    // Helper to check if specific image exists (without fallback)
    func hasSpecificImage(for family: WidgetFamilyType) -> Bool {
        guard let url = imageURL(for: family) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
    
    private func loadFromURL(_ url: URL) -> UIImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        let maxDimension: CGFloat = 800
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        
        return nil
    }
    
    // MARK: - Delete
    
    func deleteImage(for family: WidgetFamilyType = .common) {
        guard let url = imageURL(for: family) else { return }
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                print("WidgetBackgroundManager: Image deleted for \(family.displayName).")
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            print("WidgetBackgroundManager: Error deleting image - \(error)")
        }
    }
    
    // Delete all images (Reset)
    func deleteAllImages() {
        for family in WidgetFamilyType.allCases {
            deleteImage(for: family)
        }
    }
    
    func hasCustomBackground() -> Bool {
        // Check if any background exists
        for family in WidgetFamilyType.allCases {
            if let url = imageURL(for: family), fileManager.fileExists(atPath: url.path) {
                return true
            }
        }
        return false
    }
}

private extension UIImage {
    func resizedForWidget(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let size = self.size
        
        // If image is already smaller than max dimension, return original
        if size.width <= maxDimension && size.height <= maxDimension {
            return self
        }
        
        let aspectRatio = size.width / size.height
        var newSize: CGSize
        
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
