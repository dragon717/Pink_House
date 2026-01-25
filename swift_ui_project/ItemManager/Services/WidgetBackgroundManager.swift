//
//  WidgetBackgroundManager.swift
//  ItemManager
//
//  Created by Pink House Dev on 1/20/26.
//

import UIKit
import WidgetKit
import ImageIO

class WidgetBackgroundManager {
    static let shared = WidgetBackgroundManager()
    private let fileManager = FileManager.default
    private let filename = "widget_background.jpg"
    
    // Computed property to get the file URL in the App Group container
    private var imageURL: URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetDataManager.appGroupIdentifier) else {
            print("WidgetBackgroundManager: Could not find App Group container.")
            return nil
        }
        return container.appendingPathComponent(filename)
    }
    
    func saveImage(_ image: UIImage) {
        guard let url = imageURL else { return }
        
        // Resize image to avoid memory limits (Widget limit is around 2.5M pixels)
        // Using 600px as max dimension is safe for all widget sizes (Large widget is around 360x360 points)
        // @3x screen needs ~1080px, but for background 800px is a good balance between quality and memory
        let maxDimension: CGFloat = 800
        let resizedImage = image.resized(toMaxDimension: maxDimension)
        
        // Compress and write to shared container
        // Use 0.6 quality for better compression
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
    
    func loadImage() -> UIImage? {
        guard let url = imageURL else { return nil }
        
        // Check if file exists before trying to open it to avoid console errors
        if !fileManager.fileExists(atPath: url.path) {
            return nil
        }
        
        // Use ImageIO to downsample image while loading
        // This prevents loading full resolution image into memory if the file on disk is large
        // (e.g. if it was saved by an older version of the app)
        
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
    
    func deleteImage() {
        guard let url = imageURL else { return }
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                print("WidgetBackgroundManager: Image deleted.")
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch {
            print("WidgetBackgroundManager: Error deleting image - \(error)")
        }
    }
    
    func hasCustomBackground() -> Bool {
        guard let url = imageURL else { return false }
        return fileManager.fileExists(atPath: url.path)
    }
}

// MARK: - Image Resizing Extension
private extension UIImage {
    func resized(toMaxDimension maxDimension: CGFloat) -> UIImage {
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
